#!/usr/bin/env bash
# Pre-commit / pre-push wrapper around the leak-check regex(es).
# Catches things the CI workflow can't see: commit messages + branch names
# (where the historical R2 leak happened) in addition to tracked-file content.
#
# Two regexes:
#   - CONTENT_PATTERN  — same as .github/workflows/leak-check.yml (scans
#                        tracked-file content; narrow on \bR[0-9]{2,3}\b
#                        to avoid false-positiving region labels like R1
#                        in deployment .puml files).
#   - SURFACE_PATTERN — broader \bR[0-9]+\b (single-digit OK) — applied to
#                       commit messages + branch names only, where the
#                       false-positive risk doesn't exist.
#
# Usage:
#   bash scripts/check-leaks.sh                                 # full sweep
#   bash scripts/check-leaks.sh --staged                        # staged files
#   bash scripts/check-leaks.sh --range main..HEAD              # range diff
#   bash scripts/check-leaks.sh --pre-push <local-ref> <remote-ref>
#     # tracked-file content in commits about to be pushed +
#     # commit messages in those commits + the branch name itself
#
# Exit codes:
#   0 — clean.
#   1 — leak found.
#   2 — environment problem.

set -uo pipefail

# Load CONTENT_PATTERN + SURFACE_PATTERN from `scripts/leak-patterns.txt` —
# single source of truth shared with `.github/workflows/leak-check.yml`.
# Format: KEY=regex, one per line; lines starting with `#` ignored.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEAK_PATTERNS_FILE="${SCRIPT_DIR}/leak-patterns.txt"
if [ ! -f "${LEAK_PATTERNS_FILE}" ]; then
  echo "FAIL: ${LEAK_PATTERNS_FILE} missing — cannot load leak regex" >&2
  exit 2
fi
CONTENT_PATTERN="$(grep -E '^CONTENT_PATTERN=' "${LEAK_PATTERNS_FILE}" | head -1 | cut -d= -f2-)"
SURFACE_PATTERN="$(grep -E '^SURFACE_PATTERN=' "${LEAK_PATTERNS_FILE}" | head -1 | cut -d= -f2-)"
if [ -z "${CONTENT_PATTERN}" ] || [ -z "${SURFACE_PATTERN}" ]; then
  echo "FAIL: CONTENT_PATTERN or SURFACE_PATTERN missing in ${LEAK_PATTERNS_FILE}" >&2
  exit 2
fi

EXCLUDED_PATHS=(
  ':!.github/workflows/leak-check.yml'
  ':!scripts/leak-patterns.txt'
  ':!tests/leak-fixtures.txt'
)
EXCLUDED_PATH_GREP='^(\.github/workflows/leak-check\.yml|scripts/leak-patterns\.txt|tests/leak-fixtures\.txt):'

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: not inside a git repository" >&2
  exit 2
fi

mode="full"
range=""
pre_push_local=""
pre_push_remote=""
case "${1:-}" in
  --staged)
    mode="staged"
    ;;
  --range)
    mode="range"
    range="${2:-}"
    if [ -z "${range}" ]; then
      echo "FAIL: --range requires a value (e.g. main..HEAD)" >&2
      exit 2
    fi
    ;;
  --pre-push)
    mode="pre-push"
    pre_push_local="${2:-}"
    pre_push_remote="${3:-}"
    if [ -z "${pre_push_local}" ] || [ -z "${pre_push_remote}" ]; then
      echo "FAIL: --pre-push requires <local-ref> <remote-ref>" >&2
      exit 2
    fi
    ;;
  "")
    mode="full"
    ;;
  *)
    echo "FAIL: unknown argument '$1'" >&2
    exit 2
    ;;
esac

content_matches=""
surface_matches=""

scan_content_files() {
  local files="$1"
  if [ -z "${files}" ]; then return 0; fi
  # -H forces the filename prefix even when grep is handed a single file
  # (or xargs splits into single-file batches) — without it EXCLUDED_PATH_GREP
  # can't match and the leak-check.yml / check-leaks.sh exclusions silently fail.
  echo "${files}" | xargs grep -HInE "${CONTENT_PATTERN}" 2>/dev/null | grep -vE "${EXCLUDED_PATH_GREP}" || true
}

case "${mode}" in
  full)
    content_matches=$(git grep -InE "${CONTENT_PATTERN}" -- "${EXCLUDED_PATHS[@]}" 2>/dev/null || true)
    ;;
  staged)
    staged_files=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
    content_matches=$(scan_content_files "${staged_files}")
    ;;
  range)
    range_files=$(git diff --name-only --diff-filter=ACMR "${range}" 2>/dev/null || true)
    content_matches=$(scan_content_files "${range_files}")
    ;;
  pre-push)
    # Commits in the range remote..local. The exclusion list is built from
    # every remote-tracking ref AND every local branch tip, so that:
    #   - new-branch pushes exclude commits reachable from any remote-tracking
    #     ref (origin/main, fixture/*, etc.) — this is the fix for the
    #     fixture-rebuild workaround applied in Phases 2.4/2.5/2.6/2.6.5,
    #     where `--not --remotes` still hit historical commits because the
    #     range computation included commits the topic branch shared with
    #     `origin/main` reachable via the local branch's history but unmarked
    #     by `--remotes` after a delete-then-fresh-push cycle.
    #   - existing-branch pushes scan only the new commits being added,
    #     which is what the original `${pre_push_remote}..${pre_push_local}`
    #     range already does correctly.
    if [ "${pre_push_remote}" = "0000000000000000000000000000000000000000" ]; then
      commit_range="${pre_push_local}"
      # Build an explicit exclusion list of every remote-tracking ref to
      # ensure we exclude historical commits already reachable from any of
      # them, not just whatever `--remotes` currently expands to.
      mapfile -t remote_refs < <(git for-each-ref --format='%(refname)' refs/remotes/ 2>/dev/null)
      pushed_commits=$(git rev-list "${pre_push_local}" --not "${remote_refs[@]}" 2>/dev/null || true)
    else
      commit_range="${pre_push_remote}..${pre_push_local}"
      pushed_commits=$(git rev-list "${commit_range}" 2>/dev/null || true)
    fi

    # 1. Tracked-file content (narrow regex).
    pushed_files=$(echo "${pushed_commits}" | xargs -r git diff-tree --no-commit-id --name-only --diff-filter=ACMR -r 2>/dev/null | sort -u || true)
    content_matches=$(scan_content_files "${pushed_files}")

    # 2. Commit messages (broader regex).
    if [ -n "${pushed_commits}" ]; then
      while IFS= read -r sha; do
        [ -n "${sha}" ] || continue
        msg=$(git log -1 --pretty=%B "${sha}")
        if echo "${msg}" | grep -qiE "${SURFACE_PATTERN}"; then
          surface_matches="${surface_matches}commit ${sha} message: $(echo "${msg}" | head -1)"$'\n'
        fi
      done <<< "${pushed_commits}"
    fi

    # 3. Branch name (broader regex).
    branch="${pre_push_local#refs/heads/}"
    if echo "${branch}" | grep -qiE "${SURFACE_PATTERN}"; then
      surface_matches="${surface_matches}branch name '${branch}'"$'\n'
    fi
    ;;
esac

if [ -n "${content_matches}" ] || [ -n "${surface_matches}" ]; then
  echo "FAIL: internal tokens found:"
  [ -n "${content_matches}" ] && { echo ""; echo "Tracked-file content:"; echo "${content_matches}"; }
  [ -n "${surface_matches}" ] && { echo ""; echo "Commit messages / branch names:"; echo "${surface_matches}"; }
  echo ""
  echo "Fix the leak before committing/pushing. If the match is a legitimate"
  echo "public reference, extend the exclusion list in"
  echo ".github/workflows/leak-check.yml + this script."
  exit 1
fi

echo "PASS: no internal tokens detected (mode=${mode}${range:+, range=${range}})"
exit 0

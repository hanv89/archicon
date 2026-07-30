#!/usr/bin/env bash
# Assert the skill sits where the ecosystem `skills` CLI (`npx skills add ...`)
# can find it, and that the pre-move location holds the manifest pair only.
#
# Why this gate exists: the CLI discovers skills by walking a checkout for
# `SKILL.md`, pruning a fixed set of directory names on the way down. A skill
# stored under any pruned name is invisible to it — the install reports zero
# skills found and exits 0, so nothing downstream notices. Every other gate in
# this repo checks files in isolation and would stay green through exactly that
# move, which is why the layout rule is asserted here instead of only in prose.
#
# Offline by design: the prune list is pinned below rather than probed from a
# live CLI, so this gate never touches the network.
#
# File list comes from git (index + not-yet-added files that .gitignore does
# not exclude), never a raw walk of the working tree: build output such as
# dist/chat-ui-bundle.zip is ignored and must not be able to fail this gate,
# while a file staged or dropped in by hand is still seen.
#
# Run locally:
#   bash scripts/test_skills_cli_discovery.sh
#
# Exit codes:
#   0 — skill discoverable on disk AND in git; no SKILL.md under a pruned
#       directory; manifest dir clean.
#   1 — at least one of those four assertions failed.
#   2 — environment problem (git missing, not a work tree, config absent).
set -uo pipefail
export LC_ALL=C

command -v git >/dev/null 2>&1 || { echo "ERROR: git not installed" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: ${REPO_ROOT} is not a git work tree" >&2; exit 2; }

# Both paths come from archicon.config, so a move shows up here instead of
# drifting silently. The CLI keeps its own copies; scripts/test_version_sync.sh
# is the gate that asserts the two agree.
[ -f "${REPO_ROOT}/archicon.config" ] || { echo "ERROR: archicon.config missing" >&2; exit 2; }
# shellcheck source=../archicon.config
. "${REPO_ROOT}/archicon.config"

# Both halves of the manifest pair are derived from the config value, never
# spelled out: renaming the manifest in archicon.config must not leave this gate
# demanding a basename that no longer exists.
MANIFEST_DIR="$(dirname "${SKILL_MANIFEST_PATH}")"
MANIFEST_BASE="$(basename "${SKILL_MANIFEST_PATH}")"
SCHEMA_BASE="${MANIFEST_BASE%.json}.schema.json"

# Directory names the ecosystem CLI prunes while walking for SKILL.md.
# Source: `skills@1.5.20`, `dist/cli.mjs`, verified 2026-07-29 — the same five
# names appear at both discovery paths (the clone walk's SKIP_DIRS array and the
# git-tree walk's SKIP_DIRS Set). Pinned here as a copy so the gate stays
# offline — re-read that constant in a newer CLI release before assuming this
# list is still current.
#
# Only `dist` and `build` can actually fire against this repo: `.git` is never
# listed by `git ls-files`, and `node_modules` / `__pycache__` are excluded by
# .gitignore. The other three are kept for parity with upstream so the copy can
# be diffed against the constant it came from.
SKIP_DIRS=(dist build node_modules .git __pycache__)

# Tracked files plus untracked-but-not-ignored ones. Read with a `while read`
# loop rather than `mapfile`, which is bash 4+: on macOS's default /bin/bash 3.2
# the builtin is missing and the script would die under `set -u` with exit 1,
# reading as "an assertion failed" instead of "wrong environment".
FILES=()
while IFS= read -r line; do
  FILES+=("${line}")
done < <(git ls-files --cached --others --exclude-standard)
[ "${#FILES[@]}" -gt 0 ] || { echo "ERROR: git listed no files" >&2; exit 2; }

failures=0
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

# --- 1. the skill is where the CLI looks, on disk ---
SKILL_MD="${SKILL_SRC_DIR}/SKILL.md"
if [ -f "${SKILL_MD}" ]; then
  echo "OK    ${SKILL_MD} present"
else
  fail "${SKILL_MD} does not exist — the ecosystem CLI has nothing to discover"
fi

# --- 2. the same file is visible to git ---
# Assertion 1 tests the working tree; assertion 3 iterates the git-visible list.
# Without this bridge the two views can disagree: drop SKILL.md from the index
# (or let a future ignore rule match it) and assertion 3 scans a list containing
# no SKILL.md at all, finds nothing under a pruned directory, and reports OK for
# a repo that publishes no skill. What git does not carry never reaches a clone,
# so on-disk presence alone proves nothing.
skill_md_tracked=0
for path in "${FILES[@]}"; do
  if [ "${path}" = "${SKILL_MD}" ]; then
    skill_md_tracked=1
    break
  fi
done
if [ "${skill_md_tracked}" -eq 1 ]; then
  echo "OK    ${SKILL_MD} is git-visible"
else
  fail "${SKILL_MD} exists on disk but git does not list it — it would never reach a clone, and the scan below would report OK having seen no SKILL.md at all. Run: git add ${SKILL_MD}"
fi

# --- 3. no SKILL.md anywhere under a pruned directory name ---
hidden=0
for path in "${FILES[@]}"; do
  [ "$(basename "${path}")" = "SKILL.md" ] || continue
  IFS='/' read -r -a segments <<< "${path}"
  for segment in "${segments[@]}"; do
    for skip in "${SKIP_DIRS[@]}"; do
      if [ "${segment}" = "${skip}" ]; then
        fail "${path} sits under '${skip}/', which the ecosystem CLI prunes — it will never be discovered"
        hidden=$((hidden + 1))
        break 2
      fi
    done
  done
done
[ "${hidden}" -eq 0 ] && echo "OK    no SKILL.md under a pruned directory (${SKIP_DIRS[*]})"

# --- 4. the manifest directory holds the manifest pair and nothing else ---
# Why: the manifest stayed at its published URL under a directory the ecosystem
# CLI prunes. Anything else left behind there is invisible to that CLI while
# this repo's CLI would still install it from manifest.files[], so the two
# install channels would ship different trees from one commit.
EXPECTED_PAIR="$(printf '%s\n' "${SKILL_MANIFEST_PATH}" "${MANIFEST_DIR}/${SCHEMA_BASE}" | sort)"
ACTUAL_PAIR="$(printf '%s\n' "${FILES[@]}" | grep "^${MANIFEST_DIR}/" | sort || true)"
if [ "${ACTUAL_PAIR}" = "${EXPECTED_PAIR}" ]; then
  echo "OK    ${MANIFEST_DIR}/ holds the manifest pair only"
else
  fail "${MANIFEST_DIR}/ contents differ from the manifest pair (expected < / actual >)"
  diff <(echo "${EXPECTED_PAIR}") <(echo "${ACTUAL_PAIR}") | sed 's/^/      /' >&2 || true
fi

if [ "${failures}" -gt 0 ]; then
  echo "" >&2
  echo "test_skills_cli_discovery: ${failures} failure(s)." >&2
  exit 1
fi
echo "PASS  skill is discoverable by the ecosystem CLI layout rules."

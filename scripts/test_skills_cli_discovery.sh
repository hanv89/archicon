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
#   0 — skill discoverable; no SKILL.md under a pruned directory; manifest dir clean.
#   1 — at least one of those three assertions failed.
#   2 — environment problem (git missing, not a work tree, config absent).
set -uo pipefail
export LC_ALL=C

command -v git >/dev/null 2>&1 || { echo "ERROR: git not installed" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: ${REPO_ROOT} is not a git work tree" >&2; exit 2; }

# archicon.config is the single source of truth for both paths, so a move
# shows up here instead of drifting silently.
[ -f "${REPO_ROOT}/archicon.config" ] || { echo "ERROR: archicon.config missing" >&2; exit 2; }
# shellcheck source=../archicon.config
. "${REPO_ROOT}/archicon.config"

MANIFEST_DIR="$(dirname "${SKILL_MANIFEST_PATH}")"

# Directory names the ecosystem CLI prunes while walking for SKILL.md.
# Source: the SKIP_DIRS constant in the `skills` CLI. Pinned here as a copy so
# the gate stays offline — re-read that constant in a newer CLI release before
# assuming this list is still current.
SKIP_DIRS=(dist build node_modules .git __pycache__)

# Tracked files plus untracked-but-not-ignored ones.
mapfile -t FILES < <(git ls-files --cached --others --exclude-standard)
[ "${#FILES[@]}" -gt 0 ] || { echo "ERROR: git listed no files" >&2; exit 2; }

failures=0
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

# --- 1. the skill is where the CLI looks ---
SKILL_MD="${SKILL_SRC_DIR}/SKILL.md"
if [ -f "${SKILL_MD}" ]; then
  echo "OK    ${SKILL_MD} present"
else
  fail "${SKILL_MD} does not exist — the ecosystem CLI has nothing to discover"
fi

# --- 2. no SKILL.md anywhere under a pruned directory name ---
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

# --- 3. the manifest directory holds the manifest pair and nothing else ---
EXPECTED_PAIR="$(printf '%s\n' "${MANIFEST_DIR}/manifest.json" "${MANIFEST_DIR}/manifest.schema.json" | sort)"
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

#!/usr/bin/env bash
# Verify the @hanv89/arch-skill CLI builds and the documented
# exit-code contract is intact. Re-runnable any time; no side effects
# beyond a transient packages/cli/dist/ build artifact (gitignored).
#
# Intended to be invoked manually before commits that touch
# packages/cli/, and as a release gate by future CI workflows.
#
# Exit codes:
#   0 — build succeeded and all probed subcommand paths exited as
#       documented.
#   1 — at least one assertion failed.
#   2 — environment problem (node, npm, working tree, or registry
#       reachability missing). Network failure during npm ci is an
#       environment issue, not a logic failure.
#
# no -e: per-assertion accounting must complete so the user sees every
# failure in one run, not just the first.
set -uo pipefail
export LC_ALL=C

command -v node >/dev/null 2>&1 || { echo "ERROR: node not installed"; exit 2; }
command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm not installed";  exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_DIR="${REPO_ROOT}/packages/cli"
[ -d "${CLI_DIR}" ] || { echo "ERROR: ${CLI_DIR} missing"; exit 2; }
[ -f "${CLI_DIR}/package.json" ]      || { echo "ERROR: ${CLI_DIR}/package.json missing";      exit 2; }
[ -f "${CLI_DIR}/package-lock.json" ] || { echo "ERROR: ${CLI_DIR}/package-lock.json missing"; exit 2; }

cd "${CLI_DIR}"

PASSED=0
FAILED=0

assert_exit() {
  local label="$1"; local expected="$2"; shift 2
  local err
  err="$("$@" 2>&1 >/dev/null)"
  local actual=$?
  if [ "${actual}" -eq "${expected}" ]; then
    echo "PASS ${label} (exit ${actual})"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL ${label} (expected exit ${expected}, got ${actual})"
    if [ -n "${err}" ]; then
      echo "  stderr: ${err}" | head -5
    fi
    FAILED=$((FAILED + 1))
  fi
}

# Step 1 — deterministic dependency install. npm ci fails loudly if
# node_modules is out of sync with package-lock.json, never mutates the
# lockfile, and exits non-zero on registry unreachability — exactly the
# semantics this smoke wants. Network failure → exit 2 ("env"), not 1.
echo "INFO  npm ci..."
if ! npm ci --silent; then
  echo "FAIL  npm ci (registry unreachable, lockfile out of sync, or proxy issue) — treated as env error"
  exit 2
fi

# Step 2 — build.
echo "INFO  building..."
npm run build --silent || { echo "FAIL  npm run build"; exit 1; }
[ -s dist/index.js ] || { echo "FAIL  dist/index.js missing after build"; exit 1; }
echo "PASS  build"

# Step 3 — exit-code contracts.
# `list --agent=claude-code` against an empty/missing skills root exits 0
# (prints '(no skills installed)'). Production code path requires the target
# to live inside ~/.claude (default allow-list); tests opt into a wider root
# via ARCH_SKILL_TARGET_ROOT, set to a fresh mktemp dir per run so
# concurrent smoke runs don't collide and a /tmp symlink-plant attack
# (Linux TOCTOU) cannot redirect the test target.
TEST_TARGET_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_TARGET_ROOT}"' EXIT

assert_exit "list (empty root) exits 0"   0 \
  env ARCH_SKILL_TARGET_ROOT="${TEST_TARGET_ROOT}" \
  node dist/index.js list --agent=claude-code --target="${TEST_TARGET_ROOT}/empty-skills-root"
assert_exit "no-arg exits 1 (commander)"   1 node dist/index.js
assert_exit "bogus  exits 1"               1 node dist/index.js bogus
assert_exit "unknown agent exits 1"        1 node dist/index.js install --agent=bogus
assert_exit "--help exits 0"               0 node dist/index.js --help
assert_exit "--cli-version prints exits 0" 0 node dist/index.js --cli-version
assert_exit "install --help exits 0"       0 node dist/index.js install --help

# Step 3b — install assertion + persisted dotfile manifest check.
# Catches two regression classes the unit tests don't cover:
#   (1) Commander `--version <semver>` short-circuit (pre-2.6.9): would
#       short-circuit to the top-level version printer instead of dispatching
#       to the install action, leaving the target dir empty.
#   (2) Persisted manifest is a DOTFILE (`.arch-skill-manifest.json`).
#       Earlier verification commands used `*manifest*` globs which skip
#       dotfiles by default; the manifest landed but was never inspected.
#       Use a literal filename here.
INSTALL_TARGET="${TEST_TARGET_ROOT}/install-target-test"
if env ARCH_SKILL_TARGET_ROOT="${TEST_TARGET_ROOT}" \
     node dist/index.js install --agent=claude-code --target="${INSTALL_TARGET}" >/dev/null 2>&1; then
  if [ -f "${INSTALL_TARGET}/SKILL.md" ] && [ -f "${INSTALL_TARGET}/.arch-skill-manifest.json" ]; then
    echo "PASS  install lands SKILL.md + .arch-skill-manifest.json (literal dotfile path)"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL  install dropped files but persisted manifest dotfile is missing"
    ls -la "${INSTALL_TARGET}" | head -10
    FAILED=$((FAILED + 1))
  fi
else
  echo "FAIL  install (default skill version) did not complete"
  FAILED=$((FAILED + 1))
fi

# Step 4 — node:test unit tests (parseFrontmatter regression coverage).
echo "INFO  running unit tests..."
if npm test --silent; then
  echo "PASS  unit tests"
  PASSED=$((PASSED + 1))
else
  echo "FAIL  unit tests"
  FAILED=$((FAILED + 1))
fi

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

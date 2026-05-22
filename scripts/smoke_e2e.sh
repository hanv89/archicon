#!/usr/bin/env bash
# End-to-end smoke for the install path: Node-18 negative test (engines
# floor) + icon-set-unreachable fixture test. Manual Claude Code
# rendering is NOT exercised here — those end-to-end checks are
# recorded as attestation artifacts maintained upstream.
#
# Exit codes:
#   0 — both tests passed (or Test A skipped due to no Docker).
#   1 — at least one assertion failed.
#   2 — environment problem (node missing, packages/cli build fails, etc.).
#
# no -e: per-test accounting must complete.
set -uo pipefail
export LC_ALL=C

command -v node >/dev/null 2>&1 || { echo "ERROR: node not installed"; exit 2; }
command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm not installed";  exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_DIR="${REPO_ROOT}/packages/cli"
[ -d "${CLI_DIR}" ] || { echo "ERROR: ${CLI_DIR} missing"; exit 2; }

cd "${CLI_DIR}"

PASSED=0
FAILED=0
SKIPPED=0

# ---------- Build a fresh tarball for Test A ----------
echo "INFO  building tarball..."
npm ci --silent || { echo "ERROR: npm ci failed"; exit 2; }
npm run build --silent || { echo "ERROR: npm run build failed"; exit 2; }
TARBALL="$(npm pack --silent | tail -1)"
[ -s "${TARBALL}" ] || { echo "ERROR: npm pack produced empty tarball"; exit 2; }

# Cleanup tarball + any test target dirs on exit, regardless of outcome.
TEST_TARGET_ROOT="$(mktemp -d)"
cleanup() {
  rm -f "${CLI_DIR}/${TARBALL}"
  rm -rf "${TEST_TARGET_ROOT}"
}
trap cleanup EXIT

# ---------- Test A — Node-18 engines refusal ----------
# npm's default behavior is to warn (EBADENGINE) and proceed when a package's
# engines.node range excludes the current runtime. The publisher cannot force
# the consumer's npm to be strict, so this test uses --engine-strict to verify
# the engines field is correctly declared: a Node-18 user who has opted into
# strict-mode (or whose distro's npm config sets it) WILL get a hard refusal.
if command -v docker >/dev/null 2>&1; then
  echo "INFO  Test A: Node-18 install with --engine-strict (Docker)..."
  set +e
  DOCKER_OUT="$(docker run --rm \
    -v "${CLI_DIR}/${TARBALL}:/tmp/cli.tgz:ro" -w /tmp \
    node:18-alpine sh -c "npm install -g --engine-strict /tmp/cli.tgz" 2>&1)"
  DOCKER_RC=$?
  set -e
  if [ "${DOCKER_RC}" -ne 0 ] && echo "${DOCKER_OUT}" | grep -qiE "EBADENGINE|EUNSUPPORTEDENGINE|unsupported engine"; then
    echo "PASS Test A: Node-18 install refused under --engine-strict"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL Test A: expected non-zero exit + EBADENGINE/EUNSUPPORTEDENGINE, got rc=${DOCKER_RC}"
    echo "${DOCKER_OUT}" | tail -10
    FAILED=$((FAILED + 1))
  fi
else
  echo "SKIP Test A: docker not available; Node-18 negative test skipped (env-degraded, not failure)"
  SKIPPED=$((SKIPPED + 1))
fi

# ---------- Test B — Icon-set unreachable via fixture branch ----------
echo "INFO  Test B: icon-set-unreachable via fixture/skill-md-only..."

set +e
B_OUT="$(ARCH_SKILL_BASE_URL="https://raw.githubusercontent.com/hanv89/archicon/fixture/skill-md-only" \
  ARCH_SKILL_TARGET_ROOT="${TEST_TARGET_ROOT}" \
  node dist/index.js install --agent=claude-code \
    --target="${TEST_TARGET_ROOT}/architecture-diagram" 2>&1)"
B_RC=$?
set -e
if [ "${B_RC}" -eq 1 ] && echo "${B_OUT}" | grep -qE "^fatal: icon-set unreachable"; then
  echo "PASS Test B: icon-set-unreachable produced fatal: + exit 1"
  PASSED=$((PASSED + 1))
else
  echo "FAIL Test B: expected exit 1 + 'fatal: icon-set unreachable', got rc=${B_RC}"
  echo "${B_OUT}" | tail -10
  FAILED=$((FAILED + 1))
fi

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed, ${SKIPPED} skipped."
[ "${FAILED}" -eq 0 ] || exit 1

#!/usr/bin/env bash
# Unit test for build_azure.sh pure logic against a synthetic fixture
# upstream tree (BUILD_SELFTEST=1, no network clone):
#   - PNG-only copy from <source>/dist preserving category structure;
#   - non-PNG files excluded;
#   - UPSTREAM-SHA.txt written under the dist dir.
#
# Exit codes: 0 all pass, 1 a case failed, 2 env (rsync missing).
set -uo pipefail
export LC_ALL=C

command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync not installed" >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

PASSED=0; FAILED=0
pass() { PASSED=$(( PASSED + 1 )); echo "PASS: $*"; }
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

WORK="$(mktemp -d)"; trap 'rm -rf "${WORK}"' EXIT
SRC="${WORK}/src"
DIST="${WORK}/dist"

# Synthetic Azure-PlantUML-style dist/ tree: PNGs across category subdirs
# (colored + monochrome) + a non-PNG that must be excluded.
mkdir -p "${SRC}/dist/Compute" "${SRC}/dist/Networking"
printf 'PNG' > "${SRC}/dist/Compute/AzureVirtualMachine.png"
printf 'PNG' > "${SRC}/dist/Compute/AzureVirtualMachine(m).png"
printf 'PNG' > "${SRC}/dist/Networking/AzureFrontDoor.png"
printf 'puml' > "${SRC}/dist/Compute/AzureVirtualMachine.puml"   # must NOT copy

out="$(BUILD_SELFTEST=1 BUILD_SOURCE_DIR="${SRC}" BUILD_DIST_DIR="${DIST}" \
       bash "${SCRIPT_DIR}/build_azure.sh" 2>&1)"; rc=$?

[ "${rc}" -eq 0 ] && pass "build exits 0 on fixture" || fail "build exit ${rc}: ${out}"
n="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${n}" -eq 3 ] && pass "3 PNGs copied" || fail "expected 3 PNGs, got ${n}"
[ -f "${DIST}/Compute/AzureVirtualMachine.png" ] && pass "category structure preserved" || fail "VM PNG not at expected subpath"
[ -f "${DIST}/Compute/AzureVirtualMachine(m).png" ] && pass "monochrome variant copied" || fail "monochrome variant missing"
[ ! -f "${DIST}/Compute/AzureVirtualMachine.puml" ] && pass "non-PNG (.puml) excluded" || fail ".puml was copied"
[ -f "${DIST}/UPSTREAM-SHA.txt" ] && pass "UPSTREAM-SHA.txt written" || fail "UPSTREAM-SHA.txt missing"

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

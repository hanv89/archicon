#!/usr/bin/env bash
# Unit test for build_kubernetes.sh pure logic against a synthetic fixture
# upstream tree (BUILD_SELFTEST=1, no network clone):
#   - PNG-only copy preserving subdir structure;
#   - upstream zero-byte placeholder drop;
#   - non-PNG files excluded.
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
REC="${WORK}/UPSTREAM-SHA.txt"

# Synthetic upstream icons/png tree:
#   - 2 real PNGs in resources/labeled/
#   - 1 real PNG in infrastructure_components/labeled/
#   - 1 zero-byte placeholder `etcd-.png` (must be dropped)
#   - 1 SVG (must be excluded by the PNG-only filter)
mkdir -p "${SRC}/icons/png/resources/labeled" \
         "${SRC}/icons/png/infrastructure_components/labeled"
printf 'PNGDATA' > "${SRC}/icons/png/resources/labeled/pod-128.png"
printf 'PNGDATA' > "${SRC}/icons/png/resources/labeled/svc-256.png"
printf 'PNGDATA' > "${SRC}/icons/png/infrastructure_components/labeled/node-128.png"
: > "${SRC}/icons/png/infrastructure_components/labeled/etcd-.png"   # zero-byte placeholder
printf '<svg/>' > "${SRC}/icons/png/resources/labeled/should-not-copy.svg"

out="$(BUILD_SELFTEST=1 BUILD_SOURCE_DIR="${SRC}" BUILD_DIST_DIR="${DIST}" \
       BUILD_UPSTREAM_RECORD="${REC}" \
       bash "${SCRIPT_DIR}/build_kubernetes.sh" 2>&1)"; rc=$?

[ "${rc}" -eq 0 ] && pass "build exits 0 on fixture" || fail "build exit ${rc}: ${out}"

n="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${n}" -eq 3 ] && pass "3 real PNGs copied (zero-byte dropped)" || fail "expected 3 PNGs, got ${n}"

[ -f "${DIST}/resources/labeled/pod-128.png" ] && pass "subdir structure preserved" || fail "pod-128.png not at expected subpath"
[ ! -f "${DIST}/infrastructure_components/labeled/etcd-.png" ] && pass "zero-byte placeholder dropped" || fail "zero-byte placeholder survived"
[ ! -f "${DIST}/resources/labeled/should-not-copy.svg" ] && pass "non-PNG excluded" || fail "SVG was copied"

# zero-byte count under dist must be 0
z="$(find "${DIST}" -name '*.png' -size 0 | wc -l | tr -d ' ')"
[ "${z}" -eq 0 ] && pass "no zero-byte PNGs remain" || fail "${z} zero-byte PNG(s) remain"

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

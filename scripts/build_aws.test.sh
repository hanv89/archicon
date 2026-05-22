#!/usr/bin/env bash
# Unit test for build_aws.sh pure logic against a synthetic fixture upstream
# tree (BUILD_SELFTEST=1, no network clone):
#   - VERBATIM PNG-only copy preserving per-category subdir structure;
#   - non-PNG files (SVG, .puml, JSON) excluded;
#   - copied PNG bytes are IDENTICAL to source (CC-BY-ND: no transform);
#   - the build script itself never references rsvg/convert.
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

# Synthetic upstream dist/ tree (mirrors awslabs layout: dist/<Category>/<svc>.png):
#   - 2 real PNGs in Compute/, 1 in Storage/
#   - a .puml + .svg + .json that MUST be excluded by the PNG-only filter
mkdir -p "${SRC}/dist/Compute" "${SRC}/dist/Storage"
printf 'PNGBYTES-ec2' > "${SRC}/dist/Compute/EC2.png"
printf 'PNGBYTES-lambda' > "${SRC}/dist/Compute/Lambda.png"
printf 'PNGBYTES-s3' > "${SRC}/dist/Storage/SimpleStorageService.png"
printf '@startuml\n@enduml\n' > "${SRC}/dist/AWSCommon.puml"
printf '<svg/>' > "${SRC}/dist/Compute/EC2.svg"
printf '{}' > "${SRC}/dist/aws-icons-mermaid.json"

out="$(BUILD_SELFTEST=1 BUILD_SOURCE_DIR="${SRC}" BUILD_DIST_DIR="${DIST}" \
       BUILD_UPSTREAM_RECORD="${REC}" \
       bash "${SCRIPT_DIR}/build_aws.sh" 2>&1)"; rc=$?

[ "${rc}" -eq 0 ] && pass "build exits 0 on fixture" || fail "build exit ${rc}: ${out}"

n="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${n}" -eq 3 ] && pass "3 PNGs copied" || fail "expected 3 PNGs, got ${n}"

[ -f "${DIST}/Compute/EC2.png" ] && pass "per-category subdir preserved" || fail "Compute/EC2.png not at expected subpath"
[ ! -f "${DIST}/AWSCommon.puml" ] && pass ".puml excluded" || fail ".puml was copied"
[ ! -f "${DIST}/Compute/EC2.svg" ] && pass ".svg excluded" || fail ".svg was copied"
[ ! -f "${DIST}/aws-icons-mermaid.json" ] && pass ".json excluded" || fail ".json was copied"

# Verbatim: copied bytes must equal source bytes (no transform).
if cmp -s "${SRC}/dist/Compute/EC2.png" "${DIST}/Compute/EC2.png"; then
  pass "copied PNG is byte-identical to source (verbatim)"
else
  fail "copied PNG differs from source — NOT verbatim"
fi

# UPSTREAM-SHA.txt records verbatim mode.
if grep -q 'verbatim' "${REC}"; then pass "UPSTREAM-SHA.txt records verbatim mode"; else fail "UPSTREAM-SHA.txt missing verbatim marker"; fi

# Static guard: build_aws.sh must never call an image converter.
if grep -qE '\brsvg|--convert|\bmagick\b|\binkscape\b' "${SCRIPT_DIR}/build_aws.sh"; then
  fail "build_aws.sh references an image converter"
else
  pass "build_aws.sh references no image converter (rsvg/convert/magick/inkscape)"
fi

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

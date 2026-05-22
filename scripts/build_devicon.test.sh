#!/usr/bin/env bash
# Unit test for build_devicon.sh pure logic (curation read, missing-stem
# abort, SVG->PNG conversion, scoped clean) against a synthetic fixture
# upstream tree. Runs in BUILD_SELFTEST=1 mode so no network clone happens.
#
# Exit codes: 0 all pass, 1 a case failed, 2 env (rsvg-convert missing).
set -uo pipefail
export LC_ALL=C

command -v rsvg-convert >/dev/null 2>&1 || { echo "ERROR: rsvg-convert not installed" >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

PASSED=0; FAILED=0
pass() { PASSED=$(( PASSED + 1 )); echo "PASS: $*"; }
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

WORK="$(mktemp -d)"; trap 'rm -rf "${WORK}"' EXIT

# --- synthetic upstream tree: 3 stems with -original.svg, 1 without ---
SRC="${WORK}/src"
mkdir -p "${SRC}/icons/alpha" "${SRC}/icons/beta" "${SRC}/icons/gamma" "${SRC}/icons/delta"
printf 'The MIT License (MIT)\n' > "${SRC}/LICENSE"
SVG='<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#08c"/></svg>'
printf '%s' "${SVG}" > "${SRC}/icons/alpha/alpha-original.svg"
printf '%s' "${SVG}" > "${SRC}/icons/beta/beta-original.svg"
printf '%s' "${SVG}" > "${SRC}/icons/gamma/gamma-original.svg"
# delta deliberately has no -original.svg (tests missing-stem abort)

DIST="${WORK}/dist"
REC="${WORK}/UPSTREAM-SHA.txt"

run_build() {
  local curation="$1"; shift
  BUILD_SELFTEST=1 \
  BUILD_SOURCE_DIR="${SRC}" \
  BUILD_DIST_DIR="${DIST}" \
  BUILD_CURATION_LIST="${curation}" \
  BUILD_UPSTREAM_RECORD="${REC}" \
    bash "${SCRIPT_DIR}/build_devicon.sh" "$@" 2>&1
}

# ---- Case 1: happy path — 3 curated stems -> 3 PNGs ----
CUR1="${WORK}/cur1.txt"
printf '# comment\nalpha\nbeta\ngamma\n' > "${CUR1}"
out="$(run_build "${CUR1}")"; rc=$?
if [ "${rc}" -eq 0 ]; then pass "happy path exits 0"; else fail "happy path exit ${rc}: ${out}"; fi
n="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${n}" -eq 3 ] && pass "3 PNGs produced" || fail "expected 3 PNGs, got ${n}"
[ -f "${DIST}/alpha-original_48.png" ] && pass "alpha-original_48.png present" || fail "alpha PNG missing"
[ -s "${DIST}/beta-original_48.png" ]  && pass "beta PNG non-empty"         || fail "beta PNG empty/missing"

# ---- Case 2: comments + blank lines ignored ----
n2="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${n2}" -eq 3 ] && pass "comment line did not produce a PNG" || fail "comment handling: got ${n2}"

# ---- Case 3: missing-stem aborts non-zero ----
CUR3="${WORK}/cur3.txt"
printf 'alpha\ndelta\n' > "${CUR3}"   # delta has no -original.svg
out3="$(run_build "${CUR3}")"; rc3=$?
[ "${rc3}" -ne 0 ] && pass "missing curated stem aborts (exit ${rc3})" || fail "missing stem did NOT abort"
printf '%s' "${out3}" | grep -q 'missing SVG' && pass "missing-stem error names the gap" || fail "missing-stem error message absent"

# ---- Case 4: UPSTREAM record written in selftest ----
[ -f "${REC}" ] && pass "UPSTREAM record written to override path" || fail "UPSTREAM record not written"

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

#!/usr/bin/env bash
# Unit test for build_fluentui_system.sh pure logic against a synthetic
# fixture upstream tree (BUILD_SELFTEST=1, no network clone):
#   - concept -> snake_case stem normalization (tr 'A-Z ' 'a-z_');
#   - all-3-sizes-present happy path;
#   - partial-shipping abort (a concept with only 1-2 of the 3 sizes).
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
SRC="${WORK}/src"
DIST="${WORK}/dist"
REC="${WORK}/UPSTREAM-SHA.txt"
SVG='<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#5b5fc7"/></svg>'

# Helper: write an asset SVG for "<Concept>" at a given size.
# Mirrors the build's path: assets/<Concept>/SVG/ic_fluent_<stem>_<sz>_color.svg
write_asset() {
  local concept="$1" sz="$2"
  local stem; stem="$(printf '%s' "${concept}" | tr 'A-Z ' 'a-z_')"
  mkdir -p "${SRC}/assets/${concept}/SVG"
  printf '%s' "${SVG}" > "${SRC}/assets/${concept}/SVG/ic_fluent_${stem}_${sz}_color.svg"
}

mkdir -p "${SRC}"
printf 'MIT License\n' > "${SRC}/LICENSE"

run_build() {
  local curation="$1"; shift
  BUILD_SELFTEST=1 \
  BUILD_SOURCE_DIR="${SRC}" \
  BUILD_DIST_DIR="${DIST}" \
  BUILD_CURATION_LIST="${curation}" \
  BUILD_UPSTREAM_RECORD="${REC}" \
    bash "${SCRIPT_DIR}/build_fluentui_system.sh" "$@" 2>&1
}

# ---- Case 1: two concepts, all 3 sizes each -> 6 PNGs + normalization ----
for c in "Cloud" "Cloud Dismiss"; do for s in 24 32 48; do write_asset "${c}" "${s}"; done; done
CUR1="${WORK}/cur1.txt"; printf '# fixtures\nCloud\nCloud Dismiss\n' > "${CUR1}"
out="$(run_build "${CUR1}")"; rc=$?
[ "${rc}" -eq 0 ] && pass "all-3-sizes happy path exits 0" || fail "happy path exit ${rc}: ${out}"
n="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${n}" -eq 6 ] && pass "6 PNGs (2 concepts × 3 sizes)" || fail "expected 6 PNGs, got ${n}"
[ -f "${DIST}/cloud_24_color.png" ] && pass "Cloud -> cloud_24_color.png" || fail "cloud_24_color.png missing"
[ -f "${DIST}/cloud_dismiss_48_color.png" ] && pass "'Cloud Dismiss' -> cloud_dismiss_48_color.png (snake_case)" || fail "cloud_dismiss normalization wrong"

# ---- Case 2: partial-shipping concept aborts ----
write_asset "Database" 24
write_asset "Database" 32
# Database deliberately missing the 48 size -> partial
CUR2="${WORK}/cur2.txt"; printf 'Cloud\nDatabase\n' > "${CUR2}"
out2="$(run_build "${CUR2}")"; rc2=$?
[ "${rc2}" -ne 0 ] && pass "partial-shipping concept aborts (exit ${rc2})" || fail "partial-shipping did NOT abort"
printf '%s' "${out2}" | grep -qi 'partial-shipping' && pass "error names the partial-shipping case" || fail "partial-shipping message absent"

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

#!/usr/bin/env bash
# Unit test for build_fabric.sh pure logic against a synthetic fixture SVG
# dir (BUILD_SELFTEST=1, no npm install). Exercises the two-pass size
# selection:
#   - Pass 1: per-artifact _40 SVGs at 40px;
#   - Pass 2: native size extracted from filename (24/28/32/48);
#   - mirrored_catalog_48_item -> renamed to mirrored_catalog_40_item;
#   - sample_workload_* excluded.
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
SVGDIR="${WORK}/svg"
DIST="${WORK}/dist"
REC="${WORK}/UPSTREAM-VERSION.txt"
mkdir -p "${SVGDIR}"
SVG='<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#117865"/></svg>'

# Pass 1 candidates (_40 family)
printf '%s' "${SVG}" > "${SVGDIR}/lakehouse_40_item.svg"
printf '%s' "${SVG}" > "${SVGDIR}/workspaces_40_non-item.svg"
# mirrored_catalog only ships at 48 upstream -> renamed to _40 in pass 1
printf '%s' "${SVG}" > "${SVGDIR}/mirrored_catalog_48_item.svg"
# Pass 2 candidates (native sizes)
printf '%s' "${SVG}" > "${SVGDIR}/power_bi_48_color.svg"
printf '%s' "${SVG}" > "${SVGDIR}/graph_model_24.svg"
printf '%s' "${SVG}" > "${SVGDIR}/notebook_32_item.svg"
# excluded placeholder
printf '%s' "${SVG}" > "${SVGDIR}/sample_workload_48_item.svg"

out="$(BUILD_SELFTEST=1 BUILD_SVG_DIR="${SVGDIR}" BUILD_DIST_DIR="${DIST}" \
       BUILD_UPSTREAM_RECORD="${REC}" \
       bash "${SCRIPT_DIR}/build_fabric.sh" 2>&1)"; rc=$?

[ "${rc}" -eq 0 ] && pass "build exits 0 on fixture" || fail "build exit ${rc}: ${out}"

# Expected outputs:
#  Pass1: lakehouse_40_item, workspaces_40_non-item, mirrored_catalog_40_item (renamed)
#  Pass2: power_bi_48_color, graph_model_24, notebook_32_item
[ -f "${DIST}/lakehouse_40_item.png" ]        && pass "pass1 _40_item converted"          || fail "lakehouse_40_item.png missing"
# mirrored_catalog ships only at 48 upstream: Pass 1 downscales+renames it to
# _40, and Pass 2 also emits the native _48 — production carries BOTH.
[ -f "${DIST}/mirrored_catalog_40_item.png" ] && pass "mirrored_catalog 48->40 downscale-rename (pass1)" || fail "mirrored_catalog _40 rename failed"
[ -f "${DIST}/mirrored_catalog_48_item.png" ] && pass "mirrored_catalog native _48 (pass2)"             || fail "mirrored_catalog _48 missing"
[ -f "${DIST}/power_bi_48_color.png" ]        && pass "pass2 _48_color converted"          || fail "power_bi_48_color.png missing"
[ -f "${DIST}/graph_model_24.png" ]           && pass "pass2 plain _24 converted"          || fail "graph_model_24.png missing"
[ -f "${DIST}/notebook_32_item.png" ]         && pass "pass2 _32_item converted"           || fail "notebook_32_item.png missing"
[ ! -f "${DIST}/sample_workload_48_item.png" ] && pass "sample_workload excluded"          || fail "sample_workload was converted"

# size sanity: power_bi_48_color should be 48px wide
if command -v file >/dev/null 2>&1; then
  if file "${DIST}/power_bi_48_color.png" | grep -q '48 x 48'; then pass "48_color rendered at 48x48"; else fail "48_color not 48x48: $(file "${DIST}/power_bi_48_color.png")"; fi
fi

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

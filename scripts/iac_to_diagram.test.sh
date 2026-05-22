#!/usr/bin/env bash
# Unit test for scripts/iac_to_diagram.mjs (experimental):
#   - emits valid PlantUML (@startuml/@enduml) from the sample .tf;
#   - every emitted <img:...dist/Azure/...png> path exists on disk;
#   - mapped-resource count meets the floor;
#   - uncovered types are reported on stderr (not silently dropped);
#   - every map-table icon path exists in dist/.
#
# Exit codes: 0 all pass, 1 a case failed, 2 env (node missing).
set -uo pipefail
export LC_ALL=C

command -v node >/dev/null 2>&1 || { echo "ERROR: node not installed" >&2; exit 2; }
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

PASSED=0; FAILED=0
pass() { PASSED=$(( PASSED + 1 )); echo "PASS: $*"; }
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

MAP="scripts/fixtures/iac-azurerm-icon-map.tsv"
SAMPLE="scripts/fixtures/sample-azure.tf"
[ -f "${MAP}" ]    || { echo "ERROR: ${MAP} missing" >&2; exit 2; }
[ -f "${SAMPLE}" ] || { echo "ERROR: ${SAMPLE} missing" >&2; exit 2; }

# --- 1. every map-table icon path exists ---
mapmiss=0
while IFS=$'\t' read -r t p l; do
  case "${t}" in ''|\#*) continue;; esac
  [ -f "${p}" ] || { echo "  map row missing icon: ${p}" >&2; mapmiss=$(( mapmiss + 1 )); }
done < "${MAP}"
[ "${mapmiss}" -eq 0 ] && pass "all map-table icon paths exist in dist/" || fail "${mapmiss} map row(s) point at a missing icon"

# --- run the parser ---
OUT="$(mktemp)"; ERR="$(mktemp)"; trap 'rm -f "${OUT}" "${ERR}"' EXIT
node scripts/iac_to_diagram.mjs "${SAMPLE}" > "${OUT}" 2> "${ERR}"
rc=$?
[ "${rc}" -eq 0 ] && pass "parser exits 0 on sample" || fail "parser exit ${rc}"

# --- 2. valid PlantUML envelope ---
head -1 "${OUT}" | grep -q '@startuml' && tail -1 "${OUT}" | grep -q '@enduml' \
  && pass "output is @startuml..@enduml" || fail "missing PlantUML envelope"

# --- 3. emitted icon paths resolve ---
badpaths=0
for p in $(grep -oE 'dist/Azure/[^>]+\.png' "${OUT}" | sort -u); do
  [ -f "${p}" ] || { echo "  emitted path missing: ${p}" >&2; badpaths=$(( badpaths + 1 )); }
done
[ "${badpaths}" -eq 0 ] && pass "all emitted icon paths resolve in dist/" || fail "${badpaths} emitted path(s) do not resolve"

# --- 4. mapped-count floor (sample has 9 mappable + 2 unmapped) ---
rects="$(grep -c '^rectangle ' "${OUT}")"
[ "${rects}" -ge 11 ] && pass "emitted ${rects} nodes (>= 11)" || fail "expected >= 11 nodes, got ${rects}"

# --- 5. uncovered types reported, not dropped ---
grep -qiE 'uncovered|not mapped|unknown' "${ERR}" \
  && grep -q 'azurerm_dns_zone' "${ERR}" \
  && pass "uncovered types reported on stderr (incl. azurerm_dns_zone)" \
  || fail "uncovered-type report missing"

# the unmapped types must still appear as nodes in the output (not dropped)
grep -q 'azurerm_dns_zone: main' "${OUT}" \
  && pass "unmapped resource still rendered as a text node" \
  || fail "unmapped resource was dropped from the diagram"

# --- 6. adversarial: commented-out resource is NOT emitted (phantom node) ---
CMT="$(mktemp)"
printf 'resource "azurerm_resource_group" "real" {\n  name = "rg"\n}\n# resource "azurerm_storage_account" "fake" {\n}\n' > "${CMT}"
if node scripts/iac_to_diagram.mjs "${CMT}" 2>/dev/null | grep -q 'fake'; then
  fail "commented-out resource emitted as a phantom node"
else
  pass "commented-out resource ignored (no phantom node)"
fi
rm -f "${CMT}"

# --- 7. adversarial: brace inside a string value does not drop later resources ---
BR="$(mktemp)"
printf 'resource "azurerm_resource_group" "a" {\n  name = "weird{brace"\n}\nresource "azurerm_key_vault" "b" {\n  name = "kv"\n}\n' > "${BR}"
n="$(node scripts/iac_to_diagram.mjs "${BR}" 2>/dev/null | grep -c '^rectangle ')"
[ "${n}" -eq 2 ] && pass "brace-in-string did not desync block slicing (2 nodes)" || fail "brace-in-string mis-parse: got ${n} nodes, expected 2"
rm -f "${BR}"

# --- 8. adversarial: --ref validation ---
node scripts/iac_to_diagram.mjs "${SAMPLE}" --ref '../../etc' >/dev/null 2>&1
[ "$?" -eq 2 ] && pass "path-traversal --ref rejected (exit 2)" || fail "bad --ref not rejected"
node scripts/iac_to_diagram.mjs "${SAMPLE}" --ref >/dev/null 2>&1
[ "$?" -eq 2 ] && pass "missing --ref value rejected (exit 2)" || fail "missing --ref value not rejected"
node scripts/iac_to_diagram.mjs "${SAMPLE}" --ref icons-v1.4.0 >/dev/null 2>&1
[ "$?" -eq 0 ] && pass "valid --ref accepted (exit 0)" || fail "valid --ref rejected"

echo
echo "Summary: ${PASSED} passed, ${FAILED} failed."
[ "${FAILED}" -eq 0 ] || exit 1

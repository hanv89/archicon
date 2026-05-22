#!/usr/bin/env bash
# Fixture-based tests for monitor_ms_tou.sh. Drives the monitor against
# three local HTML fixtures via the URL env override:
#   - matching: all 4 patterns present + identical to baseline → exit 0.
#   - drifted:  all 4 patterns present but text differs → exit 1.
#   - broken:   page structure changed, patterns missing → exit 1.
# Exits 0 if all three behave as expected.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures"
MONITOR="${SCRIPT_DIR}/monitor_ms_tou.sh"

PASSED=0
FAILED=0
fail() {
  FAILED=$(( FAILED + 1 ))
  echo "FAIL: $*" >&2
}
pass() {
  PASSED=$(( PASSED + 1 ))
  echo "PASS: $*"
}

# ---- matching fixture: exit 0 ----
URL="file://${FIXTURES}/ms-tou-matching.html" bash "${MONITOR}" >/dev/null 2>&1
[ $? -eq 0 ] && pass "matching fixture exits 0" \
             || fail "matching fixture did not exit 0"

# ---- drifted fixture: exit 1 (baseline drift detected) ----
URL="file://${FIXTURES}/ms-tou-drifted.html" bash "${MONITOR}" >/dev/null 2>&1
[ $? -eq 1 ] && pass "drifted fixture exits 1 (baseline drift)" \
             || fail "drifted fixture did not exit 1 (got: $?)"

# ---- broken fixture: exit 1 (patterns missing → structural change) ----
URL="file://${FIXTURES}/ms-tou-broken.html" bash "${MONITOR}" >/dev/null 2>&1
[ $? -eq 1 ] && pass "broken fixture exits 1 (patterns missing)" \
             || fail "broken fixture did not exit 1 (got: $?)"

echo "---"
echo "Total: PASS=${PASSED} FAIL=${FAILED}"
[ "${FAILED}" -eq 0 ] || exit 1
exit 0

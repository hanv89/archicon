#!/usr/bin/env bash
# Unit tests for scripts/_lib_icon_build.sh. Zero-dep — pure bash + diff/grep.
# Exit codes:
#   0 — all cases pass.
#   1 — at least one case failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_lib_icon_build.sh"

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

# ---- set_locale_deterministic ----
set_locale_deterministic
[ "${LC_ALL}" = "C" ] && pass "set_locale_deterministic exports LC_ALL=C" \
                     || fail "set_locale_deterministic did not export LC_ALL=C (got: '${LC_ALL:-unset}')"

# ---- assert_relative_drop_safe — old=0 always passes ----
if assert_relative_drop_safe 0 0 10 0 2>/dev/null; then
  pass "assert_relative_drop_safe accepts old=0 new=0 (first build case)"
else
  fail "assert_relative_drop_safe refused old=0 new=0"
fi

# ---- assert_relative_drop_safe — large drop refused without allow flag ----
if assert_relative_drop_safe 100 80 10 0 2>/dev/null; then
  fail "assert_relative_drop_safe accepted 20% drop without --allow-removals"
else
  pass "assert_relative_drop_safe refused 20% drop (no allow_removals flag)"
fi

# ---- assert_relative_drop_safe — large drop accepted with allow flag ----
if assert_relative_drop_safe 100 80 10 1 2>/dev/null; then
  pass "assert_relative_drop_safe accepts 20% drop when allow_removals=1"
else
  fail "assert_relative_drop_safe refused 20% drop even with allow_removals=1"
fi

# ---- assert_relative_drop_safe — within threshold passes ----
if assert_relative_drop_safe 100 95 10 0 2>/dev/null; then
  pass "assert_relative_drop_safe accepts 5% drop within 10% threshold"
else
  fail "assert_relative_drop_safe refused 5% drop (should be within threshold)"
fi

# ---- write_upstream_record round-trip ----
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
write_upstream_record "${tmp}" "test-upstream-line"
content=$(cat "${tmp}")
[ "${content}" = "test-upstream-line" ] \
  && pass "write_upstream_record round-trip" \
  || fail "write_upstream_record content mismatch (got: '${content}')"

# ---- scoped_find_delete refuses '/' ----
# Run in a subshell so the lib's `${var:?}` mandatory-arg checks don't
# abort the test runner if the function returns non-zero a different way.
if ( scoped_find_delete "/" "*.png" 2>/dev/null ); then
  fail "scoped_find_delete accepted root_dir='/'"
else
  pass "scoped_find_delete refuses root_dir='/'"
fi

# ---- scoped_find_delete refuses empty root_dir ----
# Note: the lib's `${1:?}` will exit the shell with stderr msg if root_dir
# is empty — subshell isolation captures that without killing the runner.
if ( scoped_find_delete "" "*.png" 2>/dev/null ); then
  fail "scoped_find_delete accepted empty root_dir"
else
  pass "scoped_find_delete refuses empty root_dir"
fi

# ---- scoped_find_delete silent on missing dir ----
if ( scoped_find_delete "/tmp/this-dir-definitely-does-not-exist-$$" "*.png" 2>/dev/null ); then
  pass "scoped_find_delete silent-success on missing dir"
else
  fail "scoped_find_delete failed on missing dir (expected silent success)"
fi

# ---- scoped_find_delete actually removes matching files ----
sandbox=$(mktemp -d)
mkdir -p "${sandbox}/sub"
touch "${sandbox}/a.png" "${sandbox}/sub/b.png" "${sandbox}/keep.txt"
scoped_find_delete "${sandbox}" "*.png"
remaining=$(find "${sandbox}" -name '*.png' | wc -l)
keep=$(find "${sandbox}" -name 'keep.txt' | wc -l)
rm -rf "${sandbox}"
if [ "${remaining}" -eq 0 ] && [ "${keep}" -eq 1 ]; then
  pass "scoped_find_delete removes *.png recursively, preserves other files"
else
  fail "scoped_find_delete left ${remaining} pngs (expected 0); preserved ${keep} txt (expected 1)"
fi

echo "---"
echo "Total: PASS=${PASSED} FAIL=${FAILED}"
[ "${FAILED}" -eq 0 ] || exit 1
exit 0

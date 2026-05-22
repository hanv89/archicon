#!/usr/bin/env bash
# Microsoft Azure Architecture Icons Terms-of-Use monitor.
#
# Fetches the live ToU page, greps the canonical "Icon terms" sentence
# and the three "Don'ts" directly out of the raw HTML, and diffs against
# the baseline at dist/baselines/microsoft-azure-icons-tou.txt.
#
# Raw-HTML grep (no w3m/lynx) because the Microsoft Learn page is partly
# JS-rendered; text-mode browsers see placeholder consent UI instead of
# the actual ToU text. The verbatim sentences are present in the raw
# HTML markup either way.
#
# Exit codes:
#   0 — baseline unchanged.
#   1 — baseline drifted (license re-audit owed before next icon refresh).
#   2 — environment problem (network unreachable, etc.).
#
# The drift gate is narrow: only the verbatim Microsoft permission text
# + the three Don'ts. Page chrome, TOC, "Icon updates" month-by-month
# table — all volatile, all skipped.

# set -uo pipefail (no -e): the grep -oE patterns return non-zero when a
# pattern legitimately doesn't match (which we want to detect via the
# explicit "missing pattern" check below); -e would abort the script
# before that check runs. The `|| true` pattern after each grep keeps
# the variables empty rather than crashing.
set -uo pipefail

# URL is fetch target; CANONICAL_URL is the source recorded in the
# baseline header. Tests can override URL (e.g. file://fixture.html) while
# keeping CANONICAL_URL stable so the diff against the baseline stays
# meaningful.
CANONICAL_URL="https://learn.microsoft.com/en-us/azure/architecture/icons/"
URL="${URL:-${CANONICAL_URL}}"
# Resolve BASELINE relative to the script's own location so the monitor
# works regardless of the caller's cwd (CI checks it out in any path).
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASELINE="${BASELINE:-${REPO_ROOT}/dist/baselines/microsoft-azure-icons-tou.txt}"

if [ ! -f "${BASELINE}" ]; then
  echo "FAIL: baseline missing at ${BASELINE}" >&2
  exit 2
fi

tmpfetch=$(mktemp) || exit 2
canonical=$(mktemp) || { rm -f "${tmpfetch}"; exit 2; }
trap 'rm -f "${tmpfetch}" "${canonical}"' EXIT

if ! curl -fsSL --max-time 30 "${URL}" > "${tmpfetch}" 2>/dev/null; then
  echo "FAIL: could not fetch ${URL} (exit 2)" >&2
  exit 2
fi

# Build the canonical extract directly from raw HTML. Each pattern is
# narrow enough that volatile page chrome doesn't drift it; broad enough
# that minor markup tweaks (extra spaces, attribute reorder) don't false-
# trigger.

icon_terms=$(grep -oE "Microsoft permits the use of these icons in architectural diagrams[^<]*" "${tmpfetch}" | head -1 || true)
dont_crop=$(grep -oE "Don't crop, flip, or rotate icons\." "${tmpfetch}" | head -1 || true)
dont_distort=$(grep -oE "Don't distort or change icon shape in any way\." "${tmpfetch}" | head -1 || true)
dont_use=$(grep -oE "Don't use Microsoft product icons to represent your product or service\." "${tmpfetch}" | head -1 || true)

# If ANY pattern misses (e.g. Microsoft restructured the page), treat as
# baseline drift — manual triage required regardless.
if [ -z "${icon_terms}" ] || [ -z "${dont_crop}" ] || [ -z "${dont_distort}" ] || [ -z "${dont_use}" ]; then
  echo "FAIL: one or more ToU patterns missing from live HTML (page structure changed?)" >&2
  echo "  icon_terms:   $( [ -n "${icon_terms}" ] && echo found || echo missing )" >&2
  echo "  dont_crop:    $( [ -n "${dont_crop}" ] && echo found || echo missing )" >&2
  echo "  dont_distort: $( [ -n "${dont_distort}" ] && echo found || echo missing )" >&2
  echo "  dont_use:     $( [ -n "${dont_use}" ] && echo found || echo missing )" >&2
  exit 1
fi

{
  printf '# Canonical extract of the Microsoft Azure Architecture Icons Terms of Use.\n'
  printf '# Source: %s\n' "${CANONICAL_URL}"
  printf '# Captured: 2026-05-11.\n'
  printf '# This file is the baseline that scripts/monitor_ms_tou.sh diffs against.\n'
  printf '# If the upstream ToU changes, the monitor fails, an issue is opened, and\n'
  printf '# a license re-audit is owed before the next icon refresh.\n'
  printf '\n'
  printf '[ICON TERMS]\n'
  printf '%s\n' "${icon_terms}"
  printf '\n'
  printf "[DON'TS]\n"
  printf '%s\n' "${dont_crop}"
  printf '%s\n' "${dont_distort}"
  printf '%s\n' "${dont_use}"
} > "${canonical}"

if diff -u "${BASELINE}" "${canonical}" >/dev/null 2>&1; then
  echo "PASS: Microsoft Azure Icons ToU baseline unchanged"
  exit 0
fi

echo "FAIL: Microsoft Azure Icons ToU baseline drifted" >&2
echo "--- baseline (${BASELINE}) +++ live (${URL})" >&2
diff -u "${BASELINE}" "${canonical}" | head -40 >&2
exit 1

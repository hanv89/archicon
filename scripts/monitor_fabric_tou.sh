#!/usr/bin/env bash
# Microsoft Fabric Icons Terms-of-Use monitor.
#
# Fetches the live Fabric icon ToU page, greps the canonical "Icon terms"
# sentence and the three "Don'ts" directly out of the raw HTML, and diffs
# against the baseline at dist/baselines/microsoft-fabric-icons-tou.txt.
#
# Modelled on `monitor_ms_tou.sh` (Azure ToU monitor). Both Microsoft ToU
# pages carry identical Don'ts text; Fabric adds an extra sentence pointing
# at the @fabric-msft/svg-icons npm package. The "Icon terms" pattern is
# narrowed to the first sentence so the Fabric-specific npm-pointer doesn't
# false-trigger drift.
#
# Exit codes:
#   0 — baseline unchanged.
#   1 — baseline drifted (license re-audit owed before next icon refresh).
#   2 — environment problem (network unreachable, etc.).

set -uo pipefail

CANONICAL_URL="https://learn.microsoft.com/en-us/fabric/fundamentals/icons"
URL="${URL:-${CANONICAL_URL}}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASELINE="${BASELINE:-${REPO_ROOT}/dist/baselines/microsoft-fabric-icons-tou.txt}"

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

# Narrow patterns: each captures a single sentence ending in `.`. The
# Fabric "Icon terms" paragraph continues with an npm-package pointer
# (`Fabric icons are also available as a ...`) which is content-volatile
# (npm version changes), so we cut the canonical extract at the first
# sentence boundary.
icon_terms=$(grep -oE "Microsoft permits the use of these icons in architectural diagrams[^.]*\." "${tmpfetch}" | head -1 || true)
dont_crop=$(grep -oE "Don't crop, flip, or rotate icons\." "${tmpfetch}" | head -1 || true)
dont_distort=$(grep -oE "Don't distort or change icon shape in any way\." "${tmpfetch}" | head -1 || true)
dont_use=$(grep -oE "Don't use Microsoft product icons to represent your product or service\." "${tmpfetch}" | head -1 || true)

if [ -z "${icon_terms}" ] || [ -z "${dont_crop}" ] || [ -z "${dont_distort}" ] || [ -z "${dont_use}" ]; then
  echo "FAIL: one or more Fabric ToU patterns missing from live HTML (page structure changed?)" >&2
  echo "  icon_terms:   $( [ -n "${icon_terms}" ] && echo found || echo missing )" >&2
  echo "  dont_crop:    $( [ -n "${dont_crop}" ] && echo found || echo missing )" >&2
  echo "  dont_distort: $( [ -n "${dont_distort}" ] && echo found || echo missing )" >&2
  echo "  dont_use:     $( [ -n "${dont_use}" ] && echo found || echo missing )" >&2
  exit 1
fi

{
  printf '# Canonical extract of the Microsoft Fabric Icons Terms of Use.\n'
  printf '# Source: %s\n' "${CANONICAL_URL}"
  printf '# Captured: 2026-05-19.\n'
  printf '# This file is the baseline that scripts/monitor_fabric_tou.sh diffs against.\n'
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
  echo "PASS: Microsoft Fabric Icons ToU baseline unchanged"
  exit 0
fi

echo "FAIL: Microsoft Fabric Icons ToU baseline drifted" >&2
echo "--- baseline (${BASELINE}) +++ live (${URL})" >&2
diff -u "${BASELINE}" "${canonical}" | head -40 >&2
exit 1

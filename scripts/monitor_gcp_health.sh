#!/usr/bin/env bash
# Google Cloud icon-pack drift monitor.
#
# Google ships its product icons as a single static ZIP behind a fixed URL
# (no git ref to pin). build_gcp.sh records the ZIP's sha256 in
# dist/GCP/UPSTREAM-SHA.txt. This monitor re-fetches the ZIP, recomputes its
# sha256, and diffs against that recorded baseline. A drift means upstream
# re-published the pack — a refresh + license/brand re-audit is owed before
# the next icon refresh, so the cron short-circuits and a watchdog issue is
# opened (mirroring the other per-vendor monitors).
#
# Modelled structurally on `monitor_fabric_tou.sh` (fetch live source → derive
# a canonical value → diff against the recorded baseline → 0/1/2 exit codes).
# Here the "canonical value" is the ZIP content hash rather than ToU prose.
#
# Exit codes:
#   0 — ZIP sha256 unchanged (baseline matches).
#   1 — ZIP sha256 drifted (re-audit owed before next refresh).
#   2 — environment problem (network unreachable, baseline missing, etc.).

set -uo pipefail

CANONICAL_URL="https://services.google.com/fh/files/misc/core-products-icons.zip"
URL="${URL:-${CANONICAL_URL}}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASELINE="${BASELINE:-${REPO_ROOT}/dist/GCP/UPSTREAM-SHA.txt}"

command -v curl       >/dev/null 2>&1 || { echo "FAIL: curl required" >&2; exit 2; }
command -v sha256sum  >/dev/null 2>&1 || { echo "FAIL: sha256sum required" >&2; exit 2; }

if [ ! -f "${BASELINE}" ]; then
  echo "FAIL: baseline missing at ${BASELINE} (run build_gcp.sh first)" >&2
  exit 2
fi

recorded="$(head -1 "${BASELINE}" | tr -d '[:space:]')"
if [ -z "${recorded}" ]; then
  echo "FAIL: baseline ${BASELINE} is empty" >&2
  exit 2
fi

tmpzip=$(mktemp) || exit 2
trap 'rm -f "${tmpzip}"' EXIT

if ! curl -fsSL --max-time 120 "${URL}" > "${tmpzip}" 2>/dev/null; then
  echo "FAIL: could not fetch ${URL} (exit 2)" >&2
  exit 2
fi

# Defend against an HTML error page returned with a 200.
case "$(head -c 2 "${tmpzip}")" in
  PK) : ;;
  *)  echo "FAIL: fetched content is not a ZIP (missing PK magic) — upstream URL may have changed" >&2; exit 2 ;;
esac

live="$(sha256sum "${tmpzip}" | awk '{print $1}')"

if [ "${live}" = "${recorded}" ]; then
  echo "PASS: Google Cloud icon-pack ZIP sha256 unchanged (${recorded})"
  exit 0
fi

echo "FAIL: Google Cloud icon-pack ZIP sha256 drifted" >&2
echo "  recorded (${BASELINE}): ${recorded}" >&2
echo "  live     (${URL}): ${live}" >&2
echo "Re-audit the pack contents + brand guidelines, then re-run build_gcp.sh." >&2
exit 1

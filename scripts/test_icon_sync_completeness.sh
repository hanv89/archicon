#!/usr/bin/env bash
# Assert the upstream -> dist/ icon sync is COMPLETE (offline).
#
# A build that silently drops icons ships an incomplete set with no other
# automated catch — the gap only surfaces when a user references a missing
# icon and gets a broken render. This gate reconciles the shipped dist/
# tree against the source of truth for each vendor:
#
#   - Curation-driven vendors (the curation fixture IS the contract):
#       Devicon  — every stem -> dist/Devicon/png/<stem>-original_48.png
#       FluentUI — every concept (normalized `tr 'A-Z ' 'a-z_'`, mirroring
#                  build_fluentui_system.sh) -> dist/FluentUI/png/<stem>_{24,32,48}_color.png
#   - Full-copy vendors (no curation list): Azure / Fabric / Kubernetes
#       count >= the recorded floor in scripts/fixtures/expected-icon-counts.tsv
#       (>= so a legit cron-driven upstream addition does not fail the gate;
#        a partial-sync regression with fewer files does).
#   - Global: no zero-byte PNG anywhere under dist/.
#
# NOT in scope (network-dependent, owned by update-icons.yml cron):
#   detecting icons that upstream NOW offers but dist/ is missing.
#
# Exit codes:
#   0 — sync complete across all vendors.
#   1 — a missing curated icon, a short-count vendor, or a zero-byte PNG.
#   2 — environment problem (fixtures absent).
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

DEVICON_CUR="scripts/fixtures/devicon-curation.txt"
FLUENTUI_CUR="scripts/fixtures/fluentui-curation.txt"
COUNTS_TSV="scripts/fixtures/expected-icon-counts.tsv"
[ -f "${DEVICON_CUR}" ]  || { echo "ERROR: ${DEVICON_CUR} missing"  >&2; exit 2; }
[ -f "${FLUENTUI_CUR}" ] || { echo "ERROR: ${FLUENTUI_CUR} missing" >&2; exit 2; }
[ -f "${COUNTS_TSV}" ]   || { echo "ERROR: ${COUNTS_TSV} missing"   >&2; exit 2; }

FAILED=0
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

# Non-comment, non-blank lines of a fixture.
cur_lines() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$1"; }

# --- Devicon: 1 PNG per curated stem ---
dev_total=0 dev_miss=0
while IFS= read -r stem; do
  [ -n "${stem}" ] || continue
  dev_total=$(( dev_total + 1 ))
  f="dist/Devicon/png/${stem}-original_48.png"
  [ -f "${f}" ] || { fail "Devicon curated stem has no PNG: ${stem} (${f})"; dev_miss=$(( dev_miss + 1 )); }
done < <(cur_lines "${DEVICON_CUR}")
[ "${dev_miss}" -eq 0 ] && echo "PASS  Devicon: all ${dev_total} curated stems present."

# --- FluentUI: 3 sizes per curated concept ---
fui_total=0 fui_miss=0
for sz in 24 32 48; do :; done
while IFS= read -r concept; do
  [ -n "${concept}" ] || continue
  fui_total=$(( fui_total + 1 ))
  stem="$(printf '%s' "${concept}" | tr 'A-Z ' 'a-z_')"
  for sz in 24 32 48; do
    f="dist/FluentUI/png/${stem}_${sz}_color.png"
    [ -f "${f}" ] || { fail "FluentUI curated concept missing size: '${concept}' -> ${f}"; fui_miss=$(( fui_miss + 1 )); }
  done
done < <(cur_lines "${FLUENTUI_CUR}")
[ "${fui_miss}" -eq 0 ] && echo "PASS  FluentUI: all ${fui_total} curated concepts present at 3 sizes ($(( fui_total * 3 )) PNGs)."

# --- Full-copy vendors: count floor ---
while IFS=$'\t' read -r vendor mincount; do
  case "${vendor}" in ''|\#*) continue;; esac
  [ -d "dist/${vendor}" ] || { fail "expected vendor dir missing: dist/${vendor}"; continue; }
  actual="$(find "dist/${vendor}" -name '*.png' | wc -l | tr -d ' ')"
  if [ "${actual}" -lt "${mincount}" ]; then
    fail "${vendor}: ${actual} PNG(s) < expected floor ${mincount} (partial sync?)"
  else
    echo "PASS  ${vendor}: ${actual} PNG(s) >= floor ${mincount}."
  fi
done < "${COUNTS_TSV}"

# --- Global: no zero-byte PNGs ---
mapfile -t zerobyte < <(find dist -name '*.png' -size 0)
if [ "${#zerobyte[@]}" -gt 0 ]; then
  for z in "${zerobyte[@]}"; do fail "zero-byte PNG: ${z}"; done
else
  echo "PASS  no zero-byte PNGs under dist/."
fi

if [ "${FAILED}" -eq 0 ]; then
  echo "PASS  upstream->dist sync is complete across all vendors."
  exit 0
fi
echo "test_icon_sync_completeness: ${FAILED} failure(s)." >&2
exit 1

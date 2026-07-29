#!/usr/bin/env bash
# Render a Mermaid .mmd (icon mode) to PNG with the vendor icons visible.
#
# Bundles the three things mermaid-cli needs that are not obvious:
#   - htmlLabels:true + securityLevel:loose  (so inline <img> labels render)
#   - puppeteer --no-sandbox                 (Ubuntu 23.10+ blocks unprivileged
#                                             user namespaces -> Chromium crashes
#                                             with "No usable sandbox!" without it)
#   - the canonical icon.css                 (object-fit + uniform size + wrap)
#
# SECURITY: --no-sandbox + securityLevel:loose are accepted ONLY because the
# .mmd here is author-controlled. Do NOT render untrusted Mermaid with these.
#
# Usage:  ./render-mermaid.sh <input.mmd> [output.png]
set -euo pipefail

IN="${1:?usage: render-mermaid.sh <input.mmd> [output.png]}"
OUT="${2:-${IN%.mmd}.png}"
HERE="$(cd "$(dirname "$0")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
printf '%s' '{"flowchart":{"htmlLabels":true},"securityLevel":"loose"}' > "${TMP}/mmcfg.json"
printf '%s' '{"args":["--no-sandbox","--disable-setuid-sandbox"]}'       > "${TMP}/pptr.json"

npx -y @mermaid-js/mermaid-cli@latest \
  -i "${IN}" -o "${OUT}" -b white \
  -c "${TMP}/mmcfg.json" -p "${TMP}/pptr.json" -C "${HERE}/icon.css" \
  --width 2600

echo "rendered ${OUT}"

#!/usr/bin/env bash
# Reproducible Google Cloud product-icon build (full set of the official
# "Core products" icon pack).
# Source: Official Google Cloud Icon Library, distributed as a static ZIP
#   https://services.google.com/fh/files/misc/core-products-icons.zip
# Idempotent: safe to re-run.
#
# Unlike the other vendors (git-cloned upstreams), Google ships its product
# icons as a single versioned ZIP behind a static URL — there is no git ref to
# pin. We therefore pin on the ZIP's sha256 (recorded in
# dist/GCP/UPSTREAM-SHA.txt) instead of a commit SHA. monitor_gcp_health.sh
# re-fetches the ZIP and alerts if that hash drifts.
#
# Brand-guidelines / trademark note (reference-use, NOT no-derivatives):
#   Google permits these product icons to accurately reference Google's
#   technology in architecture diagrams. The brand guidelines forbid
#   distortion, recolor and crop, but DO permit uniform (proportional)
#   scaling. This build therefore converts each SVG to PNG at a UNIFORM
#   square size only (width == height); a non-uniform raster would distort
#   the glyph and breach the guidelines. See dist/GCP/USAGE-RULES.txt and
#   the NOTICE § Google Cloud Icons.
#
# Exit codes:
#   0 — success (PNG set refreshed, UPSTREAM-SHA.txt updated).
#   1 — build failure or refused content drop (use --allow-removals to override).
#   2 — environment problem (curl / unzip / rsvg-convert / network missing).
#
# Inherits the build-script hardening pattern (shared via _lib_icon_build.sh):
#   - Relative-drop threshold (10% default) refuses to shrink the PNG set
#     unless --allow-removals.
#   - --allow-removals CLI flag (or ALLOW_REMOVALS=1 env) bypasses it.
#   - LC_ALL=C export for deterministic sort + find order.
#   - UPSTREAM-SHA.txt persisted under dist/GCP/ for release-notes traceability.
#   - Structured 0/1/2 exit codes.
#   - Scoped find -delete (-name *.png -delete) preserves .gitkeep.
#
# Scope:
#   Every product directory inside the ZIP's "Unique Icons/<Product>/SVG/"
#   tree ships exactly one color SVG. We flatten to a per-product PNG under
#   dist/GCP/png/<stem>.png where <stem> is a sanitized PascalCase product
#   key (derived from the product directory name, NOT the inconsistent SVG
#   filename). Expected count == number of product dirs (~19 in the v1 pack).
#
# Layout produced (flat, one PNG per product):
#   dist/GCP/png/GKE.png
#   dist/GCP/png/BigQuery.png
#   dist/GCP/png/CloudStorage.png
#   ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_lib_icon_build.sh"
set_locale_deterministic

# ---- CLI arg parse ----
ALLOW_REMOVALS="${ALLOW_REMOVALS:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-removals) ALLOW_REMOVALS=1; shift ;;
    -h|--help)
      grep -E '^# (Exit|  |Reproducible|Idempotent|Inherits|Scope|Layout|Brand|Source|Unlike)' "$0" >&2
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SOURCE_DIR / DIST_DIR / record path are overridable via env so the build
# logic can be unit-tested against a synthetic fixture tree (BUILD_SELFTEST=1
# skips the network download + count floor). Production defaults unchanged.
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/GCP/png}"
UPSTREAM_RECORD="${BUILD_UPSTREAM_RECORD:-${REPO_ROOT}/dist/GCP/UPSTREAM-SHA.txt}"
SELFTEST="${BUILD_SELFTEST:-0}"
UPSTREAM_URL="${UPSTREAM_URL:-https://services.google.com/fh/files/misc/core-products-icons.zip}"
# In self-test the caller pre-populates an extracted SVG tree here; in
# production we download + unzip into a private temp dir.
SOURCE_DIR="${BUILD_SOURCE_DIR:-}"
# Uniform raster size (px). Square only — width == height — to preserve the
# glyph aspect ratio per Google's brand guidelines. Override via env for tests.
SIZE="${BUILD_SIZE:-64}"

# ---- Uniform-scale assertion (defensive: the only place the size is wired
#      into rsvg-convert is via $W and $H below; assert they are equal here so
#      a future edit that introduces a non-uniform size fails loudly). ----
W="${SIZE}"
H="${SIZE}"
if [ "${W}" != "${H}" ]; then
  echo "ERROR: refusing non-uniform raster size (-w ${W} != -h ${H}). Google brand guidelines permit proportional scaling only." >&2
  exit 1
fi

# ---- Tooling probe ----
command -v rsvg-convert >/dev/null 2>&1 || { echo "ERROR: rsvg-convert not installed (apt install librsvg2-bin)" >&2; exit 2; }
command -v sha256sum    >/dev/null 2>&1 || { echo "ERROR: sha256sum not installed" >&2; exit 2; }
if [ "${SELFTEST}" != "1" ]; then
  command -v curl  >/dev/null 2>&1 || { echo "ERROR: curl not installed"  >&2; exit 2; }
  command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip not installed" >&2; exit 2; }
fi

TMPDIR_BUILD=""
cleanup() { [ -n "${TMPDIR_BUILD}" ] && rm -rf "${TMPDIR_BUILD}"; }
trap cleanup EXIT

# ---- 1. Acquire source ----
if [ "${SELFTEST}" = "1" ]; then
  [ -n "${SOURCE_DIR}" ] || { echo "ERROR: BUILD_SELFTEST=1 requires BUILD_SOURCE_DIR" >&2; exit 2; }
  ZIP_SHA="selftest"
  echo "SELFTEST: using pre-populated SOURCE_DIR=${SOURCE_DIR} (no download)"
else
  TMPDIR_BUILD="$(mktemp -d)"
  ZIP_PATH="${TMPDIR_BUILD}/core-products-icons.zip"
  echo "Downloading ${UPSTREAM_URL}..."
  curl -fsSL --max-time 120 -o "${ZIP_PATH}" "${UPSTREAM_URL}" || {
    echo "ERROR: download failed from ${UPSTREAM_URL}" >&2; exit 2
  }
  # Verify it is actually a ZIP (defends against an HTML error page slipping
  # through with a 200).
  case "$(head -c 2 "${ZIP_PATH}")" in
    PK) : ;;
    *)  echo "ERROR: downloaded file is not a ZIP (missing PK magic) — upstream may have changed" >&2; exit 2 ;;
  esac
  ZIP_SHA="$(sha256sum "${ZIP_PATH}" | awk '{print $1}')"
  echo "Source ZIP sha256: ${ZIP_SHA}"
  SOURCE_DIR="${TMPDIR_BUILD}/extracted"
  mkdir -p "${SOURCE_DIR}"
  unzip -q "${ZIP_PATH}" -d "${SOURCE_DIR}" || { echo "ERROR: unzip failed" >&2; exit 2; }
fi

# ---- 2. Enumerate product SVGs ----
# Each product dir holds exactly one color SVG under .../SVG/. We key on the
# product directory NAME (stable, human-meaningful) and sanitize it into a
# PascalCase stem, ignoring the noisy per-file naming (e.g. -512-color-rgb).
declare -a JOBS=()
declare -a SEEN_STEMS=()
while IFS= read -r svg; do
  [ -n "${svg}" ] || continue
  # product dir = parent of the SVG/ dir
  product_dir="$(dirname "$(dirname "${svg}")")"
  product="$(basename "${product_dir}")"
  # Sanitize: drop spaces -> PascalCase-ish stem; keep existing capitalization.
  # "Cloud Storage" -> "CloudStorage"; "GKE" -> "GKE"; "Vertex AI" -> "VertexAI".
  stem="$(printf '%s' "${product}" | sed -E 's/[^A-Za-z0-9 ]//g' | awk '{ for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2) } OFS=""; $1=$1; print }')"
  if [ -z "${stem}" ]; then
    echo "ERROR: empty stem derived from product dir '${product}'" >&2; exit 1
  fi
  # Guard against collisions.
  for s in "${SEEN_STEMS[@]:-}"; do
    if [ "${s}" = "${stem}" ]; then
      echo "ERROR: duplicate stem '${stem}' (product '${product}') — refine sanitization" >&2; exit 1
    fi
  done
  SEEN_STEMS+=("${stem}")
  JOBS+=("${svg}|${stem}")
done < <(find "${SOURCE_DIR}" -name '*.svg' -type f | sort)

NEW_COUNT="${#JOBS[@]}"
if [ "${NEW_COUNT}" -eq 0 ]; then
  echo "ERROR: no SVGs found under ${SOURCE_DIR} (zip layout changed?)" >&2; exit 1
fi

# ---- 3. Drop-threshold gate ----
mkdir -p "${DIST_DIR}"
OLD_COUNT="$(find "${DIST_DIR}" -name '*.png' 2>/dev/null | wc -l)"
echo "Counts: old=${OLD_COUNT} new=${NEW_COUNT}"
assert_relative_drop_safe "${OLD_COUNT}" "${NEW_COUNT}" 10 "${ALLOW_REMOVALS}"

# ---- 4. Scoped clean ----
echo "Cleaning ${DIST_DIR}/*.png..."
scoped_find_delete "${DIST_DIR}" '*.png'

# ---- 5. SVG -> PNG (UNIFORM square only; -w == -h asserted above) ----
echo "Converting ${NEW_COUNT} SVGs at ${W}x${H} (uniform)..."
for job in "${JOBS[@]}"; do
  IFS='|' read -r svg stem <<< "${job}"
  rsvg-convert -w "${W}" -h "${H}" -o "${DIST_DIR}/${stem}.png" "${svg}" || {
    echo "ERROR: rsvg-convert failed on ${svg}" >&2; exit 1
  }
done

# ---- 6. Persist UPSTREAM-SHA.txt (ZIP content hash, not a git ref) ----
write_upstream_record "${UPSTREAM_RECORD}" "${ZIP_SHA}"

# ---- 7. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 15 ]; then
  echo "ERROR: count < 15, aborting (expected ~19 products in the core pack)" >&2
  exit 1
fi

# ---- 8. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;$p'

echo "OK · gcp zip_sha256=${ZIP_SHA} count=${COUNT} size=${W}x${H}"

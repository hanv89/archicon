#!/usr/bin/env bash
# Reproducible Microsoft Fabric icon build (Variant B — @fabric-msft/svg-icons
# npm upstream, Microsoft first-party MIT).
# Idempotent: safe to re-run.
#
# Exit codes:
#   0 — success (PNG set refreshed, UPSTREAM-VERSION.txt updated).
#   1 — build failure or refused content drop (use --allow-removals to override).
#   2 — environment problem (rsvg-convert / npm / network missing, etc.).
#
# Inherits the same hardenings as build_azure.sh:
#   (a) Upstream version auto-detected via `npm view @fabric-msft/svg-icons version`.
#       Allow FABRIC_VERSION env override.
#   (b) Relative-drop threshold: refuse if (OLD - NEW) > OLD * 10% unless
#       --allow-removals.
#   (c) --allow-removals CLI flag (or ALLOW_REMOVALS=1 env) bypasses the gate.
#   (d) LC_ALL=C export at script top for deterministic sort + find order.
#   (e) UPSTREAM-VERSION.txt persisted under dist/Fabric/ for release-notes traceability.
#       Format: single line `@fabric-msft/svg-icons@<semver>`.
#   (f) Structured 0/1/2 exit codes matching smoke_urls.sh / smoke_e2e.sh.
#   (g) Scoped find -delete ('-name *.png -delete') preserves USAGE-RULES.txt.
#
# Scope (post-v0.2.1 widening):
#
# Pass 1 — per-artifact icons at size 40 ("_item" family, 65 icons):
#   *_40_item.svg     — primary item icons (Lakehouse, Pipeline, Notebook, ...)
#   *_40_non-item.svg — secondary forms (Folder, GroupWorkspace, MyWorkspace,
#                       AddPipeline, ImportNotebook, Sample, EventHouse-alt)
#   *_40.svg          — special-form services with no _item suffix
#                       (graph_model, graph_queryset)
#   mirrored_catalog: downscaled from upstream _48_item to 40x40.
#
# Pass 2 — sizes 24, 28, 32, 48 across all suffix families (~247 icons added v0.2.2):
#   *_{24,28,32,48}_item.svg
#   *_{24,28,32,48}_non-item.svg
#   *_{24,28,32,48}_color.svg
#   *_{24,28,32,48}.svg                  (plain — graph_model, graph_queryset)
#   Each PNG sized to match its filename (24/28/32/48). Upstream filenames
#   preserved (e.g. fabric_48_color.svg -> fabric_48_color.png).
#   Sample_workload skipped (only ships at _32_color, placeholder).
#
# Out of scope: 565 _regular + 564 _filled (generic UI affordances), smaller
# _color sizes (16/20 — too small for architecture diagrams), size 64+
# (Microsoft Fabric guidance reserves 64 for nav/dock use).
#
# Total: ~312 icons at @fabric-msft/svg-icons@7.0.1.

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
      grep -E '^# (Exit|  |Reproducible|Idempotent|Inherits|Scope)' "$0" >&2
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SOURCE_DIR / DIST_DIR / SVG_DIR / record path are overridable via env so the
# two-pass size-selection logic can be unit-tested against a synthetic fixture
# SVG dir (BUILD_SELFTEST=1 skips the npm install + version/license probe +
# count floor). Production defaults are unchanged.
SOURCE_DIR="${BUILD_SOURCE_DIR:-${REPO_ROOT}/source/fabric-svg-icons}"
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/Fabric/png}"
UPSTREAM_RECORD="${BUILD_UPSTREAM_RECORD:-${REPO_ROOT}/dist/Fabric/UPSTREAM-VERSION.txt}"
SELFTEST="${BUILD_SELFTEST:-0}"
NPM_PKG="@fabric-msft/svg-icons"

# ---- Tooling probe ----
command -v rsvg-convert >/dev/null 2>&1 || { echo "ERROR: rsvg-convert not installed (apt install librsvg2-bin)" >&2; exit 2; }

if [ "${SELFTEST}" = "1" ]; then
  # Self-test: SVG_DIR is pre-populated via BUILD_SVG_DIR; skip npm + probes.
  FABRIC_VERSION="selftest"
  SVG_DIR="${BUILD_SVG_DIR:?BUILD_SVG_DIR required in selftest}"
  [ -d "${SVG_DIR}" ] || { echo "ERROR: BUILD_SVG_DIR not a dir: ${SVG_DIR}" >&2; exit 2; }
  echo "SELFTEST: using pre-populated SVG_DIR=${SVG_DIR} (no npm install)"
  mkdir -p "${DIST_DIR}"
else
  command -v npm          >/dev/null 2>&1 || { echo "ERROR: npm not installed" >&2; exit 2; }

  # ---- Upstream version auto-detect (item a) ----
  FABRIC_VERSION="${FABRIC_VERSION:-}"
  if [ -z "${FABRIC_VERSION}" ]; then
    FABRIC_VERSION=$(npm view "${NPM_PKG}" version 2>/dev/null | tail -1)
  fi
  if [ -z "${FABRIC_VERSION}" ]; then
    echo "ERROR: cannot detect ${NPM_PKG} version from npm registry" >&2
    exit 2
  fi
  echo "Upstream: ${NPM_PKG}@${FABRIC_VERSION}"

  # ---- MIT license re-verification gate (re-checked every build) ----
  LICENSE=$(npm view "${NPM_PKG}@${FABRIC_VERSION}" license 2>/dev/null | tail -1)
  if [ "${LICENSE}" != "MIT" ]; then
    echo "ERROR: ${NPM_PKG}@${FABRIC_VERSION} license is '${LICENSE}', expected MIT" >&2
    exit 2
  fi
  echo "License: ${LICENSE} (gate satisfied)"

  # ---- 1. npm install into isolated source dir ----
  mkdir -p "${SOURCE_DIR}"
  echo "Installing ${NPM_PKG}@${FABRIC_VERSION} into ${SOURCE_DIR}..."
  ( cd "${SOURCE_DIR}" && npm install --no-package-lock --no-save --silent "${NPM_PKG}@${FABRIC_VERSION}" ) || {
    echo "ERROR: npm install failed" >&2; exit 2;
  }
  SVG_DIR="${SOURCE_DIR}/node_modules/${NPM_PKG}/dist/svg"
  [ -d "${SVG_DIR}" ] || { echo "ERROR: expected SVG dir not found at ${SVG_DIR}" >&2; exit 2; }
fi

# ---- 2. Build the conversion list (Pass 1 + Pass 2) ----
mkdir -p "${DIST_DIR}"
OLD_COUNT="$(find "${DIST_DIR}" -name '*.png' 2>/dev/null | wc -l)"

# Pass 1 — per-artifact icons at size 40.
PASS1_LIST=$(find "${SVG_DIR}" \
  \( -name '*_40_item.svg' -o -name '*_40_non-item.svg' -o -name '*_40.svg' \) \
  | sort)
MIRRORED_SRC="${SVG_DIR}/mirrored_catalog_48_item.svg"
if [ -f "${MIRRORED_SRC}" ]; then
  PASS1_LIST="${PASS1_LIST}
${MIRRORED_SRC}"
fi
PASS1_COUNT=$(echo "${PASS1_LIST}" | grep -c '\.svg$' || true)

# Pass 2 — sizes 24/28/32/48 across all suffix families (_item, _non-item,
# _color, plain). Each PNG sized to match its filename. Skip sample_workload
# (placeholder).
PASS2_LIST=$(find "${SVG_DIR}" \
  \(    -name '*_24_item.svg'     -o -name '*_24_non-item.svg' \
     -o -name '*_24_color.svg'    -o -name '*_24.svg' \
     -o -name '*_28_item.svg'     -o -name '*_28_non-item.svg' \
     -o -name '*_28_color.svg'    -o -name '*_28.svg' \
     -o -name '*_32_item.svg'     -o -name '*_32_non-item.svg' \
     -o -name '*_32_color.svg'    -o -name '*_32.svg' \
     -o -name '*_48_item.svg'     -o -name '*_48_non-item.svg' \
     -o -name '*_48_color.svg'    -o -name '*_48.svg' \) \
  ! -name 'sample_workload_*' \
  | sort)
PASS2_COUNT=$(echo "${PASS2_LIST}" | grep -c '\.svg$' || true)

NEW_COUNT=$(( PASS1_COUNT + PASS2_COUNT ))
echo "Counts: old=${OLD_COUNT} new=${NEW_COUNT} (pass1=${PASS1_COUNT} pass2=${PASS2_COUNT})"

assert_relative_drop_safe "${OLD_COUNT}" "${NEW_COUNT}" 10 "${ALLOW_REMOVALS}"

# ---- 3. Scoped clean (item g) ----
echo "Cleaning ${DIST_DIR}/*.png..."
scoped_find_delete "${DIST_DIR}" '*.png'

# ---- 4a. Pass 1 — SVG -> PNG at 40x40 (item / non-item / plain _40) ----
echo "Pass 1: converting ${PASS1_COUNT} per-artifact SVGs at 40x40..."
CONVERTED=0
while IFS= read -r SVG; do
  [ -n "${SVG}" ] || continue
  NAME=$(basename "${SVG}" .svg)
  # mirrored_catalog has no _40 size upstream — downscale from 48 and rename.
  if [ "${NAME}" = "mirrored_catalog_48_item" ]; then
    NAME="mirrored_catalog_40_item"
  fi
  rsvg-convert -w 40 -h 40 -o "${DIST_DIR}/${NAME}.png" "${SVG}" || {
    echo "ERROR: rsvg-convert failed on ${SVG}" >&2; exit 1;
  }
  CONVERTED=$(( CONVERTED + 1 ))
done <<< "${PASS1_LIST}"

# ---- 4b. Pass 2 — SVG -> PNG at native filename size (24/28/32/48 across all suffixes) ----
echo "Pass 2: converting ${PASS2_COUNT} multi-size SVGs at native size..."
while IFS= read -r SVG; do
  [ -n "${SVG}" ] || continue
  NAME=$(basename "${SVG}" .svg)
  # SIZE extracted from filename (e.g. fabric_48_color -> 48, lakehouse_32_item -> 32,
  # graph_model_24 -> 24). Match either trailing _N or _N_<suffix>.
  SIZE=$(echo "${NAME}" | grep -oE '_(24|28|32|48)(_[a-z-]+)?$' | grep -oE '(24|28|32|48)' | head -1)
  rsvg-convert -w "${SIZE}" -h "${SIZE}" -o "${DIST_DIR}/${NAME}.png" "${SVG}" || {
    echo "ERROR: rsvg-convert failed on ${SVG}" >&2; exit 1;
  }
  CONVERTED=$(( CONVERTED + 1 ))
done <<< "${PASS2_LIST}"

echo "Converted: ${CONVERTED}"

# ---- 5. Persist UPSTREAM-VERSION.txt (item e) ----
write_upstream_record "${UPSTREAM_RECORD}" "${NPM_PKG}@${FABRIC_VERSION}"

# ---- 6. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 250 ]; then
  echo "ERROR: count < 250, aborting (expected ~312 Fabric icons across sizes 24/28/32/40/48)" >&2
  exit 1
fi

# ---- 7. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;25p;$p'

echo "OK · upstream=${NPM_PKG}@${FABRIC_VERSION} count=${COUNT}"

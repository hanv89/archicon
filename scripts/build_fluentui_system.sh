#!/usr/bin/env bash
# Reproducible Microsoft Fluent UI System Icons build (curated subset).
# Source: microsoft/fluentui-system-icons (Microsoft first-party MIT —
# same evidence chain as Fabric per the parent precedent).
# Idempotent: safe to re-run.
#
# Exit codes:
#   0 — success (PNG set refreshed, UPSTREAM-SHA.txt updated).
#   1 — build failure or refused content drop (use --allow-removals to override).
#   2 — environment problem (git / rsvg-convert / network missing, etc.).
#
# Inherits the 7-item build-script hardening pattern (consolidated in
# _lib_icon_build.sh):
#   (a) Upstream branch auto-detect via `git ls-remote --symref HEAD`.
#       Allow UPSTREAM_BRANCH env override.
#   (b) Relative-drop threshold (10% default) refuses to shrink the PNG
#       set unless --allow-removals.
#   (c) --allow-removals CLI flag (or ALLOW_REMOVALS=1 env) bypasses (b).
#   (d) LC_ALL=C export for deterministic sort + find order.
#   (e) UPSTREAM-SHA.txt persisted under dist/FluentUI/ for release-notes
#       traceability.
#   (f) Structured 0/1/2 exit codes matching smoke_urls.sh / smoke_e2e.sh.
#   (g) Scoped find -delete (-name *.png -delete) preserves .gitkeep.
#
# Scope:
#   Reads scripts/fixtures/fluentui-curation.txt (one concept name per
#   line, matching upstream `assets/<Concept>/SVG/` dir name). For each
#   concept, converts the `_color` variant SVG at sizes 24, 32, 48 into
#   PNGs under dist/FluentUI/png/<stem>_<size>_color.png (flat layout,
#   mirroring Fabric's scheme).
#   Expected count: curation_lines × 3 PNGs (~75 with the v1 curation).
#
# Out of scope: `_regular` / `_filled` variants (off-style alternatives),
# sizes other than 24/32/48, concepts that don't ship `_color` at all 3
# sizes (curation list is the authoritative scope).

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
# SOURCE_DIR / DIST_DIR / CURATION_LIST / record path are overridable via env
# so the build logic can be unit-tested against a synthetic fixture upstream
# tree (BUILD_SELFTEST=1 skips the network clone + count floor). Production
# defaults are unchanged.
SOURCE_DIR="${BUILD_SOURCE_DIR:-${REPO_ROOT}/source/fluentui-system-icons}"
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/FluentUI/png}"
CURATION_LIST="${BUILD_CURATION_LIST:-${REPO_ROOT}/scripts/fixtures/fluentui-curation.txt}"
UPSTREAM_RECORD="${BUILD_UPSTREAM_RECORD:-${REPO_ROOT}/dist/FluentUI/UPSTREAM-SHA.txt}"
SELFTEST="${BUILD_SELFTEST:-0}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/microsoft/fluentui-system-icons.git}"
SIZES=(24 32 48)

# ---- Tooling probe ----
command -v git           >/dev/null 2>&1 || { echo "ERROR: git not installed" >&2; exit 2; }
command -v rsvg-convert  >/dev/null 2>&1 || { echo "ERROR: rsvg-convert not installed (apt install librsvg2-bin)" >&2; exit 2; }
[ -f "${CURATION_LIST}" ] || { echo "ERROR: curation list not found at ${CURATION_LIST}" >&2; exit 2; }

# ---- Upstream sync (skipped in self-test: SOURCE_DIR is pre-populated) ----
if [ "${SELFTEST}" = "1" ]; then
  UPSTREAM_BRANCH="selftest"
  UPSTREAM_SHA="selftest"
  echo "SELFTEST: using pre-populated SOURCE_DIR=${SOURCE_DIR} (no clone)"
else
  # ---- Upstream branch auto-detect ----
  UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-}"
  if [ -z "${UPSTREAM_BRANCH}" ]; then
    UPSTREAM_BRANCH=$(git ls-remote --symref "${UPSTREAM_REPO}" HEAD 2>/dev/null \
                      | head -1 | awk '/^ref:/ {print $2}' | sed 's|refs/heads/||')
  fi
  if [ -z "${UPSTREAM_BRANCH}" ]; then
    echo "ERROR: cannot detect upstream default branch from ${UPSTREAM_REPO}" >&2
    exit 2
  fi
  echo "Upstream: ${UPSTREAM_REPO} branch=${UPSTREAM_BRANCH}"

  # ---- 1. Ensure upstream cloned (shallow, detected branch) ----
  if [ ! -d "${SOURCE_DIR}/.git" ]; then
    echo "Cloning fluentui-system-icons upstream..."
    mkdir -p "${REPO_ROOT}/source"
    git clone --depth 1 --branch "${UPSTREAM_BRANCH}" "${UPSTREAM_REPO}" "${SOURCE_DIR}" || {
      echo "ERROR: clone failed" >&2; exit 2
    }
  else
    echo "Refreshing existing clone..."
    git -C "${SOURCE_DIR}" fetch --depth 1 origin "${UPSTREAM_BRANCH}" || {
      echo "ERROR: fetch failed" >&2; exit 2
    }
    git -C "${SOURCE_DIR}" reset --hard "origin/${UPSTREAM_BRANCH}"
  fi

  UPSTREAM_SHA="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
  echo "Upstream SHA: ${UPSTREAM_SHA}"
fi

# ---- 2. MIT licence re-verification gate ----
LICENSE_HEAD=$(head -1 "${SOURCE_DIR}/LICENSE" 2>/dev/null || true)
if [ "${LICENSE_HEAD}" != "MIT License" ]; then
  echo "ERROR: ${UPSTREAM_REPO} LICENSE no longer starts with 'MIT License' (got: '${LICENSE_HEAD}'). Re-audit before shipping." >&2
  exit 2
fi
echo "License: MIT (gate satisfied — first-party Microsoft Corporation 2020)"

# ---- 3. Drop-threshold gate ----
mkdir -p "${DIST_DIR}"
OLD_COUNT="$(find "${DIST_DIR}" -name '*.png' 2>/dev/null | wc -l)"

# Build expected-SVG list from curation × sizes; verify every SVG exists upstream
# (catches curation drift early — every curation stem MUST ship all 3 sizes of
# the `_color` variant, or the build aborts; partial-shipping is not allowed).
declare -a JOBS=()
MISSING=()
declare -a PARTIAL=()                       # concepts missing ≥1 size but not all 3
while IFS= read -r concept; do
  case "${concept}" in
    ''|\#*) continue ;;
  esac
  stem="$(echo "${concept}" | tr 'A-Z ' 'a-z_')"
  concept_missing=0
  concept_found=0
  for sz in "${SIZES[@]}"; do
    svg="${SOURCE_DIR}/assets/${concept}/SVG/ic_fluent_${stem}_${sz}_color.svg"
    if [ -f "${svg}" ]; then
      JOBS+=("${svg}|${stem}|${sz}")
      concept_found=$((concept_found + 1))
    else
      MISSING+=("${concept}/${sz} (expected ${svg#${SOURCE_DIR}/})")
      concept_missing=$((concept_missing + 1))
    fi
  done
  # Per-concept assertion: if 1 or 2 sizes ship but not all 3, that's a
  # partial-shipping case. Flag separately so the error message is
  # actionable: "concept FOO ships some sizes but not all".
  if [ "${concept_missing}" -gt 0 ] && [ "${concept_found}" -gt 0 ]; then
    PARTIAL+=("${concept}: ${concept_found}/3 sizes present, ${concept_missing} missing")
  fi
done < "${CURATION_LIST}"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: curation list refers to ${#MISSING[@]} missing SVG(s):" >&2
  for m in "${MISSING[@]}"; do echo "  ${m}" >&2; done
  if [ ${#PARTIAL[@]} -gt 0 ]; then
    echo "" >&2
    echo "Partial-shipping concepts (some sizes upstream but not all 3):" >&2
    for p in "${PARTIAL[@]}"; do echo "  ${p}" >&2; done
    echo "" >&2
    echo "Resolution: either re-curate to a concept that ships all 3 sizes," >&2
    echo "remove the offending concept from scripts/fixtures/fluentui-curation.txt," >&2
    echo "or extend SIZES[] in this script if upstream now ships at additional sizes." >&2
  fi
  echo "" >&2
  echo "Either update curation list or audit upstream changes." >&2
  exit 1
fi

NEW_COUNT="${#JOBS[@]}"
echo "Counts: old=${OLD_COUNT} new=${NEW_COUNT}"
assert_relative_drop_safe "${OLD_COUNT}" "${NEW_COUNT}" 10 "${ALLOW_REMOVALS}"

# ---- 4. Scoped clean ----
echo "Cleaning ${DIST_DIR}/*.png..."
scoped_find_delete "${DIST_DIR}" '*.png'

# ---- 5. SVG → PNG ----
echo "Converting ${NEW_COUNT} SVGs..."
for job in "${JOBS[@]}"; do
  IFS='|' read -r svg stem sz <<< "${job}"
  rsvg-convert -w "${sz}" -h "${sz}" -o "${DIST_DIR}/${stem}_${sz}_color.png" "${svg}" || {
    echo "ERROR: rsvg-convert failed on ${svg}" >&2; exit 1
  }
done

# ---- 6. Persist UPSTREAM-SHA.txt ----
write_upstream_record "${UPSTREAM_RECORD}" "${UPSTREAM_SHA}"

# ---- 7. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 50 ]; then
  echo "ERROR: count < 50, aborting (expected ~75 across 25 curated concepts × 3 sizes)" >&2
  exit 1
fi

# ---- 8. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;38p;$p'

echo "OK · upstream=${UPSTREAM_SHA} branch=${UPSTREAM_BRANCH} count=${COUNT}"

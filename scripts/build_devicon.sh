#!/usr/bin/env bash
# Reproducible Devicon build (curated subset).
# Source: devicons/devicon (community-maintained MIT — Copyright (c) 2015
# konpa). Per-tool depicted brands are trademarks of their respective owners;
# NOTICE carries the per-tool-trademark disclaim.
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
#   (e) UPSTREAM-SHA.txt persisted under dist/Devicon/ for release-notes
#       traceability.
#   (f) Structured 0/1/2 exit codes matching smoke_urls.sh / smoke_e2e.sh.
#   (g) Scoped find -delete (-name *.png -delete) preserves .gitkeep.
#
# Scope:
#   Reads scripts/fixtures/devicon-curation.txt (one stem per line, matching
#   upstream `icons/<stem>/<stem>-original.svg`). For each stem, converts the
#   `-original` variant SVG at size 48 into a PNG under
#   dist/Devicon/png/<stem>-original_48.png (flat layout).
#   Expected count: curation_lines × 1 PNG (~150 with the v1 curation).
#
# Out of scope: `-plain`, `-line`, `-wordmark` variants (off-style alternatives),
# sizes other than 48, stems that don't ship `-original.svg` (curation list is
# the authoritative scope).

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
SOURCE_DIR="${BUILD_SOURCE_DIR:-${REPO_ROOT}/source/devicon}"
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/Devicon/png}"
CURATION_LIST="${BUILD_CURATION_LIST:-${REPO_ROOT}/scripts/fixtures/devicon-curation.txt}"
UPSTREAM_RECORD="${BUILD_UPSTREAM_RECORD:-${REPO_ROOT}/dist/Devicon/UPSTREAM-SHA.txt}"
SELFTEST="${BUILD_SELFTEST:-0}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/devicons/devicon.git}"
SIZE=48

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
    echo "Cloning devicon upstream..."
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
if [ "${LICENSE_HEAD}" != "The MIT License (MIT)" ]; then
  echo "ERROR: ${UPSTREAM_REPO} LICENSE no longer starts with 'The MIT License (MIT)' (got: '${LICENSE_HEAD}'). Re-audit before shipping." >&2
  exit 2
fi
echo "License: MIT (gate satisfied — community-maintained, Copyright 2015 konpa)"

# ---- 3. Drop-threshold gate ----
mkdir -p "${DIST_DIR}"
OLD_COUNT="$(find "${DIST_DIR}" -name '*.png' 2>/dev/null | wc -l)"

# Build expected-SVG list from curation; verify every SVG exists upstream
# (strict-curation: missing stem aborts the build).
declare -a JOBS=()
MISSING=()
while IFS= read -r stem; do
  case "${stem}" in
    ''|\#*) continue ;;
  esac
  svg="${SOURCE_DIR}/icons/${stem}/${stem}-original.svg"
  if [ -f "${svg}" ]; then
    JOBS+=("${svg}|${stem}")
  else
    MISSING+=("${stem} (expected ${svg#${SOURCE_DIR}/})")
  fi
done < "${CURATION_LIST}"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: curation list refers to ${#MISSING[@]} missing SVG(s):" >&2
  for m in "${MISSING[@]}"; do echo "  ${m}" >&2; done
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
  IFS='|' read -r svg stem <<< "${job}"
  rsvg-convert -w "${SIZE}" -h "${SIZE}" -o "${DIST_DIR}/${stem}-original_${SIZE}.png" "${svg}" || {
    echo "ERROR: rsvg-convert failed on ${svg}" >&2; exit 1
  }
done

# ---- 6. Persist UPSTREAM-SHA.txt ----
write_upstream_record "${UPSTREAM_RECORD}" "${UPSTREAM_SHA}"

# ---- 7. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 100 ]; then
  echo "ERROR: count < 100, aborting (expected ~150 curated stems × 1 size)" >&2
  exit 1
fi

# ---- 8. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;75p;$p'

echo "OK · upstream=${UPSTREAM_SHA} branch=${UPSTREAM_BRANCH} count=${COUNT}"

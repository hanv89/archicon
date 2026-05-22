#!/usr/bin/env bash
# Reproducible Azure icon build (Variant B — Azure-PlantUML upstream).
# Idempotent: safe to re-run.
#
# Exit codes:
#   0 — success (PNG set refreshed, UPSTREAM-SHA.txt updated).
#   1 — build failure or refused content drop (use --allow-removals to override).
#   2 — environment problem (git missing, upstream unreachable, etc.).
#
# Hardenings landed 2026-05-11:
#   (a) Upstream branch auto-detected via `git ls-remote --symref HEAD` so the
#       script keeps working if the upstream renames master→main. Allow
#       UPSTREAM_BRANCH env override.
#   (b) Relative-drop threshold: refuse to proceed if the new PNG count is
#       >10% smaller than what's already in dist/Azure unless --allow-removals.
#   (c) --allow-removals CLI flag (or ALLOW_REMOVALS=1 env) bypasses the gate.
#   (d) LC_ALL=C export at script top for deterministic sort + find order.
#   (e) UPSTREAM-SHA.txt persisted under dist/Azure/ so release notes can
#       reference the exact upstream commit each build was sourced from.
#   (f) Structured 0/1/2 exit codes matching smoke_urls.sh / smoke_e2e.sh.
#   (g) Scoped find -delete (`-name '*.png' -delete`) preserves USAGE-RULES.txt
#       + .gitkeep + future non-PNG artifacts.

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
      grep -E '^# (Exit|  |Reproducible|Idempotent|Hardenings)' "$0" >&2
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SOURCE_DIR / DIST_DIR are overridable via env so the copy logic can be
# unit-tested against a synthetic fixture upstream tree (BUILD_SELFTEST=1
# skips the network clone + count floor). Production defaults are unchanged.
SOURCE_DIR="${BUILD_SOURCE_DIR:-${REPO_ROOT}/source/Azure-PlantUML}"
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/Azure}"
SELFTEST="${BUILD_SELFTEST:-0}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/plantuml-stdlib/Azure-PlantUML.git}"

# ---- Upstream sync (skipped in self-test: SOURCE_DIR is pre-populated) ----
if [ "${SELFTEST}" = "1" ]; then
  UPSTREAM_BRANCH="selftest"
  UPSTREAM_SHA="selftest"
  echo "SELFTEST: using pre-populated SOURCE_DIR=${SOURCE_DIR} (no clone)"
else
  # ---- Upstream branch auto-detect (item a) ----
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
    echo "Cloning Azure-PlantUML upstream..."
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

# ---- 2. Drop-threshold gate (items b + c) ----
mkdir -p "${DIST_DIR}"
OLD_COUNT="$(find "${DIST_DIR}" -name '*.png' 2>/dev/null | wc -l)"
NEW_COUNT="$(find "${SOURCE_DIR}/dist" -name '*.png' 2>/dev/null | wc -l)"
echo "Counts: old=${OLD_COUNT} upstream=${NEW_COUNT}"

assert_relative_drop_safe "${OLD_COUNT}" "${NEW_COUNT}" 10 "${ALLOW_REMOVALS}"

# ---- 3. Scoped clean (item g) — preserve USAGE-RULES.txt, .gitkeep, etc. ----
echo "Cleaning ${DIST_DIR}/**/*.png..."
scoped_find_delete "${DIST_DIR}" '*.png'

# ---- 4. Copy *.png only, preserving category structure ----
echo "Copying PNGs..."
rsync -a \
  --include='*/' \
  --include='*.png' \
  --exclude='*' \
  "${SOURCE_DIR}/dist/" "${DIST_DIR}/"

# ---- 5. Drop empty directories left by the include/exclude filter ----
find "${DIST_DIR}" -type d -empty -delete

# ---- 6. Persist UPSTREAM-SHA.txt (item e) ----
write_upstream_record "${DIST_DIR}/UPSTREAM-SHA.txt" "${UPSTREAM_SHA}"

# ---- 7. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 500 ]; then
  echo "ERROR: count < 500, aborting" >&2
  exit 1
fi

# ---- 8. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;100p;$p'

echo "OK · upstream=${UPSTREAM_SHA} branch=${UPSTREAM_BRANCH} count=${COUNT}"

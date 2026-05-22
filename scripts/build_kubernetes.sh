#!/usr/bin/env bash
# Reproducible Kubernetes icon build (kubernetes/community/icons upstream,
# Apache-2.0 / CC-BY-4.0 dual licence — verified at icons/README.md § License).
# Idempotent: safe to re-run.
#
# Exit codes:
#   0 — success (PNG set refreshed, UPSTREAM-SHA.txt updated).
#   1 — build failure or refused content drop (use --allow-removals to override).
#   2 — environment problem (git missing, upstream unreachable, etc.).
#
# Inherits the same hardenings as build_azure.sh and build_fabric.sh
# (the 7-item build-script hardening pattern, consolidated in
# _lib_icon_build.sh):
#   (a) Upstream branch auto-detected via `git ls-remote --symref HEAD`.
#       (Upstream renamed master→main; auto-detect handles either.) Allow
#       UPSTREAM_BRANCH env override.
#   (b) Relative-drop threshold: refuse if (OLD - NEW) > OLD * 10% unless
#       --allow-removals.
#   (c) --allow-removals CLI flag (or ALLOW_REMOVALS=1 env) bypasses the gate.
#   (d) LC_ALL=C export at script top for deterministic sort + find order.
#   (e) UPSTREAM-SHA.txt persisted under dist/Kubernetes/ for release-notes
#       traceability.
#   (f) Structured 0/1/2 exit codes matching smoke_urls.sh / smoke_e2e.sh.
#   (g) Scoped find -delete ('-name *.png -delete') preserves .gitkeep
#       + future non-PNG artifacts.
#
# Scope:
#   Copies kubernetes/community/icons/png/**/*.png to dist/Kubernetes/png/
#   preserving subdir structure (labeled / unlabeled / control_plane_components
#   / infrastructure_components × 128 / 256 sizes).
#   Expected count: ~148 PNGs (10 upstream zero-byte placeholders dropped).
#   - resources/labeled: 60
#   - resources/unlabeled: 60
#   - control_plane_components/labeled: 12 (6 placeholders skipped)
#   - infrastructure_components/labeled: 8 (3 placeholders skipped)
#   - infrastructure_components/unlabeled: 8 (1 placeholder skipped)
#   Upstream does not currently ship control_plane_components/unlabeled.
#
# Upstream zero-byte placeholders: filenames of the form `<concept>-.png`
# (no size suffix) exist as empty 0-byte files in upstream
# control_plane_components/ + infrastructure_components/. They are not
# functional icons (cannot render via <img:URL>). Step 5b drops them.
#
# Out of scope: SVG sources (kept upstream only per tech-stack.md § Image format),
# Visio stencils, examples/, docs/.

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
# SOURCE_DIR / DIST_DIR / record path are overridable via env so the copy +
# zero-byte-drop logic can be unit-tested against a synthetic fixture upstream
# tree (BUILD_SELFTEST=1 skips the network clone + count floor). Production
# defaults are unchanged.
SOURCE_DIR="${BUILD_SOURCE_DIR:-${REPO_ROOT}/source/kubernetes-community}"
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/Kubernetes/png}"
UPSTREAM_RECORD="${BUILD_UPSTREAM_RECORD:-${REPO_ROOT}/dist/Kubernetes/UPSTREAM-SHA.txt}"
SELFTEST="${BUILD_SELFTEST:-0}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/kubernetes/community.git}"

# ---- Tooling probe ----
command -v git    >/dev/null 2>&1 || { echo "ERROR: git not installed" >&2; exit 2; }
command -v rsync  >/dev/null 2>&1 || { echo "ERROR: rsync not installed" >&2; exit 2; }

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
    echo "Cloning kubernetes/community upstream..."
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
NEW_COUNT="$(find "${SOURCE_DIR}/icons/png" -name '*.png' 2>/dev/null | wc -l)"
echo "Counts: old=${OLD_COUNT} upstream=${NEW_COUNT}"

assert_relative_drop_safe "${OLD_COUNT}" "${NEW_COUNT}" 10 "${ALLOW_REMOVALS}"

# ---- 3. Scoped clean (item g) — preserve .gitkeep, future non-PNG artifacts ----
echo "Cleaning ${DIST_DIR}/**/*.png..."
scoped_find_delete "${DIST_DIR}" '*.png'

# ---- 4. Copy *.png only, preserving subdir structure ----
echo "Copying PNGs..."
rsync -a \
  --include='*/' \
  --include='*.png' \
  --exclude='*' \
  "${SOURCE_DIR}/icons/png/" "${DIST_DIR}/"

# ---- 5a. Drop upstream zero-byte placeholder PNGs ----
# Upstream ships some `<concept>-.png` files at 0 bytes (placeholders without
# size suffix in control_plane_components/ + infrastructure_components/).
# They are not functional icons; drop before persisting.
DROPPED_PLACEHOLDERS=$(find "${DIST_DIR}" -name '*.png' -size 0 | wc -l)
echo "Dropping ${DROPPED_PLACEHOLDERS} upstream zero-byte placeholder PNG(s)..."
find "${DIST_DIR}" -name '*.png' -size 0 -delete

# ---- 5b. Drop empty directories left by the include/exclude filter ----
find "${DIST_DIR}" -type d -empty -delete

# ---- 6. Persist UPSTREAM-SHA.txt (item e) ----
write_upstream_record "${UPSTREAM_RECORD}" "${UPSTREAM_SHA}"

# ---- 7. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 130 ]; then
  echo "ERROR: count < 130, aborting (expected ~148 K8s PNGs after dropping upstream zero-byte placeholders)" >&2
  exit 1
fi

# ---- 8. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;80p;$p'

echo "OK · upstream=${UPSTREAM_SHA} branch=${UPSTREAM_BRANCH} count=${COUNT}"

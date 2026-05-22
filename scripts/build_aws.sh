#!/usr/bin/env bash
# VERBATIM-copy AWS icon build — CC-BY-ND 2.0 forbids derivatives, so PNGs are
# copied byte-identically from upstream (no image transform of any kind:
# no resize, no recolor, no crop, no re-encode).
#
# Source: awslabs/aws-icons-for-plantuml (CC-BY-ND 2.0; AWS Architecture Icons).
# The "NoDerivatives" clause means a resize/re-encode IS a derivative and is
# forbidden. This script therefore only clones upstream and `cp`s the shipped
# PNGs verbatim; scripts/test_aws_verbatim.sh asserts no image-converter token
# appears here and that the shipped PNGs are sha256-identical to upstream.
# Idempotent.
#
# Exit codes:
#   0 — success (PNG set refreshed, UPSTREAM-SHA.txt updated).
#   1 — build failure or refused content drop (use --allow-removals to override).
#   2 — environment problem (git missing, upstream unreachable, etc.).
#
# Inherits the build-script hardenings consolidated in _lib_icon_build.sh —
# but ONLY the non-resize helpers (this vendor must never resize):
#   (a) Upstream branch auto-detected via `git ls-remote --symref HEAD`
#       (allow UPSTREAM_BRANCH env override).
#   (b) Relative-drop threshold: refuse if (OLD - NEW) > OLD * 10% unless
#       --allow-removals.
#   (c) --allow-removals CLI flag (or ALLOW_REMOVALS=1 env) bypasses the gate.
#   (d) LC_ALL=C export for deterministic sort + find order.
#   (e) UPSTREAM-SHA.txt persisted under dist/AWS/ for release-notes traceability.
#   (f) Structured 0/1/2 exit codes.
#   (g) Scoped find -delete ('-name *.png -delete') preserves USAGE-RULES.txt
#       + UPSTREAM-SHA.txt.
#
# Scope:
#   Copies upstream dist/<Category>/<Service>.png verbatim to
#   dist/AWS/<Category>/<Service>.png (flat per-category, all 64x64). NO size
#   subdirs. Expected count: ~868 PNGs.
#
# Out of scope: .puml stdlib files, SVG/Visio sources, mermaid/structurizr JSON,
#   examples/. SVGs are NOT rendered — the verbatim regime ships only the PNGs
#   upstream already ships.

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
      grep -E '^# (Exit|  |VERBATIM|Source|The|Inherits|Scope|Out)' "$0" >&2
      exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SOURCE_DIR / DIST_DIR / record path are overridable via env so the verbatim
# copy logic can be unit-tested against a synthetic fixture upstream tree
# (BUILD_SELFTEST=1 skips the network clone + count floor). Production
# defaults are unchanged.
SOURCE_DIR="${BUILD_SOURCE_DIR:-${REPO_ROOT}/source/aws-icons-for-plantuml}"
DIST_DIR="${BUILD_DIST_DIR:-${REPO_ROOT}/dist/AWS}"
UPSTREAM_RECORD="${BUILD_UPSTREAM_RECORD:-${REPO_ROOT}/dist/AWS/UPSTREAM-SHA.txt}"
SELFTEST="${BUILD_SELFTEST:-0}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/awslabs/aws-icons-for-plantuml.git}"

# ---- Tooling probe (NOTE: no image converter — verbatim copy only) ----
command -v git   >/dev/null 2>&1 || { echo "ERROR: git not installed"   >&2; exit 2; }
command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync not installed" >&2; exit 2; }

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
    echo "Cloning awslabs/aws-icons-for-plantuml upstream..."
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

# ---- 3. Scoped clean (item g) — preserve USAGE-RULES.txt + UPSTREAM-SHA.txt ----
echo "Cleaning ${DIST_DIR}/**/*.png..."
scoped_find_delete "${DIST_DIR}" '*.png'

# ---- 4. Copy *.png ONLY, VERBATIM, preserving per-category subdir structure ----
#         No image transform of any kind, no resize: CC-BY-ND forbids
#         derivatives. rsync -a copies bytes as-is (a derivative would be a
#         licence breach).
echo "Copying PNGs verbatim (no resize/re-encode)..."
rsync -a \
  --include='*/' \
  --include='*.png' \
  --exclude='*' \
  "${SOURCE_DIR}/dist/" "${DIST_DIR}/"

# ---- 5. Drop empty directories left by the include/exclude filter ----
find "${DIST_DIR}" -type d -empty -delete

# ---- 6. Persist UPSTREAM-SHA.txt (item e) ----
write_upstream_record "${UPSTREAM_RECORD}" "$(printf 'upstream=%s\nsha=%s\nlicense=CC-BY-ND-2.0\nmode=verbatim-copy (no resize/recolor/crop/re-encode)' "${UPSTREAM_REPO%.git}" "${UPSTREAM_SHA}")"

# ---- 7. Verify ----
COUNT="$(find "${DIST_DIR}" -name '*.png' | wc -l)"
echo "PNG count: ${COUNT}"
if [ "${SELFTEST}" != "1" ] && [ "${COUNT}" -lt 800 ]; then
  echo "ERROR: count < 800, aborting (expected ~868 AWS PNGs)" >&2
  exit 1
fi

# ---- 8. Sample report ----
echo "Sample paths:"
find "${DIST_DIR}" -name '*.png' | sort | sed -n '1p;400p;$p'

echo "OK · upstream=${UPSTREAM_SHA} branch=${UPSTREAM_BRANCH} count=${COUNT} (verbatim CC-BY-ND)"

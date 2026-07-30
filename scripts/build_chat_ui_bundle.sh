#!/usr/bin/env bash
# Build a reproducible chat-UI distribution bundle ZIP.
#
# Produces dist/chat-ui-bundle.zip containing:
#   - README.md             (top-level "what's in this bundle + how to use")
#   - SKILL.md              (copy of skills/architecture-diagram/SKILL.md)
#   - NOTICE                (copy of repo-root NOTICE)
#   - examples/<NN-name>.{puml,mmd,md} (all skills/architecture-diagram/examples/*.{puml,mmd,md} flat; .md = worked agent-dialogue transcript such as 20-init-clarify.md)
#   - indexes/<Vendor>-INDEX.md       (per-vendor catalog, 5 files)
#   - usage-rules/<Vendor>-USAGE-RULES.txt (per-vendor licence/trademark, 5 files)
#
# The bundle is consumed by:
#   - claude.ai Project recipe (docs/chat-ui-distribution/claude-project/)
#   - ChatGPT Custom GPT recipe (docs/chat-ui-distribution/chatgpt-gpt/)
# Both channels upload the bundle's files as knowledge inputs to a chat-UI agent.
#
# Determinism guarantees (byte-stable across runs on the same source tree):
#   - LC_ALL=C + TZ=UTC pin sort order and any timestamp formatting.
#   - File list is sorted before zip invocation.
#   - mtimes on bundle inputs are normalised to a fixed epoch via touch
#     before zipping, so source-tree mtimes don't leak into the archive.
#   - `zip -X` strips extra-field bytes (uid/gid/extended-attrs) from the
#     archive headers.
#
# Exit codes:
#   0 — bundle built successfully.
#   1 — missing input file (script-detectable; e.g. skills/architecture-diagram/SKILL.md absent).
#   2 — environment problem (zip CLI missing).
set -euo pipefail
export LC_ALL=C
export TZ=UTC

command -v zip >/dev/null 2>&1 || { echo "ERROR: zip CLI not installed" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

SKILL_SRC="skills/architecture-diagram/SKILL.md"
NOTICE_SRC="NOTICE"
EXAMPLES_SRC_DIR="skills/architecture-diagram/examples"
DIST_DIR="dist"
OUT_ZIP="${DIST_DIR}/chat-ui-bundle.zip"

# Auto-discover vendors from dist/<Vendor>/INDEX.md (mirrors release-icons.yml
# excluded-names pattern). EXCLUDE_NAMES filters out non-vendor companion dirs.
EXCLUDE_NAMES="skill Custom baselines notes"
VENDORS=()
for d in dist/*/; do
  name="$(basename "${d}")"
  skip=""
  for e in ${EXCLUDE_NAMES}; do
    if [ "${name}" = "${e}" ]; then skip="1"; break; fi
  done
  [ -n "${skip}" ] && continue
  [ -f "${d}/INDEX.md" ] || continue
  VENDORS+=("${name}")
done

# Sort vendor list deterministically (LC_ALL=C makes this stable).
IFS=$'\n' VENDORS_SORTED=($(printf '%s\n' "${VENDORS[@]}" | sort)); unset IFS

# Pre-flight checks.
[ -f "${SKILL_SRC}" ]    || { echo "ERROR: ${SKILL_SRC} missing"    >&2; exit 1; }
[ -f "${NOTICE_SRC}" ]   || { echo "ERROR: ${NOTICE_SRC} missing"   >&2; exit 1; }
[ -d "${EXAMPLES_SRC_DIR}" ] || { echo "ERROR: ${EXAMPLES_SRC_DIR} missing" >&2; exit 1; }
[ "${#VENDORS_SORTED[@]}" -ge 1 ] || { echo "ERROR: no vendors with INDEX.md found under dist/" >&2; exit 1; }

# Stage into a temp dir, then zip from there.
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

mkdir -p "${STAGE}/examples" "${STAGE}/indexes" "${STAGE}/usage-rules"

cp "${SKILL_SRC}"  "${STAGE}/SKILL.md"
cp "${NOTICE_SRC}" "${STAGE}/NOTICE"

# Examples — flatten skills/architecture-diagram/examples/*.{puml,mmd,md} into examples/
# (.puml = PlantUML, .mmd = Mermaid, .md = worked agent-dialogue transcript
# such as 20-init-clarify.md). Without .md, SKILL.md cross-references the
# dialogue example but the bundle would ship without it — chat-UI users
# (claude.ai Projects, ChatGPT Custom GPT) would hit a broken link.
for f in "${EXAMPLES_SRC_DIR}"/*.puml "${EXAMPLES_SRC_DIR}"/*.mmd "${EXAMPLES_SRC_DIR}"/*.md; do
  [ -e "${f}" ] || continue
  cp "${f}" "${STAGE}/examples/$(basename "${f}")"
done
# Example support assets (icon.css, render-mermaid.sh) preserve their subdir.
if [ -d "${EXAMPLES_SRC_DIR}/assets" ]; then
  mkdir -p "${STAGE}/examples/assets"
  for f in "${EXAMPLES_SRC_DIR}"/assets/*; do
    [ -e "${f}" ] || continue
    cp "${f}" "${STAGE}/examples/assets/$(basename "${f}")"
  done
fi

# Per-vendor INDEX + USAGE-RULES.
for v in "${VENDORS_SORTED[@]}"; do
  cp "dist/${v}/INDEX.md"        "${STAGE}/indexes/${v}-INDEX.md"
  if [ -f "dist/${v}/USAGE-RULES.txt" ]; then
    cp "dist/${v}/USAGE-RULES.txt" "${STAGE}/usage-rules/${v}-USAGE-RULES.txt"
  fi
done

# Inline README — short pointer + bundle contents.
cat >"${STAGE}/README.md" <<'EOF'
# Architecture Diagram Skill — Chat-UI Bundle

This ZIP packages the architecture-diagram skill for upload into a chat-UI
agent's knowledge base (claude.ai Project or ChatGPT Custom GPT).

## What's inside

- `SKILL.md` — the canonical skill content. Read first.
- `NOTICE` — per-vendor attribution + trademark notices.
- `examples/` — worked diagram examples (`.puml` = PlantUML, `.mmd` = Mermaid).
- `indexes/<Vendor>-INDEX.md` — per-vendor icon catalogs (5 files: Azure,
  Fabric, Kubernetes, FluentUI, Devicon). Look up filenames here before
  emitting `<img:URL>` tokens — see SKILL.md § "Filename rule (non-negotiable)".
- `usage-rules/<Vendor>-USAGE-RULES.txt` — per-vendor licence + trademark
  rules. The agent must respect these when emitting diagrams.

## How to use

This bundle is consumed by two chat-UI channels — see the channel-specific
setup guides in the project's `docs/chat-ui-distribution/` directory on
GitHub:

- claude.ai Project recipe
- ChatGPT Custom GPT recipe

Both channels upload the files in this ZIP as knowledge inputs and paste a
short system prompt that routes the model to `SKILL.md`. Updates ship on
the same release cadence as the npm-distributed CLI/IDE skill — re-download
this ZIP and re-upload on each new release.
EOF

# Normalise mtimes inside the stage to a fixed epoch so the archive is
# byte-stable across runs regardless of source-tree mtimes.
find "${STAGE}" -exec touch -t 198001010000 {} +

# Build the file list deterministically (sorted, relative to STAGE).
cd "${STAGE}"
FILE_LIST="$(find . -type f | sed 's|^\./||' | sort)"

# Build the zip. -X strips extra-fields (uid/gid/extended attrs); -q quiet;
# the file list is piped in sorted order so per-entry order is stable.
echo "${FILE_LIST}" | zip -X -q "${REPO_ROOT}/${OUT_ZIP}" -@

cd "${REPO_ROOT}"

echo "OK: ${OUT_ZIP} ($(wc -c <"${OUT_ZIP}") bytes; sha256 $(sha256sum "${OUT_ZIP}" | awk '{print $1}'))"
echo "Vendors: ${VENDORS_SORTED[*]}"
echo "Entries: $(unzip -l "${OUT_ZIP}" | tail -1 | awk '{print $2}')"

#!/usr/bin/env bash
# Assert every <img:URL> icon reference taught by the skill resolves to a
# real file in dist/ AND appears in the relevant per-vendor INDEX.md.
#
# This is the executable form of the "Filename rule (non-negotiable)" in
# SKILL.md: a guessed / renamed / removed icon path returns HTTP 404 from
# raw.githubusercontent.com and PlantUML renders a silent broken-image
# placeholder. Catching it here (offline) closes the loop before the
# manual render gate.
#
# Scope notes:
#   - Only real repo-hosted URLs
#     (raw.githubusercontent.com/hanv89/archicon/<ref>/dist/...png)
#     are validated. Documentation placeholders like `<img:URL>` are ignored.
#   - SKILL.md deliberately contains ONE broken reference inside a fenced
#     "WRONG" anti-example block (it demonstrates the 404 failure mode).
#     Fenced code blocks whose body contains the WRONG marker are stripped
#     before extraction so the anti-example does not trip the gate.
#   - URL-encoded parens (%28 / %29) in Azure monochrome filenames are
#     decoded before the existence check.
#
# Exit codes:
#   0 — every reference resolves + is indexed.
#   1 — at least one broken reference or missing INDEX entry.
#   2 — environment problem (no source files found).
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

SKILL="dist/skill/SKILL.md"
[ -f "${SKILL}" ] || { echo "ERROR: ${SKILL} missing" >&2; exit 2; }

REPO_SLUG="hanv89/archicon"
IMG_RE="<img:https://raw\.githubusercontent\.com/${REPO_SLUG}/[^>]+\.png>"

FAILED=0
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

url_decode() { printf '%s' "$1" | sed 's/%28/(/g; s/%29/)/g'; }

# Strip fenced ``` code blocks whose body contains a WRONG anti-example
# marker (SKILL.md only). awk: toggle on ```, buffer the block, flush it
# only if it did NOT contain "WRONG".
strip_wrong_fences() {
  awk '
    /^```/ {
      if (infence) { if (buf !~ /WRONG/) printf "%s", buf; buf=""; infence=0; next }
      else { infence=1; buf=$0 "\n"; next }
    }
    { if (infence) buf=buf $0 "\n"; else print }
    END { if (infence) printf "%s", buf }   # unterminated fence: emit as-is
  ' "$1"
}

# Collect unique repo-hosted img paths (relative to repo root) from all sources.
collect_refs() {
  strip_wrong_fences "${SKILL}" | grep -ohE "${IMG_RE}"
  for ex in dist/skill/examples/*.puml; do
    [ -f "${ex}" ] && grep -ohE "${IMG_RE}" "${ex}"
  done
}

REFS="$(collect_refs \
  | sed -E "s|<img:https://raw\.githubusercontent\.com/${REPO_SLUG}/[^/]+/||; s|>$||" \
  | sort -u)"

CHECKED=0
while IFS= read -r relpath; do
  [ -n "${relpath}" ] || continue
  CHECKED=$(( CHECKED + 1 ))
  decoded="$(url_decode "${relpath}")"
  # 1. file must exist
  if [ ! -f "${decoded}" ]; then
    fail "icon path does not exist in dist/: ${relpath}"
    continue
  fi
  # 2. basename must appear in the vendor INDEX.md
  vendor="$(printf '%s' "${decoded}" | sed -E 's|^dist/([^/]+)/.*|\1|')"
  base="$(basename "${decoded}")"
  idx="dist/${vendor}/INDEX.md"
  if [ ! -f "${idx}" ]; then
    fail "no INDEX.md for vendor ${vendor} (referenced by ${base})"
  elif ! grep -qF "${base}" "${idx}"; then
    fail "icon not listed in ${idx}: ${base}"
  fi
done <<< "${REFS}"

if [ "${FAILED}" -eq 0 ]; then
  echo "PASS  ${CHECKED} unique icon reference(s) across SKILL.md + examples all resolve + are indexed."
  exit 0
fi
echo "test_skill_refs: ${FAILED} broken reference(s)." >&2
exit 1

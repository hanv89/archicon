#!/usr/bin/env bash
# Lint the bundled skill examples (offline, fast). Two checks the other
# contract gates do not cover:
#
#   (A) Mermaid (.mmd) sanity: the first non-comment, non-blank line must be a
#       known Mermaid diagram type, and `subgraph`/`end` must balance. Without
#       this, a broken .mmd (e.g. example 11) can bit-rot undetected —
#       test_skill_refs.sh globs *.puml only, the manifest checks existence
#       only, and the bundle repro test only hashes the zip.
#
#   (B) PlantUML (.puml) stray-diagram-boundary: no line OTHER than the first
#       @startuml / last @enduml may contain a literal `@startuml`/`@enduml`.
#       A `@startuml` inside comment prose is parsed as a new diagram start and
#       silently splits the render (the gotcha found while shipping example 10).
#
# Exit codes: 0 all examples clean, 1 a lint failure, 2 env (no examples dir).
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"
EX="dist/skill/examples"
[ -d "${EX}" ] || { echo "ERROR: ${EX} missing" >&2; exit 2; }

FAILED=0
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

MERMAID_TYPES='flowchart|graph|sequenceDiagram|classDiagram|stateDiagram|erDiagram|journey|gantt|pie|architecture-beta|mindmap|timeline|gitGraph|quadrantChart|requirementDiagram|C4Context'

shopt -s nullglob

# (A) Mermaid .mmd
for f in "${EX}"/*.mmd; do
  # Strip a leading `---` YAML frontmatter config block (Mermaid `config:`
  # directive) if present, then ignore `%%` comments + blanks, so the first
  # *meaningful* line is the diagram type.
  body="$(awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {infm=0; next} !infm {print}' "${f}")"
  first="$(printf '%s\n' "${body}" | grep -vE '^\s*(%%|$)' | head -1 | sed -E 's/^\s+//')"
  if ! printf '%s' "${first}" | grep -qE "^(${MERMAID_TYPES})\b"; then
    fail "${f}: first non-comment line is not a known Mermaid diagram type: '${first}'"
  fi
  opens="$(grep -cE '^\s*subgraph\b' "${f}")"
  # 'end' closes subgraph; count standalone end tokens
  closes="$(grep -cE '^\s*end\s*$' "${f}")"
  if [ "${opens}" -ne "${closes}" ]; then
    fail "${f}: ${opens} subgraph vs ${closes} end (unbalanced)"
  fi
  [ "${FAILED}" -eq 0 ] && echo "ok (mmd): $(basename "${f}")"
done

# (B) PlantUML .puml stray @startuml/@enduml
for f in "${EX}"/*.puml; do
  total="$(wc -l < "${f}")"
  # @startuml allowed only on the first line; @enduml only on the last
  badstart="$(grep -nE '@startuml' "${f}" | grep -vE '^1:' | head -1)"
  badend="$(grep -nE '@enduml' "${f}" | grep -vE "^${total}:" | head -1)"
  [ -n "${badstart}" ] && fail "${f}: stray @startuml at ${badstart%%:*} (only line 1 may declare it)"
  [ -n "${badend}" ]   && fail "${f}: stray @enduml at ${badend%%:*} (only the last line may close it)"
done

if [ "${FAILED}" -eq 0 ]; then
  echo "PASS  all examples lint clean ($(ls "${EX}"/*.mmd 2>/dev/null | wc -l | tr -d ' ') mmd, $(ls "${EX}"/*.puml 2>/dev/null | wc -l | tr -d ' ') puml)."
  exit 0
fi
echo "lint_examples: ${FAILED} failure(s)." >&2
exit 1

#!/usr/bin/env bash
# Asserts dist/skill/SKILL.md frontmatter parses as YAML + carries the three
# required scalar fields (name, version, requires_icons) the CLI's install
# path depends on (packages/cli/src/adapters/_shared.ts:328 parseFrontmatter +
# adapters/_shared.ts:566 / adapters/cursor.ts:114 requires_icons enforcement).
#
# Pre-empts the v1.4.3 regression class: a plain (unquoted) YAML scalar that
# contained ": " (colon-space) inside the description value made yaml.load()
# raise "bad indentation of a mapping entry", parseFrontmatter returned {},
# and every install threw "fatal: SKILL.md missing requires_icons frontmatter".
#
# Run locally:
#   bash scripts/test_skill_frontmatter_parse.sh
#
# Exit codes:
#   0 — frontmatter parses cleanly + has all 3 required keys.
#   1 — parse error or missing required key.

set -euo pipefail
export LC_ALL=C

SKILL_MD="${SKILL_MD:-dist/skill/SKILL.md}"
# Resolve js-yaml location: prefer packages/cli/node_modules (where it's a
# CLI dep), fall back to repo-root node_modules if installed there.
JS_YAML_PATH=""
for cand in packages/cli/node_modules/js-yaml node_modules/js-yaml; do
  if [ -d "$cand" ]; then JS_YAML_PATH="$cand"; break; fi
done
if [ -z "$JS_YAML_PATH" ]; then
  # Install on demand for ad-hoc CI shell that hasn't run `npm ci` yet.
  echo "WARN  js-yaml not found in node_modules; running 'npm --prefix packages/cli ci' first" >&2
  npm --prefix packages/cli ci --silent
  JS_YAML_PATH="packages/cli/node_modules/js-yaml"
fi

node -e "
const fs = require('fs');
const yaml = require('$(pwd)/${JS_YAML_PATH}');
const text = fs.readFileSync('${SKILL_MD}', 'utf8');
const m = text.match(/^---\\r?\\n([\\s\\S]*?)\\r?\\n---/);
if (!m) { console.error('FAIL  no frontmatter block in ${SKILL_MD}'); process.exit(1); }
let parsed;
try {
  parsed = yaml.load(m[1]);
} catch (e) {
  console.error('FAIL  yaml.load() error: ' + e.message);
  console.error('      This is the v1.4.3-class regression — usually a colon-space');
  console.error('      sequence inside an unquoted scalar value. Wrap the value in');
  console.error('      single quotes, or remove the colon-space.');
  process.exit(1);
}
if (!parsed || typeof parsed !== 'object') {
  console.error('FAIL  frontmatter did not parse as an object');
  process.exit(1);
}
for (const k of ['name', 'version', 'requires_icons']) {
  if (typeof parsed[k] !== 'string') {
    console.error('FAIL  frontmatter.' + k + ' missing or not a string (got: ' + typeof parsed[k] + ')');
    process.exit(1);
  }
}
console.log('PASS  frontmatter parses; name=' + parsed.name + ' version=' + parsed.version + ' requires_icons=' + parsed.requires_icons);
"

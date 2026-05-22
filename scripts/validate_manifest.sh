#!/usr/bin/env bash
# Validate dist/skill/manifest.json against dist/skill/manifest.schema.json
# AND assert every files[].src path exists on disk.
#
# Dependency-free: a small Node script enforces the schema's load-bearing
# constraints (required keys, additionalProperties, role enum, version
# pattern, index-0-is-SKILL.md) rather than pulling in a full JSON-Schema
# engine. The schema file remains the documentation of record; this script
# is the executable guard.
#
# Exit codes:
#   0 — manifest valid + every files[].src exists.
#   1 — schema-conformance failure or a missing src file.
#   2 — environment problem (node missing, manifest/schema absent).
set -uo pipefail
export LC_ALL=C

command -v node >/dev/null 2>&1 || { echo "ERROR: node not installed" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

MANIFEST="dist/skill/manifest.json"
SCHEMA="dist/skill/manifest.schema.json"
[ -f "${MANIFEST}" ] || { echo "ERROR: ${MANIFEST} missing" >&2; exit 2; }
[ -f "${SCHEMA}" ]   || { echo "ERROR: ${SCHEMA} missing"   >&2; exit 2; }

node - "${MANIFEST}" "${SCHEMA}" <<'NODE'
const fs = require("fs");
const [manifestPath, schemaPath] = process.argv.slice(2);

let manifest, schema;
try { manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8")); }
catch (e) { console.error(`FAIL  manifest is not valid JSON: ${e.message}`); process.exit(1); }
try { schema = JSON.parse(fs.readFileSync(schemaPath, "utf8")); }
catch (e) { console.error(`FAIL  schema is not valid JSON: ${e.message}`); process.exit(1); }

let failures = 0;
const fail = (m) => { console.error(`FAIL  ${m}`); failures++; };

// --- required top-level keys (from schema.required) ---
for (const key of schema.required || []) {
  if (!(key in manifest)) fail(`manifest missing required key: ${key}`);
}

// --- additionalProperties:false on the root ---
const allowedRoot = new Set(Object.keys(schema.properties || {}));
for (const key of Object.keys(manifest)) {
  if (!allowedRoot.has(key)) fail(`manifest has unexpected top-level key: ${key}`);
}

// --- version pattern ---
const verPattern = new RegExp(schema.properties.version.pattern);
if (typeof manifest.version === "string" && !verPattern.test(manifest.version)) {
  fail(`version "${manifest.version}" does not match ${schema.properties.version.pattern}`);
}
const iconsVerPattern = new RegExp(schema.properties.icons_version.pattern);
if (typeof manifest.icons_version === "string" && !iconsVerPattern.test(manifest.icons_version)) {
  fail(`icons_version "${manifest.icons_version}" does not match ${schema.properties.icons_version.pattern}`);
}

// --- files[] structure ---
if (!Array.isArray(manifest.files) || manifest.files.length < 1) {
  fail("files must be a non-empty array");
} else {
  const roleEnum = new Set(schema.properties.files.items.properties.role.enum);
  const allowedFileKeys = new Set(Object.keys(schema.properties.files.items.properties));
  manifest.files.forEach((f, i) => {
    for (const k of schema.properties.files.items.required) {
      if (!(k in f)) fail(`files[${i}] missing required key: ${k}`);
    }
    for (const k of Object.keys(f)) {
      if (!allowedFileKeys.has(k)) fail(`files[${i}] has unexpected key: ${k}`);
    }
    if (f.role && !roleEnum.has(f.role)) fail(`files[${i}].role "${f.role}" not in {${[...roleEnum].join(", ")}}`);
  });
  // index 0 MUST be SKILL.md (schema description + install precheck contract)
  if (manifest.files[0] && manifest.files[0].role !== "skill") {
    fail(`files[0].role must be "skill" (is "${manifest.files[0].role}")`);
  }
  // --- every files[].src exists on disk ---
  manifest.files.forEach((f, i) => {
    if (f.src && !fs.existsSync(f.src)) fail(`files[${i}].src does not exist on disk: ${f.src}`);
  });
}

if (failures > 0) {
  console.error(`\nvalidate_manifest: ${failures} failure(s).`);
  process.exit(1);
}
console.log("PASS  manifest conforms to schema; all files[].src exist.");
NODE

#!/usr/bin/env bash
# Validate the skill manifest against its schema AND assert every files[].src
# exists on disk, lives under the skill source dir, hashes to the sha256 the
# manifest claims, and that the skill source dir holds nothing the manifest
# omits. Both paths come from archicon.config (SKILL_MANIFEST_PATH,
# SKILL_SRC_DIR) so this script and the CLI share one origin.
#
# Dependency-free: a small Node script enforces the schema's load-bearing
# constraints (required keys, additionalProperties, role enum, version
# pattern, index-0-is-SKILL.md) rather than pulling in a full JSON-Schema
# engine. The schema file remains the documentation of record; this script
# is the executable guard.
#
# Two of the checks are about what actually ships:
#   - sha256 recompute: the CLI verifies each fetched body against the
#     manifest hash and aborts the install on mismatch, so a content edit
#     that forgets to regenerate hashes ships a bundle nobody can install.
#     Asserting the file merely exists never catches that.
#   - src set == skill dir: the skill directory is itself an install unit —
#     the ecosystem `skills` CLI copies it wholesale, while this project's CLI
#     installs exactly manifest.files[]. A file present in one and not the
#     other means the two channels install different trees from one commit.
#
# Exit codes:
#   0 — manifest valid; every files[].src exists under the skill source dir,
#       hashes as claimed, and matches the directory contents exactly.
#   1 — schema-conformance failure, a missing/off-tree src, a hash mismatch,
#       or a directory/manifest set difference.
#   2 — environment problem (node or git missing, config/manifest/schema absent).
set -uo pipefail
export LC_ALL=C

command -v node >/dev/null 2>&1 || { echo "ERROR: node not installed" >&2; exit 2; }
command -v git  >/dev/null 2>&1 || { echo "ERROR: git not installed"  >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

# archicon.config is the single source of truth for both paths (KEY=value,
# shell-sourceable). Sourced rather than duplicated so a move shows up here.
[ -f "${REPO_ROOT}/archicon.config" ] || { echo "ERROR: archicon.config missing" >&2; exit 2; }
# shellcheck source=../archicon.config
. "${REPO_ROOT}/archicon.config"

MANIFEST="${SKILL_MANIFEST_PATH}"
SCHEMA="$(dirname "${MANIFEST}")/manifest.schema.json"
[ -f "${MANIFEST}" ] || { echo "ERROR: ${MANIFEST} missing" >&2; exit 2; }
[ -f "${SCHEMA}" ]   || { echo "ERROR: ${SCHEMA} missing"   >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: ${REPO_ROOT} is not a git work tree" >&2; exit 2; }

# What the skill directory actually contains, per git: tracked files plus
# untracked ones .gitignore does not exclude. Read from the index rather than
# walked so build output and editor scratch cannot fail the set comparison,
# while a newly added file still counts.
SKILL_DIR_FILES="$(git ls-files --cached --others --exclude-standard -- "${SKILL_SRC_DIR}")"
export SKILL_DIR_FILES

node - "${MANIFEST}" "${SCHEMA}" "${SKILL_SRC_DIR}" <<'NODE'
const fs = require("fs");
const crypto = require("crypto");
const [manifestPath, schemaPath, skillSrcDir] = process.argv.slice(2);

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
  // --- every files[].src exists on disk, under the skill source dir ---
  manifest.files.forEach((f, i) => {
    if (!f.src) return;
    if (!fs.existsSync(f.src)) fail(`files[${i}].src does not exist on disk: ${f.src}`);
    if (!f.src.startsWith(`${skillSrcDir}/`)) fail(`files[${i}].src is outside ${skillSrcDir}/: ${f.src}`);
  });

  // --- every files[].sha256 recomputes from the bytes at its src ---
  // sha256 is optional in the schema (older bundles omit it and the CLI warns
  // instead of failing), so only entries that declare one are checked.
  let hashed = 0;
  manifest.files.forEach((f, i) => {
    if (!f.src || !f.sha256 || !fs.existsSync(f.src)) return;
    const actual = crypto.createHash("sha256").update(fs.readFileSync(f.src)).digest("hex");
    if (actual !== String(f.sha256).toLowerCase()) {
      fail(`files[${i}].sha256 does not match ${f.src}\n      manifest: ${f.sha256}\n      on disk:  ${actual}\n      regenerate the manifest hash for this file`);
    } else {
      hashed++;
    }
  });

  // --- the skill directory and manifest.files[] describe the same set ---
  const dirFiles = new Set(
    (process.env.SKILL_DIR_FILES || "").split("\n").map((s) => s.trim()).filter(Boolean)
  );
  const manifestSrcs = new Set(manifest.files.map((f) => f.src).filter(Boolean));
  for (const p of dirFiles) {
    if (!manifestSrcs.has(p)) {
      fail(`${p} is in ${skillSrcDir}/ but not in manifest.files[] — the ecosystem CLI would copy it, this CLI would not install it`);
    }
  }
  for (const p of manifestSrcs) {
    if (p.startsWith(`${skillSrcDir}/`) && !dirFiles.has(p)) {
      fail(`manifest lists ${p} but git does not carry it under ${skillSrcDir}/ — it would never reach a user`);
    }
  }
  if (failures === 0) {
    console.log(`PASS  ${hashed}/${manifest.files.length} files[] hashes recomputed and matched.`);
    console.log(`PASS  ${skillSrcDir}/ and manifest.files[] hold the same ${dirFiles.size} paths.`);
  }
}

if (failures > 0) {
  console.error(`\nvalidate_manifest: ${failures} failure(s).`);
  process.exit(1);
}
console.log("PASS  manifest conforms to schema; all files[].src exist.");
NODE

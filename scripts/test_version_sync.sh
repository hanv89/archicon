#!/usr/bin/env bash
# Assert the skill version reads identically at every site that carries it.
#
# The manifest schema *describes* this rule — its `version` property says the
# value MUST match SKILL.md frontmatter and packages/cli/package.json — but a
# description is not a check, and a partial bump has no symptom until install
# time: the CLI compares the manifest version against the installed SKILL.md to
# decide whether `update` is a no-op, so a manifest that says 1.4.9 over a
# SKILL.md that says 1.4.8 leaves users pinned to stale content with no error.
#
# Sites compared (npm treats the lockfile's two version fields as one bump;
# both are checked because `npm version` writes both and a hand edit forgets):
#   packages/cli/package.json        .version
#   packages/cli/package-lock.json   .version and .packages[""].version
#   <SKILL_MANIFEST_PATH>            .version
#   <SKILL_SRC_DIR>/SKILL.md         frontmatter version
#
# Frontmatter is read with a line regex rather than a YAML parser so this gate
# runs on a bare checkout, before `npm ci` has put js-yaml in node_modules.
# scripts/test_skill_frontmatter_parse.sh is the gate that proves the block is
# real YAML; this one only reads a value out of it.
#
# Run locally:
#   bash scripts/test_version_sync.sh
#
# Exit codes:
#   0 — all sites agree.
#   1 — at least two sites disagree, or a version could not be read.
#   2 — environment problem (node missing, config or a version file absent).
set -uo pipefail
export LC_ALL=C

command -v node >/dev/null 2>&1 || { echo "ERROR: node not installed" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

[ -f "${REPO_ROOT}/archicon.config" ] || { echo "ERROR: archicon.config missing" >&2; exit 2; }
# shellcheck source=../archicon.config
. "${REPO_ROOT}/archicon.config"

PKG_JSON="packages/cli/package.json"
PKG_LOCK="packages/cli/package-lock.json"
SKILL_MD="${SKILL_SRC_DIR}/SKILL.md"

for f in "${PKG_JSON}" "${PKG_LOCK}" "${SKILL_MANIFEST_PATH}" "${SKILL_MD}"; do
  [ -f "${f}" ] || { echo "ERROR: ${f} missing" >&2; exit 2; }
done

node - "${PKG_JSON}" "${PKG_LOCK}" "${SKILL_MANIFEST_PATH}" "${SKILL_MD}" <<'NODE'
const fs = require("fs");
const [pkgJson, pkgLock, manifestPath, skillMd] = process.argv.slice(2);

let failures = 0;
const fail = (m) => { console.error(`FAIL  ${m}`); failures++; };

const readJson = (p) => {
  try { return JSON.parse(fs.readFileSync(p, "utf8")); }
  catch (e) { fail(`${p} is not valid JSON: ${e.message}`); return null; }
};

const pkg = readJson(pkgJson);
const lock = readJson(pkgLock);
const manifest = readJson(manifestPath);

// Frontmatter `version:` — value may be quoted or bare.
let skillVersion;
const text = fs.readFileSync(skillMd, "utf8");
const block = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
if (!block) {
  fail(`${skillMd} has no frontmatter block`);
} else {
  const line = block[1].match(/^version:[ \t]*(.+?)[ \t]*$/m);
  if (!line) fail(`${skillMd} frontmatter has no version: line`);
  else skillVersion = line[1].replace(/^['"]|['"]$/g, "");
}

const sites = [
  [`${pkgJson} .version`, pkg && pkg.version],
  [`${pkgLock} .version`, lock && lock.version],
  [`${pkgLock} .packages[""].version`, lock && lock.packages && lock.packages[""] && lock.packages[""].version],
  [`${manifestPath} .version`, manifest && manifest.version],
  [`${skillMd} frontmatter version`, skillVersion],
];

for (const [label, value] of sites) {
  if (typeof value !== "string" || value === "") fail(`could not read a version from ${label}`);
}

const values = [...new Set(sites.map(([, v]) => v).filter((v) => typeof v === "string" && v !== ""))];
if (values.length > 1) {
  fail(`version sites disagree: ${values.join(", ")}`);
  for (const [label, value] of sites) console.error(`      ${String(value)}  ${label}`);
}

if (failures > 0) {
  console.error(`\ntest_version_sync: ${failures} failure(s). Bump every site in lockstep.`);
  process.exit(1);
}
console.log(`PASS  all ${sites.length} version sites read ${values[0]}.`);
NODE

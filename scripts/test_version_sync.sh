#!/usr/bin/env bash
# Assert the skill version reads identically at every site that carries it, and
# that archicon.config and the CLI's compiled-in constants have not drifted.
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
# The second half is a drift check on the paths, not the version. archicon.config
# calls itself the single source of truth, but the CLI does not read it — it
# compiles its own copies into packages/cli/src/adapters/_shared.ts. Editing the
# config alone would silently repoint every bash gate while the CLI kept fetching
# the old path, leaving all of them green over a manifest the CLI never reads.
# Pairs compared (config key ↔ exported TS constant):
#   SKILL_MANIFEST_PATH ↔ MANIFEST_PATH
#   SKILL_SRC_DIR       ↔ SKILL_SRC_DIR
#   SKILL_NAME          ↔ SKILL_NAME
#   CANARY_ICON_PATH    ↔ CANARY_ICON_PATH
# The constants are parsed out of the .ts source textually so this runs on a
# bare checkout, with no build and no node_modules.
#
# Run locally:
#   bash scripts/test_version_sync.sh
#
# Exit codes:
#   0 — all version sites agree and config matches the CLI constants.
#   1 — at least two version sites disagree, a version could not be read, or a
#       config value and its TS constant differ.
#   2 — environment problem (node missing, config, a version file, or
#       _shared.ts absent).
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
SHARED_TS="packages/cli/src/adapters/_shared.ts"

[ -f "${SHARED_TS}" ] || { echo "ERROR: ${SHARED_TS} missing" >&2; exit 2; }

# --- archicon.config vs the constants compiled into the CLI ---
# Runs BEFORE the version-site checks on purpose: two of those sites are located
# through config values, so a drifted config makes them point at paths that do
# not exist. Reported in that order the operator would see "file missing", which
# is the symptom; the drift is the cause.
export SKILL_MANIFEST_PATH SKILL_SRC_DIR SKILL_NAME CANARY_ICON_PATH

node - "${SHARED_TS}" <<'NODE'
const fs = require("fs");
const [sharedTs] = process.argv.slice(2);

let failures = 0;
const fail = (m) => { console.error(`FAIL  ${m}`); failures++; };

// Parsed textually from the .ts source: no build, no node_modules, and no
// import of a file that would drag in the whole adapter tree.
const tsSource = fs.readFileSync(sharedTs, "utf8");
const readConst = (name) => {
  const m = tsSource.match(new RegExp(`^export const ${name}\\s*=\\s*"([^"]*)"`, "m"));
  return m ? m[1] : undefined;
};

const pathPairs = [
  ["SKILL_MANIFEST_PATH", "MANIFEST_PATH"],
  ["SKILL_SRC_DIR", "SKILL_SRC_DIR"],
  ["SKILL_NAME", "SKILL_NAME"],
  ["CANARY_ICON_PATH", "CANARY_ICON_PATH"],
];

let pathsChecked = 0;
for (const [configKey, tsName] of pathPairs) {
  const configValue = process.env[configKey];
  const tsValue = readConst(tsName);
  if (typeof configValue !== "string" || configValue === "") {
    fail(`archicon.config has no value for ${configKey}`);
    continue;
  }
  if (tsValue === undefined) {
    fail(`could not read 'export const ${tsName}' out of ${sharedTs} — the drift check cannot verify ${configKey}`);
    continue;
  }
  if (configValue !== tsValue) {
    fail(
      `${configKey} and ${tsName} have drifted:\n` +
      `      archicon.config: ${configValue}\n` +
      `      ${sharedTs}: ${tsValue}\n` +
      `      the bash gates read the config, the CLI reads its own constant — change both or neither`,
    );
    continue;
  }
  pathsChecked++;
}

if (failures > 0) {
  console.error(`\ntest_version_sync: ${failures} config/CLI drift failure(s).`);
  process.exit(1);
}
console.log(`PASS  all ${pathsChecked} archicon.config paths match the CLI's compiled-in constants.`);
NODE
drift_status=$?
[ "${drift_status}" -eq 0 ] || exit "${drift_status}"

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
  // CRLF-safe without a `\r` in the trailing class: JS counts CR as a line
  // terminator, so `.` never matches one and `$` under /m asserts before it.
  // A CRLF checkout therefore captures `1.4.9`, not `1.4.9\r`.
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
  // Name the majority value and the sites that differ from it, rather than
  // printing every value and leaving the reader to spot the odd one out.
  const counts = new Map();
  for (const [, v] of sites) {
    if (typeof v === "string" && v !== "") counts.set(v, (counts.get(v) || 0) + 1);
  }
  const [majority, majorityCount] = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
  const odd = sites.filter(([, v]) => v !== majority);
  fail(
    `version sites disagree: ${majorityCount} site${majorityCount === 1 ? "" : "s"} read ${majority}; ` +
    odd.map(([label, v]) => `${label} reads ${String(v)}`).join("; "),
  );
  for (const [label, value] of sites) {
    console.error(`      ${String(value)}  ${label}${value === majority ? "" : "   <-- differs"}`);
  }
}

if (failures > 0) {
  console.error(`\ntest_version_sync: ${failures} failure(s). Bump every site in lockstep.`);
  process.exit(1);
}
console.log(`PASS  all ${sites.length} version sites read ${values[0]}.`);
NODE

import * as fs from "node:fs/promises";
import * as path from "node:path";
import { Adapter, InstallOptions, UninstallOptions, UpdateOptions, ListOptions } from "./types";
import {
  SKILL_NAME,
  baseUrl,
  fetchManifest,
  fetchText,
  parseFrontmatter,
  safeResolveTarget,
  stripFrontmatter,
  verifyBundleFile,
  verifyIconsAvailability,
  withFatalReturn,
} from "./_shared";

// Cursor's project-scoped rules live at <cwd>/.cursor/rules/*.mdc with a
// distinct frontmatter shape (description / globs / alwaysApply). User Rules
// are settings-only and not programmatically writable from an external CLI,
// so this adapter targets Project Rules only.
//
// Unlike Claude Code + Codex (per-user folder containing SKILL.md + examples/),
// Cursor installs a SINGLE .mdc file. The skill body is concatenated under a
// Cursor-shaped frontmatter; examples are NOT bundled locally — the skill body
// references their public raw GitHub URLs and the agent fetches them at
// diagram-authoring time.
//
// See https://cursor.com/docs/context/rules for the format reference.

const RULE_BASENAME = "arch-skill.mdc";

const RULE_DESCRIPTION =
  "Use this rule when drawing Microsoft Azure or Microsoft Fabric architecture diagrams using PlantUML. " +
  "Triggers on \"draw Azure architecture\", \"draw Azure diagram\", \"create deployment diagram\", " +
  "\"Lakehouse + Notebook + Warehouse diagram\", \"PlantUML diagram for [project]\". " +
  "Also triggers on the Vietnamese phrase \"vẽ Azure\".";

// Cursor's rule discovery is per-project: <cwd>/.cursor/rules/*.mdc is the
// canonical install location, so the team picks up the rule via the project's
// git repo. A HOME-relative install would only help the local developer. The
// trade-off — running install from an unintended cwd — is mitigated by a
// runtime warn-line (see `install` below) and the `--target=<path>` override.
function defaultTarget(): string {
  return path.join(process.cwd(), ".cursor", "rules");
}

const CWD_DISPLAY = "<cwd>/.cursor/rules";

async function resolveTarget(target: string): Promise<string> {
  return safeResolveTarget(target, process.cwd(), CWD_DISPLAY);
}

// `provenanceMarker` and `PROVENANCE_RE` are paired: the regex MUST parse what
// the marker writes. Keep them in lockstep — a unit test in version.test.ts
// asserts the round-trip.
function provenanceMarker(version: string, requiresIcons: string): string {
  return `<!-- ${SKILL_NAME} v${version} (requires_icons: ${requiresIcons}) -->`;
}

const PROVENANCE_RE = new RegExp(`<!--\\s*${SKILL_NAME}\\s+v([^\\s]+)\\s+\\(requires_icons:\\s*([^)]+)\\)\\s*-->`);

export { provenanceMarker, PROVENANCE_RE };

function renderRule(skillBody: string, version: string, requiresIcons: string): string {
  return [
    "---",
    `description: ${RULE_DESCRIPTION}`,
    "alwaysApply: false",
    "---",
    "",
    provenanceMarker(version, requiresIcons),
    "",
    skillBody.trimStart(),
  ].join("\n");
}

async function isOurRuleFile(file: string): Promise<{ ours: boolean; version?: string }> {
  try {
    const body = await fs.readFile(file, "utf8");
    const match = body.match(PROVENANCE_RE);
    if (!match) return { ours: false };
    return { ours: true, version: match[1] };
  } catch {
    return { ours: false };
  }
}

async function install(opts: InstallOptions): Promise<number> {
  return withFatalReturn(async () => {
    if (opts.target === undefined) {
      process.stderr.write(`note: Cursor target resolved to ${defaultTarget()} (per-project install). Pass --target=<path> to override.\n`);
    }
    const targetDir = await resolveTarget(opts.target ?? defaultTarget());
    const base = baseUrl(opts.version);
    const ruleFile = path.join(targetDir, RULE_BASENAME);

    // Fetch manifest first so we know which file is the canonical SKILL.md
    // and what version / requires_icons to embed in the provenance marker.
    const manifest = await fetchManifest(base);
    if (manifest.name !== SKILL_NAME) {
      throw new Error(`manifest name mismatch: expected '${SKILL_NAME}', got '${manifest.name}'. CLI and bundle are out of sync.`);
    }

    const skillFile = manifest.files[0];
    const skillUrl = `${base}/${skillFile.src}`;
    const skillMd = await fetchText(skillUrl);
    // Integrity gate (verify-before-write): the Cursor adapter doesn't use
    // makeFolderInstallAdapter, so it must apply the same sha256 check the
    // folder adapters get for free. Keeps the manifest-checksum guarantee
    // uniform across all three adapters.
    verifyBundleFile(skillFile, skillMd);
    const fm = parseFrontmatter(skillMd);
    if (!fm.requires_icons) {
      throw new Error("SKILL.md missing requires_icons frontmatter");
    }
    await verifyIconsAvailability(base, manifest, opts.version);

    const exists = await fs.stat(ruleFile).then(() => true).catch(() => false);
    if (exists && !opts.overwrite) {
      const probe = await isOurRuleFile(ruleFile);
      throw new Error(probe.ours
        ? `${ruleFile} already contains an install. Run 'arch-skill update --agent=cursor' to refresh.`
        : `${ruleFile} exists but is not one of ours (no '${SKILL_NAME}' provenance marker). Move/rename the file or remove it manually if intentional.`);
    }

    await fs.mkdir(targetDir, { recursive: true });
    const body = stripFrontmatter(skillMd);
    const rendered = renderRule(body, fm.version ?? manifest.version, fm.requires_icons);
    await fs.writeFile(ruleFile, rendered, "utf8");

    process.stdout.write(`installed ${SKILL_NAME} to ${ruleFile}\n`);
    return 0;
  });
}

async function uninstall(opts: UninstallOptions): Promise<number> {
  return withFatalReturn(async () => {
    const targetDir = await resolveTarget(opts.target ?? defaultTarget());
    const ruleFile = path.join(targetDir, RULE_BASENAME);

    const exists = await fs.stat(ruleFile).then(() => true).catch(() => false);
    if (!exists) {
      process.stdout.write(`(nothing to uninstall at ${ruleFile})\n`);
      return 0;
    }

    const probe = await isOurRuleFile(ruleFile);
    if (!probe.ours) {
      throw new Error(`refusing to remove ${ruleFile} - missing '${SKILL_NAME}' provenance marker. Move/rename the file or remove it manually if intentional.`);
    }

    await fs.unlink(ruleFile);
    process.stdout.write(`uninstalled ${SKILL_NAME} from ${ruleFile}\n`);
    return 0;
  });
}

async function update(opts: UpdateOptions): Promise<number> {
  return withFatalReturn(async () => {
    const targetDir = await resolveTarget(opts.target ?? defaultTarget());
    const ruleFile = path.join(targetDir, RULE_BASENAME);
    const base = baseUrl(opts.version);

    // Already-at-version short-circuit (parity with the folder-install
    // adapters). Read the installed .mdc, extract version from the
    // provenance marker, compare to the upstream manifest's version.
    const probe = await isOurRuleFile(ruleFile);
    if (probe.ours && probe.version) {
      const manifest = await fetchManifest(base);
      if (manifest.name !== SKILL_NAME) {
        throw new Error(`manifest name mismatch: expected '${SKILL_NAME}', got '${manifest.name}'. CLI and bundle are out of sync.`);
      }
      if (probe.version === manifest.version) {
        process.stdout.write(`${SKILL_NAME} already at version ${manifest.version} (no-op)\n`);
        return 0;
      }
    }

    // Otherwise, overwriting install.
    return install({ ...opts, overwrite: true });
  });
}

async function list(opts: ListOptions): Promise<number> {
  return withFatalReturn(async () => {
    const targetDir = await resolveTarget(opts.target ?? defaultTarget());
    const ruleFile = path.join(targetDir, RULE_BASENAME);

    const probe = await isOurRuleFile(ruleFile);
    if (!probe.ours) {
      process.stdout.write("(no skills installed)\n");
      return 0;
    }
    process.stdout.write(`${SKILL_NAME}\t${probe.version ?? "?"}\n`);
    return 0;
  });
}

export const cursorAdapter: Adapter = { install, uninstall, update, list };

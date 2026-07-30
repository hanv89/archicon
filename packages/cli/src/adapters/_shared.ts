import * as fs from "node:fs/promises";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { load as yamlLoad } from "js-yaml";
import pkg from "../../package.json";
import type { Adapter, AdapterOpts, InstallOptions, UninstallOptions, UpdateOptions, ListOptions, Scope } from "./types";

// Shared adapter plumbing. Helpers here must be agent-agnostic — anything
// Claude-Code-specific (default install path, allowed root) lives in the
// adapter file that imports from here. Codex / Cursor / future adapters
// re-use these helpers via the same import path.

export const DEFAULT_BASE_RAW_URL = "https://raw.githubusercontent.com/hanv89/archicon/main";

// Same repo root without the ref segment; baseUrl() appends `main` (default)
// or `skill-vX.Y.Z` when --version is supplied.
const RAW_BASE_NO_REF = "https://raw.githubusercontent.com/hanv89/archicon";

const VERSION_RE = /^\d+\.\d+\.\d+$/;

// SKILL_NAME must stay in lockstep with skills/architecture-diagram/SKILL.md
// frontmatter `name`. Renaming the skill is a breaking change requiring a
// coordinated CLI release; existing installs become un-uninstallable until
// users upgrade the CLI (uninstall's allow-list refuses folders whose
// SKILL.md `name` differs).
export const SKILL_NAME = "architecture-diagram";

// Fetched at install/update time from this repo-relative path. FROZEN: that URL
// is a published contract every released CLI fetches at install time, so moving
// the manifest breaks installs already in users' hands. The skill content moved
// to SKILL_SRC_DIR; the manifest deliberately did not follow it.
// files[0] MUST be SKILL.md so the frontmatter precheck has a stable target.
export const MANIFEST_PATH = "dist/skill/manifest.json";

// Repo-relative directory holding the skill source the manifest's files[].src
// entries point into. FROZEN, for the same reason as MANIFEST_PATH: fetchManifest
// rejects any files[].src outside this dir or LEGACY_SKILL_SRC_DIR, and that
// check is compiled into every CLI published from 1.4.9 onward. Moving the skill
// content anywhere else makes those released CLIs hard-fail the install against
// the new manifest — not degrade, refuse. A move is therefore a coordinated
// breaking release: widen the accepted prefixes here first, let that CLI reach
// users, and only then relocate the content.
export const SKILL_SRC_DIR = "skills/architecture-diagram";

// Where the skill source lived before it moved to SKILL_SRC_DIR. Tags published
// before the move still serve manifests whose files[].src start here, and
// `--version=X.Y.Z` against those tags is a supported install path.
export const LEGACY_SKILL_SRC_DIR = "dist/skill";

export const CANARY_ICON_PATH = "dist/Azure/Compute/AzureVirtualMachine.png";

export const FETCH_TIMEOUT_MS = 30_000;
export const USER_AGENT = `arch-skill/${pkg.version}`;

const ALLOWED_BASE_URL_HOSTS = new Set(["raw.githubusercontent.com"]);
const ALLOWED_BASE_URL_PATH_PREFIX = "/hanv89/archicon/";

export interface ManifestFile {
  src: string;
  dest: string;
  role: "skill" | "example";
  // Optional sha256 (hex, 64 chars) of the fetched file body. When present,
  // the install/update flow verifies the body BEFORE writing it and aborts on
  // mismatch. Bundles built before this field landed omit it; the CLI then
  // proceeds with a one-line warning (back-compat).
  sha256?: string;
}

export interface Manifest {
  name: string;
  version: string;
  requires_icons: string;
  // Exact icons-vX.Y.Z tag this skill bundle was built against. Optional:
  // bundles built before this field landed (skill-v0.7.x and earlier) omit
  // it; the CLI falls back to the requires_icons lower-bound inference.
  icons_version?: string;
  files: ManifestFile[];
}

export interface Frontmatter {
  name?: string;
  version?: string;
  requires_icons?: string;
}

/**
 * Resolve the base URL for fetching the skill bundle.
 *
 * - `version` undefined → `<RAW_BASE>/main` (default, tracks the upstream main branch).
 * - `version="X.Y.Z"`   → `<RAW_BASE>/skill-vX.Y.Z` (tag-pinned fetch).
 * - `ARCH_SKILL_BASE_URL` env set → env override wins; `version` is ignored
 *   (the env exists only for validation harnesses).
 *
 * `version` is validated against the strict X.Y.Z regex here as defense-in-depth;
 * `src/index.ts` also rejects malformed values pre-dispatch.
 */
export function baseUrl(version?: string): string {
  const override = process.env.ARCH_SKILL_BASE_URL;
  if (override) {
    let u: URL;
    try {
      u = new URL(override);
    } catch {
      throw new Error(`ARCH_SKILL_BASE_URL is not a valid URL: ${override}`);
    }
    if (u.protocol !== "https:") {
      throw new Error(`ARCH_SKILL_BASE_URL must use https; got ${u.protocol}`);
    }
    if (!ALLOWED_BASE_URL_HOSTS.has(u.hostname)) {
      throw new Error(`ARCH_SKILL_BASE_URL host '${u.hostname}' not in allow-list (${[...ALLOWED_BASE_URL_HOSTS].join(", ")})`);
    }
    if (!u.pathname.startsWith(ALLOWED_BASE_URL_PATH_PREFIX)) {
      throw new Error(`ARCH_SKILL_BASE_URL path must start with ${ALLOWED_BASE_URL_PATH_PREFIX}`);
    }
    process.stderr.write(`warn: ARCH_SKILL_BASE_URL override active: ${override}\n`);
    return override.replace(/\/$/, "");
  }

  if (version !== undefined) {
    if (!VERSION_RE.test(version)) {
      throw new Error(`--version must match X.Y.Z (got: ${version})`);
    }
    return `${RAW_BASE_NO_REF}/skill-v${version}`;
  }

  return DEFAULT_BASE_RAW_URL;
}

let envTargetRootWarned = false;

/**
 * Resolve `target` and assert it lives inside an allowed root. Resolution
 * follows symlinks (via fs.realpath on the deepest existing ancestor) so
 * a symlink inside an allowed root that points outside cannot bypass the
 * check.
 *
 * `defaultAllowedRoot` is supplied by the adapter (e.g. `~/.claude` for the
 * Claude Code adapter, `~/.codex` for a future Codex adapter). Setting the
 * `ARCH_SKILL_TARGET_ROOT` env var widens the allow-list to include
 * that root (intended for validation/CI use against a `mktemp -d` directory).
 * Production users should never set the env var.
 *
 * `displayName` controls how the default root appears in error messages
 * when the check fails (e.g. `~/.claude` instead of `/home/user/.claude`).
 * Defaults to the resolved absolute path.
 */
export async function safeResolveTarget(
  target: string,
  defaultAllowedRoot: string,
  displayName: string = defaultAllowedRoot,
): Promise<string> {
  const lexicallyResolved = path.resolve(target);

  let probe = lexicallyResolved;
  let realProbe: string | null = null;
  while (true) {
    try {
      realProbe = await fs.realpath(probe);
      break;
    } catch (err: unknown) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== "ENOENT" && code !== "ENOTDIR") throw err;
      const parent = path.dirname(probe);
      if (parent === probe) {
        throw new Error(`unable to resolve target ${target}`);
      }
      probe = parent;
    }
  }
  const tail = lexicallyResolved.slice(probe.length);
  const realResolved = path.resolve(realProbe + tail);

  const explicit = process.env.ARCH_SKILL_TARGET_ROOT;
  if (explicit && !envTargetRootWarned) {
    process.stderr.write(`warn: ARCH_SKILL_TARGET_ROOT override active: ${explicit}\n`);
    envTargetRootWarned = true;
  }

  const allowedRoots = [
    path.resolve(defaultAllowedRoot),
    explicit ? path.resolve(explicit) : null,
  ].filter((r): r is string => r !== null);

  const inside = allowedRoots.some(root => realResolved === root || realResolved.startsWith(root + path.sep));
  if (!inside) {
    const allowList = `${displayName}${explicit ? `, $ARCH_SKILL_TARGET_ROOT=${explicit}` : ""}`;
    throw new Error(`refusing to operate on ${realResolved} (resolved from ${target}) - outside allowed roots (${allowList})`);
  }
  return realResolved;
}

/**
 * Defense-in-depth: assert a manifest `dest` resolves inside `target` before
 * any write/unlink. `fetchManifest` already rejects absolute / `..` paths at
 * the trust boundary; this is the second guard at the filesystem-touch site so
 * a per-file path can never escape the install dir even if the parse-time
 * check is ever bypassed. Returns the safe absolute path.
 */
export function joinWithinTarget(target: string, dest: string): string {
  const full = path.resolve(target, dest);
  const root = path.resolve(target);
  if (full !== root && !full.startsWith(root + path.sep)) {
    throw new Error(`refusing to operate on ${full} (from dest '${dest}') - outside install target ${root}`);
  }
  return full;
}

/**
 * Compute the sha256 of `body` and throw a clear error if it does not match
 * `expectedSha256` (case-insensitive hex compare). Adapter-agnostic so every
 * adapter built on the shared helpers inherits verify-before-write integrity.
 */
export function verifyFileHash(body: string | Buffer, expectedSha256: string): void {
  const actual = crypto.createHash("sha256").update(body).digest("hex");
  if (actual.toLowerCase() !== expectedSha256.toLowerCase()) {
    throw new Error(`sha256 mismatch: expected ${expectedSha256}, computed ${actual}`);
  }
}

/**
 * Fetch with timeout and 2-retry exponential backoff on transient 5xx
 * responses. Used by `fetchText` and `headOk`; both inherit the retry
 * behavior. The 2-retry default was added to absorb transient 5xx upstream
 * errors — future agent adapters reusing this helper get the retry path
 * for free.
 *
 * Backoff schedule: 500ms after attempt 0, 1s after attempt 1, 2s after
 * attempt 2. Network errors (AbortError, DNS failures) re-throw only
 * after the final attempt.
 *
 * @internal — exported only so unit tests can mock `globalThis.fetch`
 *             around it. Not part of the public adapter API.
 */
export async function fetchWithTimeout(
  url: string,
  init: RequestInit = {},
  retries = 2,
): Promise<Response> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    try {
      const res = await fetch(url, {
        ...init,
        signal: ctrl.signal,
        headers: { ...(init.headers || {}), "User-Agent": USER_AGENT },
      });
      if (res.status < 500 || attempt === retries) {
        return res;
      }
    } catch (e) {
      lastError = e;
      if (attempt === retries) throw e;
    } finally {
      clearTimeout(t);
    }
    await new Promise((r) => setTimeout(r, 2 ** attempt * 500));
  }
  throw lastError ?? new Error("fetchWithTimeout: exhausted retries");
}

export async function fetchText(url: string): Promise<string> {
  const res = await fetchWithTimeout(url);
  if (!res.ok) throw new Error(`fetch ${url} returned HTTP ${res.status}`);
  return res.text();
}

export async function headOk(url: string): Promise<boolean> {
  const res = await fetchWithTimeout(url, { method: "HEAD" });
  return res.ok;
}

/**
 * Fetch + parse the bundle manifest. Validates required fields and the
 * SKILL.md-at-index-0 invariant. Throws with a clear error on any issue —
 * callers should not silently fall back.
 */
export async function fetchManifest(base: string): Promise<Manifest> {
  const url = `${base}/${MANIFEST_PATH}`;
  const body = await fetchText(url);
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch (err) {
    throw new Error(`manifest ${url} is not valid JSON: ${err instanceof Error ? err.message : String(err)}`);
  }
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`manifest ${url} did not parse to an object`);
  }
  const m = parsed as Partial<Manifest>;
  for (const key of ["name", "version", "requires_icons"] as const) {
    if (typeof m[key] !== "string" || !m[key]) {
      throw new Error(`manifest ${url} missing required field: ${key}`);
    }
  }
  if (m.icons_version !== undefined) {
    if (typeof m.icons_version !== "string" || !/^\d+\.\d+\.\d+$/.test(m.icons_version)) {
      throw new Error(`manifest ${url} icons_version malformed (must match X.Y.Z): ${String(m.icons_version)}`);
    }
  }
  if (!Array.isArray(m.files) || m.files.length === 0) {
    throw new Error(`manifest ${url} files[] missing or empty`);
  }
  for (const [i, f] of m.files.entries()) {
    if (!f || typeof f !== "object") {
      throw new Error(`manifest ${url} files[${i}] not an object`);
    }
    for (const key of ["src", "dest", "role"] as const) {
      if (typeof (f as Partial<ManifestFile>)[key] !== "string") {
        throw new Error(`manifest ${url} files[${i}].${key} missing`);
      }
    }
    // Optional sha256: when present it must be 64 hex chars. A malformed
    // value is rejected here rather than silently skipped, so a typo in a
    // published manifest cannot quietly disable integrity checking.
    const sha = (f as Partial<ManifestFile>).sha256;
    if (sha !== undefined && (typeof sha !== "string" || !/^[0-9a-fA-F]{64}$/.test(sha))) {
      throw new Error(`manifest ${url} files[${i}].sha256 must be a 64-char hex string (got: ${String(sha)})`);
    }
    // Path-traversal guard: dest/src are joined onto the install target +
    // the fetch base. A manifest from a compromised repo / malicious tag with
    // an absolute path or a `..` segment could escape the target dir (arbitrary
    // file write) or fetch off-path. Reject both here, at the trust boundary.
    for (const key of ["dest", "src"] as const) {
      const p = (f as ManifestFile)[key];
      if (path.isAbsolute(p) || p.split(/[\\/]/).includes("..")) {
        throw new Error(`manifest ${url} files[${i}].${key} must be a relative path with no '..' segment (got: ${p})`);
      }
    }
    // Every src must sit inside the skill source dir. BOTH prefixes are
    // accepted on purpose: tags published before the skill moved still serve
    // manifests rooted at LEGACY_SKILL_SRC_DIR, and `--version=X.Y.Z` against
    // those tags is a supported install path. Narrowing this to the current
    // shape alone would break every pinned install of an older tag.
    const src = (f as ManifestFile).src;
    if (!src.startsWith(`${SKILL_SRC_DIR}/`) && !src.startsWith(`${LEGACY_SKILL_SRC_DIR}/`)) {
      throw new Error(`manifest ${url} files[${i}].src must live under ${SKILL_SRC_DIR}/ or ${LEGACY_SKILL_SRC_DIR}/ (got: ${src})`);
    }
  }
  if (m.files[0].dest !== "SKILL.md" || m.files[0].role !== "skill") {
    throw new Error(`manifest ${url} files[0] must be SKILL.md (role=skill); got dest=${m.files[0].dest} role=${m.files[0].role}`);
  }
  return m as Manifest;
}

/**
 * YAML frontmatter parser. Uses `js-yaml` to handle the full YAML spec
 * (folded scalars `>`, literal block scalars `|`, quoted strings, comments,
 * nested mappings, etc) so SKILL.md frontmatter can grow beyond simple
 * `key: value` pairs without silent mis-parses.
 *
 * Returns only the 3 keys the CLI cares about (`name`, `version`,
 * `requires_icons`); other top-level keys are ignored.
 */
export function parseFrontmatter(md: string): Frontmatter {
  const text = md.replace(/^﻿/, "");
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};
  let parsed: unknown;
  try {
    parsed = yamlLoad(match[1]);
  } catch (err) {
    return {};
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  const obj = parsed as Record<string, unknown>;
  const out: Frontmatter = {};
  for (const key of ["name", "version", "requires_icons"] as const) {
    const raw = obj[key];
    if (typeof raw === "string") {
      out[key] = raw;
    } else if (typeof raw === "number") {
      out[key] = String(raw);
    }
  }
  return out;
}

/**
 * Strip the leading `---\n...\n---\n` YAML frontmatter block from a markdown
 * string. Returns the body unchanged if no frontmatter is detected.
 *
 * Used by adapters that re-render the upstream SKILL.md for a different host
 * (e.g. Cursor's `.mdc` rule files, which carry their own frontmatter shape
 * and embed the SKILL.md body without its original frontmatter).
 */
export function stripFrontmatter(md: string): string {
  const text = md.replace(/^﻿/, "");
  const match = text.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
  return match ? text.slice(match[0].length) : text;
}

/**
 * Test whether an icons-tag semver satisfies the SKILL.md's `requires_icons`
 * constraint. Hand-rolled to keep the runtime dep tree minimal (commander +
 * nothing else; pulling in `semver` would add transitive deps for a feature
 * that today only needs `>=X.Y.Z` matching).
 *
 * Supported constraint forms:
 *   - "X.Y.Z"     (exact match)
 *   - ">=X.Y.Z"   (tag >= constraint)
 *   - "^X.Y.Z"    (same major, tag >= constraint — npm caret semantics)
 *   - "~X.Y.Z"    (same major.minor, tag.patch >= constraint.patch)
 *
 * Throws on any other input. The project's SKILL.md frontmatter only ships
 * `>=X.Y.Z` today; the other 3 forms exist for future-proofing.
 *
 * Numeric encoding `maj * 1e6 + min * 1e3 + pat` rules out individual segments
 * >= 1000 — if a future icons release ever bumps any segment to 4 digits the
 * encoding silently collides (e.g. 1.0.1000 vs 1.1.0). We hard-fail on that
 * input rather than mis-compare.
 */
// Pre-release suffixes (`1.2.3-rc.1`) are intentionally NOT supported here
// or in the `VERSION_RE` regex above. The release workflows tag from main
// only — no rc branches in scope. If pre-release tags ever ship, this
// matcher needs a re-design (build-metadata + precedence ordering).
const SEMVER_SEGMENT_MAX = 999;

export function satisfiesRequiresIcons(constraint: string, iconsSemver: string): boolean {
  const tagParts = iconsSemver.split(".").map(Number);
  if (tagParts.length !== 3 || tagParts.some(n => isNaN(n))) {
    throw new Error(`icons semver malformed: ${iconsSemver}`);
  }
  const [tagMaj, tagMin, tagPat] = tagParts;
  if (tagMaj > SEMVER_SEGMENT_MAX || tagMin > SEMVER_SEGMENT_MAX || tagPat > SEMVER_SEGMENT_MAX) {
    throw new Error(`icons semver segment exceeds matcher capacity (${SEMVER_SEGMENT_MAX}): ${iconsSemver}`);
  }

  const trimmed = constraint.trim().replace(/^["']|["']$/g, "");
  const m = trimmed.match(/^(>=|\^|~|)(\d+)\.(\d+)\.(\d+)$/);
  if (!m) {
    throw new Error(`requires_icons constraint form not supported: ${constraint}`);
  }
  const [, op, majS, minS, patS] = m;
  const maj = Number(majS);
  const min = Number(minS);
  const pat = Number(patS);
  if (maj > SEMVER_SEGMENT_MAX || min > SEMVER_SEGMENT_MAX || pat > SEMVER_SEGMENT_MAX) {
    throw new Error(`requires_icons segment exceeds matcher capacity (${SEMVER_SEGMENT_MAX}): ${constraint}`);
  }
  const tag = tagMaj * 1e6 + tagMin * 1e3 + tagPat;
  const ref = maj * 1e6 + min * 1e3 + pat;

  if (op === "")    return tag === ref;
  if (op === ">=")  return tag >= ref;
  if (op === "^")   return tagMaj === maj && tag >= ref;
  if (op === "~")   return tagMaj === maj && tagMin === min && tagPat >= pat;
  throw new Error(`unreachable constraint op: ${op}`);
}

/**
 * Verify the icon set the skill bundle references is reachable AND its
 * semver satisfies SKILL.md's requires_icons.
 *
 * Source of the icons-tag, in priority order:
 *   1. `manifest.icons_version` — exact tag (preferred).
 *   2. Lower-bound parse of `manifest.requires_icons` — fallback for
 *      bundles published before the field landed (cannot be edited
 *      retroactively on a tag).
 *
 * The fallback path makes the gate trivially pass by construction (a
 * lower bound always satisfies its own constraint), preserving install
 * behaviour for older tags. New bundles ship the field, so the gate
 * becomes a real cross-track compatibility check going forward.
 */
export async function verifyIconsAvailability(
  base: string,
  manifest: Manifest,
  requestedVersion: string | undefined,
): Promise<void> {
  const requires = manifest.requires_icons;

  const canaryUrl = `${base}/${CANARY_ICON_PATH}`;
  const reachable = await headOk(canaryUrl);
  if (!reachable) {
    throw new Error(`icon-set unreachable - HEAD ${canaryUrl} failed (skill declares requires_icons=${requires})`);
  }

  if (!requestedVersion) {
    return;
  }

  let iconsTagSemver: string;
  let source: string;
  if (manifest.icons_version) {
    iconsTagSemver = manifest.icons_version;
    source = `manifest icons_version`;
  } else {
    const lowerMatch = requires.match(/(\d+\.\d+\.\d+)/);
    if (!lowerMatch) {
      throw new Error(`SKILL.md requires_icons has no parseable lower bound: ${requires}`);
    }
    iconsTagSemver = lowerMatch[1];
    source = `requires_icons lower-bound (bundle has no icons_version field)`;
  }

  if (!satisfiesRequiresIcons(requires, iconsTagSemver)) {
    throw new Error(`requires_icons constraint ${requires} not satisfied by ${source} ${iconsTagSemver}`);
  }
}

export async function withFatalReturn(fn: () => Promise<number>): Promise<number> {
  try {
    return await fn();
  } catch (err) {
    process.stderr.write(`fatal: ${err instanceof Error ? err.message : String(err)}\n`);
    return 1;
  }
}

/**
 * Build a "folder install" adapter — the install shape shared by Claude Code
 * and Codex CLI, both of which manage a per-user skills folder containing
 * `<skill-name>/SKILL.md` + bundled examples.
 *
 * Configuration:
 *   - `rootDir()`     — absolute path to the agent's root (e.g. `~/.claude` or `~/.codex`).
 *   - `rootDisplay()` — human-readable name for the root (used in error messages).
 *   - `agentFlag`     — value of the `--agent=<flag>` for THIS adapter (used in error messages).
 *
 * Returns an `Adapter` with the same 4 methods every adapter ships. Cursor
 * does NOT use this factory because its on-disk layout (single .mdc file at
 * `<cwd>/.cursor/rules/`) is structurally different.
 */
export interface FolderAdapterConfig {
  /**
   * Absolute path to the agent's root dir for the given scope (the install-scope feature).
   *   `user`    → e.g. `~/.claude`  (personal across all repos)
   *   `project` → e.g. `<cwd>/.claude`  (team-shared via git)
   * Adapter implementations decide the per-scope mapping (claude-code +
   * codex follow the `~/.<agent>` vs `<cwd>/.<agent>` pattern; cursor does
   * not use this factory because its on-disk layout differs).
   */
  rootDir(scope: Scope): string;
  /** Human-readable name for the per-scope root (e.g. `~/.claude` vs `./.claude`). Used in error messages. */
  rootDisplay(scope: Scope): string;
  agentFlag: string;
}

// Persisted at install time so uninstall can iterate the file list without
// re-fetching the manifest over the network. Hidden filename so it doesn't
// clutter the user-visible skill folder.
//
// LOAD-BEARING: this basename is the only signal uninstall has to
// distinguish a current-era install from a pre-0.9.0 install (when no
// manifest was persisted). Renaming this constant is a one-way migration:
// installs done under the old name fall into the legacy whole-folder
// `rm -rf` path, which still works but loses the manifest-scoped
// preservation of user-authored content alongside the skill. If renamed,
// keep at least one release cycle of dual-read support.
const PERSISTED_MANIFEST_BASENAME = ".arch-skill-manifest.json";

export function makeFolderInstallAdapter(cfg: FolderAdapterConfig): Adapter {
  // Install-scope flag: per-scope path resolution. `user` is the backward-compat default
  // (the pre-flag default). `--scope=project` opts into `<cwd>/.<agent>/skills/...` for team-shared
  // installs checked in via git.
  const pickScope = (opts: AdapterOpts): Scope => opts.scope ?? "user";
  const defaultTarget = (scope: Scope): string => path.join(cfg.rootDir(scope), "skills", SKILL_NAME);
  const defaultSkillsRoot = (scope: Scope): string => path.join(cfg.rootDir(scope), "skills");
  const resolve = (target: string, scope: Scope): Promise<string> =>
    safeResolveTarget(target, cfg.rootDir(scope), cfg.rootDisplay(scope));

  const isOurSkillDir = async (dir: string): Promise<boolean> => {
    try {
      const skillMd = await fs.readFile(path.join(dir, "SKILL.md"), "utf8");
      return parseFrontmatter(skillMd).name === SKILL_NAME;
    } catch {
      return false;
    }
  };

  async function install(opts: InstallOptions): Promise<number> {
    return withFatalReturn(async () => {
      const scope = pickScope(opts);
      const target = await resolve(opts.target ?? defaultTarget(scope), scope);
      const base = baseUrl(opts.version);

      if (!process.env.ARCH_SKILL_TARGET_ROOT && path.basename(target) !== SKILL_NAME) {
        throw new Error(`refusing to install at ${target} - target basename must be '${SKILL_NAME}' (default ${cfg.rootDisplay(scope)}/skills/${SKILL_NAME}/). Set ARCH_SKILL_TARGET_ROOT to install into a custom test root.`);
      }

      const manifest = await fetchManifest(base);
      if (manifest.name !== SKILL_NAME) {
        throw new Error(`manifest name mismatch: expected '${SKILL_NAME}', got '${manifest.name}'. CLI and bundle are out of sync.`);
      }

      const presence = await Promise.all(
        manifest.files.map(async ({ dest }) => ({
          dest,
          exists: await fs.stat(path.join(target, dest)).then(() => true).catch(() => false),
        })),
      );
      const someExist = presence.some(p => p.exists);
      const allExist = presence.every(p => p.exists);
      if (someExist && !opts.overwrite) {
        throw new Error(allExist
          ? `${target} already contains an install. Run 'arch-skill update --agent=${cfg.agentFlag}' to refresh.`
          : `${target} contains a partial install (${presence.filter(p => !p.exists).map(p => p.dest).join(", ")} missing). Run 'arch-skill update --agent=${cfg.agentFlag}' to repair.`);
      }

      const skillFile = manifest.files[0];
      const skillUrl = `${base}/${skillFile.src}`;
      const skillMd = await fetchText(skillUrl);
      // Integrity gate (verify-before-write) for SKILL.md. See verifyBundleFile.
      verifyBundleFile(skillFile, skillMd);
      const fm = parseFrontmatter(skillMd);
      if (!fm.requires_icons) {
        throw new Error("SKILL.md missing requires_icons frontmatter");
      }
      await verifyIconsAvailability(base, manifest, opts.version);

      // Fetch + verify every remaining file BEFORE writing any of them, so an
      // integrity failure aborts the whole install with nothing written.
      const remaining = manifest.files.slice(1);
      const remainingBodies: { dest: string; body: string }[] = [];
      for (const f of remaining) {
        const body = await fetchText(`${base}/${f.src}`);
        verifyBundleFile(f, body);
        remainingBodies.push({ dest: f.dest, body });
      }

      for (const { dest } of manifest.files) {
        await fs.mkdir(path.dirname(joinWithinTarget(target, dest)), { recursive: true });
      }
      await fs.writeFile(joinWithinTarget(target, skillFile.dest), skillMd, "utf8");
      for (const { dest, body } of remainingBodies) {
        await fs.writeFile(joinWithinTarget(target, dest), body, "utf8");
      }

      // Persist the manifest so uninstall can iterate the file list without
      // re-fetching from the network.
      await fs.writeFile(
        path.join(target, PERSISTED_MANIFEST_BASENAME),
        JSON.stringify(manifest, null, 2) + "\n",
        "utf8",
      );

      process.stdout.write(`installed ${SKILL_NAME} to ${target}\n`);
      return 0;
    });
  }

  async function uninstall(opts: UninstallOptions): Promise<number> {
    return withFatalReturn(async () => {
      const scope = pickScope(opts);
      const target = await resolve(opts.target ?? defaultTarget(scope), scope);

      const exists = await fs.stat(target).then(() => true).catch(() => false);
      if (!exists) {
        process.stdout.write(`(nothing to uninstall at ${target})\n`);
        return 0;
      }

      const ours = await isOurSkillDir(target);
      if (!ours) {
        throw new Error(`refusing to remove ${target} - not an architecture-diagram skill folder (no matching SKILL.md). Move/rename the directory or remove it manually if intentional.`);
      }

      // Manifest-scoped removal: read the persisted manifest at install time
      // and remove only its files + the manifest itself. Leaves any
      // user-authored content under the same folder in place (with a note).
      // Fallback: bundles installed before 0.9.0 have no persisted manifest;
      // legacy whole-folder rm preserves the pre-0.9.0 behaviour.
      const persistedPath = path.join(target, PERSISTED_MANIFEST_BASENAME);
      const manifestBody = await fs.readFile(persistedPath, "utf8").catch(() => null);

      if (!manifestBody) {
        // Legacy uninstall: rm -rf whole folder.
        try {
          await fs.rm(target, { recursive: true, force: false });
        } catch (err) {
          const stillExists = await fs.stat(target).then(() => true).catch(() => false);
          if (stillExists) {
            const msg = err instanceof Error ? err.message : String(err);
            throw new Error(`uninstall partially failed at ${target}: ${msg}; manual cleanup may be required`);
          }
          throw err;
        }
      } else {
        let persistedManifest: Manifest;
        try {
          persistedManifest = JSON.parse(manifestBody) as Manifest;
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          throw new Error(`persisted manifest at ${persistedPath} is not valid JSON: ${msg}. Remove the file manually then retry.`);
        }
        for (const f of persistedManifest.files) {
          // joinWithinTarget guards against a tampered persisted manifest whose
          // dest escapes target (which would delete files outside the install).
          let victim: string;
          try { victim = joinWithinTarget(target, f.dest); } catch { continue; }
          await fs.unlink(victim).catch(() => null);
        }
        await fs.unlink(persistedPath).catch(() => null);

        // Recursively prune empty directories under target. Stop at target
        // itself — only rmdir target if no user-authored files remain.
        const pruneEmptyDirs = async (dir: string): Promise<void> => {
          const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => []);
          for (const e of entries) {
            if (e.isDirectory()) {
              await pruneEmptyDirs(path.join(dir, e.name));
              const subEntries = await fs.readdir(path.join(dir, e.name)).catch(() => []);
              if (subEntries.length === 0) {
                await fs.rmdir(path.join(dir, e.name)).catch(() => null);
              }
            }
          }
        };
        await pruneEmptyDirs(target);

        const leftover = await fs.readdir(target).catch(() => []);
        if (leftover.length === 0) {
          await fs.rmdir(target).catch(() => null);
        } else {
          process.stdout.write(`note: ${target} contains files outside the skill manifest; left in place. Remove manually if intentional.\n`);
        }
      }

      process.stdout.write(`uninstalled ${SKILL_NAME} from ${target}\n`);
      return 0;
    });
  }

  async function update(opts: UpdateOptions): Promise<number> {
    return withFatalReturn(async () => {
      const scope = pickScope(opts);
      const target = await resolve(opts.target ?? defaultTarget(scope), scope);
      const base = baseUrl(opts.version);
      const manifest = await fetchManifest(base);
      if (manifest.name !== SKILL_NAME) {
        throw new Error(`manifest name mismatch: expected '${SKILL_NAME}', got '${manifest.name}'. CLI and bundle are out of sync.`);
      }

      // Already-at-version short-circuit: read the on-disk SKILL.md
      // frontmatter version and compare to manifest. Equal -> no-op.
      const installedSkillMdPath = path.join(target, "SKILL.md");
      const installedBody = await fs.readFile(installedSkillMdPath, "utf8").catch(() => null);
      if (installedBody) {
        const fmInstalled = parseFrontmatter(installedBody);
        if (fmInstalled.version && fmInstalled.version === manifest.version) {
          process.stdout.write(`${SKILL_NAME} already at version ${manifest.version} (no-op)\n`);
          return 0;
        }
      }

      // Otherwise proceed with overwriting install (the existing path).
      return install({ ...opts, overwrite: true });
    });
  }

  async function list(opts: ListOptions): Promise<number> {
    return withFatalReturn(async () => {
      // Install-scope flag: `list` scans BOTH user + project scope roots by default so
      // a user sees every scope a skill is installed in. `--scope=user` or
      // `--scope=project` restricts to one. `--target=<path>` overrides scope
      // entirely (legacy behavior).
      const scopesToScan: Scope[] = opts.target
        ? [pickScope(opts)]
        : opts.scope
        ? [opts.scope]
        : ["user", "project"];

      const allRows: string[] = [];
      for (const scope of scopesToScan) {
        const root = opts.target
          ? await resolve(opts.target, scope)
          : await resolve(defaultSkillsRoot(scope), scope);
        const exists = await fs.stat(root).then(() => true).catch(() => false);
        if (!exists) continue;
        const entries = await fs.readdir(root, { withFileTypes: true });
        for (const e of entries) {
          if (!e.isDirectory()) continue;
          const skillMdPath = path.join(root, e.name, "SKILL.md");
          try {
            const md = await fs.readFile(skillMdPath, "utf8");
            const fm = parseFrontmatter(md);
            allRows.push(`${fm.name ?? e.name}\t${scope}\t${fm.version ?? "?"}\t${path.join(root, e.name)}`);
          } catch {
            // not a skill folder; skip silently
          }
        }
      }
      process.stdout.write(allRows.length ? allRows.join("\n") + "\n" : "(no skills installed)\n");
      return 0;
    });
  }

  return { install, uninstall, update, list };
}

/**
 * Supply-chain integrity gate for a single bundle file, applied AFTER the
 * body is fetched and BEFORE it is written to disk.
 *
 * - manifest entry HAS `sha256` → verify; mismatch throws and aborts install.
 * - manifest entry has NO `sha256` (back-compat) → print one-line `warn:` and
 *   proceed, so older manifests keep installing.
 *
 * Lives in _shared.ts so every adapter built on makeFolderInstallAdapter (and
 * future adapters reusing these helpers) inherits the check for free.
 */
export function verifyBundleFile(file: ManifestFile, body: string | Buffer): void {
  if (file.sha256) {
    verifyFileHash(body, file.sha256);
  } else {
    process.stderr.write(`warn: manifest entry ${file.dest} has no sha256; skipping integrity check\n`);
  }
}

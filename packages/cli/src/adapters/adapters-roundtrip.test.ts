import { test } from "node:test";
import assert from "node:assert/strict";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { Adapter } from "./types";
import { ADAPTERS } from "./registry";
import { parseFrontmatter } from "./_shared";
import {
  installFetchMock,
  mkTmpdir,
  rmTmpdir,
  SYNTHETIC_VERSION,
  SYNTHETIC_SKILL_MD,
  SYNTHETIC_EXAMPLE,
  SYNTHETIC_REQUIRES_ICONS,
  SYNTHETIC_ICONS_VERSION,
} from "../__test_fixtures__/synthetic-bundle";

const realFetch = globalThis.fetch;

// A fetch-mock that advertises a sha256 for SKILL.md in the manifest but
// serves a TAMPERED body whose hash will not match. Used to prove the
// _shared.ts verify-before-write integrity check is enforced through every
// adapter's install path (it is adapter-agnostic, so this is a regression
// guard against any adapter bypassing fetchText/verifyFileHash).
function tamperedSkillFetchMock(): { restore: () => void } {
  const honestSha = crypto.createHash("sha256").update(SYNTHETIC_SKILL_MD).digest("hex");
  const exampleSha = crypto.createHash("sha256").update(SYNTHETIC_EXAMPLE).digest("hex");
  const manifest = {
    $schema: "./manifest.schema.json",
    name: "architecture-diagram",
    version: SYNTHETIC_VERSION,
    requires_icons: SYNTHETIC_REQUIRES_ICONS,
    icons_version: SYNTHETIC_ICONS_VERSION,
    files: [
      { src: "dist/skill/SKILL.md", dest: "SKILL.md", role: "skill", sha256: honestSha },
      { src: "dist/skill/examples/01-context.puml", dest: "examples/01-context.puml", role: "example", sha256: exampleSha },
    ],
  };
  globalThis.fetch = (async (url: any, init?: any) => {
    const u = url.toString();
    const method = (init?.method ?? "GET").toUpperCase();
    if (method === "HEAD") return new Response(null, { status: 200 });
    if (u.endsWith("/dist/skill/manifest.json")) {
      return new Response(JSON.stringify(manifest), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u.endsWith("/dist/skill/SKILL.md")) {
      // Body tampered: real frontmatter (so name/requires_icons checks pass)
      // but appended bytes so the sha256 no longer matches the manifest.
      return new Response(SYNTHETIC_SKILL_MD + "\n<!-- tampered -->\n", { status: 200 });
    }
    if (u.endsWith("/dist/skill/examples/01-context.puml")) {
      return new Response(SYNTHETIC_EXAMPLE, { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;
  return { restore: () => { globalThis.fetch = realFetch; } };
}

// ---- Adapter round-trip (install → list → uninstall) ----
// Iterates over every adapter in the shared registry. Adding a new adapter
// is a one-line entry in registry.ts plus (if the adapter writes a different
// on-disk layout than the manifest-mirror default) one EXPECTATIONS entry.

// Per-adapter assertion overrides for adapters whose on-disk layout differs
// from the default manifest-mirror (Claude Code + Codex install a folder
// containing SKILL.md + examples/; Cursor installs a single .mdc file).
interface Expectations {
  installedFile: (target: string) => string;
  readdirAt: (skillsRoot: string, target: string) => string;
  expectedTopEntries: string[];
  listTarget: (skillsRoot: string, target: string) => string;
  uninstallProbeMissing: (target: string) => string;
}

const FOLDER_INSTALL: Expectations = {
  installedFile: (t) => path.join(t, "SKILL.md"),
  readdirAt: (skillsRoot) => skillsRoot,
  expectedTopEntries: ["architecture-diagram"],
  listTarget: (skillsRoot) => skillsRoot,
  uninstallProbeMissing: (t) => t,
};

const CURSOR_INSTALL: Expectations = {
  installedFile: (t) => path.join(t, "arch-skill.mdc"),
  readdirAt: (_skillsRoot, target) => target,
  expectedTopEntries: ["arch-skill.mdc"],
  listTarget: (_skillsRoot, target) => target,
  uninstallProbeMissing: (t) => path.join(t, "arch-skill.mdc"),
};

const EXPECTATIONS: Record<string, Expectations> = {
  "claude-code": FOLDER_INSTALL,
  "codex":       FOLDER_INSTALL,
  "cursor":      CURSOR_INSTALL,
};

const ADAPTER_ENTRIES = Object.entries(ADAPTERS) as Array<[string, Adapter]>;

// Meta-test: every adapter registered in ADAPTERS must have an EXPECTATIONS
// entry, otherwise the round-trip suite silently skips it. Fails fast at
// test-run time rather than during a later release smoke.
test("meta: every registered adapter has an EXPECTATIONS entry", () => {
  const missing = Object.keys(ADAPTERS).filter(name => !EXPECTATIONS[name]);
  assert.deepEqual(missing, [], `adapters missing EXPECTATIONS: ${missing.join(", ")}`);
});

for (const [name, adapter] of ADAPTER_ENTRIES) {
  const exp = EXPECTATIONS[name];

  test(`${name} round-trip: install writes SKILL.md + example into target`, async () => {
    const tmpdir = mkTmpdir();
    const target = path.join(tmpdir, "skills", "architecture-diagram");
    const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
    process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
    const { restore } = installFetchMock();
    try {
      const exit = await adapter.install({ target });
      assert.equal(exit, 0);
      assert.ok(fs.existsSync(exp.installedFile(target)), `installed file present at ${exp.installedFile(target)}`);
      const written = fs.readFileSync(exp.installedFile(target), "utf8");
      assert.ok(written.startsWith("---"), "installed file preserves frontmatter");
      assert.match(written, /architecture-diagram/);
    } finally {
      restore();
      if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
      else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
      rmTmpdir(tmpdir);
    }
  });

  test(`${name} round-trip: list after install discovers the installed skill`, async () => {
    // Assert via fs + parseFrontmatter rather than capturing list()'s stdout —
    // see synthetic-bundle.ts silenceStderr() note for the gotcha.
    const tmpdir = mkTmpdir();
    const skillsRoot = path.join(tmpdir, "skills");
    const target = path.join(skillsRoot, "architecture-diagram");
    const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
    process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
    const { restore } = installFetchMock();
    try {
      await adapter.install({ target });

      const skillEntries = fs.readdirSync(exp.readdirAt(skillsRoot, target), { withFileTypes: true }).map(d => d.name);
      assert.deepEqual(skillEntries, exp.expectedTopEntries, "post-install directory contains exactly the expected entries");

      const installedPath = exp.installedFile(target);
      const body = fs.readFileSync(installedPath, "utf8");
      const fm = parseFrontmatter(body);
      if (name === "cursor") {
        assert.match(body, new RegExp(`<!--\\s*architecture-diagram\\s+v${SYNTHETIC_VERSION.replace(/\./g, "\\.")}\\s+`));
      } else {
        assert.equal(fm.name, "architecture-diagram");
        assert.equal(fm.version, SYNTHETIC_VERSION);
      }

      const exit = await adapter.list({ target: exp.listTarget(skillsRoot, target) });
      assert.equal(exit, 0);
    } finally {
      restore();
      if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
      else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
      rmTmpdir(tmpdir);
    }
  });

  test(`${name} round-trip: uninstall removes the installed skill`, async () => {
    const tmpdir = mkTmpdir();
    const target = path.join(tmpdir, "skills", "architecture-diagram");
    const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
    process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
    const { restore } = installFetchMock();
    try {
      await adapter.install({ target });
      assert.ok(fs.existsSync(exp.installedFile(target)), "precondition: install landed");
      const exit = await adapter.uninstall({ target });
      assert.equal(exit, 0);
      assert.equal(fs.existsSync(exp.uninstallProbeMissing(target)), false, "post-uninstall: target absent");
    } finally {
      restore();
      if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
      else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
      rmTmpdir(tmpdir);
    }
  });

  test(`${name} round-trip: install rejects a body whose sha256 mismatches the manifest`, async () => {
    const tmpdir = mkTmpdir();
    const target = path.join(tmpdir, "skills", "architecture-diagram");
    const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
    process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
    const { restore } = tamperedSkillFetchMock();
    const origStderr = process.stderr.write.bind(process.stderr);
    (process.stderr.write as any) = (_chunk: any) => true;
    try {
      const exit = await adapter.install({ target });
      assert.equal(exit, 1, "tampered SKILL.md body must fail the sha256 verify-before-write check");
      assert.equal(fs.existsSync(exp.installedFile(target)), false, "no file written when integrity check fails");
    } finally {
      process.stderr.write = origStderr as any;
      restore();
      if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
      else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
      rmTmpdir(tmpdir);
    }
  });
}

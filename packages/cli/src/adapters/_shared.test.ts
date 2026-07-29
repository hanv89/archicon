import { test } from "node:test";
import assert from "node:assert/strict";
import * as crypto from "node:crypto";
import * as fsp from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import {
  safeResolveTarget,
  baseUrl,
  fetchManifest,
  stripFrontmatter,
  joinWithinTarget,
  verifyFileHash,
  MANIFEST_PATH,
} from "./_shared";

// ---------------------------------------------------------------------------
// MANIFEST_PATH — frozen published contract.
// ---------------------------------------------------------------------------

test("MANIFEST_PATH is frozen at dist/skill/manifest.json", () => {
  // Every CLI version already published to npm has this path compiled in and
  // fetches it from the repo at install time. Moving the manifest breaks
  // installs and updates for releases already in users' hands — a change here
  // is a breaking release, never a tidy-up. The skill content moved to
  // skills/architecture-diagram/; the manifest deliberately did not follow.
  assert.equal(MANIFEST_PATH, "dist/skill/manifest.json");
});

// ---------------------------------------------------------------------------
// safeResolveTarget — the symlink/escape security guard.
// ---------------------------------------------------------------------------

test("safeResolveTarget: target inside the allowed root resolves", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-root-"));
  try {
    const target = path.join(root, "skills", "architecture-diagram");
    const resolved = await safeResolveTarget(target, root);
    assert.equal(resolved, path.resolve(target));
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test("safeResolveTarget: target outside the allowed root is refused", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-root-"));
  const outside = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-out-"));
  try {
    await assert.rejects(
      () => safeResolveTarget(path.join(outside, "x"), root),
      /outside allowed roots/,
    );
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
    await fsp.rm(outside, { recursive: true, force: true });
  }
});

test("safeResolveTarget: a symlink inside root that points outside is refused (realpath escape)", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-root-"));
  const outside = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-out-"));
  try {
    const link = path.join(root, "escape");
    await fsp.symlink(outside, link); // root/escape -> /tmp/sr-out-XXXX
    await assert.rejects(
      () => safeResolveTarget(path.join(link, "skill"), root),
      /outside allowed roots/,
    );
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
    await fsp.rm(outside, { recursive: true, force: true });
  }
});

test("safeResolveTarget: ARCH_SKILL_TARGET_ROOT widens the allow-list", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-root-"));
  const widened = await fsp.mkdtemp(path.join(os.tmpdir(), "sr-wide-"));
  const prev = process.env.ARCH_SKILL_TARGET_ROOT;
  try {
    process.env.ARCH_SKILL_TARGET_ROOT = widened;
    const target = path.join(widened, "skills", "x");
    const resolved = await safeResolveTarget(target, root);
    assert.equal(resolved, path.resolve(target));
  } finally {
    if (prev === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prev;
    await fsp.rm(root, { recursive: true, force: true });
    await fsp.rm(widened, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// baseUrl — ARCH_SKILL_BASE_URL override allow-list.
// ---------------------------------------------------------------------------

function withBaseUrlEnv(value: string | undefined, fn: () => void): void {
  const prev = process.env.ARCH_SKILL_BASE_URL;
  if (value === undefined) delete process.env.ARCH_SKILL_BASE_URL;
  else process.env.ARCH_SKILL_BASE_URL = value;
  try { fn(); }
  finally {
    if (prev === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prev;
  }
}

test("baseUrl: valid raw.githubusercontent.com override is returned (trailing slash stripped)", () => {
  withBaseUrlEnv(
    "https://raw.githubusercontent.com/hanv89/archicon/main/",
    () => {
      assert.equal(
        baseUrl(),
        "https://raw.githubusercontent.com/hanv89/archicon/main",
      );
    },
  );
});

test("baseUrl: non-https override is rejected", () => {
  withBaseUrlEnv("http://raw.githubusercontent.com/hanv89/archicon/main", () => {
    assert.throws(() => baseUrl(), /must use https/);
  });
});

test("baseUrl: off-allow-list host is rejected", () => {
  withBaseUrlEnv("https://evil.example.com/hanv89/archicon/main", () => {
    assert.throws(() => baseUrl(), /not in allow-list/);
  });
});

test("baseUrl: wrong path prefix is rejected", () => {
  withBaseUrlEnv("https://raw.githubusercontent.com/someone-else/other-repo/main", () => {
    assert.throws(() => baseUrl(), /path must start with/);
  });
});

// ---------------------------------------------------------------------------
// fetchManifest — error paths (previously only the happy path via integration).
// ---------------------------------------------------------------------------

function mockFetchBody(body: string, status = 200): { restore: () => void } {
  const real = globalThis.fetch;
  globalThis.fetch = (async () => new Response(body, { status })) as typeof fetch;
  return { restore: () => { globalThis.fetch = real; } };
}

const BASE = "https://raw.githubusercontent.com/hanv89/archicon/main";

test("fetchManifest: malformed JSON throws a clear error", async () => {
  const m = mockFetchBody("{ not json");
  try {
    await assert.rejects(() => fetchManifest(BASE), /is not valid JSON/);
  } finally { m.restore(); }
});

test("fetchManifest: missing required field throws", async () => {
  const m = mockFetchBody(JSON.stringify({ name: "x", version: "1.0.0" })); // no requires_icons / files
  try {
    await assert.rejects(() => fetchManifest(BASE), /missing required field|files\[\] missing/);
  } finally { m.restore(); }
});

test("fetchManifest: files[0] not SKILL.md is rejected", async () => {
  const m = mockFetchBody(JSON.stringify({
    name: "x", version: "1.0.0", requires_icons: ">=1.0.0",
    files: [{ src: "skills/architecture-diagram/examples/01.puml", dest: "examples/01.puml", role: "example" }],
  }));
  try {
    await assert.rejects(() => fetchManifest(BASE), /files\[0\] must be SKILL\.md/);
  } finally { m.restore(); }
});

test("fetchManifest: valid manifest parses", async () => {
  const m = mockFetchBody(JSON.stringify({
    name: "architecture-diagram", version: "1.4.2", requires_icons: ">=1.4.0",
    icons_version: "1.4.0",
    files: [{ src: "skills/architecture-diagram/SKILL.md", dest: "SKILL.md", role: "skill" }],
  }));
  try {
    const parsed = await fetchManifest(BASE);
    assert.equal(parsed.name, "architecture-diagram");
    assert.equal(parsed.files[0].dest, "SKILL.md");
  } finally { m.restore(); }
});

test("fetchManifest: valid manifest with a per-file sha256 parses", async () => {
  const sha = crypto.createHash("sha256").update("x").digest("hex");
  const m = mockFetchBody(JSON.stringify({
    name: "architecture-diagram", version: "1.4.2", requires_icons: ">=1.4.0",
    icons_version: "1.4.0",
    files: [{ src: "skills/architecture-diagram/SKILL.md", dest: "SKILL.md", role: "skill", sha256: sha }],
  }));
  try {
    const parsed = await fetchManifest(BASE);
    assert.equal(parsed.files[0].sha256, sha);
  } finally { m.restore(); }
});

test("fetchManifest: malformed sha256 (not 64 hex) is rejected", async () => {
  const m = mockFetchBody(JSON.stringify({
    name: "architecture-diagram", version: "1.4.2", requires_icons: ">=1.4.0",
    files: [{ src: "skills/architecture-diagram/SKILL.md", dest: "SKILL.md", role: "skill", sha256: "deadbeef" }],
  }));
  try {
    await assert.rejects(() => fetchManifest(BASE), /sha256 must be a 64-char hex string/);
  } finally { m.restore(); }
});

// ---------------------------------------------------------------------------
// stripFrontmatter.
// ---------------------------------------------------------------------------

test("stripFrontmatter: removes the leading --- block", () => {
  const md = "---\nname: x\nversion: 1.0.0\n---\n# Body\ntext";
  assert.equal(stripFrontmatter(md), "# Body\ntext");
});

test("stripFrontmatter: returns body unchanged when no frontmatter", () => {
  const md = "# Body\nno frontmatter here";
  assert.equal(stripFrontmatter(md), md);
});

test("stripFrontmatter: CRLF frontmatter handled", () => {
  const md = "---\r\nname: x\r\n---\r\n# Body";
  assert.equal(stripFrontmatter(md), "# Body");
});

// ---------------------------------------------------------------------------
// verifyFileHash — supply-chain integrity (sha256 verify-before-write).
// ---------------------------------------------------------------------------

test("verifyFileHash: a body whose sha256 matches the expected value passes", () => {
  const body = "the skill bundle content";
  const expected = crypto.createHash("sha256").update(body).digest("hex");
  assert.doesNotThrow(() => verifyFileHash(body, expected));
});

test("verifyFileHash: a mismatching sha256 throws", () => {
  const body = "the skill bundle content";
  const wrong = crypto.createHash("sha256").update("different content").digest("hex");
  assert.throws(() => verifyFileHash(body, wrong), /sha256 mismatch/);
});

test("verifyFileHash: hex comparison is case-insensitive", () => {
  const body = "content";
  const expected = crypto.createHash("sha256").update(body).digest("hex").toUpperCase();
  assert.doesNotThrow(() => verifyFileHash(body, expected));
});

test("verifyFileHash: Buffer body is hashed the same as its string form", () => {
  const body = Buffer.from("binary-ish content", "utf8");
  const expected = crypto.createHash("sha256").update(body).digest("hex");
  assert.doesNotThrow(() => verifyFileHash(body, expected));
});

// ---------------------------------------------------------------------------
// Path-traversal hardening (manifest dest/src). A malicious served manifest
// must not be able to escape the install target.
// ---------------------------------------------------------------------------

const VALID_SKILL = { src: "skills/architecture-diagram/SKILL.md", dest: "SKILL.md", role: "skill" };
function manifestWith(extra: object) {
  return JSON.stringify({
    name: "architecture-diagram", version: "1.6.3", requires_icons: ">=1.4.0",
    icons_version: "1.4.0", files: [VALID_SKILL, extra],
  });
}

test("fetchManifest: rejects a `..` traversal in dest", async () => {
  const m = mockFetchBody(manifestWith({ src: "skills/architecture-diagram/x.puml", dest: "../../../../.bashrc", role: "example" }));
  try { await assert.rejects(() => fetchManifest(BASE), /relative path with no '\.\.'/); }
  finally { m.restore(); }
});

test("fetchManifest: rejects an absolute dest", async () => {
  const m = mockFetchBody(manifestWith({ src: "skills/architecture-diagram/x.puml", dest: "/etc/cron.d/evil", role: "example" }));
  try { await assert.rejects(() => fetchManifest(BASE), /relative path with no/); }
  finally { m.restore(); }
});

test("fetchManifest: rejects a `..` traversal in src", async () => {
  const m = mockFetchBody(manifestWith({ src: "../../../secret", dest: "examples/x.puml", role: "example" }));
  try { await assert.rejects(() => fetchManifest(BASE), /relative path with no/); }
  finally { m.restore(); }
});

test("joinWithinTarget: returns the path for an in-target dest", () => {
  const t = "/home/u/.claude/skills/architecture-diagram";
  assert.equal(joinWithinTarget(t, "examples/01.puml"), path.join(t, "examples/01.puml"));
});

test("joinWithinTarget: throws on an escaping dest", () => {
  const t = "/home/u/.claude/skills/architecture-diagram";
  assert.throws(() => joinWithinTarget(t, "../../../../.bashrc"), /outside install target/);
});

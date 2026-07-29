import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { baseUrl, satisfiesRequiresIcons, verifyIconsAvailability, Manifest } from "./adapters/_shared";
import { claudeCodeAdapter } from "./adapters/claude-code";
import { provenanceMarker, PROVENANCE_RE } from "./adapters/cursor";
import {
  mkTmpdir,
  rmTmpdir,
  SYNTHETIC_SKILL_MD,
  SYNTHETIC_MANIFEST,
  SYNTHETIC_EXAMPLE,
} from "./__test_fixtures__/synthetic-bundle";

// ---- satisfiesRequiresIcons unit tests ----

test("satisfiesRequiresIcons: exact match", () => {
  assert.equal(satisfiesRequiresIcons("0.2.2", "0.2.2"), true);
});

test("satisfiesRequiresIcons: exact mismatch", () => {
  assert.equal(satisfiesRequiresIcons("0.2.2", "0.3.0"), false);
});

test("satisfiesRequiresIcons: >= passes when tag >= constraint", () => {
  assert.equal(satisfiesRequiresIcons(">=0.2.0", "0.5.0"), true);
  assert.equal(satisfiesRequiresIcons(">=0.2.0", "0.2.0"), true);
});

test("satisfiesRequiresIcons: >= fails when tag < constraint", () => {
  assert.equal(satisfiesRequiresIcons(">=0.5.0", "0.4.9"), false);
});

test("satisfiesRequiresIcons: caret same major passes", () => {
  assert.equal(satisfiesRequiresIcons("^0.2.0", "0.5.0"), true);
});

test("satisfiesRequiresIcons: caret different major fails", () => {
  assert.equal(satisfiesRequiresIcons("^0.2.0", "1.0.0"), false);
});

test("satisfiesRequiresIcons: tilde same major.minor passes", () => {
  assert.equal(satisfiesRequiresIcons("~0.2.0", "0.2.5"), true);
});

test("satisfiesRequiresIcons: tilde different minor fails", () => {
  assert.equal(satisfiesRequiresIcons("~0.2.0", "0.3.0"), false);
});

test("satisfiesRequiresIcons: quoted constraint normalised", () => {
  assert.equal(satisfiesRequiresIcons('">=0.2.2"', "0.5.0"), true);
});

test("satisfiesRequiresIcons: unsupported constraint form throws", () => {
  assert.throws(() => satisfiesRequiresIcons("<1.0.0", "0.5.0"), /not supported/);
  assert.throws(() => satisfiesRequiresIcons(">0.2.0", "0.5.0"), /not supported/);
});

test("satisfiesRequiresIcons: malformed icons semver throws", () => {
  assert.throws(() => satisfiesRequiresIcons(">=0.2.0", "not.a.semver"), /malformed/);
});

test("satisfiesRequiresIcons: 4-digit segment throws (encoding capacity guard)", () => {
  assert.throws(() => satisfiesRequiresIcons(">=0.2.0", "0.0.1000"), /exceeds matcher capacity/);
  assert.throws(() => satisfiesRequiresIcons(">=0.0.1000", "0.5.0"), /exceeds matcher capacity/);
});

// ---- baseUrl(version?) unit tests ----

test("baseUrl(): default returns main ref", () => {
  const prev = process.env.ARCH_SKILL_BASE_URL;
  delete process.env.ARCH_SKILL_BASE_URL;
  try {
    const url = baseUrl();
    assert.ok(url.endsWith("/main"), `expected default URL to end with /main, got: ${url}`);
    assert.ok(url.startsWith("https://raw.githubusercontent.com/hanv89/"));
  } finally {
    if (prev === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prev;
  }
});

test("baseUrl('0.5.0'): returns tag-pinned ref", () => {
  const prev = process.env.ARCH_SKILL_BASE_URL;
  delete process.env.ARCH_SKILL_BASE_URL;
  try {
    const url = baseUrl("0.5.0");
    assert.ok(url.endsWith("/skill-v0.5.0"), `expected URL to end with /skill-v0.5.0, got: ${url}`);
  } finally {
    if (prev === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prev;
  }
});

test("baseUrl('invalid'): throws X.Y.Z error", () => {
  const prev = process.env.ARCH_SKILL_BASE_URL;
  delete process.env.ARCH_SKILL_BASE_URL;
  try {
    assert.throws(() => baseUrl("invalid"), /must match X\.Y\.Z/);
    assert.throws(() => baseUrl("v1.2.3"),  /must match X\.Y\.Z/);
    assert.throws(() => baseUrl("1.2"),     /must match X\.Y\.Z/);
  } finally {
    if (prev === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prev;
  }
});

// ---- Cursor provenance marker round-trip ----

test("Cursor: PROVENANCE_RE parses what provenanceMarker writes", () => {
  const marker = provenanceMarker("1.2.3", ">=0.1.0");
  const match = marker.match(PROVENANCE_RE);
  assert.ok(match, `PROVENANCE_RE failed to parse marker: ${marker}`);
  assert.equal(match![1], "1.2.3");
  assert.equal(match![2], ">=0.1.0");
});

// ---- verifyIconsAvailability: icons_version field handling ----

function makeManifest(overrides: Partial<Manifest> = {}): Manifest {
  return {
    name: "architecture-diagram",
    version: "0.8.0",
    requires_icons: ">=0.2.2",
    icons_version: "0.2.2",
    files: [{ src: "skills/architecture-diagram/SKILL.md", dest: "SKILL.md", role: "skill" }],
    ...overrides,
  };
}

// All three tests below mock fetch to make HEAD canary succeed; the test
// substance is what verifyIconsAvailability does AFTER that succeeds.
function mockHeadOk(): { restore: () => void } {
  const real = globalThis.fetch;
  globalThis.fetch = (async (_url: any, init?: any) => {
    const method = (init?.method ?? "GET").toUpperCase();
    if (method === "HEAD") return new Response(null, { status: 200 });
    return new Response("unexpected", { status: 500 });
  }) as typeof fetch;
  return { restore: () => { globalThis.fetch = real; } };
}

test("verifyIconsAvailability: prefers manifest.icons_version when present", async () => {
  const mock = mockHeadOk();
  try {
    await verifyIconsAvailability(
      "https://raw.githubusercontent.com/hanv89/archicon/skill-v0.8.0",
      makeManifest({ requires_icons: ">=0.2.2", icons_version: "0.2.2" }),
      "0.8.0",
    );
    // No throw → field path was used + satisfied the constraint.
  } finally {
    mock.restore();
  }
});

test("verifyIconsAvailability: throws when icons_version mismatches requires_icons", async () => {
  const mock = mockHeadOk();
  try {
    await assert.rejects(
      () => verifyIconsAvailability(
        "https://raw.githubusercontent.com/hanv89/archicon/skill-v0.8.0",
        makeManifest({ requires_icons: ">=0.3.0", icons_version: "0.2.2" }),
        "0.8.0",
      ),
      /not satisfied by manifest icons_version 0\.2\.2/,
    );
  } finally {
    mock.restore();
  }
});

test("verifyIconsAvailability: falls back to lower-bound when icons_version absent", async () => {
  const mock = mockHeadOk();
  try {
    const m = makeManifest({ requires_icons: ">=0.2.2" });
    delete m.icons_version;
    await verifyIconsAvailability(
      "https://raw.githubusercontent.com/hanv89/archicon/skill-v0.5.0",
      m,
      "0.5.0",
    );
    // No throw → fallback path (pre-1.6.5 bundle) trivially satisfies.
  } finally {
    mock.restore();
  }
});

// ---- --version integration: claude-code install asserts the fetched URL is tag-pinned ----

const realFetch = globalThis.fetch;

test("--version=0.5.0 integration: install fetches from skill-v0.5.0 ref", async () => {
  const tmpdir = mkTmpdir();
  const target = path.join(tmpdir, "skills", "architecture-diagram");
  const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
  const prevBase = process.env.ARCH_SKILL_BASE_URL;
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
  delete process.env.ARCH_SKILL_BASE_URL;

  const requestedUrls: string[] = [];
  globalThis.fetch = (async (url: any, init?: any) => {
    const u = url.toString();
    requestedUrls.push(u);
    const method = (init?.method ?? "GET").toUpperCase();
    if (method === "HEAD") return new Response(null, { status: 200 });
    if (u.endsWith("/dist/skill/manifest.json")) {
      return new Response(JSON.stringify(SYNTHETIC_MANIFEST), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u.endsWith("/skills/architecture-diagram/SKILL.md")) return new Response(SYNTHETIC_SKILL_MD, { status: 200 });
    if (u.endsWith("/skills/architecture-diagram/examples/01-context.puml")) {
      return new Response(SYNTHETIC_EXAMPLE, { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;

  try {
    const exit = await claudeCodeAdapter.install({ target, version: "0.5.0" });
    assert.equal(exit, 0);

    const tagPinned = requestedUrls.filter(u => u.includes("/skill-v0.5.0/"));
    assert.ok(tagPinned.length >= 1, `expected at least one URL with /skill-v0.5.0/, got: ${JSON.stringify(requestedUrls)}`);

    // Match the ref segment itself, not a path under it. An earlier form
    // checked "/main/dist/", which was equivalent only while every fetched
    // file lived under dist/. Now that SKILL.md and the examples sit under
    // skills/, that form would miss an unpinned fetch of exactly the files
    // this test exists to protect. No legitimate path segment is named
    // "main", so the ref position is the only thing this can match.
    const mainRefHit = requestedUrls.filter(u => u.includes("/main/"));
    assert.equal(mainRefHit.length, 0, `expected no /main/ URLs when --version is set, got: ${JSON.stringify(mainRefHit)}`);
  } finally {
    globalThis.fetch = realFetch;
    if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
    if (prevBase === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prevBase;
    rmTmpdir(tmpdir);
  }
});

test("--version=99.99.99 integration: fetch 404 surfaces as fatal error", async () => {
  const tmpdir = mkTmpdir();
  const target = path.join(tmpdir, "skills", "architecture-diagram");
  const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
  const prevBase = process.env.ARCH_SKILL_BASE_URL;
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
  delete process.env.ARCH_SKILL_BASE_URL;

  globalThis.fetch = (async () => new Response("not found", { status: 404 })) as typeof fetch;

  const origStderr = process.stderr.write.bind(process.stderr);
  (process.stderr.write as any) = (_chunk: any) => true;

  try {
    const exit = await claudeCodeAdapter.install({ target, version: "99.99.99" });
    assert.equal(exit, 1, "non-existent tag should produce exit 1");
  } finally {
    process.stderr.write = origStderr as any;
    globalThis.fetch = realFetch;
    if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
    if (prevBase === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prevBase;
    rmTmpdir(tmpdir);
  }
});

// ---- Idempotency: update no-op + uninstall manifest-scoped + legacy fallback ----

test("update: already-at-version emits no-op, does not re-fetch examples", async () => {
  const tmpdir = mkTmpdir();
  const target = path.join(tmpdir, "skills", "architecture-diagram");
  const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
  const prevBase = process.env.ARCH_SKILL_BASE_URL;
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
  delete process.env.ARCH_SKILL_BASE_URL;

  // First: install at SYNTHETIC_VERSION (0.5.0) via the standard mock.
  const installMock = (await import("./__test_fixtures__/synthetic-bundle")).installFetchMock();
  try {
    await claudeCodeAdapter.install({ target, version: "0.5.0" });
  } finally {
    installMock.restore();
  }

  // Now: a second fetch-mock that returns the SAME manifest version (0.5.0)
  // but counts how many non-manifest fetches happen. If update short-circuits,
  // only manifest.json + HEAD canary should be fetched — no SKILL.md/example.
  const realFetchInner = globalThis.fetch;
  const fetchedUrls: string[] = [];
  globalThis.fetch = (async (url: any, init?: any) => {
    const u = url.toString();
    const method = (init?.method ?? "GET").toUpperCase();
    fetchedUrls.push(`${method} ${u}`);
    if (method === "HEAD") return new Response(null, { status: 200 });
    if (u.endsWith("/dist/skill/manifest.json")) {
      return new Response(JSON.stringify(SYNTHETIC_MANIFEST), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u.endsWith("/skills/architecture-diagram/SKILL.md")) {
      return new Response(SYNTHETIC_SKILL_MD, { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;

  const origStdout = process.stdout.write.bind(process.stdout);
  let captured = "";
  (process.stdout.write as any) = (chunk: any) => { captured += typeof chunk === "string" ? chunk : chunk.toString(); return true; };

  try {
    const exit = await claudeCodeAdapter.update({ target, version: "0.5.0" });
    process.stdout.write = origStdout as any;
    assert.equal(exit, 0);
    assert.match(captured, /already at version 0\.5\.0 \(no-op\)/);
    // No SKILL.md GET should have happened during update (only manifest + HEAD).
    const skillMdGets = fetchedUrls.filter(u => u.startsWith("GET ") && u.endsWith("/skills/architecture-diagram/SKILL.md"));
    assert.equal(skillMdGets.length, 0, `expected zero SKILL.md GETs during no-op update, got: ${JSON.stringify(skillMdGets)}`);
  } finally {
    process.stdout.write = origStdout as any;
    globalThis.fetch = realFetchInner;
    if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
    if (prevBase === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prevBase;
    rmTmpdir(tmpdir);
  }
});

test("uninstall: manifest-scoped removal preserves out-of-manifest files", async () => {
  const tmpdir = mkTmpdir();
  const target = path.join(tmpdir, "skills", "architecture-diagram");
  const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;

  const mock = (await import("./__test_fixtures__/synthetic-bundle")).installFetchMock();
  try {
    await claudeCodeAdapter.install({ target });
    // Drop a user-authored file into the same folder.
    await import("node:fs/promises").then(p => p.writeFile(path.join(target, "user-notes.md"), "my notes\n", "utf8"));

    const origStdout = process.stdout.write.bind(process.stdout);
    let captured = "";
    (process.stdout.write as any) = (chunk: any) => { captured += typeof chunk === "string" ? chunk : chunk.toString(); return true; };

    try {
      const exit = await claudeCodeAdapter.uninstall({ target });
      process.stdout.write = origStdout as any;
      assert.equal(exit, 0);
      assert.match(captured, /contains files outside the skill manifest; left in place/);
      // user-notes.md still present; SKILL.md gone.
      const userNotesExists = await import("node:fs/promises").then(p => p.stat(path.join(target, "user-notes.md")).then(() => true).catch(() => false));
      const skillMdGone = await import("node:fs/promises").then(p => p.stat(path.join(target, "SKILL.md")).then(() => false).catch(() => true));
      assert.equal(userNotesExists, true, "user-notes.md preserved");
      assert.equal(skillMdGone, true, "SKILL.md removed");
    } finally {
      process.stdout.write = origStdout as any;
    }
  } finally {
    mock.restore();
    if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
    rmTmpdir(tmpdir);
  }
});

test("uninstall: legacy install (no persisted manifest) falls back to rm -rf", async () => {
  // Simulate a pre-0.9.0 install by writing SKILL.md + example but NOT the
  // persisted manifest. Verify uninstall falls back to whole-folder removal.
  const tmpdir = mkTmpdir();
  const target = path.join(tmpdir, "skills", "architecture-diagram");
  const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;

  const fsp = await import("node:fs/promises");
  await fsp.mkdir(path.join(target, "examples"), { recursive: true });
  await fsp.writeFile(path.join(target, "SKILL.md"), SYNTHETIC_SKILL_MD, "utf8");
  await fsp.writeFile(path.join(target, "examples/01-context.puml"), "@startuml\n@enduml\n", "utf8");
  // No .arch-skill-manifest.json — this is the legacy condition.

  try {
    const exit = await claudeCodeAdapter.uninstall({ target });
    assert.equal(exit, 0);
    const dirGone = await fsp.stat(target).then(() => false).catch(() => true);
    assert.equal(dirGone, true, "legacy uninstall removed the whole folder");
  } finally {
    if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
    rmTmpdir(tmpdir);
  }
});

// ---- Cursor adapter idempotency parity ----

test("cursor: update already-at-version emits no-op, does not overwrite", async () => {
  const { cursorAdapter } = await import("./adapters/cursor");
  const tmpdir = mkTmpdir();
  const target = path.join(tmpdir, ".cursor", "rules");
  const prevHome = process.env.HOME;
  const prevCwd = process.cwd();
  const prevEnv = process.env.ARCH_SKILL_TARGET_ROOT;
  const prevBase = process.env.ARCH_SKILL_BASE_URL;
  process.env.HOME = tmpdir;
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
  process.chdir(tmpdir);
  delete process.env.ARCH_SKILL_BASE_URL;

  // First install via the standard mock.
  const installMock = (await import("./__test_fixtures__/synthetic-bundle")).installFetchMock();
  try {
    await cursorAdapter.install({ target });
  } finally {
    installMock.restore();
  }

  // Now a second fetch-mock counting GETs.
  const realFetchInner = globalThis.fetch;
  const fetchedUrls: string[] = [];
  globalThis.fetch = (async (url: any, init?: any) => {
    const u = url.toString();
    const method = (init?.method ?? "GET").toUpperCase();
    fetchedUrls.push(`${method} ${u}`);
    if (method === "HEAD") return new Response(null, { status: 200 });
    if (u.endsWith("/dist/skill/manifest.json")) {
      return new Response(JSON.stringify(SYNTHETIC_MANIFEST), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u.endsWith("/skills/architecture-diagram/SKILL.md")) {
      return new Response(SYNTHETIC_SKILL_MD, { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;

  const origStdout = process.stdout.write.bind(process.stdout);
  let captured = "";
  (process.stdout.write as any) = (chunk: any) => { captured += typeof chunk === "string" ? chunk : chunk.toString(); return true; };

  try {
    const exit = await cursorAdapter.update({ target });
    process.stdout.write = origStdout as any;
    assert.equal(exit, 0);
    assert.match(captured, /already at version 0\.5\.0 \(no-op\)/);
    // No SKILL.md GET during update — only manifest.json (and no HEADs because
    // verifyIconsAvailability is only called in install, not update no-op).
    const skillMdGets = fetchedUrls.filter(u => u.startsWith("GET ") && u.endsWith("/skills/architecture-diagram/SKILL.md"));
    assert.equal(skillMdGets.length, 0, `expected zero SKILL.md GETs during Cursor no-op update, got: ${JSON.stringify(skillMdGets)}`);
  } finally {
    process.stdout.write = origStdout as any;
    globalThis.fetch = realFetchInner;
    process.chdir(prevCwd);
    if (prevHome === undefined) delete process.env.HOME;
    else process.env.HOME = prevHome;
    if (prevEnv === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
    else process.env.ARCH_SKILL_TARGET_ROOT = prevEnv;
    if (prevBase === undefined) delete process.env.ARCH_SKILL_BASE_URL;
    else process.env.ARCH_SKILL_BASE_URL = prevBase;
    rmTmpdir(tmpdir);
  }
});

// Use fs imports so node:test doesn't complain about unused imports.
void fs;

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// Synthetic skill bundle used by every test suite that mocks the network.
// Keeping all three suites (adapters-roundtrip, all, version) on the same
// fixture eliminates per-file drift (e.g. SKILL.md version: 0.5.0 vs 0.6.0
// landed in earlier test files because the fixture was copy-pasted).

export const SYNTHETIC_VERSION = "0.5.0";
export const SYNTHETIC_REQUIRES_ICONS = ">=0.2.2";
export const SYNTHETIC_ICONS_VERSION = "0.2.2";

export const SYNTHETIC_SKILL_MD = [
  "---",
  "name: architecture-diagram",
  "description: test fixture",
  `version: ${SYNTHETIC_VERSION}`,
  `requires_icons: "${SYNTHETIC_REQUIRES_ICONS}"`,
  "---",
  "# Test skill body",
  "",
  "This is a synthetic SKILL.md used only by the test fixtures.",
].join("\n");

export const SYNTHETIC_EXAMPLE = "@startuml\ntitle Test\n@enduml\n";

export const SYNTHETIC_MANIFEST = {
  $schema: "./manifest.schema.json",
  name: "architecture-diagram",
  version: SYNTHETIC_VERSION,
  requires_icons: SYNTHETIC_REQUIRES_ICONS,
  icons_version: SYNTHETIC_ICONS_VERSION,
  files: [
    { src: "skills/architecture-diagram/SKILL.md", dest: "SKILL.md", role: "skill" },
    { src: "skills/architecture-diagram/examples/01-context.puml", dest: "examples/01-context.puml", role: "example" },
  ],
};

const realFetch = globalThis.fetch;

/**
 * Returns 200 for the manifest, SKILL.md, and the one bundled example;
 * 200 for any HEAD; 404 otherwise.
 */
export function installFetchMock(): { restore: () => void } {
  globalThis.fetch = (async (url: any, init?: any) => {
    const u = url.toString();
    const method = (init?.method ?? "GET").toUpperCase();
    if (method === "HEAD") {
      return new Response(null, { status: 200 });
    }
    if (u.endsWith("/dist/skill/manifest.json")) {
      return new Response(JSON.stringify(SYNTHETIC_MANIFEST), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u.endsWith("/skills/architecture-diagram/SKILL.md")) {
      return new Response(SYNTHETIC_SKILL_MD, { status: 200 });
    }
    if (u.endsWith("/skills/architecture-diagram/examples/01-context.puml")) {
      return new Response(SYNTHETIC_EXAMPLE, { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;
  return { restore: () => { globalThis.fetch = realFetch; } };
}

/**
 * Like `installFetchMock` but the Nth HEAD request returns 404. Used by
 * the rollback test to fail the third adapter's canary while the first
 * two have already installed.
 */
export function failOnNthHeadFetchMock(failOnHeadIndex: number): { restore: () => void; headCount: () => number } {
  let headCount = 0;
  globalThis.fetch = (async (url: any, init?: any) => {
    const u = url.toString();
    const method = (init?.method ?? "GET").toUpperCase();
    if (method === "HEAD") {
      headCount++;
      if (headCount === failOnHeadIndex) {
        return new Response(null, { status: 404 });
      }
      return new Response(null, { status: 200 });
    }
    if (u.endsWith("/dist/skill/manifest.json")) {
      return new Response(JSON.stringify(SYNTHETIC_MANIFEST), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u.endsWith("/skills/architecture-diagram/SKILL.md")) {
      return new Response(SYNTHETIC_SKILL_MD, { status: 200 });
    }
    if (u.endsWith("/skills/architecture-diagram/examples/01-context.puml")) {
      return new Response(SYNTHETIC_EXAMPLE, { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;
  return {
    restore: () => { globalThis.fetch = realFetch; },
    headCount: () => headCount,
  };
}

export function mkTmpdir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "arch-skill-test-"));
}

export function rmTmpdir(dir: string): void {
  fs.rmSync(dir, { recursive: true, force: true });
}

// Silence stderr summary lines so the test reporter's output stays readable.
// IMPORTANT: do NOT silence stdout. Hijacking process.stdout.write inside a
// node:test test confuses the runner's buffered reporter — other tests' ✔
// lines get eaten by the capture buffer and silently drop from the count.
export function silenceStderr(): { restore: () => void } {
  const orig = process.stderr.write.bind(process.stderr);
  (process.stderr.write as any) = (_chunk: any) => true;
  return { restore: () => { process.stderr.write = orig as any; } };
}

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { runOverAll } from "./all";
import {
  installFetchMock as happyFetchMock,
  failOnNthHeadFetchMock,
  mkTmpdir,
  rmTmpdir,
  silenceStderr,
} from "./__test_fixtures__/synthetic-bundle";

// All three adapters' default targets resolve under the env-var widened root.
// claude-code → <root>/.claude/skills/architecture-diagram/
// codex       → <root>/.codex/skills/architecture-diagram/
// cursor      → <root>/.cursor/rules/arch-skill.mdc  (cwd-relative by design — per-project rule discovery)
// For the tests we set HOME = tmpdir AND cwd = tmpdir so all three resolve under it.

interface IsolatedEnv {
  tmpdir: string;
  restore: () => void;
}

function isolateEnv(): IsolatedEnv {
  const tmpdir = mkTmpdir();
  const prevTargetRoot = process.env.ARCH_SKILL_TARGET_ROOT;
  const prevHome = process.env.HOME;
  const prevCwd = process.cwd();
  process.env.ARCH_SKILL_TARGET_ROOT = tmpdir;
  process.env.HOME = tmpdir;
  process.chdir(tmpdir);
  return {
    tmpdir,
    restore: () => {
      process.chdir(prevCwd);
      if (prevHome === undefined) delete process.env.HOME;
      else process.env.HOME = prevHome;
      if (prevTargetRoot === undefined) delete process.env.ARCH_SKILL_TARGET_ROOT;
      else process.env.ARCH_SKILL_TARGET_ROOT = prevTargetRoot;
      rmTmpdir(tmpdir);
    },
  };
}

function claudeInstallPath(home: string): string {
  return path.join(home, ".claude", "skills", "architecture-diagram");
}
function codexInstallPath(home: string): string {
  return path.join(home, ".codex", "skills", "architecture-diagram");
}
function cursorRulePath(cwd: string): string {
  return path.join(cwd, ".cursor", "rules", "arch-skill.mdc");
}

test("runOverAll install --agent=all happy: all three adapters install successfully", async () => {
  const env = isolateEnv();
  const mock = happyFetchMock();
  const silent = silenceStderr();
  try {
    const exit = await runOverAll("install", {});
    assert.equal(exit, 0);
    assert.ok(fs.existsSync(path.join(claudeInstallPath(env.tmpdir), "SKILL.md")), "claude-code SKILL.md present");
    assert.ok(fs.existsSync(path.join(codexInstallPath(env.tmpdir), "SKILL.md")), "codex SKILL.md present");
    assert.ok(fs.existsSync(cursorRulePath(env.tmpdir)), "cursor .mdc present");
  } finally {
    silent.restore();
    mock.restore();
    env.restore();
  }
});

test("runOverAll install --agent=all rollback: 3rd-adapter fail unrolls the earlier installs", async () => {
  const env = isolateEnv();
  // HEAD 1 succeeds (claude-code canary) → claude installs.
  // HEAD 2 succeeds (codex canary)       → codex installs.
  // HEAD 3 fails    (cursor canary)      → cursor install throws; dispatcher rolls back.
  const mock = failOnNthHeadFetchMock(3);
  const silent = silenceStderr();
  try {
    const exit = await runOverAll("install", {});
    assert.equal(exit, 1, "exit code is 1 when any adapter fails");
    assert.equal(fs.existsSync(claudeInstallPath(env.tmpdir)), false, "claude-code rolled back (folder removed)");
    assert.equal(fs.existsSync(codexInstallPath(env.tmpdir)), false, "codex rolled back (folder removed)");
    assert.equal(fs.existsSync(cursorRulePath(env.tmpdir)), false, "cursor never wrote (failed at canary)");
    assert.equal(mock.headCount(), 3, "exactly 3 HEAD requests = halted before the rollback's HEADs would have fired");
  } finally {
    silent.restore();
    mock.restore();
    env.restore();
  }
});

test("runOverAll uninstall --agent=all best-effort: empty state is exit 0 per-adapter", async () => {
  const env = isolateEnv();
  const silent = silenceStderr();
  try {
    const exit = await runOverAll("uninstall", {});
    assert.equal(exit, 0, "no installed state → each adapter exits 0 → aggregate exit 0");
  } finally {
    silent.restore();
    env.restore();
  }
});

test("runOverAll list --agent=all: post-install lists all three adapters", async () => {
  const env = isolateEnv();
  const mock = happyFetchMock();
  const silent = silenceStderr();
  const origStdout = process.stdout.write.bind(process.stdout);
  let captured = "";
  try {
    await runOverAll("install", {});

    (process.stdout.write as any) = (chunk: any) => {
      captured += typeof chunk === "string" ? chunk : chunk.toString();
      return true;
    };
    const exit = await runOverAll("list", {});
    process.stdout.write = origStdout as any;

    assert.equal(exit, 0);
    const matches = captured.match(/architecture-diagram/g) ?? [];
    assert.ok(matches.length >= 3, `expected 3+ adapter list lines, captured: ${JSON.stringify(captured)}`);
  } finally {
    process.stdout.write = origStdout as any;
    silent.restore();
    mock.restore();
    env.restore();
  }
});

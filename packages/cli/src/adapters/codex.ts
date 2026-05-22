import * as path from "node:path";
import * as os from "node:os";
import { Adapter } from "./types";
import { makeFolderInstallAdapter } from "./_shared";

// Codex CLI discovers user-installed skills at $CODEX_HOME/skills/<name>/SKILL.md,
// defaulting to ~/.codex/skills/ when CODEX_HOME is unset. Verified against the
// Codex Rust binary's bundled prompt strings. See https://github.com/openai/codex.

function codexRootDir(): string {
  const explicit = process.env.CODEX_HOME;
  if (explicit) return path.resolve(explicit);
  return path.join(os.homedir(), ".codex");
}

function codexRootDisplay(): string {
  return process.env.CODEX_HOME ? `$CODEX_HOME=${process.env.CODEX_HOME}` : "~/.codex";
}

export const codexAdapter: Adapter = makeFolderInstallAdapter({
  rootDir: codexRootDir,
  rootDisplay: codexRootDisplay,
  agentFlag: "codex",
});

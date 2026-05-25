import * as path from "node:path";
import * as os from "node:os";
import { Adapter, Scope } from "./types";
import { makeFolderInstallAdapter } from "./_shared";

// Codex CLI discovers user-installed skills at $CODEX_HOME/skills/<name>/SKILL.md,
// defaulting to ~/.codex/skills/ when CODEX_HOME is unset. Verified against the
// Codex Rust binary's bundled prompt strings. See https://github.com/openai/codex.
//
// Install-scope flag: scope-aware root.
//   user    → $CODEX_HOME ?? ~/.codex/skills/...   (personal across all repos; default)
//   project → <cwd>/.codex/skills/...              (team-shared via git; opt-in via --scope=project)
// Note: $CODEX_HOME applies only to user scope. Project scope intentionally ignores
// $CODEX_HOME because the project's `./.codex/` is the contractual location for
// team-shared installs and should not be reconfigurable via env.

function codexRootDir(scope: Scope): string {
  if (scope === "project") {
    return path.join(process.cwd(), ".codex");
  }
  const explicit = process.env.CODEX_HOME;
  if (explicit) return path.resolve(explicit);
  return path.join(os.homedir(), ".codex");
}

function codexRootDisplay(scope: Scope): string {
  if (scope === "project") return "./.codex";
  return process.env.CODEX_HOME ? `$CODEX_HOME=${process.env.CODEX_HOME}` : "~/.codex";
}

export const codexAdapter: Adapter = makeFolderInstallAdapter({
  rootDir: codexRootDir,
  rootDisplay: codexRootDisplay,
  agentFlag: "codex",
});

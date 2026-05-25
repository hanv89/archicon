import * as path from "node:path";
import * as os from "node:os";
import { Adapter, Scope } from "./types";
import { makeFolderInstallAdapter } from "./_shared";

// Install-scope flag: scope-aware root.
//   user    → ~/.claude/skills/...     (personal across all repos; default)
//   project → <cwd>/.claude/skills/... (team-shared via git; opt-in via --scope=project)
function claudeRootDir(scope: Scope): string {
  return scope === "project"
    ? path.join(process.cwd(), ".claude")
    : path.join(os.homedir(), ".claude");
}

function claudeRootDisplay(scope: Scope): string {
  return scope === "project" ? "./.claude" : "~/.claude";
}

export const claudeCodeAdapter: Adapter = makeFolderInstallAdapter({
  rootDir: claudeRootDir,
  rootDisplay: claudeRootDisplay,
  agentFlag: "claude-code",
});

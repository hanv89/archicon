import * as path from "node:path";
import * as os from "node:os";
import { Adapter } from "./types";
import { makeFolderInstallAdapter } from "./_shared";

function claudeRootDir(): string {
  return path.join(os.homedir(), ".claude");
}

export const claudeCodeAdapter: Adapter = makeFolderInstallAdapter({
  rootDir: claudeRootDir,
  rootDisplay: () => "~/.claude",
  agentFlag: "claude-code",
});

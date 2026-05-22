import { Adapter } from "./types";
import { claudeCodeAdapter } from "./claude-code";

// Single source of truth for the supported-agent set. Add a new adapter by
// importing it here and adding one entry below; both `src/index.ts` (CLI
// dispatch + --agent help text) reads from this map directly.
//
// Only the Claude Code adapter ships in this phase; Codex / Cursor / the
// `--agent=all` fan-out land in a later port.

export const ADAPTERS = {
  "claude-code": claudeCodeAdapter,
} as const satisfies Record<string, Adapter>;

export type AgentName = keyof typeof ADAPTERS;

export const SUPPORTED_AGENTS: AgentName[] = Object.keys(ADAPTERS) as AgentName[];

/** Full target set the CLI's `--agent` flag accepts. */
export const SUPPORTED_TARGETS: ReadonlyArray<AgentName> = [...SUPPORTED_AGENTS];

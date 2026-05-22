import { Adapter, AdapterOpts } from "./adapters/types";
import { ADAPTERS, AgentName, SUPPORTED_AGENTS } from "./adapters/registry";

// Dispatcher for --agent=all. Iterates the agent registry and applies one
// of two semantics depending on subcommand:
//
//   install / update — TRANSACTIONAL: first failure halts the loop, then
//     the dispatcher rolls back each adapter that already succeeded this
//     invocation by calling its `uninstall(opts)` in LIFO order. Rollback
//     itself is best-effort; if a compensating uninstall fails, log + move
//     on (the alternative leaves more partial state on disk).
//
//   uninstall / list — BEST-EFFORT: per-adapter failure is logged but does
//     not halt the loop. Aggregate exit code = 0 iff every adapter exited 0.
//
// Pre-existing installs are never rolled back: `completed[]` only carries
// adapters whose install/update succeeded *this invocation*.

export type Subcommand = keyof Adapter;

interface AdapterOutcome {
  agent: AgentName;
  exit: number;
  error?: Error;
}

export async function runOverAll(sub: Subcommand, opts: AdapterOpts): Promise<number> {
  if (SUPPORTED_AGENTS.length === 0) {
    throw new Error("no adapters loaded in registry (registry.ts ADAPTERS is empty)");
  }

  const completed: AgentName[] = [];
  const successes: AgentName[] = [];
  const failures: AdapterOutcome[] = [];
  const isTransactional = sub === "install" || sub === "update";

  for (const agent of SUPPORTED_AGENTS) {
    const adapter = ADAPTERS[agent];
    const outcome = await runOne(adapter, agent, sub, opts);
    if (outcome.exit === 0) {
      successes.push(agent);
      if (isTransactional) completed.push(agent);
    } else {
      failures.push(outcome);
      if (isTransactional) break; // halt + roll back below
      // uninstall / list: best-effort, keep going
    }
  }

  const rolledBack: AgentName[] = [];
  if (isTransactional && failures.length > 0) {
    for (const agent of completed.slice().reverse()) {
      try {
        const exit = await ADAPTERS[agent].uninstall(opts);
        if (exit === 0) {
          rolledBack.push(agent);
        } else {
          process.stderr.write(`fatal: rollback failed for ${agent}: uninstall exited ${exit}\n`);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        process.stderr.write(`fatal: rollback failed for ${agent}: ${msg}\n`);
        // continue with the rest (best-effort cleanup)
      }
    }
  }

  process.stderr.write(formatSummary(sub, successes, failures, rolledBack, isTransactional));
  return failures.length > 0 ? 1 : 0;
}

async function runOne(adapter: Adapter, agent: AgentName, sub: Subcommand, opts: AdapterOpts): Promise<AdapterOutcome> {
  try {
    // All four Adapter methods now accept the same AdapterOpts shape (see types.ts).
    const exit = await adapter[sub](opts);
    return { agent, exit };
  } catch (err) {
    return { agent, exit: 1, error: err instanceof Error ? err : new Error(String(err)) };
  }
}

function formatSummary(
  sub: Subcommand,
  successes: AgentName[],
  failures: AdapterOutcome[],
  rolledBack: AgentName[],
  isTransactional: boolean,
): string {
  const fmt = (list: string[], fallback: string) => `[${list.length > 0 ? list.join(", ") : fallback}]`;
  const succLabel = fmt(successes, "(none)");
  const failLabel = fmt(failures.map(f => f.agent), "(none)");
  const rbLabel = isTransactional ? fmt(rolledBack, "(none)") : "[(n/a)]";
  return `--agent=all (${sub}): succeeded=${succLabel} failed=${failLabel} rolled-back=${rbLabel}\n`;
}

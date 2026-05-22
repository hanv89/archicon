#!/usr/bin/env node

import { Command } from "commander";
import pkg from "../package.json";
import { ADAPTERS, AgentName, ALL_TARGET, SUPPORTED_AGENTS, SUPPORTED_TARGETS } from "./adapters/registry";
import { runOverAll, Subcommand } from "./all";

const program = new Command()
  .name("arch-skill")
  .description("Install the architecture diagram skill into your AI coding agent.")
  // Top-level flag uses `--cli-version` (not `--version`) so subcommand
  // `--version <semver>` (skill pin) dispatches correctly. Earlier shipping
  // cycles bound both at `--version`; Commander short-circuited to the
  // top-level printer before invoking the subcommand action, breaking
  // documented tag-pin examples.
  .version(pkg.version, "-V, --cli-version");

const VERSION_RE = /^\d+\.\d+\.\d+$/;

function defineSubcommand(name: Subcommand, description: string): void {
  program
    .command(name)
    .description(description)
    .requiredOption("--agent <name>", `target AI agent (${SUPPORTED_TARGETS.join("|")})`)
    .option("--target <dir>", "override target directory (validation use)")
    // Subcommand-scoped `--version <semver>` pins which skill bundle to
    // fetch. Distinct from the top-level `--cli-version` flag which prints
    // the CLI tool's own version. The two are namespaced cleanly now that
    // the top-level flag is renamed.
    .option("--version <semver>", "pin to a specific skill version (X.Y.Z); default = latest from main")
    .action(async (opts) => {
      // Validate --version pre-dispatch as defense-in-depth; baseUrl() in
      // _shared.ts also rejects malformed values when it builds the URL.
      if (opts.version !== undefined && !VERSION_RE.test(opts.version)) {
        throw new Error(`--version must match X.Y.Z (got: ${opts.version})`);
      }
      const optsForAdapter = { target: opts.target, version: opts.version };
      if (opts.agent === ALL_TARGET) {
        process.exitCode = await runOverAll(name, optsForAdapter);
        return;
      }
      if (!SUPPORTED_AGENTS.includes(opts.agent)) {
        throw new Error(`unknown agent: ${opts.agent} (supported: ${SUPPORTED_AGENTS.join(", ")})`);
      }
      process.exitCode = await ADAPTERS[opts.agent as AgentName][name](optsForAdapter);
    });
}

defineSubcommand("install",   "Install the skill into an AI agent's skill folder.");
defineSubcommand("uninstall", "Remove a previously installed skill.");
defineSubcommand("update",    "Update an installed skill to the latest version.");
defineSubcommand("list",      "List installed skills and their versions.");

// Top-level catch: setting process.exitCode (instead of process.exit(1)) lets
// any pending async cleanup (file handles, the override-warning stderr write)
// drain before the event loop empties. Both this path and adapter-internal
// failures emit a single '^fatal: ' prefix line on stderr — log-parsers can
// rely on the prefix.
program.parseAsync(process.argv).catch(err => {
  process.stderr.write(`fatal: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});

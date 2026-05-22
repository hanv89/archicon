/**
 * Common option shape for every adapter subcommand. Individual subcommands
 * extend this when they need extra fields (currently only `install` adds
 * `overwrite`). The flat shape keeps the `--agent=all` dispatcher's typing
 * honest: `runOverAll` accepts AdapterOpts and any subcommand can read any
 * field — fields a subcommand doesn't consume are simply ignored.
 */
export interface AdapterOpts {
  /** Override target directory. Validation tests use this. */
  target?: string;
  /** Pin the fetched skill bundle to a specific tag (X.Y.Z). Default = main branch. */
  version?: string;
  /** Force overwrite of an existing skill at the target. `update` passes true; `install` defaults false. Ignored by `uninstall` / `list`. */
  overwrite?: boolean;
}

// Aliases preserved so adapters + tests reading per-subcommand names stay
// stable. All four point at the same shape.
export type InstallOptions = AdapterOpts;
export type UninstallOptions = AdapterOpts;
export type UpdateOptions = AdapterOpts;
export type ListOptions = AdapterOpts;

/**
 * Every CLI adapter implements this interface.
 *
 * Methods MUST resolve to a numeric exit code; wrap I/O in try/catch and
 * return that code, OR delegate to a method that already does so. The
 * top-level `.catch` in src/index.ts only covers commander parser
 * rejections, not adapter-internal errors.
 *
 * Adding a 5th method requires synchronized rev across every adapter
 * — accept this rigid contract for the small adapter set in scope. If
 * capability discovery becomes necessary later, switch to optional
 * methods (`verify?: ...`) at that point.
 */
export interface Adapter {
  install(opts: InstallOptions):     Promise<number>;
  uninstall(opts: UninstallOptions): Promise<number>;
  update(opts: UpdateOptions):       Promise<number>;
  list(opts: ListOptions):           Promise<number>;
}

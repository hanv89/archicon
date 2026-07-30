# Contributing

Thanks for your interest. Issues and PRs are welcome.

## One-time setup

```bash
make setup    # points git at the in-tree pre-push hook (.githooks) + checks prereqs (node, npm, gh)
```

The pre-push hook runs a leak check (`scripts/check-leaks.sh`) — the same regex
the `leak-check` CI workflow enforces — before any push reaches GitHub.

## Adding / changing icons

Icons are redistributed **unmodified** from documented upstreams (see
[`NOTICE`](./NOTICE)). To add a vendor or icon:

1. Confirm the upstream license permits redistribution (and any
   no-derivatives / brand constraints — e.g. AWS CC-BY-ND is verbatim-only).
2. Add a `scripts/build_<vendor>.sh` (model it on the existing ones +
   `scripts/_lib_icon_build.sh`); record the upstream SHA/version.
3. Regenerate the per-vendor `INDEX.md` via `scripts/build_icon_index.sh`.
4. Update `NOTICE` + add `dist/<Vendor>/USAGE-RULES.txt`.
5. Ensure the contract gates pass (`scripts/test_*.sh`) and CI is green.

## Skill / CLI changes

- Skill content (SKILL.md + examples) lives in `skills/architecture-diagram/`.
  The install manifest stays at `dist/skill/manifest.json` — that URL is
  compiled into every published CLI and fetched at install time, so moving it
  would break releases already in users' hands. Do not reunite the two. The
  content directory is frozen for the same reason: CLIs from 1.4.9 on reject a
  manifest whose `files[].src` sits anywhere else.
- **Every file under `skills/architecture-diagram/` needs a `manifest.files[]`
  entry with a matching `sha256`** — `scripts/validate_manifest.sh` fails
  otherwise, and it hashes the file's *staged* bytes. So after adding or editing
  an example:

  ```bash
  git add skills/architecture-diagram/examples/<file>
  node -e 'console.log(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' \
    skills/architecture-diagram/examples/<file>
  ```

  Paste that hash into the file's `dist/skill/manifest.json` entry (`src`,
  `dest`, `role`, `sha256`) and re-run `bash scripts/validate_manifest.sh`.
  Without an entry the ecosystem CLI would copy the file while this repo's CLI
  would not install it, so the two channels ship different trees.
- A user-facing change bumps the version across `packages/cli/package.json`,
  `package-lock.json`, `dist/skill/manifest.json`, and the SKILL.md frontmatter
  (kept in lockstep — `scripts/test_version_sync.sh` enforces it).
- Path constants live in `archicon.config` **and** in
  `packages/cli/src/adapters/_shared.ts`; the CLI does not read the config, so
  change both or neither. `scripts/test_version_sync.sh` fails on drift.
- CLI lives in `packages/cli/`; `npm test` must pass.

## What not to commit

No internal/organization identifiers in any tracked file (the leak check
rejects them). Code is MIT; keep that in mind for contributions.

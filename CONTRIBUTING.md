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
  would break releases already in users' hands. Do not reunite the two. A
  user-facing change bumps the version across `packages/cli/package.json`,
  `package-lock.json`, `dist/skill/manifest.json`, and the SKILL.md frontmatter
  (kept in lockstep), and the manifest's per-file `sha256` is regenerated.
- CLI lives in `packages/cli/`; `npm test` must pass.

## What not to commit

No internal/organization identifiers in any tracked file (the leak check
rejects them). Code is MIT; keep that in mind for contributions.

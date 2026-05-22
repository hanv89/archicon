# archicon

A public icon library + AI-agent skill for drawing architecture diagrams as
code, covering multiple cloud and developer-tool icon sets. PlantUML is the
primary output (icons embed inline via `<img:URL>`); a secondary Mermaid mode
and an experimental IaC→diagram path are planned.

> **Status: under construction.** This repository is being scaffolded. Icons,
> the skill bundle, and the CLI land incrementally. The npm package is
> `@hanv89/arch-skill`.

## Install (coming soon)

```
npx @hanv89/arch-skill install --agent=claude-code
```

Adapters for Claude Code, Codex CLI, and Cursor will ship with the CLI.

## Icon sources

Icons are redistributed from their upstream projects under each upstream's
license; per-source attribution is in [`NOTICE`](./NOTICE). Planned sources:
Microsoft Azure, Microsoft Fabric, Kubernetes, Microsoft FluentUI System
Icons, Devicon, AWS, and Google Cloud.

## IaC → diagram (experimental)

`scripts/iac_to_diagram.mjs` turns a **Terraform** file into a PlantUML
architecture diagram that uses this repo's Azure icons:

```bash
node scripts/iac_to_diagram.mjs path/to/main.tf > architecture.puml
# then render architecture.puml as usual (play.plantuml.com, Confluence, CI)
```

It extracts `resource "azurerm_<type>" "<name>"` blocks, maps known types to
Azure icons via [`scripts/fixtures/iac-azurerm-icon-map.tsv`](scripts/fixtures/iac-azurerm-icon-map.tsv),
and infers edges from Terraform references (`<type>.<name>`) between resources.

**Scope + limitations (experimental):**
- **Terraform `azurerm` only** (a curated subset of common resource types). Bicep / CloudFormation / AWS / GCP are not supported yet.
- **Best-effort regex extraction** — no HCL modules, `for_each`/`count`, interpolation, or data sources. Whole-line `#`/`//` comments are stripped before parsing, and braces inside `"..."` string values are handled; **but braces inside heredocs (`<<EOF`) are not** and can mis-slice blocks — sanity-check the output if your `.tf` uses heredocs.
- **Unknown resource types are not dropped** — they render as plain text-labelled nodes and are listed in a coverage report on stderr, so you can see what was and wasn't iconified.
- Pin the icon `git-ref` with `--ref <tag>` (e.g. `--ref icons-v0.2.0`) for output stable against a released icon snapshot; the default `main` tracks the latest icons. `--ref` is validated as a git ref.

This is a starting point for IaC-driven diagrams; coverage expands as the map grows.

## License

Code (CLI, scripts, workflows): [MIT](./LICENSE). Icons: under their
respective upstream licenses — see [`NOTICE`](./NOTICE).

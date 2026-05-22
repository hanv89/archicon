# archicon

A public icon library + AI-agent skill for drawing **architecture diagrams as
code**. PlantUML is the primary output (icons embed inline via `<img:URL>`); a
secondary Mermaid mode and an experimental Terraform→diagram path are included.
Diagrams render on Confluence, GitHub, and `play.plantuml.com` with no
separately-hosted assets.

npm: **`@hanv89/arch-skill`** · stable since **v1.0.0**.

## What ships

- **Icons — 7 vendors, ~2100 PNGs**: Microsoft Azure (528), Microsoft Fabric
  (312), Kubernetes (148), Microsoft FluentUI System Icons (75), Devicon (149),
  AWS (868, redistributed **verbatim** under CC-BY-ND — no resize), Google Cloud
  (19, official icon pack at uniform scale).
  Each redistributed from its upstream under that upstream's license (see
  [`NOTICE`](./NOTICE) + per-vendor `dist/<Vendor>/USAGE-RULES.txt`). Referenced
  by tag-pinned `raw.githubusercontent.com` URL — no CDN, no auth.
- **Skill** (`dist/skill/SKILL.md`): PlantUML authoring conventions, the
  per-vendor INDEX-lookup rule, an edit-existing-diagram workflow, and a Mermaid
  mode. 12 worked examples under `dist/skill/examples/`.
- **CLI** (`@hanv89/arch-skill`): installs the skill into your agent.
- **Supply-chain integrity**: the install manifest carries a per-file `sha256`
  the CLI verifies before writing each file.
- **IaC → diagram (experimental)**: `scripts/iac_to_diagram.mjs` (Terraform
  `azurerm` → PlantUML).

> **AWS** ships verbatim per its CC-BY-ND license (no resize/recolor — a CI
> gate enforces byte-identity to upstream). **Google Cloud** ships at uniform
> 64×64 per Google's brand guidelines. Both are not affiliated with / endorsed
> by AWS or Google — see [`NOTICE`](./NOTICE) + each `dist/<V>/USAGE-RULES.txt`.

## Install

```bash
npx @hanv89/arch-skill install --agent=claude-code   # or codex | cursor | all
```

| Command | Purpose |
|---|---|
| `install --agent=<claude-code\|codex\|cursor\|all>` | Install the skill bundle into the agent's folder |
| `uninstall --agent=<…>` | Remove it |
| `update --agent=<…>` | Re-install the latest (idempotent) |
| `list` | Show installed adapters |
| `--version=X.Y.Z` | Pin a specific skill release |

Adapters: **Claude Code**, **Codex CLI**, **Cursor**. After install, ask your
agent to "draw an Azure architecture diagram" (etc.) and it follows the skill.

Chat-UI users (Claude.ai Projects, ChatGPT) can use the downloadable
`chat-ui-bundle.zip` attached to each skill release.

## IaC → diagram (experimental)

```bash
node scripts/iac_to_diagram.mjs path/to/main.tf > architecture.puml
```
Extracts `resource "azurerm_<type>" "<name>"` blocks, maps known types to Azure
icons via [`scripts/fixtures/iac-azurerm-icon-map.tsv`](scripts/fixtures/iac-azurerm-icon-map.tsv),
and infers edges from Terraform references. Terraform `azurerm` only;
best-effort regex (no modules/`for_each`/heredocs); unknown types render as
text nodes + a coverage report on stderr. Pin icons with `--ref icons-v1.0.0`
for output stable against a released snapshot (default `main` tracks latest).

## Contributing

Issues + PRs welcome — see [`CONTRIBUTING.md`](./CONTRIBUTING.md) (adding icons,
the leak-check pre-push hook via `make setup`).

## License

Code (CLI, scripts, workflows): [MIT](./LICENSE). Icons: under their respective
upstream licenses — see [`NOTICE`](./NOTICE).

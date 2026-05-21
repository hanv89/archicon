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

## License

Code (CLI, scripts, workflows): [MIT](./LICENSE). Icons: under their
respective upstream licenses — see [`NOTICE`](./NOTICE).

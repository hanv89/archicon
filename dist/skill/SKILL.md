---
name: architecture-diagram
description: Use this skill when creating Microsoft Azure architecture diagrams using PlantUML with official Azure icons. Covers icon usage from the canonical icon repository, layout patterns (clusters, alignment, edge styling), and Confluence/GitHub/PlantUML rendering. Triggers on requests like "draw Azure architecture", "draw architecture for [service]", "create deployment diagram", "PlantUML diagram for [project]". Primary output is PlantUML with embedded Azure icons. More vendors (Fabric, Kubernetes, FluentUI, Devicon, AWS, Google Cloud), a Mermaid mode, and an IaC→diagram path are added in later releases.
version: 0.1.0
requires_icons: ">=0.1.0"
---

# Architecture Diagram Skill (PlantUML)

Draw Azure architecture diagrams with PlantUML, using icons from the
`hanv89/archicon` repository. Icons are referenced by public `raw.githubusercontent.com`
URL — no local assets, no CDN. PlantUML fetches each `<img:URL>` at render time.

## When to use
- Reference architecture documents (Confluence pages), technical design docs, RFC proposals
- Deployment topologies, runbook diagrams

## Finding the right icon — use the INDEX (non-negotiable)
Every `<img:URL>` token MUST use a filename copied **verbatim** from the `path` column of the
relevant `INDEX.md`. **Guessing a filename from the product name is forbidden** — Microsoft's
canonical casing routinely differs from common usage.

1. Fetch the Azure index:
   `https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/INDEX.md`
2. `grep` for the service; copy the `path` column value exactly.
3. Build the URL: `https://raw.githubusercontent.com/hanv89/archicon/main/<path>`.

**Filename rule (canonical casing):** use the exact casing from INDEX, e.g.
`AzureSqlDatabase` (NOT `AzureSQLDatabase`), `AzureActiveDirectory`. Initialisms follow
Microsoft's file casing, not English convention.

### Anti-example (do NOT emit)
```
' WRONG — guessed name, wrong casing → broken image at render:
rectangle "<img:.../dist/Azure/Databases/AzureSQLDatabase.png>" as db
' RIGHT — path copied verbatim from INDEX.md:
rectangle "<img:.../dist/Azure/Databases/AzureSqlDatabase.png>" as db
```

## Authoring a diagram
- Use `rectangle "<img:URL>\nLabel" as id` for icon nodes; group with `rectangle "Cluster" { ... }`.
- Keep edges labelled (protocol/transport). Prefer top-down or left-right consistent flow.
- One icon per logical component; don't crop/recolor/rotate icons (see NOTICE / USAGE-RULES).

## Worked example
See `examples/01-context.puml` (Azure 3-tier web app: Front Door → App Service → SQL Database).
Render by pasting its content into `https://www.plantuml.com/plantuml/uml/`.

## Rendering targets
- **Confluence** (PlantUML app), **GitHub Markdown** (via the `plantuml.com` proxy), and
  `play.plantuml.com` — all fetch the icon URLs directly.

## License / attribution
Azure icons are redistributed under the upstream terms; see the repository `NOTICE` and
`dist/Azure/USAGE-RULES.txt`. This project is not affiliated with or endorsed by Microsoft.

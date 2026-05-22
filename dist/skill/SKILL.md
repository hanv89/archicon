---
name: architecture-diagram
description: Use this skill when creating Microsoft Azure, Microsoft Fabric, Kubernetes, Microsoft Fluent UI-decorated, or Devicon dev-tool architecture diagrams using PlantUML. Covers icon usage from the canonical icon repository (Azure + Fabric + Kubernetes + FluentUI + Devicon), layout patterns (clusters, alignment, edge styling), multiple diagram types (system architecture, sequence flow, component view, deployment topology, data engineering pipeline, mixed AKS deployment, UI-decorated Azure, DevOps pipeline with dev tools), and Confluence integration via PlantUML apps. Triggers on requests like "draw Azure architecture", "draw architecture for [service]", "create deployment diagram", "PlantUML diagram for [project]", "draw Fabric data pipeline", "Lakehouse + Notebook + Warehouse diagram", "Kubernetes deployment diagram", "AKS architecture", "K8s Pod + Service + Deployment diagram", "diagram with status icons", "Azure with user/auth/data icons", "devops pipeline diagram", "draw [language/framework/tool] in architecture", "edit/update an existing diagram", "Mermaid architecture diagram", "render on GitHub", "diagram from Terraform". Primary output is PlantUML with embedded vendor icons; a secondary Mermaid mode (§ "Mermaid mode") renders vendor icons via inline HTML under cli/browser render (icon-light when viewed inline on GitHub, which strips HTML), and an experimental Terraform→PlantUML generator exists (see the repo README).
version: 1.0.0
requires_icons: ">=1.0.0"
---

# Architecture Diagram Skill (PlantUML)

This skill describes how to draw architecture diagrams with PlantUML, using icons from the `hanv89/archicon` repository. Icons are referenced by public `raw.githubusercontent.com` URL — no local assets, no CDN. PlantUML fetches each `<img:URL>` at render time.

## When to use

Use this skill for:
- Reference architecture documents (Confluence pages)
- Technical design documents (TDD)
- Pre-RFC architecture proposals
- Production runbook diagrams
- Multi-region deployment topologies

Do NOT use this skill for:
- UI mockups (use Figma / draw.io)
- Network packet flow diagrams (use Wireshark)
- Database ER diagrams (use dbdiagram.io or PlantUML's separate ER syntax)

## Microsoft icon use rules (read before authoring)

> **By referencing or redistributing Microsoft Azure architecture icons via this skill, you agree to the [Microsoft Azure Architecture Icons Terms of Use](https://learn.microsoft.com/en-us/azure/architecture/icons/) and the [Microsoft Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general). This skill does not transfer or sublicense Microsoft's trademarks; it propagates Microsoft's terms unchanged.**

The Microsoft icons referenced by this skill are Microsoft trademarks. Their use is governed by the Microsoft Azure Architecture Icons Terms of Use and the Microsoft Trademark and Brand Guidelines (linked above). The repository's `dist/Azure/USAGE-RULES.txt` and `NOTICE` files re-state these terms in human-readable form; this section binds them into the diagrams an AI agent emits.

### Verbatim Don'ts (from Microsoft)

- Don't crop, flip, or rotate icons.
- Don't distort or change icon shape in any way.
- Don't use Microsoft product icons to represent your product or service.

Use the icons only for architectural diagrams, training materials, or documentation. Always show the product name as a label adjacent to the icon (this is a Microsoft Do).

### Anti-example (do NOT emit) and corrected version

```plantuml
' WRONG — this rotates the Front Door icon, violating MS ToU.
rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureFrontDoor.png>\nAzure Front Door" as fd
fd -[hidden]-> fake_anchor : "rotate=45 — never do this"
' (PlantUML doesn't have a rotate primitive on <img:>, but if it did, it would be off-limits.
'  The same rule applies to recoloring, mirroring (`flip`), or scaling the icon non-uniformly.)
```

```plantuml
' RIGHT — icon used as-published, with the product name labelled next to it.
rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureFrontDoor.png>\nAzure Front Door" as fd
```

If a downstream PlantUML rendering pipeline applies a global transform that would crop / flip / rotate Microsoft icons, the agent must explicitly disable it for icon images, even if that means refusing to emit the diagram and asking the user to remove the offending pipeline step.

## Setup

> **Output modes**: this skill is PlantUML-first (vendor icons embedded via `<img:URL>`). For a GitHub-native, icon-light diagram, see § "Mermaid mode". To generate a starting diagram from a Terraform file, see the repo README § "IaC → diagram (experimental)". To revise a diagram the user already has, see § "Editing an existing diagram".

Every diagram should include 3 setup blocks. Use **literal URLs** in every `<img:URL>` reference (see § "Do not use `!define` macros for icon URLs" below).

```plantuml
@startuml DiagramName

' 1. Skinparam: layout, fonts, default colors
top to bottom direction
skinparam linetype ortho
skinparam ranksep 60
skinparam nodesep 50
skinparam shadowing false
skinparam roundcorner 10
skinparam defaultFontName "Inter, Arial, sans-serif"
skinparam defaultFontSize 13
skinparam defaultTextAlignment center
skinparam ArrowColor #475569
skinparam ArrowFontSize 11
hide stereotype

' 2. Icon container - transparent (icons float freely without a frame)
skinparam rectangle {
  BackgroundColor transparent
  BorderColor transparent
  FontColor #1F2937
}

' 3. Cluster styles - define stereotype for each group type
skinparam rectangle<<edge>> {
  BackgroundColor #FFF7ED
  BorderColor #EA580C
  FontColor #9A3412
}
skinparam rectangle<<vnet>> {
  BackgroundColor #F0F7FF
  BorderColor #0078D4
  FontColor #075985
}
' ... (see full palette in § Common patterns reference below)
```

## Icon URLs

Reference each icon with its full literal URL inside a `<img:URL>` token. The base URL pattern is:

```
https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/<Category>/<ServiceName>.png
```

Example references:

```plantuml
' Azure core services (paste the full URL into <img:>; do not abbreviate with macros — see below)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureFrontDoor.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Containers/AzureKubernetesService.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Databases/AzureDatabaseForPostgreSQL.png>
```

### Finding the right icon (use the INDEX)

Every icon ships with a flat markdown catalog you can grep. Each row carries the path, a human name, a description, and tags so you can look up the right `<Category>/<file>.png` without guessing.

- Azure: <https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/INDEX.md>
- Fabric: <https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/INDEX.md>
- Kubernetes: <https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/INDEX.md>
- FluentUI: <https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/INDEX.md>
- Devicon: <https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/INDEX.md>

When the user names a service, **fetch the relevant INDEX.md once at the start of a session, search it (case-insensitive substring or tag match across name + description + tags), and use the `path` column from the matching row** verbatim in your `<img:URL>` token.

The category-level directory listing is still useful for browsing: `https://github.com/hanv89/archicon/tree/main/dist/Azure`.

### Filename rule (non-negotiable)

> Every `<img:URL>` token MUST use a filename copied verbatim from the `path` column of the relevant `INDEX.md`. Guessing a filename from the product name is forbidden. Vendor canonical filenames routinely diverge from common product naming, and a mismatch returns HTTP 404 from `raw.githubusercontent.com` — PlantUML then renders a broken-image placeholder with no error message. The render looks "almost right" until a reviewer notices.

Worked counter-examples (real canonical filenames vs the names an agent would guess):

| Product name a user might say | Wrong (guessed) filename | Correct (canonical) filename |
|---|---|---|
| `Azure SQL Database` | `AzureSQLDatabase.png` | `AzureSqlDatabase.png` |
| `Microsoft Entra ID` | `MicrosoftEntraID.png` | `AzureActiveDirectory.png` |
| `Azure Cache for Redis` | `AzureCacheForRedis.png` | `AzureRedisCache.png` |
| `Microsoft Fabric Lakehouse` | `Lakehouse.png` | `lakehouse_40_item.png` |
| `Kubernetes Pod` | `Pod.png` | `resources/labeled/pod-128.png` |
| `Microsoft FluentUI Cloud` | `Cloud.png` | `cloud_48_color.png` |
| `Python (Devicon)` | `python.png` | `python-original_48.png` |

The `INDEX.md` `path` column is authoritative; PNG-on-disk filenames are authoritative; product names are not. If an agent has not consulted the INDEX.md for the source it's drawing from, it has not yet earned the right to emit an `<img:URL>` token for that vendor.

#### Anti-example (do NOT emit) and corrected version

```plantuml
' WRONG — guessed filename `AzureSQLDatabase.png` does not exist on disk;
'         raw.githubusercontent.com returns 404; PlantUML renders a broken-image placeholder.
rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Databases/AzureSQLDatabase.png>\nAzure SQL Database" as sql
```

```plantuml
' RIGHT — canonical filename `AzureSqlDatabase.png` from dist/Azure/INDEX.md row.
rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Databases/AzureSqlDatabase.png>\nAzure SQL Database" as sql
```

This exact typo broke `examples/07-azure-aks-mixed.puml` in an early shipping cycle and forced a hotfix. The render gate detected it post-tag; the cost was a same-day patch release. Cheaper to consult the INDEX upfront.

### Per-vendor INDEX guide

Each vendor uses a different canonical filename convention. The pattern is fixed by upstream; do not adapt it. Quick reference:

**Azure** (`dist/Azure/INDEX.md` · `https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/INDEX.md`)
- Pattern: `dist/Azure/<Category>/<PascalCaseStem>.png` (colored) or `<PascalCaseStem>(m).png` (monochrome, URL-encode parens as `%28m%29`).
- Quirk: PascalCase that is NOT all-upper for acronyms — `AzureSqlDatabase` (NOT `AzureSQLDatabase`); `AzureCosmosDb` (NOT `AzureCosmosDB`); `AzureIoTHub` keeps `IoT`; `AzureRedisCache` (NOT `AzureCacheForRedis`).
- Worked example: `<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Databases/AzureSqlDatabase.png>`

**Fabric** (`dist/Fabric/INDEX.md` · `https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/INDEX.md`)
- Pattern: `dist/Fabric/png/<snake_case_stem>_<size>_<suffix>.png` where `<size>` ∈ {24, 28, 32, 40, 48} and `<suffix>` ∈ {`item`, `non-item`, `color`, or none for plain forms like `graph_model_40.png`}.
- Quirk: per-artifact icons use `_item` / `_non-item` / plain; per-experience workload icons use `_color`. Pair both families on the same diagram (see § Microsoft Fabric icons for the pane↔artifact mapping).
- Worked example: `<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/png/lakehouse_40_item.png>`

**Kubernetes** (`dist/Kubernetes/INDEX.md` · `https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/INDEX.md`)
- Pattern: `dist/Kubernetes/png/<subdir>/<variant>/<stem>-<size>.png` where `<subdir>` ∈ {`resources`, `control_plane_components`, `infrastructure_components`}, `<variant>` ∈ {`labeled`, `unlabeled`}, `<size>` ∈ {128, 256}.
- Quirk: subdir-structured (NOT flat). Service is `svc-128.png` (NOT `service-128.png`); Deployment is `deploy-128.png`; ConfigMap is `cm-128.png`; Cloud Controller Manager is `c-c-m-128.png` (hyphenated abbreviation).
- Worked example: `<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/resources/labeled/pod-128.png>`

**FluentUI** (`dist/FluentUI/INDEX.md` · `https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/INDEX.md`)
- Pattern: `dist/FluentUI/png/<stem>_<size>_color.png` where `<size>` ∈ {24, 32, 48}, `<stem>` is snake_case lowercase matching the upstream concept name (multi-word concepts use `_` not space).
- Quirk: `_color` variant only is shipped (no `_regular` line-art, no `_filled` mono). Multi-word stems use underscore: `Cloud Dismiss` → `cloud_dismiss`, `Person Add` → `person_add`, `Code Block` → `code_block`.
- Worked example: `<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/cloud_48_color.png>`

**Devicon** (`dist/Devicon/INDEX.md` · `https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/INDEX.md`)
- Pattern: `dist/Devicon/png/<stem>-original_48.png` where `<stem>` is the lowercase upstream key.
- Quirk: `-original` variant + `_48` size only. Some stems use hyphens (`dot-net`, not `dotnet`); some use full words (`googlecloud`, not `gcp`); some keep abbreviations (`vuejs`, `nextjs`, `nodejs`). Always look up the canonical stem in INDEX.md — guessing `gcp.png` instead of `googlecloud-original_48.png` is a 404.
- Worked example: `<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/python-original_48.png>`

### Filenames with parentheses (URL encoding required)

Microsoft Fabric and some Azure icons ship a colored-and-monochrome pair. The monochrome variants carry an `(m)` suffix in their filename, for example:

| Disk filename | Encoded URL form |
|---|---|
| `AzureBatchAI.png` | `AzureBatchAI.png` (no encoding needed) |
| `AzureBatchAI(m).png` | `AzureBatchAI%28m%29.png` |

Parentheses (`(`, `)`) must be URL-encoded as `%28` / `%29` inside the `<img:URL>` token. The PlantUML server fetches the URL as-is; literal parens break the URL. Worked example:

```plantuml
' Monochrome Front Door variant — note %28m%29 in place of (m)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureFrontDoor%28m%29.png>
```

The same rule applies to any other special URL characters (`@` becomes `%40`, spaces become `%20`, etc.). Microsoft icon filenames in this repo only use `(` `)` and ASCII letters/digits, so `%28` / `%29` are the only encodings the agent normally needs.

### Do not use `!define` macros for icon URLs

PlantUML's preprocessor does not substitute `!define` symbols inside the `<img:>` token. Macro indirection produces broken images at render time without any error message. Always use literal URLs.

```plantuml
' WRONG — !define IMG is NOT expanded inside <img:IMG/...>; the renderer fetches
' the literal string "IMG/Compute/AzureAppService.png" and produces a broken image.
!define IMG https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure
<img:IMG/Compute/AzureAppService.png>
```

```plantuml
' RIGHT — full literal URL inside <img:>; the renderer fetches the URL as-is.
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Compute/AzureAppService.png>
```

This rule was discovered while authoring `examples/01-context.puml` — the macro form silently produced broken images on `play.plantuml.com`; switching to literal URLs fixed it.

## Microsoft Fabric icons

This skill also covers Microsoft Fabric — the data engineering / analytics platform — using icons sourced from the `@fabric-msft/svg-icons` npm package (Microsoft first-party, MIT license). Fabric icons live under:

```
https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/png/
```

Two icon families, two abstraction levels:

**Family A — per-artifact icons (`_item` / `_non-item` / plain).** Per-service icons that represent individual artifacts inside a Fabric workspace (Lakehouse, Pipeline, Notebook, KQL DB, ...). Available at sizes 24, 32, 40, 48 with three suffix conventions:

- `<base>_<size>_item.png` — primary service items (most icons).
- `<base>_<size>_non-item.png` — secondary forms: workspaces, folders, action verbs (MyWorkspace, GroupWorkspace, Folder, AddPipeline, ImportNotebook, Sample, EventHouse-alt).
- `<base>_<size>.png` — special-form services with no item suffix (graph_model, graph_queryset).

Pick `_40_item` for most architecture diagrams (default size). Use 24/32 for compact layouts; 48 for hero blocks.

**Family B — per-experience workload icons (`_color`).** Color brand icons that represent Fabric experiences (the panes in the Fabric portal) — distinct from the per-artifact icons inside them. URL: `<workload>_<size>_color.png` where `<size>` ∈ {24, 28, 32, 48}.

13 workload bases: `copilot`, `databases`, `data_engineering`, `data_factory`, `data_science`, `data_warehouse`, `fabric` (umbrella brand), `graph_intelligence`, `industry_solutions`, `one_lake`, `power_bi`, `purview`, `real_time_intelligence`.

Use these for the **experience-level** layer in a Fabric architecture (the Data Engineering pane, the OneLake foundation, the Power BI consumption layer).

**Pair Family A + Family B on the same diagram**, do not collapse them. Each consumption / experience pane gets a Family B `_color` icon for the pane label; each individual artifact inside that pane gets a Family A `_item` icon. The mapping is fixed by Microsoft's reference architectures:

| When you draw …                        | Workload pane (Family B `_color`)   | Artifact(s) inside (Family A `_item`)                                    |
|----------------------------------------|--------------------------------------|--------------------------------------------------------------------------|
| OneLake storage foundation             | `one_lake_48_color.png`              | `lakehouse_40_item.png`, `data_warehouse_40_item.png`, `mirrored_catalog_40_item.png` |
| Data Engineering (Spark notebooks)     | `data_engineering_48_color.png`      | `notebook_40_item.png`, `lakehouse_40_item.png`, `spark_job_direction_40_item.png` |
| Data Factory (orchestration)           | `data_factory_48_color.png`          | `pipeline_40_item.png`, `dataflow_gen2_40_item.png`, `copy_job_40_item.png` |
| Data Warehouse (T-SQL)                 | `data_warehouse_48_color.png`        | `data_warehouse_40_item.png`                                              |
| Data Science (ML)                      | `data_science_48_color.png`          | `notebook_40_item.png`, `experiments_40_item.png`, `model_40_item.png`   |
| Real-Time Intelligence                 | `real_time_intelligence_48_color.png`| `eventstream_40_item.png`, `event_house_40_item.png`, `kql_database_40_item.png`, `real_time_dashboard_40_item.png` |
| Databases (mirroring / SQL DB)         | `databases_48_color.png`             | `mirrored_catalog_40_item.png`, `mirrored_generic_database_40_item.png`, `sql_database_40_item.png` |
| Power BI consumption                   | `power_bi_48_color.png`              | `report_40_item.png`, `semantic_model_40_item.png`, `dashboard_40_item.png` |
| Graph Intelligence                     | `graph_intelligence_48_color.png`    | `graph_model_40.png`, `graph_queryset_40.png`                            |

**DO**: in system architecture / component diagrams, draw the workload pane as the cluster boundary (or as a separate rectangle with the Family B icon as the label) AND draw each artifact inside as its own rectangle with the Family A icon.

**DO**: in sequence diagrams, when one participant must carry both concepts, stack the two icons inside the participant header so the workload context is visible alongside the artifact:

```plantuml
participant "<img:.../power_bi_48_color.png>\n<img:.../report_40_item.png>\n**Power BI Report**" as pbi
```

**DON'T**: collapse the two icons into one. Using only `report_40_item.png` and labeling it "Power BI Report" hides the workload context Microsoft draws explicitly. Same anti-pattern for `notebook_40_item.png` alone labelled "Spark Notebook" — pair it with `data_engineering_48_color.png` so the workload context is visible.

**DON'T**: use only the Family B `_color` icon for a node that represents one concrete artifact (e.g. a single Lakehouse). Use the Family A `_item` icon when you mean a specific instance; reserve Family B for the surrounding pane / experience boundary.

PlantUML scales Fabric icons automatically inside `<img:>` tokens.

### Common Fabric items reference (Family A)

| Service | Filename | Use case |
|---|---|---|
| Lakehouse | `lakehouse_40_item.png` | Storage layer for Bronze/Silver/Gold (Delta) |
| Pipeline | `pipeline_40_item.png` | Data orchestration |
| Notebook | `notebook_40_item.png` | Spark / Python transformation |
| Data Warehouse | `data_warehouse_40_item.png` | Serving Gold via T-SQL |
| Data Factory | `data_factory_40_item.png` | Parent ETL platform |
| Dataflow Gen2 | `dataflow_gen2_40_item.png` | Power Query data flows |
| Eventstream | `eventstream_40_item.png` | Real-time ingest |
| Event House (KQL DB) | `event_house_40_item.png` | KQL-queried event store |
| Semantic Model | `semantic_model_40_item.png` | Power BI / analytics semantic layer |
| Report | `report_40_item.png` | Power BI report |
| Mirrored Catalog | `mirrored_catalog_40_item.png` | Mirrored external catalog (Unity, Snowflake, etc.) |
| Graph Model | `graph_model_40.png` | Graph data model |
| Graph Queryset | `graph_queryset_40.png` | Graph queryset |
| My Workspace | `my_workspace_40_non-item.png` | Personal tenant workspace container |
| Group Workspace | `group_workspace_40_non-item.png` | Shared workspace container |
| Folder | `folder_40_non-item.png` | Workspace folder grouping |

### Common Fabric workloads reference (Family B, `_color`)

| Workload | Filename (size 48) | Use case |
|---|---|---|
| Fabric (umbrella brand) | `fabric_48_color.png` | Tenant boundary / Fabric platform group |
| OneLake | `one_lake_48_color.png` | Foundation lake storage layer |
| Data Engineering | `data_engineering_48_color.png` | Spark + Lakehouse experience |
| Data Factory | `data_factory_48_color.png` | Pipeline + Dataflow experience |
| Data Warehouse | `data_warehouse_48_color.png` | SQL warehouse experience |
| Data Science | `data_science_48_color.png` | ML experiment + model experience |
| Real-Time Intelligence | `real_time_intelligence_48_color.png` | KQL DB + Eventstream experience |
| Power BI | `power_bi_48_color.png` | Report + dashboard consumption layer |
| Databases | `databases_48_color.png` | Fabric Databases (mirrored + SQL DB) |
| Graph Intelligence | `graph_intelligence_48_color.png` | Graph model + queryset experience |
| Industry Solutions | `industry_solutions_48_color.png` | Vertical-specific bundles (healthcare, retail, sustainability) |
| Purview | `purview_48_color.png` | Governance + catalog |
| Copilot | `copilot_48_color.png` | Generative AI overlay |

Smaller workload sizes available: 24, 28, 32 — same naming pattern (`<base>_<size>_color.png`). Drop in for dense diagrams or sidebar legends.

Browse the full Fabric set at: `https://github.com/hanv89/archicon/tree/main/dist/Fabric/png`. See `dist/Fabric/USAGE-RULES.txt` for the Microsoft Fabric icon Don'ts (mirror of the Azure rules).

### Example references

```plantuml
' Fabric data engineering icons (literal URLs, same convention as Azure)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/png/lakehouse_40_item.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/png/pipeline_40_item.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/png/notebook_40_item.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Fabric/png/data_warehouse_40_item.png>
```

The Fabric icon filenames use `snake_case` (matching upstream `@fabric-msft/svg-icons` SVG names); none contain parentheses, so no URL encoding is needed.

### Mixing Azure + Fabric in one diagram

Fabric icons compose cleanly with Azure icons. Typical pattern: Azure infra surrounding a Fabric data plane (e.g. Azure Front Door → Azure App Service → Fabric Lakehouse via Fabric Pipeline → Fabric Notebook → Fabric Data Warehouse → Power BI report). See `examples/02-fabric-data-pipeline.puml` for a worked Fabric-only flow, and `examples/03-system-architecture.puml` for a full Azure AKS application feeding a Microsoft Fabric data plane (canonical Azure + Fabric mixed example).

## Kubernetes icons

The skill also covers Kubernetes — sourced from the upstream `kubernetes/community/icons` set (Apache-2.0 / CC-BY-4.0 dual licence, published by the Kubernetes project under CNCF / Linux Foundation governance). The aesthetic is hexagon-badge filled-glyph (blue badges with white concept-glyph inside), distinct from Azure's square filled-glyph but composes naturally inside an AKS / cluster boundary.

Kubernetes icons live under:

```
https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/
```

Two style variants × two sizes × three subdir families:

- **Variants**: `labeled` (concept name embedded in the badge, e.g. "Pod") and `unlabeled` (badge with glyph only — pair with a PlantUML node label when composing).
- **Sizes**: `128` (smaller, closer to Azure's 64px feel) and `256` (larger headers + isolated icons).
- **Subdirs**: `resources/` (workload + config + network + storage + RBAC concepts), `control_plane_components/` (API server, scheduler, controller-manager, kubelet, kube-proxy, cloud-controller-manager), `infrastructure_components/` (Node, etcd, master).

Filename pattern: `<concept>-<size>.png`. The `<concept>` segment may contain dashes (e.g. `c-c-m-128.png` = Cloud Controller Manager, `k-proxy-128.png` = kube-proxy, `c-role-128.png` = ClusterRole). For the complete name + tag lookup table, fetch `dist/Kubernetes/INDEX.md`.

### Common Kubernetes references

```plantuml
' Kubernetes workload + config + network (labeled variant, 128px)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/resources/labeled/pod-128.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/resources/labeled/deploy-128.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/resources/labeled/svc-128.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/resources/labeled/cm-128.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/resources/labeled/secret-128.png>

' Control plane (used inside an AKS / cluster boundary)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/control_plane_components/labeled/api-128.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/control_plane_components/labeled/sched-128.png>

' Infrastructure (Node = worker, useful for showing pool topology)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Kubernetes/png/infrastructure_components/labeled/node-128.png>
```

Kubernetes filenames use plain ASCII with dashes — no URL encoding needed (no parentheses, no spaces).

### Mixing Azure + Kubernetes in one diagram

The canonical mixed pattern is **Azure AKS (managed Kubernetes) surrounding a Kubernetes workload subgraph**: Azure Front Door → Azure App Gateway → AKS cluster (containing Service → Deployment → Pods + ConfigMap + Secret) → Azure SQL Database. See `examples/07-azure-aks-mixed.puml` for a worked example.

## FluentUI System Icons (decorator scope)

The skill carries a curated subset of **Microsoft Fluent UI System Icons** — 25 architecture-diagram concepts sourced from `microsoft/fluentui-system-icons` (Microsoft first-party, MIT license — same evidence chain as Fabric). The scope is a **decorator** pack, not a per-service architecture set: it adds UI-style affordances (Cloud, Database, Shield, Person, Mail, Calendar, status indicators, ...) that compose alongside Azure / Fabric / Kubernetes service icons to label users, data flow direction, status, or organisational boundaries.

FluentUI icons live under:

```
https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/
```

**Layout**: flat, one file per `(concept × size)` pair. Filename pattern: `<stem>_<size>_color.png` where `<stem>` is the snake_case concept name (e.g. `lock_shield`, `cloud_dismiss`, `person_add`).

**Sizes available**: `24`, `32`, `48` (single canonical pixel-dimensions). Pick `24` for inline status badges, `32` for in-line affordances, `48` for header / Azure-comparable icons.

**Variant**: `_color` only — filled-color gradient style closest to Azure's filled-glyph anchor. The upstream's `_regular` (line-art) and `_filled` (one-color) variants are intentionally not shipped (off-style for our diagrams).

**Curated 25 concepts** (full table in `dist/FluentUI/INDEX.md`):

| Family | Stems |
|---|---|
| Cloud / data | `cloud`, `cloud_dismiss`, `database`, `data_trending` |
| Identity | `person`, `people`, `person_add` |
| Security | `shield` |
| Organisation | `building`, `briefcase`, `apps` |
| Time | `clock`, `calendar` |
| Communication | `send`, `chat` |
| Code / docs | `code_block`, `clipboard`, `book` |
| Status | `checkmark_circle`, `warning`, `alert` |
| Config / control | `settings` |
| Affordances | `puzzle_piece`, `pin`, `question_circle` |

### Common FluentUI references

```plantuml
' FluentUI status + identity icons (48px, filled-color)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/cloud_48_color.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/database_48_color.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/shield_48_color.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/person_48_color.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/checkmark_circle_24_color.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/FluentUI/png/warning_24_color.png>
```

Underscored stems = no URL encoding needed (no parentheses, no spaces).

### Mixing Azure + FluentUI in one diagram

Typical pattern: Azure infrastructure decorated with FluentUI UI affordances — Front Door + App Service + SQL Database as the backbone, FluentUI Cloud / Lock Shield / Person / Mail / status icons as labels for cloud-boundary, authentication, user, notification, and health state. See `examples/08-azure-fluentui-mixed.puml` for a worked Azure + FluentUI mixed example.

## Devicon icons (dev-tool scope)

The skill carries a curated subset of **Devicon** — ~150 popular dev-tool concepts sourced from `devicons/devicon` (community-maintained MIT, Copyright (c) 2015 konpa). The scope is a **dev-tool** pack: programming languages, web frameworks, build tools, container runtimes, cloud providers, databases, observability stacks, web servers, CI/CD platforms, SCM/collab platforms, IDEs/editors, data + AI libraries, mobile frameworks, testing frameworks, OS / distros, browsers, and runtimes. Each icon depicts a third-party brand (Python, Docker, Kubernetes, etc.); per-brand trademark policies apply separately — the MIT grant from Devicon is the redistribution basis.

Devicon icons live under:

```
https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/
```

**Layout**: flat, one file per stem. Filename pattern: `<stem>-original_48.png` where `<stem>` is the lowercase upstream key (e.g. `python`, `docker`, `kubernetes`, `dot-net`, `nextjs`).

**Sizes available**: `48` only (single canonical pixel-dimension). PlantUML scales inside `<img:>` tokens automatically — sufficient for inline node labels alongside Azure 48-anchor service icons.

**Variant**: `-original` only — the colored brand glyph closest to Azure's filled-color anchor. The upstream's `-plain` (monochrome) and `-line` (outline) variants are intentionally not shipped (off-style for our diagrams).

**Curated ~150 stems** (full table with categories in `dist/Devicon/INDEX.md`):

| Category | Sample stems |
|---|---|
| Languages | `python`, `javascript`, `typescript`, `go`, `java`, `rust`, `c`, `cplusplus`, `csharp`, `ruby`, `php`, `kotlin`, `swift`, `scala`, `r`, `haskell`, `lua`, `clojure`, `elixir`, `erlang`, `dart`, `ocaml`, `fsharp`, `julia`, `bash` |
| Web frameworks | `react`, `vuejs`, `angular`, `nextjs`, `svelte`, `spring`, `flask`, `express`, `fastapi`, `nestjs`, `laravel`, `dot-net`, `dotnetcore`, `quarkus`, `symfony`, `phoenix`, `gatsby`, `nuxtjs`, `remix`, `astro` |
| Frontend | `tailwindcss`, `bootstrap`, `jquery`, `redux`, `alpinejs`, `materialui`, `storybook` |
| Build tools | `webpack`, `vite`, `babel`, `rollup`, `sass`, `postcss`, `npm`, `yarn`, `pnpm`, `bun`, `maven`, `gradle`, `bazel` |
| Containers | `docker`, `kubernetes`, `podman`, `helm`, `rancher` |
| Cloud + IaC | `azure`, `googlecloud`, `digitalocean`, `heroku`, `vercel`, `netlify`, `cloudflare`, `firebase`, `supabase`, `terraform`, `pulumi`, `ansible` |
| Databases | `postgresql`, `mysql`, `mariadb`, `mongodb`, `redis`, `sqlite`, `cassandra`, `dynamodb`, `couchbase`, `couchdb`, `neo4j`, `influxdb`, `microsoftsqlserver`, `oracle`, `clickhouse` |
| Observability | `elasticsearch`, `prometheus`, `grafana`, `kibana`, `logstash`, `sentry` |
| Messaging / web servers | `nginx`, `apache`, `envoy`, `rabbitmq` |
| CI/CD + SCM + collab | `argocd`, `jenkins`, `githubactions`, `gitlab`, `travis`, `github`, `bitbucket`, `jira`, `slack`, `notion` |
| IDEs / editors | `figma`, `vscode`, `intellij`, `visualstudio`, `pycharm`, `webstorm`, `androidstudio`, `eclipse`, `vim`, `neovim`, `emacs`, `tmux` |
| Data / AI | `pytorch`, `tensorflow`, `pandas`, `numpy`, `jupyter`, `anaconda`, `hadoop` |
| Mobile | `flutter`, `ionic`, `android` |
| Testing | `mocha`, `playwright`, `selenium` |
| OS / runtime / browsers | `linux`, `ubuntu`, `debian`, `vagrant`, `chrome`, `firefox`, `nodejs` |

### Common Devicon references

```plantuml
' Devicon language + tool icons (48px, -original variant)
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/python-original_48.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/docker-original_48.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/kubernetes-original_48.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/github-original_48.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/githubactions-original_48.png>
<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Devicon/png/postgresql-original_48.png>
```

Hyphenated stems (`dot-net`) and lowercase stems = no URL encoding needed (no parentheses, no spaces).

### Mixing Azure / Kubernetes + Devicon in one diagram

Typical patterns:

- **DevOps pipeline**: source (`github-original_48.png`) → CI/CD (`githubactions-original_48.png` or `argocd-original_48.png`) → registry (e.g. Azure Container Registry from the Azure set) → AKS / Kubernetes runtime (`kubernetes-original_48.png`) → observability (`prometheus-original_48.png` + `grafana-original_48.png`). See `examples/09-devops-pipeline.puml` for a worked example.
- **Polyglot service map**: each microservice node carries its language (`python-original_48.png`, `go-original_48.png`, `nodejs-original_48.png`) and database (`postgresql-original_48.png`, `redis-original_48.png`), with Azure / FluentUI for the surrounding infrastructure and UI affordances.
- **Tech-stack reference**: enumerate frontend (`react-original_48.png` + `tailwindcss-original_48.png`), backend (`fastapi-original_48.png` + `python-original_48.png`), data (`postgresql-original_48.png` + `redis-original_48.png` + `elasticsearch-original_48.png`), and infrastructure (`docker-original_48.png` + `kubernetes-original_48.png` + `terraform-original_48.png`) in a single legend-style diagram.

**Trademark note**: Devicon icons depict third-party brands (Python language, Docker container engine, etc.). Use these icons only to identify the tool / language / platform they depict — do not use a Devicon icon to represent **your** product or service. The MIT grant from Devicon does not transfer any trademark rights to depicted brands; see `NOTICE` § Devicon for the per-tool-trademark disclaim.

## Pattern 1: System Architecture Diagram

For high-level deployment topology — hub-spoke, AKS, managed services.

**When to use**: Reference architecture in the main project document.

**Worked example**: see `examples/01-context.puml` for a minimal Azure 3-tier (Front Door → App Service → SQL Database) using exactly this pattern.

**Template** (using literal URLs throughout):

```plantuml
@startuml SystemArchitecture
top to bottom direction
skinparam linetype ortho
skinparam ranksep 60
skinparam nodesep 50
skinparam shadowing false
skinparam roundcorner 10
skinparam defaultFontName "Inter, Arial, sans-serif"
skinparam defaultFontSize 13
skinparam defaultTextAlignment center
skinparam ArrowColor #475569
skinparam ArrowFontSize 11
hide stereotype

skinparam rectangle {
  BackgroundColor transparent
  BorderColor transparent
}

skinparam rectangle<<edge>> {
  BackgroundColor #FFF7ED
  BorderColor #EA580C
  FontColor #9A3412
}
skinparam rectangle<<vnet>> {
  BackgroundColor #F0F7FF
  BorderColor #0078D4
  FontColor #075985
}
skinparam rectangle<<spoke>> {
  BackgroundColor #F0FDF4
  BorderColor #16A34A
  FontColor #166534
}
skinparam rectangle<<aks>> {
  BackgroundColor #FAFAF9
  BorderColor #84CC16
  FontColor #365314
}
skinparam rectangle<<data>> {
  BackgroundColor #FAFAF9
  BorderColor #94A3B8
  FontColor #475569
}
skinparam rectangle<<ai>> {
  BackgroundColor #FAF5FF
  BorderColor #7E22CE
  FontColor #6B21A8
}

title <size:20><b>[Project Name] — Production Architecture</b></size>\n<size:13>[Subtitle: stage, region, etc.]</size>\n

cloud "Internet" as inet

rectangle "Edge / Global" <<edge>> {
  rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureFrontDoor.png>\n**Front Door**\n//WAF + CDN//" as fd
  rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Identity/AzureActiveDirectory.png>\n**Entra ID**\n//OIDC//" as entra
}

rectangle "Hub VNet" <<vnet>> {
  rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureApplicationGateway.png>\n**App Gateway**\n//WAF_v2//" as agw
  rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Web/AzureAPIManagement.png>\n**APIM**\n//Premium//" as apim
}

rectangle "Spoke VNet" <<spoke>> {
  rectangle "AKS" <<aks>> {
    rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Containers/AzureKubernetesService.png>\n**api-service**\n//N replicas//" as api
  }
  rectangle "Data" <<data>> {
    rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Databases/AzureDatabaseForPostgreSQL.png>\n**Postgres**\n//Flex//" as pg
    rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Security/AzureKeyVault.png>\n**Key Vault**\n//Premium//" as kv
  }
}

inet --> fd : HTTPS
fd --> agw : "TLS 1.3"
agw --> apim
apim --> api
api --> pg : "MI auth"
api ..> kv : "secrets"
entra ..> apim : "JWT"
@enduml
```

## Patterns 2-4 (sequence / component / deployment)

Pattern 1 (system architecture) is the central template above; the remaining patterns are illustrated through worked examples shipped in the same bundle:

- **Sequence flow** — `examples/04-sequence-flow.puml` traces a request across Front Door → AKS → Service Bus → Fabric Eventstream, exercising actor/lifeline/note syntax with Azure + Fabric icons.
- **Component view (C4 level 3)** — `examples/05-component.puml` zooms into the AKS cluster internals from `03-system-architecture.puml`, showing the microservices, sidecars, and platform-services hooks.
- **Deployment topology** — `examples/06-deployment.puml` shows a multi-region active-active deployment of the same architecture across paired Azure regions with Fabric workspace replication.

## Common patterns reference

### Cluster color palette

| Stereotype | Background | Border    | Text      | Use case |
|---|---|---|---|---|
| `<<edge>>`     | `#FFF7ED` | `#EA580C` | `#9A3412` | Internet-facing, CDN, WAF |
| `<<vnet>>`     | `#F0F7FF` | `#0078D4` | `#075985` | Hub VNet, networking |
| `<<spoke>>`    | `#F0FDF4` | `#16A34A` | `#166534` | Workload Spoke VNet |
| `<<aks>>`      | `#FAFAF9` | `#84CC16` | `#365314` | AKS cluster |
| `<<data>>`     | `#FAFAF9` | `#94A3B8` | `#475569` | Data layer (DB, cache, storage) |
| `<<ai>>`       | `#FAF5FF` | `#7E22CE` | `#6B21A8` | AI / Analytics |
| `<<security>>` | `#FEF2F2` | `#DC2626` | `#991B1B` | Security boundary, firewall |
| `<<dr>>`       | `#F1F5F9` | `#64748B` | `#334155` | DR region (passive) |

### Edge styling

```plantuml
' Solid arrow - synchronous call (default)
a --> b : "REST API"

' Dashed - async, optional, secondary
a ..> b : "secrets via MI"

' Bold + colored - highlight critical path
a -[#A0522D,bold]-> b : "egress traffic"

' Right direction (force horizontal in same group)
a -r-> b

' Hidden (force layout without showing edge)
a -[hidden]r- b
```

### Horizontal alignment within a group

By default, the Graphviz dot engine arranges nodes following the flow direction. To force nodes within a group to align horizontally (in a TB diagram), use **hidden right edges**:

```plantuml
rectangle "Group" {
  rectangle "A" as a
  rectangle "B" as b
  rectangle "C" as c

  ' Force horizontal alignment
  a -[hidden]r- b
  b -[hidden]r- c
}
```

### Two-line title with formatting

```plantuml
title <size:20><b>Project Name</b></size>\n<size:13>Subtitle, stage, version</size>\n
```

### Multi-line node label (with literal icon URL)

```plantuml
rectangle "<img:https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Compute/AzureAppService.png>\n**Display Name**\n//Subtitle italic//\n[Optional bracket]" as alias
```

## Confluence integration (PlantUML apps)

General workflow when using a PlantUML app in Confluence (e.g., AppsFoundry, weweave, or other apps):

1. In the Confluence editor, type `/plantuml` → select the **PlantUML Diagram** macro.
2. Paste source code into the text area.
3. Save → diagram renders via the PlantUML server (default plantuml.com).
4. Store the `.puml` source in the project's Git repo alongside related code.

**Important**:
- The default plantuml.com server runs PlantUML 1.2025+.
- URLs containing `(`, `)`, `@`, or spaces must be URL-encoded — `%28`, `%29`, `%40`, `%20` respectively. See § "Filenames with parentheses" above for the most common case in this skill.
- Complex diagrams render in ~5-10s on first load, cached afterwards.

## Authoring workflow

**Local development**:
1. VS Code + the `jebbs.plantuml` extension → press Alt+D for live preview.
2. Save `.puml` files in `docs/architecture/` of the project repo.
3. Commit alongside the corresponding code changes.

**Quick prototyping**:
- Browser: `https://www.plantuml.com/plantuml/uml/` → paste source → diagram renders inline.
- Live editing, share URL containing the encoded source.

**CI render (optional)**:
- GitHub Actions render `.puml` → PNG.
- Upload to Confluence as attachment fallback (in case the server fails).

## Editing an existing diagram

When the user asks you to **change a diagram they already have** (add a service, remove one, re-wire a connection, swap an icon), revise their existing `.puml` in place — do **not** re-author it from scratch. Re-authoring throws away the layout the user tuned and produces a noisy, unreviewable diff.

Rules for an edit:

1. **Keep the existing scaffold.** Preserve the `@startuml <Name>`, the entire skinparam/setup block, the cluster (`rectangle "..." { }`) structure, and any `together {}` / hidden-edge (`-[hidden]-`) layout anchors. These encode the user's layout intent.
2. **Make the minimal diff.** Touch only the lines the change requires. Adding a node = one new `rectangle` line + the edges that connect it. Removing a node = delete its declaration + every edge that references its alias. Swapping an icon = change only the `<img:URL>` (and the label if the product name changed).
3. **Look up any new/changed icon in the relevant `INDEX.md`** before emitting its `<img:URL>` — the filename rule (see § "Filename rule (non-negotiable)") applies to edits exactly as to authoring. A guessed filename 404s and renders a broken-image placeholder.
4. **Reuse the existing alias style.** If the diagram names nodes `as fd`, `as aks`, follow that convention for new nodes so the edge list stays readable.
5. **Don't re-flow the layout unless asked.** Keep `direction`, `ranksep`/`nodesep`, and existing hidden edges as-is. Only restructure layout when the user explicitly asks for it (e.g. "make it left-to-right").
6. **Preserve labels + cluster membership.** A new node usually belongs inside an existing cluster — place it there, not at the top level, unless it is genuinely a new boundary.

If the user pastes a diagram that uses `!define` macros or guessed filenames, fix those to literal INDEX-verified URLs as part of the edit (and say so), since they would otherwise render broken.

See [`examples/10-edit-existing.puml`](examples/10-edit-existing.puml) for a worked before/after edit (adding a cache node to an existing 3-tier diagram).

## Mermaid mode

PlantUML is still the primary mode (it embeds the vendor PNGs via `<img:URL>` everywhere). But **Mermaid CAN show the vendor icons too** — via inline HTML in node labels — when rendered by a real browser engine. There are two sub-modes; pick by the **delivery target**.

### Pick a sub-mode by where it renders

| Sub-mode | When | Icons? |
|---|---|---|
| **(a) Mermaid icon-light** | The diagram must render **inline on GitHub** (a `.md` / PR / issue). GitHub sanitises Mermaid and **strips inline `<img>`**. | No — text labels only (use the product word-mark, e.g. `Azure Front Door`). |
| **(b) Mermaid + icon (cli/local render)** — **default when the user wants icons** | The deliverable is a **PNG / Confluence / doc**, rendered with `mermaid-cli` (or any browser-based renderer). | **Yes** — vendor PNGs via inline `<img>`. |

> Mermaid is icon-light only when **viewing the `.mmd` on GitHub** (HTML stripped). Icons render fine under cli/browser render with `htmlLabels:true` + `securityLevel:loose`.

### Sub-mode (b): icons via inline HTML

Put an `<img>` (with the project's `raw.githubusercontent.com` PNG URL) inside the node label, sized by the shipped CSS — not by per-node `width` attrs:

```
flowchart TB
  fd["<img src='https://raw.githubusercontent.com/hanv89/archicon/main/dist/Azure/Networking/AzureFrontDoor.png'/><br/><b>Azure Front Door</b>"]
```

Look the icon path up in the relevant `INDEX.md` (the § "Filename rule" applies to the `src` URL exactly as to `<img:URL>`).

### Render recipe (sub-mode b)

`mermaid-cli` needs three non-obvious things or it crashes / renders wrong. Use the shipped [`examples/assets/render-mermaid.sh`](examples/assets/render-mermaid.sh) (copy + run), or inline:

```bash
npx -y @mermaid-js/mermaid-cli@latest \
  -i diagram.mmd -o diagram.png -b white \
  -c mmcfg.json -p pptr.json -C examples/assets/icon.css --width 2600
```
- `mmcfg.json`: `{"flowchart":{"htmlLabels":true},"securityLevel":"loose"}` — required so `<img>` labels render.
- `pptr.json`: `{"args":["--no-sandbox","--disable-setuid-sandbox"]}` — required on Ubuntu 23.10+ (unprivileged user namespaces are blocked → Chromium `No usable sandbox!` crash without it).
- `-C examples/assets/icon.css`: the canonical CSS that fixes icon distortion + sizing (below).

> **Security note**: `--no-sandbox` and `securityLevel:loose` are accepted trade-offs **only because the `.mmd` source here is author-controlled** (you wrote it / the skill emitted it). Never render *untrusted* Mermaid with `loose` (it permits arbitrary HTML/JS in labels).

### `icon.css` — fixes three render defects

Ship + pass [`examples/assets/icon.css`](examples/assets/icon.css) via `-C`. It encodes three fixes found in real use: `object-fit: contain` (icons distort under ELK without it — width/height alone is not enough); one **single icon-size knob** (don't size per-node); fixed block `width` + `white-space: normal` so labels wrap. **Do not use `min-width`** for the block — the cssFile applies *after* the layout engine measured the nodes, so `min-width` truncates text (e.g. `ns: trust-layer` → `ns: trust-la`). To resize icons, change the one `width`/`height` in `icon.css` (~64–80px reads well next to a ~13px label) and widen the block to match.

### Layout (ELK) + cluster colours

For a clean top-down layout with fewer crossings than the default dagre, use ELK in the frontmatter — **but it stretches the icon `foreignObject`, so it must be paired with `object-fit: contain`** (already in `icon.css`):

```
---
config:
  layout: elk
  elk:
    nodePlacementStrategy: NETWORK_SIMPLEX
---
```
(ELK is a renderer-version-dependent flag.) For cluster colours matching the PlantUML palette, add a `style` line per subgraph (cluster tint light, category-coloured border, nodes brighter than the background so they read as cards):

| PlantUML stereotype | Mermaid subgraph `style` |
|---|---|
| `<<edge>>` | `style edge fill:#FFE9D6,stroke:#EA580C,color:#9A3412;` |
| `<<vnet>>` / app | `style aks fill:#EEF6DA,stroke:#84CC16,color:#365314;` |
| `<<data>>` | `style data fill:#EBF0F5,stroke:#94A3B8,color:#475569;` |
| Fabric | `style fabric fill:#ECDDFA,stroke:#5C2D91,color:#3E1F5F;` |

### Trademark note (sizing)

The repo's icons are **square** (Azure 70×70, Fabric 40/48). Setting `width = height` (or the single `icon.css` size) is **uniform scaling**, which is ToU-compliant — no need to hesitate about normalising icon size. Do not set width ≠ height (non-uniform distortion is not allowed).

See [`examples/11-mermaid-architecture.mmd`](examples/11-mermaid-architecture.mmd) (icon-light) and [`examples/12-mermaid-icons.mmd`](examples/12-mermaid-icons.mmd) (icon mode, ELK + inline `<img>` + styled clusters). For branded vendor-icon diagrams that must also work on GitHub, prefer the PlantUML examples (`01`–`09`).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Icon renders as a broken-image placeholder | The `<img:>` URL contains an unexpanded `!define` macro | Replace the macro with the literal URL inside `<img:>` (see § "Do not use `!define` macros") |
| Icon broken on a monochrome variant only | Filename has `(m)` but URL was not encoded | Replace `(m)` with `%28m%29` in the URL |
| `(Unable to decode...)` | `@` character in URL is not encoded | Replace `@` with `%40` in the URL |
| `(Cannot decode SVG: ...)` | PlantUML can't parse SVG with gradients | Use the PNG version (path `Azure/.../service.png`) |
| Icon not visible, only label shows | URL fetch failed (404 or CORS) | Verify URL returns 200 with `curl -I`; check the icon path against `dist/Azure/<Category>/` browsable on GitHub |
| Layout broken, nodes overlapping | Diagram too complex for one layout | Split into multiple smaller diagrams (one per concern) |
| Render time > 30s | Diagram has >50 nodes or >4 nesting levels | Simplify; consider C4 model |
| Layout hard to control | Default dot engine has limited control | Use `together {}` or hidden edges |

## Extending the icon set

If an icon is **not available** in `hanv89/archicon`:

1. **New Microsoft service**: Add to `dist/Azure/[Category]/` of the repo, push a PR.
2. **Internal logo / brand**: Add to `dist/Custom/` using kebab-case naming (e.g., `your-brand.png`).
3. **Third-party service**: Add to `dist/Custom/3rdparty/` with clear attribution.

PNG specs:
- Size: 70x70 px
- Format: PNG with alpha channel
- Background: Transparent
- DPI: 72 (standard web)

## Reference

- **This repository**: `https://github.com/hanv89/archicon`
- **License**: MIT — see [`LICENSE`](../../LICENSE)
- **Third-party attribution + Microsoft ToU snapshot**: see [`NOTICE`](../../NOTICE)
- **Icon-use rules (human-readable)**: see [`USAGE-RULES.txt`](../Azure/USAGE-RULES.txt)
- **Microsoft Azure Architecture Icons Terms of Use**: `https://learn.microsoft.com/en-us/azure/architecture/icons/`
- **Microsoft Trademark and Brand Guidelines**: `https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general`
- **PlantUML docs**: `https://plantuml.com/`
- **Azure-PlantUML upstream (intermediate redistribution source)**: `https://github.com/plantuml-stdlib/Azure-PlantUML`
- **PlantUML web editor**: `https://www.plantuml.com/plantuml/uml/`

## Available examples

Renderable example diagrams live in `examples/` (file list mirrors `manifest.json`):

- [`01-context.puml`](examples/01-context.puml) — Azure 3-tier system context (Front Door → App Service → SQL Database).
- [`02-fabric-data-pipeline.puml`](examples/02-fabric-data-pipeline.puml) — Microsoft Fabric data-engineering pipeline (Eventstream → Lakehouse → Notebook → Warehouse → Power BI).
- [`03-system-architecture.puml`](examples/03-system-architecture.puml) — Azure AKS application feeding a Microsoft Fabric data plane (canonical Azure + Fabric mixed example, C4 level 2).
- [`04-sequence-flow.puml`](examples/04-sequence-flow.puml) — Request sequence across Azure Front Door → AKS → Service Bus → Fabric Eventstream.
- [`05-component.puml`](examples/05-component.puml) — AKS cluster internals (C4 level 3 zoom into the `03-system-architecture.puml` AKS box).
- [`06-deployment.puml`](examples/06-deployment.puml) — Multi-region active-active deployment with Fabric workspace replication.
- [`07-azure-aks-mixed.puml`](examples/07-azure-aks-mixed.puml) — Azure-fronted AKS deployment with a Kubernetes workload subgraph (Front Door + App Gateway → AKS Service → Deployment + Pods + ConfigMap + Secret → Azure SQL). Canonical Azure + Kubernetes mixed example.
- [`08-azure-fluentui-mixed.puml`](examples/08-azure-fluentui-mixed.puml) — Azure web architecture decorated with FluentUI UI affordances (Cloud boundary, Shield + Person Add for auth, status indicators, organisation context). Canonical Azure + FluentUI mixed example.
- [`09-devops-pipeline.puml`](examples/09-devops-pipeline.puml) — DevOps pipeline from source (GitHub) through CI/CD (GitHub Actions + Argo CD) into AKS / Kubernetes runtime, with Prometheus + Grafana observability and a Postgres data store. Canonical Devicon-decorated DevOps example.
- [`10-edit-existing.puml`](examples/10-edit-existing.puml) — worked before/after **edit** of an existing 3-tier diagram (adds a Redis cache node + re-wires it) demonstrating the § "Editing an existing diagram" minimal-diff workflow.
- [`11-mermaid-architecture.mmd`](examples/11-mermaid-architecture.mmd) — **Mermaid** (`.mmd`, not PlantUML) text-labelled topology demonstrating § "Mermaid mode" (icon-light, renders natively on GitHub).
- [`12-mermaid-icons.mmd`](examples/12-mermaid-icons.mmd) — **Mermaid** icon-mode example (ELK layout + inline `<img>` vendor icons + styled clusters) demonstrating § "Mermaid mode" sub-mode (b); render with `examples/assets/render-mermaid.sh`.
</content>
</invoke>

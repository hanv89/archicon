# Init-time clarification — two worked dialogues

These two cases show the agent applying the § "Selection workflow" Q3–Q6
skip-if-clear rules. **Case A** is genuinely ambiguous and fires 3 questions.
**Case B** has a clear create verb + vendor + level in the prompt and fires
**0** questions — the only un-resolved axis (Q5, format) is silently filled
with the table-row default.

## Why the asymmetry (read this first)

Case A asks 3 questions because 3 axes (vendor, level, mode) are genuinely
under-specified. Case B asks 0 questions because the prompt nails all 4
non-default axes and Q5 has a usable default. The skill's anti-pattern bullet
("aim 0–4 questions per init turn, never the full 6-question battery") is
the budget; the skip-rules are the mechanism for staying within budget.

## Case A — ambiguous prompt → Q3 + Q4 + Q6 fire

> **User:** I need a diagram for the payments service.
> *(Prior chat-history context: this is a one-off "Standalone" diagram for the engineering team — audience + document are inferred from session context, so Q1 + Q2 silently skip.)*

Prompt analysis: Q1 (document) + Q2 (audience) inferred from prior session
context → skip; no vendor named (→ Q3 must fire); no diagram-type word
(→ Q4 must fire); no create-vs-edit verb (→ Q6 must fire). Q5 (format) has
a sensible default — one-click render URL for new diagrams — so the agent
applies the default instead of asking.

> **Agent:** Three quick questions before I draw:
>
> 1. **Cloud provider?** Azure / AWS / GCP / multi-cloud / vendor-neutral.
> 2. **Detail level?** Context (audience: exec) / Container (audience: engineering team) / Component (one container's internals) / System Landscape (multi-system view) / Dynamic (one request's flow) / Deployment (containers → infra map).
> 3. **New diagram, or edit an existing `.puml`?** If editing, share the file path.

> **User:** AWS, Container level, new diagram.

> **Agent:** Got it — drawing an AWS Container diagram for the payments
> service. I'll include the raw `.puml` plus a one-click render URL.
>
> ```plantuml
> @startuml
> ' (… authored .puml here …)
> @enduml
> ```
>
> **Render URL:** `https://www.plantuml.com/plantuml/png/<encoded>`

## Case B — clear create-verb prompt → 0 questions fire (Q5 default applied)

> **User:** Draw an Azure Container diagram for our checkout flow: Front Door → App Service → Cosmos DB + Azure SQL + Cache for Redis, with Key Vault for secrets.

Prompt analysis: "draw" verb → skip Q6 (mode=create); "Azure" → skip Q3
(vendor=Azure); "Container diagram" → skip Q4 (level=Container); audience
inferred as engineering team from the technology depth in the prompt
(→ skip Q2); document = Standalone (no HLD/ADR/TDD signal → skip Q1); no
format hint → Q5 default applied (one-click render URL). Net: 0 questions
fired; agent goes straight to drawing.

> **Agent:** Drawing the Azure Container diagram now. (Defaulting to raw
> `.puml` + a one-click render URL — say "no URL" if you want PlantUML only.)
>
> ```plantuml
> @startuml
> ' (… authored .puml here, ~10 nodes matching the prompt …)
> @enduml
> ```
>
> **Render URL:** `https://www.plantuml.com/plantuml/png/<encoded>`


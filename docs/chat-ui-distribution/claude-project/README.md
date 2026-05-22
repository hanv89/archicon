# Claude.ai Project recipe — Architecture Diagram Skill

This guide installs the architecture-diagram skill into a Claude.ai
Project, so you can ask Claude to draw PlantUML architecture diagrams
in chat-UI flows (no CLI, no IDE).

The same skill content is also installable into Claude Code, Codex CLI,
and Cursor via the `@hanv89/arch-skill` npm CLI — this Project
recipe is for users whose primary surface is `claude.ai` chat.

## What this is

A reproducible "drop the bundle ZIP into a Project, paste the system
prompt" recipe. The bundle ships per release and contains:

- `SKILL.md` — the skill body (rules, examples references, filename rule).
- `NOTICE` — per-vendor attribution + trademark notices.
- `examples/*.puml` — 9 worked diagram examples.
- `indexes/<Vendor>-INDEX.md` — 5 per-vendor icon catalogs (Azure, Fabric,
  Kubernetes, FluentUI, Devicon).
- `usage-rules/<Vendor>-USAGE-RULES.txt` — 5 per-vendor licence + trademark
  rules.
- `README.md` — top-level pointer (inside the ZIP itself).

## Prerequisites

- A Claude.ai account on a plan that supports Projects (currently Pro / Team / Enterprise).
- The latest `chat-ui-bundle.zip` from the project's GitHub Releases page:
  <https://github.com/hanv89/archicon/releases>

## Step-by-step setup

1. **Download the bundle.** From the latest release on the GitHub Releases
   page, download `chat-ui-bundle.zip` to your local machine.
2. **Unzip locally.** `unzip chat-ui-bundle.zip -d chat-ui-bundle/` — gives
   you a directory with `SKILL.md`, `NOTICE`, `README.md`, and three
   sub-directories (`examples/`, `indexes/`, `usage-rules/`).
3. **Create a new Claude.ai Project.** In Claude.ai, click "Projects" →
   "Create project". Name it something memorable (e.g. "Architecture Diagrams").
4. **Upload the bundle as Project knowledge.** Open the Project's
   "Project knowledge" section. Drag-and-drop all files from the unzipped
   directory (including files in the sub-directories — Claude.ai flattens
   them in the knowledge store but the model can still reference them by
   filename via SKILL.md).
   - Tip: if Claude.ai imposes a file-count cap, prioritise `SKILL.md` +
     all `indexes/*.md` + all `examples/*.puml`. `usage-rules/*.txt` and
     `NOTICE` are smaller and can be added if there is room.
5. **Paste the system prompt.** Open the Project's "Custom instructions"
   field. Paste the entire content of [`system-prompt.md`](./system-prompt.md)
   into it. Save.
6. **Test render.** Open a new chat inside the Project. Try a prompt like:

   > Draw an Azure architecture diagram for a 3-tier Node.js + Python web
   > app running on AKS, with PostgreSQL + MongoDB backing stores, and a
   > GitHub + Docker DevOps pipeline. Use icons from all relevant vendors
   > (Azure, Kubernetes, Devicon).

   Claude should look up filenames in `Azure-INDEX.md`, `Kubernetes-INDEX.md`,
   and `Devicon-INDEX.md`, then emit a PlantUML diagram using literal
   `<img:URL>` references to the project's `raw.githubusercontent.com`
   hosted icons. Paste the diagram source into the rendering surface of
   your choice (Confluence PlantUML app, `play.plantuml.com`, or the
   GitHub PlantUML preview proxy).

## Updating

A new bundle ZIP ships with every skill release (typically every few
weeks). To update:

1. Download the new `chat-ui-bundle.zip` from Releases.
2. In your Project's "Project knowledge" section, remove the old files
   and re-upload the new ones.
3. Compare `system-prompt.md` against the version you pasted earlier; if
   it has changed, paste the new content.

The system prompt rarely changes between releases — most updates are
to `SKILL.md` body content or to the per-vendor `INDEX.md` catalogs as
upstream icon sets grow.

## Troubleshooting

- **Claude emits broken-image placeholders in the diagram.** The filename
  in the `<img:URL>` does not match any file in the project's `dist/`
  tree. SKILL.md has a "Filename rule (non-negotiable)" — make sure
  Claude is looking the path up in the relevant `<Vendor>-INDEX.md`
  before emitting the URL. Re-prompt: "Check the filename against
  Azure-INDEX.md before using it."
- **Claude reverts to drawing diagrams in a different style.** The
  Project's custom instructions may have been cleared or overridden in
  the chat. Re-paste `system-prompt.md` content.
- **The bundle file count is too large for Claude.ai's Project limit.**
  Use the prioritisation hint in step 4 above. Drop `usage-rules/*.txt`
  and `NOTICE` first; they are referenced by SKILL.md but the model can
  still emit correct diagrams without them.

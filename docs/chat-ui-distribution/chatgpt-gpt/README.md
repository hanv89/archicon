# ChatGPT Custom GPT recipe — Architecture Diagram Skill

This guide installs the architecture-diagram skill as a published
ChatGPT Custom GPT, so users can ask the GPT to draw PlantUML
architecture diagrams in the OpenAI chat-UI.

The same skill content is also installable into Claude Code, Codex CLI,
and Cursor via the `@hanv89/arch-skill` npm CLI, and into a
Claude.ai Project via the sibling recipe in
[`../claude-project/`](../claude-project/) — this recipe is the OpenAI
chat-UI variant.

## What this is

A reproducible "create a Custom GPT, paste instructions, upload bundle
as Knowledge, publish" recipe. The bundle ships per release and contains:

- `SKILL.md` — the skill body.
- `NOTICE` — per-vendor attribution + trademark notices.
- `examples/*.puml` — 9 worked diagram examples.
- `indexes/<Vendor>-INDEX.md` — 5 per-vendor icon catalogs (Azure, Fabric,
  Kubernetes, FluentUI, Devicon).
- `usage-rules/<Vendor>-USAGE-RULES.txt` — 5 per-vendor licence + trademark
  rules.

## Prerequisites

- An OpenAI account on a plan that supports building Custom GPTs
  (currently ChatGPT Plus / Team / Enterprise / Edu).
- GPT Builder access (open `https://chat.openai.com/gpts/editor` — if
  the page loads, you have access).
- The latest `chat-ui-bundle.zip` from the project's GitHub Releases page:
  <https://github.com/hanv89/archicon/releases>

## Step-by-step setup (publisher)

These steps are performed once, by the publisher of the Custom GPT.
End users do not run any of these — they consume the published GPT via
its shareable link.

1. **Download the bundle.** Pull `chat-ui-bundle.zip` from the latest
   GitHub Release.
2. **Unzip locally.** `unzip chat-ui-bundle.zip -d chat-ui-bundle/`.
3. **Open GPT Builder.** Visit `https://chat.openai.com/gpts/editor`.
   Click "Create a GPT".
4. **Choose "Configure" mode** (not "Create" mode — you want to paste
   instructions, not have the builder chat with you).
5. **Set the GPT identity**:
   - **Name**: e.g. "Architecture Diagram Assistant".
   - **Description**: e.g. "Draws PlantUML architecture diagrams using
     official Azure / Fabric / Kubernetes / FluentUI / Devicon icons."
   - **Profile picture**: optional — generate one via DALL·E or upload
     a custom image.
6. **Paste the GPT instructions.** Open
   [`system-prompt.md`](./system-prompt.md). Copy the entire content into
   the "Instructions" field. (OpenAI's instructions field caps at ~8K
   characters; the system prompt is well under this.)
7. **Upload bundle as Knowledge.** In the "Knowledge" section, click
   "Upload files" and select ALL files from your unzipped bundle:
   `SKILL.md`, `NOTICE`, `README.md`, all `examples/*.puml`, all
   `indexes/<Vendor>-INDEX.md`, all `usage-rules/<Vendor>-USAGE-RULES.txt`.
   - OpenAI allows up to 20 knowledge files per Custom GPT — the bundle's
     22 files exceed this; drop `NOTICE` and the inner `README.md` first
     (they are reference-only; the model can still emit correct diagrams
     without them).
8. **Capabilities**:
   - Web Browsing — **OFF** by default (the skill works fully from
     uploaded knowledge; turning Browse on adds latency).
   - DALL·E Image Generation — **OFF** (we generate PlantUML source, not
     raster images).
   - Code Interpreter & Data Analysis — **OFF** (no need).
9. **Conversation starters** — add 4 starter prompts to help users
   discover what the GPT can do. Examples:
   - "Draw an Azure 3-tier web app architecture."
   - "Draw a Fabric data pipeline (Lakehouse + Notebook + Warehouse)."
   - "Draw a Kubernetes deployment with Pod + Service + Deployment."
   - "Draw a DevOps pipeline diagram with GitHub + Docker + Azure."
10. **Test render in the right-hand preview** before publishing. Try the
    test prompt: "Draw an Azure architecture diagram for a 3-tier app on
    AKS with PostgreSQL backing store and a GitHub + Docker DevOps
    pipeline." The GPT should emit a PlantUML diagram with literal
    `<img:URL>` tokens whose filenames match the per-vendor INDEX
    catalogs.
11. **Publish.** Click "Save" → choose "Only me" (private testing) or
    "Anyone with the link" (recommended for sharing). Make a note of:
    - The published GPT's **id** (visible in the URL after publish:
      `https://chat.openai.com/g/g-<ID>-<slug>`).
    - The **shareable link**.
12. **Record the publish details.** Edit
    [`GPT-ID.md`](./GPT-ID.md) and fill in the GPT id, shareable link,
    publish date, name, description, and conversation starters. Commit
    the change.

## Updating

A new bundle ZIP ships with every skill release. To update the published GPT:

1. Download the new `chat-ui-bundle.zip` from Releases.
2. Open the Custom GPT in GPT Builder ("Configure" mode).
3. Replace the Knowledge files with the new bundle contents (delete old
   files, upload new ones).
4. Compare [`system-prompt.md`](./system-prompt.md) against the version
   in the Instructions field. If it has changed, paste the new content.
5. Save. The GPT updates in place; the shareable link does not change.

## Troubleshooting

- **GPT emits diagrams without using the INDEX lookup.** Re-paste the
  Instructions content; the GPT may have dropped the system prompt after
  an extended conversation. Alternatively, add a one-line reinforcement
  to the conversation starters: "Always look up filenames in the
  relevant Vendor-INDEX.md before emitting `<img:URL>`."
- **OpenAI's Knowledge file limit prevents uploading the full bundle.**
  See the prioritisation hint in step 7 above.
- **Microsoft icon usage flagged by a user as non-compliant.** Direct
  users to the bundled `usage-rules/Azure-USAGE-RULES.txt` and
  `NOTICE` — the GPT is instructed by SKILL.md to respect those rules,
  but enforcement is operational, not automatic.

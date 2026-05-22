# Where this skill is listed

> **archicon listings — NOT yet submitted (M3 go-to-market).** This matrix is the target list, ported from the prior product; statuses below predate archicon and must be re-submitted under the archicon identity (`@hanv89/arch-skill`, `github.com/hanv89/archicon`). Treat all rows as **pending** until re-opened.

A live record of every public skill marketplace / community index the `@hanv89/arch-skill` skill has been submitted to, and the per-target outcome. Updated on each new submission or status change.

## Decision matrix

| target | exists? | submission path | listing URL | outcome | date checked |
|---|---|---|---|---|---|
| [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) | yes | GitHub PR | [PR #855](https://github.com/ComposioHQ/awesome-claude-skills/pull/855) | pending review | 2026-05-16 |
| [travisvn/awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills) | yes | GitHub PR | [PR #742](https://github.com/travisvn/awesome-claude-skills/pull/742) | pending review | 2026-05-16 |
| [spencerpauly/awesome-cursor-skills](https://github.com/spencerpauly/awesome-cursor-skills) | yes | GitHub PR | [PR #16](https://github.com/spencerpauly/awesome-cursor-skills/pull/16) | pending review | 2026-05-16 |
| [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | yes | web-form issue (no CLI) | _pending — sponsor submission_ | pending sponsor submit | 2026-05-16 |
| [PatrickJS/awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules) | yes | GitHub PR | — | skip — list is for coding-style rules per language/framework, not domain skills for diagram-as-code; would clutter the list rather than serve it | 2026-05-16 |
| [anthropics/skills](https://github.com/anthropics/skills) | yes | n/a (curated by Anthropic) | — | skip — Anthropic-curated showcase of their own example skills; no community submission flow | 2026-05-16 |
| [agentskills.io](https://agentskills.io/) | yes | n/a (standard body) | — | skip — Agent Skills open-standard hub; specification + adopter showcase, not a community skill directory | 2026-05-16 |
| [skills.sh](https://skills.sh/) | yes | `skillsdir` CLI with GitHub OAuth | — | skip — publish flow needs an interactive `skillsdir login` (GitHub OAuth) that can't be completed in this phase; revisit when a maintainer has 5 min to authenticate | 2026-05-16 |
| [cursor.directory](https://cursor.directory) | yes | unknown (site rate-limited during research) | — | skip — submission protocol unconfirmed in this research pass; revisit when access is unblocked | 2026-05-16 |

## Per-target notes

### Pending-review (PRs)

- [ComposioHQ/awesome-claude-skills#855](https://github.com/ComposioHQ/awesome-claude-skills/pull/855) — add to *Development & Code Tools*.
- [travisvn/awesome-claude-skills#742](https://github.com/travisvn/awesome-claude-skills/pull/742) — add to *Community Skills → Individual Skills*.
- [spencerpauly/awesome-cursor-skills#16](https://github.com/spencerpauly/awesome-cursor-skills/pull/16) — add to *Planning & Architecture*.

When a PR merges, the row above will be updated to `shipped` with the canonical merged-list URL.

### Pending sponsor submit (web-form)

`hesreallyhim/awesome-claude-code` requires submission via the GitHub web UI issue form; the CLI is explicitly banned by the repo's CONTRIBUTING.md. The submission body is drafted and ready for the maintainer to paste in via <https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml>.

### Skipped

Five targets skipped per rationale in the matrix. The skips are intentional — three are not community-submission flows at all (Anthropic-curated, standard body, list category mismatch), one is OAuth-gated (skills.sh), and one is rate-limited at the time of research (cursor.directory). Future re-visits can move any of these out of the skip column without re-opening this phase.

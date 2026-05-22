# Onboarding test — session log

> **SAMPLE RESULT — illustrative.** This is a maintainer self-run, included so
> you can see what a completed log looks like. It is **not** an independent UAT
> result — the maintainer already knows the project, so the timing is optimistic
> and the stuck-point count is low by construction. Real signal comes from people
> new to the repo; submit yours via a GitHub issue (see `../README.md`).

## Tester profile

- **Handle**: hanv05
- **Background**: project maintainer (self-run for the sample)
- **Prior exposure to this project**: extensive — this is a self-run, not a blind test
- **Path taken**: hand-write `<img:URL>` (no agent) — fastest route to a first render
- **Terminal comfort**: comfortable
- **Date**: 2026-05-14
- **Observed by**: solo run

## Environment

- Skill pre-installed? no
- Pre-existing skill folder? no
- OS / shell: Linux / bash
- Internet access: yes

## Timing

- **Start** (opened README): 10:00
- **Stop** (saw a rendered diagram): 10:06
- **Total elapsed**: 6 min
- **Rendered via**: play.plantuml.com

## Stuck-point table

| # | Where in README | What you expected | What happened | Why (if observed) |
|---|---|---|---|---|
| 1 | Quick-start — choice between path A (install the skill) and path B (hand-write) | A single obvious "fastest way to a first diagram" | Two paths offered; had to decide which one serves "first rendered diagram" fastest. Path A is labelled *recommended* but needs an agent + install; path B renders immediately. | The README optimises path A for the long-term workflow, but a newcomer optimising for *a first render right now* is better served by path B. The labelling doesn't make that distinction. |

**Stuck-point count**: 1

## Near-misses (hesitations, self-corrected — not counted)

- Briefly scanned for a copy button on the path B code block before just selecting the text.

## Quotes (verbatim, if observed)

- (solo run — no observer quotes)

## Debrief

- **Top friction points, in your own words**: deciding between the two quick-start paths. Once on path B, copy the snippet → paste into play.plantuml.com → rendered, no friction.
- **One thing that would have helped most**: a one-liner up front — "just want to see it render? jump to path B" — so the path choice is framed by intent rather than by *recommended* vs not.

## Verdict (against `rubric.md`)

- Elapsed ≤ 15 min? yes
- Stuck points ≤ 3? yes
- **Result**: PASS (maintainer self-run — see the sample disclaimer above; not a substitute for independent runs)

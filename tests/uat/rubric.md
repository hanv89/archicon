# Onboarding test — rubric

The fixed scoring rules for an onboarding run. Read this before you start; don't
change it mid-test.

## The task

The person being tested gets **only** this — no verbal hints, no extra context:

> Repo: <https://github.com/hanv89/archicon>
> Task: "Get your first rendered Azure architecture diagram."

Nothing else. If they ask a clarifying question, that question is itself a data
point — log it as a stuck point, then give the most minimal possible nudge.

## Who should be tested

- Someone who has **not** used this project before. The result is only
  meaningful if the README is genuinely new to them.
- Has an AI coding agent available, **or** is willing to use the no-agent path
  (hand-writing `<img:URL>`). Note which path they took.
- Basic terminal comfort (can run a command, knows what a directory is). This
  test measures the README, not terminal literacy.

## Environment

- No prior install of the skill; no pre-existing skill folder for whichever
  agent is used.
- Internet access.
- Start where a stranger to the project would: the GitHub repo page.

## Timing

- **Start**: the moment they open the README.
- **Stop**: the moment they see a **rendered diagram** — on play.plantuml.com, a
  Confluence PlantUML app, or GitHub's inline renderer. Producing `.puml` text is
  *not* the stop point; a rendered image is.
- Use a stopwatch. Record start + end wall-clock times and total elapsed minutes.

## What counts as a stuck point

Any **one** of:

- Blocked for more than ~60 seconds.
- Backtracking (undoing a step, re-reading a section because the first read
  misled them).
- Asking a question.
- Following the README literally and getting a **wrong or broken result** —
  broken image, error message, command not found.

Log each stuck point with: **where** in the README (section + roughly which
instruction), **what they expected**, **what actually happened**, and — if the
run was observed — **why** (the observer's read of the root cause).

A "near miss" (hesitation under 60s, self-corrected) is **not** a stuck point,
but note it in one line — it's still a weak signal.

## Pass / fail bar

| Outcome | Elapsed | Stuck points |
|---|---|---|
| **PASS** | ≤ 15 min | ≤ 3 |
| **FAIL** | > 25 min | OR > 3 |
| **Marginal** | 15–25 min with ≤ 3 stuck points | counts as a soft fail — a small README fix is likely enough |

Both conditions must hold for PASS. A 12-minute run with 5 stuck points is a
FAIL. A 22-minute run with 2 stuck points is Marginal.

A FAIL is a **good** submission — it found a real gap. The point of the test is
to surface friction, not to collect clean passes.

## If the run is observed

- The observer stays silent. They intervene **only** to break a total dead-end
  (the tester genuinely cannot proceed at all). A total dead-end is the most
  severe possible finding — log it in full, then give the minimal nudge.
- No coaching, no answering "is this right?" — log the question, deflect with
  "do what the README tells you".
- Capture verbatim quotes. "Wait, where does it install?" is more useful than a
  paraphrase.

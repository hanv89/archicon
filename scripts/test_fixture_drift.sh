#!/usr/bin/env bash
# Detects drift between `fixture/skill-md-only` and `main` — scoped to the
# skill bundle (`dist/skill/`) only.
#
# The fixture branch is a stripped-down view of main used by the end-to-end
# install smoke test in `scripts/smoke_cli.sh`. The install path fetches the
# skill bundle (SKILL.md + examples + manifest, all under `dist/skill/`) from
# the fixture branch; the canary icon `dist/Azure/Compute/AzureVirtualMachine.png`
# is removed on the fixture so the install's missing-file fall-through is
# exercised (its absence is validated by smoke_cli's actual 404 expectation,
# not here).
#
# Scope (narrowed 2026-05-20): this check compares ONLY `dist/skill/`. Earlier
# it compared the whole tree minus a canary+packages exclusion, which meant any
# unrelated change to main (docs, scripts, workflows, other vendors' icons)
# tripped the gate on the next PR and forced a manual fixture rebuild — even
# though the fixture is only rebuilt on a SKILL.md shape change. Scoping to
# the bundle removes that false-positive class: the fixture only needs to track
# the bundle it actually serves.
#
# Run locally:
#   git fetch origin fixture/skill-md-only:fixture/skill-md-only
#   bash scripts/test_fixture_drift.sh
#
# Exit codes:
#   0 — no drift (fixture's dist/skill/ matches main's dist/skill/).
#   1 — drift detected; fixture needs rebuilding.
#   2 — environment problem (fixture branch missing, refs unavailable).

set -uo pipefail
export LC_ALL=C

# Ensure both refs are reachable locally.
if ! git rev-parse --verify origin/main >/dev/null 2>&1 && ! git rev-parse --verify main >/dev/null 2>&1; then
  echo "FAIL: neither main nor origin/main is reachable; cannot compare" >&2
  exit 2
fi
MAIN_REF="$(git rev-parse --verify main 2>/dev/null || git rev-parse --verify origin/main 2>/dev/null)"

if ! git rev-parse --verify fixture/skill-md-only >/dev/null 2>&1; then
  echo "FAIL: fixture/skill-md-only not reachable locally" >&2
  echo "Run: git fetch origin fixture/skill-md-only:fixture/skill-md-only" >&2
  exit 2
fi
FIXTURE_REF="$(git rev-parse --verify fixture/skill-md-only)"

echo "Comparing fixture/skill-md-only (${FIXTURE_REF:0:8}) against main (${MAIN_REF:0:8})..."

# Compute the diff between fixture and main, scoped to the skill bundle only.
# Anything outside dist/skill/ (other vendors' icons, scripts, workflows, docs,
# packages/) is intentionally out of scope — the fixture only serves the bundle.
DRIFT=$(git diff --name-status "${MAIN_REF}" "${FIXTURE_REF}" -- \
  'dist/skill/' 2>/dev/null || true)

if [ -n "${DRIFT}" ]; then
  echo "FAIL: fixture/skill-md-only has drifted from main:"
  echo "${DRIFT}"
  echo ""
  echo "Rebuild the fixture:"
  echo "  git checkout -b fixture/skill-md-only-new main"
  echo "  git rm dist/Azure/Compute/AzureVirtualMachine.png"
  echo "  git rm -r packages/"
  echo "  git commit -m 'fixture: skill-md-only — rebuild against main'"
  echo "  git push origin fixture/skill-md-only-new:fixture/skill-md-only --force-with-lease"
  exit 1
fi

echo "PASS: fixture/skill-md-only dist/skill/ is in sync with main."
exit 0

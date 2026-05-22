#!/usr/bin/env bash
# Azure-PlantUML upstream-health monitor.
#
# Calls the GitHub API to read the archived/disabled/private flags on
# plantuml-stdlib/Azure-PlantUML — the canonical Azure icon source.
# If any flag is true, the watchdog fires: subsequent icon refreshes
# would silently pull from an unmaintained or removed source.
#
# Exit codes:
#   0 — upstream healthy (archived=false, disabled=false, private=false).
#   1 — upstream flagged (one of the three is true).
#   2 — environment problem (gh CLI missing, auth missing, network failure).

set -uo pipefail

REPO="${REPO:-plantuml-stdlib/Azure-PlantUML}"

if ! command -v gh >/dev/null 2>&1; then
  echo "FAIL: gh CLI required" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq required" >&2
  exit 2
fi

data=$(gh api "repos/${REPO}" --jq '{archived: .archived, disabled: .disabled, private: .private}' 2>/dev/null) || {
  echo "FAIL: gh api repos/${REPO} failed (auth / network / rate-limit)" >&2
  exit 2
}

archived=$(jq -r '.archived' <<<"${data}")
disabled=$(jq -r '.disabled' <<<"${data}")
private=$(jq -r '.private'  <<<"${data}")

if [ "${archived}" = "true" ] || [ "${disabled}" = "true" ] || [ "${private}" = "true" ]; then
  echo "FAIL: upstream ${REPO} flagged (archived=${archived} disabled=${disabled} private=${private})" >&2
  exit 1
fi

echo "PASS: upstream ${REPO} healthy (archived=${archived} disabled=${disabled} private=${private})"
exit 0

#!/usr/bin/env bash
# AWS icon upstream-health monitor (modelled on monitor_kubernetes_health.sh).
#
# AWS Architecture Icons ship under CC-BY-ND 2.0 (NoDerivatives). This repo's
# whole AWS regime — verbatim, byte-identical redistribution with NO resize —
# is legally anchored to that license staying NoDerivatives. So this monitor
# does TWO things before the weekly icon refresh pulls anything new:
#
#   (1) Repo health: GitHub API archived / disabled / private flags on
#       awslabs/aws-icons-for-plantuml. Any true flag means a refresh would
#       silently pull from an unmaintained or removed source.
#   (2) LICENSE fingerprint: fetch the upstream LICENSE and assert it still
#       carries the CC-BY-ND (NoDerivs) marker AND matches the recorded
#       sha256 baseline (dist/baselines/aws-icons-license.txt). A license
#       change is a licensing event that owes a re-audit before any refresh.
#
# Exit codes:
#   0 — upstream healthy AND license unchanged.
#   1 — upstream flagged OR license drifted (re-audit owed).
#   2 — environment problem (gh/jq/curl/sha256sum missing, network failure,
#       baseline absent).

set -uo pipefail
export LC_ALL=C

REPO="${REPO:-awslabs/aws-icons-for-plantuml}"
BRANCH="${BRANCH:-main}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASELINE="${BASELINE:-${REPO_ROOT}/dist/baselines/aws-icons-license.txt}"
LICENSE_URL="${LICENSE_URL:-https://raw.githubusercontent.com/${REPO}/${BRANCH}/LICENSE}"

for tool in gh jq curl sha256sum; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "FAIL: ${tool} required" >&2; exit 2; }
done
[ -f "${BASELINE}" ] || { echo "FAIL: baseline missing at ${BASELINE}" >&2; exit 2; }

# ---- (1) Repo health flags ----
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

# ---- (2) LICENSE fingerprint ----
want_marker="$(awk '/^\[LICENSE MARKER\]/{getline; print; exit}' "${BASELINE}")"
want_sha="$(awk '/^\[LICENSE SHA256\]/{getline; print; exit}' "${BASELINE}")"
if [ -z "${want_marker}" ] || [ -z "${want_sha}" ]; then
  echo "FAIL: baseline ${BASELINE} malformed (missing marker or sha256)" >&2
  exit 2
fi

tmp=$(mktemp) || exit 2
trap 'rm -f "${tmp}"' EXIT
if ! curl -fsSL --max-time 30 "${LICENSE_URL}" > "${tmp}" 2>/dev/null; then
  echo "FAIL: could not fetch ${LICENSE_URL}" >&2
  exit 2
fi

got_sha="$(sha256sum "${tmp}" | cut -d' ' -f1)"

if ! grep -qF "${want_marker}" "${tmp}"; then
  echo "FAIL: AWS LICENSE no longer carries the CC-BY-ND marker '${want_marker}'" >&2
  echo "      (license may have changed — re-audit owed before next refresh)" >&2
  exit 1
fi

if [ "${got_sha}" != "${want_sha}" ]; then
  echo "FAIL: AWS LICENSE sha256 drifted (want=${want_sha} got=${got_sha})" >&2
  echo "      Marker still present, but file content changed — re-audit owed." >&2
  exit 1
fi

echo "PASS: AWS LICENSE unchanged (CC-BY-ND/NoDerivs marker present, sha256 matches baseline)"
exit 0

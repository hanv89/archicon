#!/usr/bin/env bash
# Build the chat-UI bundle twice and assert byte-identical output.
#
# Cross-run reproducibility is a non-trivial property — any host-clock
# leakage, non-sorted file order, or extra-field metadata in the archive
# would make two builds of the same source tree produce different bytes.
# This is the gate against drift in build_chat_ui_bundle.sh.
#
# Within-run only: this asserts the build is deterministic on the same
# source tree at the same moment in time. It does NOT assert the bundle
# stays byte-identical six months later (icons can change upstream).
#
# Exit codes:
#   0 — both builds produced byte-identical ZIPs.
#   1 — drift detected (sha256 mismatch or unzip-list mismatch).
#   2 — environment problem (zip / sha256sum missing).
set -uo pipefail
export LC_ALL=C
export TZ=UTC

command -v zip       >/dev/null 2>&1 || { echo "ERROR: zip missing"       >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "ERROR: sha256sum missing" >&2; exit 2; }
command -v unzip     >/dev/null 2>&1 || { echo "ERROR: unzip missing"     >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "INFO  building bundle (1/2)..."
bash scripts/build_chat_ui_bundle.sh >/dev/null
cp dist/chat-ui-bundle.zip "${WORK}/bundle-1.zip"
SHA_1="$(sha256sum "${WORK}/bundle-1.zip" | awk '{print $1}')"

echo "INFO  building bundle (2/2)..."
bash scripts/build_chat_ui_bundle.sh >/dev/null
cp dist/chat-ui-bundle.zip "${WORK}/bundle-2.zip"
SHA_2="$(sha256sum "${WORK}/bundle-2.zip" | awk '{print $1}')"

# Build deterministic file lists for comparison (sorted by path, size, mtime
# stripped). Any divergence between the two outputs flags drift.
unzip -l "${WORK}/bundle-1.zip" | awk 'NR>3 && $4!="" {print $1, $4}' | sort >"${WORK}/list-1.txt"
unzip -l "${WORK}/bundle-2.zip" | awk 'NR>3 && $4!="" {print $1, $4}' | sort >"${WORK}/list-2.txt"

echo "sha256(bundle-1): ${SHA_1}"
echo "sha256(bundle-2): ${SHA_2}"

if [ "${SHA_1}" != "${SHA_2}" ]; then
  echo "FAIL  bundle ZIP not byte-reproducible across two builds."
  if ! diff -u "${WORK}/list-1.txt" "${WORK}/list-2.txt"; then
    echo "      file-list diff above shows entries that differ in path or size."
  else
    echo "      file lists match — drift is in archive metadata (extra fields, timestamps, or compression)."
  fi
  exit 1
fi

if ! diff -q "${WORK}/list-1.txt" "${WORK}/list-2.txt" >/dev/null; then
  echo "FAIL  sha256 matched but file lists differ (this should never happen)."
  diff -u "${WORK}/list-1.txt" "${WORK}/list-2.txt"
  exit 1
fi

echo "PASS  bundle ZIP byte-reproducible across two builds."

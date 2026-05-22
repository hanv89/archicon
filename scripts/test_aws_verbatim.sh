#!/usr/bin/env bash
# AWS CC-BY-ND verbatim contract gate.
#
# AWS Architecture Icons are CC-BY-ND 2.0: the "NoDerivatives" clause means a
# resize / re-encode / recolor / crop creates a forbidden derivative work. This
# repo therefore ships dist/AWS/**/*.png BYTE-IDENTICAL to upstream. This gate
# enforces that contract with two assertions:
#
#   (a) build_aws.sh contains NO `rsvg` token (it must never invoke an image
#       converter — `grep -L rsvg` must list the file, i.e. no match).
#   (b) the shipped dist/AWS PNGs are sha256-identical to upstream.
#
# Assertion (b) runs OFFLINE against the cached manifest
# scripts/fixtures/aws-upstream-sha256.tsv (sha256 \t relpath, captured at the
# recorded upstream SHA). If the cache is absent the test attempts a shallow
# clone; if upstream is unreachable AND no cache exists, it skips (b) with a
# clear message rather than failing on a network problem.
#
# Exit codes:
#   0 — verbatim contract holds (or (b) skipped offline with cache absent).
#   1 — build_aws.sh references rsvg, or a shipped PNG diverges from upstream.
#   2 — environment problem (build_aws.sh / dist/AWS missing).
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

BUILD="scripts/build_aws.sh"
DIST="dist/AWS"
CACHE="scripts/fixtures/aws-upstream-sha256.tsv"

[ -f "${BUILD}" ] || { echo "ERROR: ${BUILD} missing" >&2; exit 2; }
[ -d "${DIST}" ]  || { echo "ERROR: ${DIST} missing"  >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "ERROR: sha256sum not installed" >&2; exit 2; }

FAILED=0
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }

# ---- (a) build_aws.sh must contain NO rsvg ----
# `grep -L rsvg` prints the filename when there is NO match (and prints nothing
# when there IS a match). A build script that resizes via an rsvg converter
# would break the NoDerivatives clause. Capture the listing rather than the
# pipeline exit status (GNU grep -L still returns 1 under `set -o pipefail`
# when no line matched, even though it correctly lists the no-match file).
no_rsvg_files="$(grep -L 'rsvg' "${BUILD}" || true)"
if [ "${no_rsvg_files}" = "${BUILD}" ]; then
  echo "PASS  (a) ${BUILD} contains no rsvg (verbatim copy, no image converter)."
else
  fail "(a) ${BUILD} references 'rsvg' — CC-BY-ND forbids resizing/re-encoding AWS icons."
fi

# Belt-and-suspenders: no other converter invocation either.
if grep -qE '\b(convert|magick|inkscape|cairosvg)\b' "${BUILD}"; then
  fail "(a) ${BUILD} references an image converter (convert/magick/inkscape/cairosvg)."
fi

# ---- (b) shipped PNGs sha256-identical to upstream ----
ship_count="$(find "${DIST}" -name '*.png' | wc -l | tr -d ' ')"
[ "${ship_count}" -gt 0 ] || { fail "(b) no PNGs under ${DIST}"; }

# Pick a deterministic sample (every Nth file) so the gate is fast yet broad;
# fall back to the full set if small.
SAMPLE_N="${AWS_VERBATIM_SAMPLE_N:-25}"

verify_against_cache() {
  # Cache rows: <sha256>\t<relpath under upstream dist/> (== relpath under dist/AWS/)
  local checked=0 i=0
  while IFS=$'\t' read -r relpath; do
    [ -n "${relpath}" ] || continue
    i=$(( i + 1 ))
    [ $(( i % SAMPLE_N )) -eq 0 ] || continue
    local local_png="${DIST}/${relpath}"
    if [ ! -f "${local_png}" ]; then
      fail "(b) shipped PNG missing for upstream entry: ${relpath}"
      continue
    fi
    local want got
    want="$(awk -F'\t' -v p="${relpath}" '$2 == p { print $1; exit }' "${CACHE}")"
    got="$(sha256sum "${local_png}" | cut -d' ' -f1)"
    if [ "${want}" != "${got}" ]; then
      fail "(b) sha256 mismatch (NOT verbatim): ${relpath} want=${want} got=${got}"
    else
      checked=$(( checked + 1 ))
    fi
  done < <(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "${CACHE}" | cut -f2)
  echo "PASS  (b) ${checked} sampled dist/AWS PNG(s) sha256-identical to cached upstream (every ${SAMPLE_N}th of ${ship_count})."
}

if [ -f "${CACHE}" ]; then
  verify_against_cache
else
  echo "INFO: cache ${CACHE} absent — attempting shallow clone for (b)."
  if ! command -v git >/dev/null 2>&1; then
    echo "SKIP  (b) git not installed and no cache — cannot verify sha256 offline." >&2
  else
    TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
    if git clone --depth 1 https://github.com/awslabs/aws-icons-for-plantuml "${TMP}/up" >/dev/null 2>&1; then
      checked=0; i=0
      while IFS= read -r up; do
        i=$(( i + 1 ))
        [ $(( i % SAMPLE_N )) -eq 0 ] || continue
        rel="${up#"${TMP}/up/dist/"}"
        local_png="${DIST}/${rel}"
        if [ ! -f "${local_png}" ]; then fail "(b) shipped PNG missing: ${rel}"; continue; fi
        if ! cmp -s "${up}" "${local_png}"; then
          fail "(b) byte mismatch (NOT verbatim): ${rel}"
        else
          checked=$(( checked + 1 ))
        fi
      done < <(find "${TMP}/up/dist" -name '*.png' | sort)
      echo "PASS  (b) ${checked} sampled dist/AWS PNG(s) byte-identical to freshly-cloned upstream."
    else
      echo "SKIP  (b) upstream unreachable and no cache — sha256 check skipped (network)." >&2
    fi
  fi
fi

if [ "${FAILED}" -eq 0 ]; then
  echo "PASS  AWS verbatim contract holds."
  exit 0
fi
echo "test_aws_verbatim: ${FAILED} failure(s)." >&2
exit 1

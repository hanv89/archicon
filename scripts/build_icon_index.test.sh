#!/usr/bin/env bash
# Unit tests for scripts/build_icon_index.sh helpers + small end-to-end
# fixtures. Zero-dep — pure bash + diff/grep.
# Exit codes:
#   0 — all cases pass.
#   1 — at least one case failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

PASSED=0
FAILED=0
fail() { FAILED=$(( FAILED + 1 )); echo "FAIL: $*" >&2; }
pass() { PASSED=$(( PASSED + 1 )); echo "PASS: $*"; }

# Source the helpers we need to test in isolation. The script's top-level
# dispatch only runs when invoked as a program, not when functions are
# exercised individually — but it does run set -euo pipefail and source
# _lib_icon_build.sh, both of which are safe.
#
# To avoid running the dispatch in `case` at sourcing time, we pass `-h`
# via $1 by sourcing inside a subshell with positional args set… no,
# simpler: source the script with mode `--help`, which exits 0 and leaves
# the functions defined when sourced via `.` only if we wrap. Actually
# `.` reuses the current shell so `exit 0` in the script would exit the
# test runner. Use `bash -c` indirection via test-fixture invocation
# (call the script as a binary against fixture dirs), and unit-test the
# pure functions by extracting them: re-source helper definitions through
# a tmpfile that strips the dispatch.

# Strip the dispatch tail and source what remains, so the functions are
# defined in this shell without running anything.
TMP_LIB="$(mktemp)"
trap 'rm -f "${TMP_LIB}"' EXIT
awk '
  /^mode="\$\{1:-all\}"/ { exit }
  { print }
' "${SCRIPT_DIR}/build_icon_index.sh" > "${TMP_LIB}"
# shellcheck disable=SC1090
. "${TMP_LIB}"

# ---- azure_humanize: simple PascalCase ----
got="$(azure_humanize 'AzureVirtualMachine')"
[ "${got}" = "Azure Virtual Machine" ] \
  && pass "azure_humanize splits AzureVirtualMachine" \
  || fail "azure_humanize: expected 'Azure Virtual Machine', got '${got}'"

# ---- azure_humanize: acronym (SQL) ----
got="$(azure_humanize 'AzureSQLServer')"
[ "${got}" = "Azure SQL Server" ] \
  && pass "azure_humanize handles SQL acronym" \
  || fail "azure_humanize: expected 'Azure SQL Server', got '${got}'"

# ---- azure_humanize: acronym (DDoS-like nested case AKS) ----
got="$(azure_humanize 'AzureAKSCluster')"
[ "${got}" = "Azure AKS Cluster" ] \
  && pass "azure_humanize handles AKS acronym" \
  || fail "azure_humanize: expected 'Azure AKS Cluster', got '${got}'"

# ---- azure_humanize: multi-token re-join from TSV (Cosmos Db -> Cosmos DB) ----
got="$(azure_humanize 'AzureCosmosDb')"
[ "${got}" = "Azure Cosmos DB" ] \
  && pass "azure_humanize re-joins Db->DB via the acronym TSV" \
  || fail "azure_humanize: expected 'Azure Cosmos DB', got '${got}'"

# ---- apply_acronyms: data-driven from an arbitrary TSV (supports AWS/GCP) ----
acr_tmp="$(mktemp)"
printf 'Ec2\tEC2\nDynamo DB\tDynamoDB\n' > "${acr_tmp}"
got="$(printf 'AWS Ec2 Dynamo DB\n' | apply_acronyms "${acr_tmp}")"
rm -f "${acr_tmp}"
[ "${got}" = "AWS EC2 DynamoDB" ] \
  && pass "apply_acronyms applies an arbitrary (AWS) TSV in order" \
  || fail "apply_acronyms: expected 'AWS EC2 DynamoDB', got '${got}'"

# ---- fabric_humanize: snake_case ----
got="$(fabric_humanize 'power_bi')"
[ "${got}" = "Power Bi" ] \
  && pass "fabric_humanize splits power_bi (TSV override fixes 'Bi'→'BI')" \
  || fail "fabric_humanize: expected 'Power Bi', got '${got}'"

# ---- fabric_humanize: multi-underscore ----
got="$(fabric_humanize 'real_time_intelligence')"
[ "${got}" = "Real Time Intelligence" ] \
  && pass "fabric_humanize handles multi-underscore" \
  || fail "fabric_humanize: expected 'Real Time Intelligence', got '${got}'"

# ---- lookup: stem key hits (4-column TSV: key\tname\tdescription\ttags) ----
TSV_FIXTURE="$(mktemp)"
trap 'rm -f "${TMP_LIB}" "${TSV_FIXTURE}"' EXIT
printf 'AzureKubernetesService\tAKS Cluster\tDesc AKS\t`compute`, `aks`\n' > "${TSV_FIXTURE}"
printf 'cat:Compute\t-\t-\t`compute`, `vm`\n' >> "${TSV_FIXTURE}"
got="$(lookup "${TSV_FIXTURE}" "AzureKubernetesService")"
[ "${got}" = "$(printf 'AKS Cluster\tDesc AKS\t`compute`, `aks`')" ] \
  && pass "lookup returns name+description+tags for stem key" \
  || fail "lookup stem: got '${got}'"

# ---- lookup: cat:<Category> key hits ----
got="$(lookup "${TSV_FIXTURE}" "cat:Compute")"
[ "${got}" = "$(printf -- '-\t-\t`compute`, `vm`')" ] \
  && pass "lookup returns row for cat:<Category> key" \
  || fail "lookup cat: got '${got}'"

# ---- lookup: missing key returns empty ----
got="$(lookup "${TSV_FIXTURE}" "DoesNotExist")"
[ -z "${got}" ] \
  && pass "lookup returns empty for missing key" \
  || fail "lookup missing: expected empty, got '${got}'"

# ---- lookup: missing TSV returns empty ----
got="$(lookup "/nonexistent/path.tsv" "any")"
[ -z "${got}" ] \
  && pass "lookup returns empty when TSV missing" \
  || fail "lookup missing-tsv: expected empty, got '${got}'"

# ---- end-to-end Azure: tiny fixture dist/ ----
FIX_ROOT="$(mktemp -d)"
trap 'rm -f "${TMP_LIB}" "${TSV_FIXTURE}"; rm -rf "${FIX_ROOT}"' EXIT
mkdir -p "${FIX_ROOT}/dist/Azure/Compute" "${FIX_ROOT}/scripts/fixtures"
touch "${FIX_ROOT}/dist/Azure/Compute/AzureVirtualMachine.png"
touch "${FIX_ROOT}/dist/Azure/Compute/AzureVirtualMachine(m).png"
touch "${FIX_ROOT}/dist/Azure/Compute/AzureFunkyService.png"   # no TSV entry → heuristic
# Minimal TSV: per-stem for the VM, category fallback for Compute.
cat > "${FIX_ROOT}/scripts/fixtures/icon-index-tags-azure.tsv" <<'EOF'
AzureVirtualMachine	-	Microsoft Azure Virtual Machine — managed VM	`compute`, `vm`, `iaas`
cat:Compute	-	-	`compute`, `vm`, `iaas`
EOF
# Copy lib + script into the fixture so the script's relative paths work.
cp "${SCRIPT_DIR}/_lib_icon_build.sh" "${FIX_ROOT}/scripts/"
cp "${SCRIPT_DIR}/build_icon_index.sh" "${FIX_ROOT}/scripts/"
( cd "${FIX_ROOT}" && bash scripts/build_icon_index.sh azure >/dev/null )
out="${FIX_ROOT}/dist/Azure/INDEX.md"
test -f "${out}" \
  && pass "end-to-end Azure: INDEX.md produced" \
  || fail "end-to-end Azure: INDEX.md missing"

# Row count: 3 PNGs → 3 data rows.
rows=$(grep -cE '^\| `dist/Azure/' "${out}")
[ "${rows}" -eq 3 ] \
  && pass "end-to-end Azure: 3 data rows for 3 PNG fixtures" \
  || fail "end-to-end Azure: expected 3 rows, got ${rows}"

# Colored variant present, monochrome variant present, both as separate rows.
grep -qE '^\| `dist/Azure/Compute/AzureVirtualMachine\.png` \|.*\| colored \|' "${out}" \
  && pass "end-to-end Azure: colored row present" \
  || fail "end-to-end Azure: colored row not as expected"
grep -qE '^\| `dist/Azure/Compute/AzureVirtualMachine\(m\)\.png` \|.*\| monochrome \|' "${out}" \
  && pass "end-to-end Azure: monochrome row present" \
  || fail "end-to-end Azure: monochrome row not as expected"

# AzureFunkyService → no per-stem TSV; falls back to heuristic + cat tags.
grep -qE '^\| `dist/Azure/Compute/AzureFunkyService\.png` \| Azure Funky Service \| Compute \| colored \| Microsoft Azure Funky Service \| `compute`, `vm`, `iaas` \|$' "${out}" \
  && pass "end-to-end Azure: heuristic + cat-fallback row correct" \
  || fail "end-to-end Azure: heuristic row not as expected (check '${out}')"

# ---- end-to-end Fabric: tiny fixture ----
mkdir -p "${FIX_ROOT}/dist/Fabric/png"
touch "${FIX_ROOT}/dist/Fabric/png/lakehouse_40_item.png"
touch "${FIX_ROOT}/dist/Fabric/png/power_bi_48_color.png"
touch "${FIX_ROOT}/dist/Fabric/png/add_pipeline_32_non-item.png"
touch "${FIX_ROOT}/dist/Fabric/png/graph_model_40.png"          # plain — no suffix
cat > "${FIX_ROOT}/scripts/fixtures/icon-index-tags-fabric.tsv" <<'EOF'
lakehouse	-	Microsoft Fabric Lakehouse	`fabric`, `lakehouse`
suffix:item	-	-	`fabric`, `item`
suffix:color	-	-	`fabric`, `color`
suffix:non-item	-	-	`fabric`, `non-item`
suffix:plain	-	-	`fabric`, `plain`
EOF
( cd "${FIX_ROOT}" && bash scripts/build_icon_index.sh fabric >/dev/null )
out_f="${FIX_ROOT}/dist/Fabric/INDEX.md"
test -f "${out_f}" \
  && pass "end-to-end Fabric: INDEX.md produced" \
  || fail "end-to-end Fabric: INDEX.md missing"

rows_f=$(grep -cE '^\| `dist/Fabric/png/' "${out_f}")
[ "${rows_f}" -eq 4 ] \
  && pass "end-to-end Fabric: 4 data rows for 4 PNG fixtures (incl. plain)" \
  || fail "end-to-end Fabric: expected 4 rows, got ${rows_f}"

# Plain (no suffix) row reads suffix=plain.
grep -qE '^\| `dist/Fabric/png/graph_model_40\.png` \| Graph Model \| 40 \| plain \|' "${out_f}" \
  && pass "end-to-end Fabric: plain-suffix row parsed" \
  || fail "end-to-end Fabric: plain-suffix row missing/malformed"

# Per-stem lakehouse uses the TSV description.
grep -qE '^\| `dist/Fabric/png/lakehouse_40_item\.png` \| Lakehouse \| 40 \| item \| Microsoft Fabric Lakehouse \| `fabric`, `lakehouse` \|$' "${out_f}" \
  && pass "end-to-end Fabric: per-stem TSV row correct" \
  || fail "end-to-end Fabric: per-stem row not as expected"

# ---- end-to-end Kubernetes: tiny fixture ----
mkdir -p "${FIX_ROOT}/dist/Kubernetes/png/resources/labeled" \
         "${FIX_ROOT}/dist/Kubernetes/png/resources/unlabeled" \
         "${FIX_ROOT}/dist/Kubernetes/png/control_plane_components/labeled" \
         "${FIX_ROOT}/dist/Kubernetes/png/infrastructure_components/labeled"
touch "${FIX_ROOT}/dist/Kubernetes/png/resources/labeled/pod-128.png"
touch "${FIX_ROOT}/dist/Kubernetes/png/resources/labeled/pod-256.png"
touch "${FIX_ROOT}/dist/Kubernetes/png/resources/unlabeled/pod-128.png"
touch "${FIX_ROOT}/dist/Kubernetes/png/control_plane_components/labeled/c-c-m-128.png"
touch "${FIX_ROOT}/dist/Kubernetes/png/infrastructure_components/labeled/funky-128.png"
cat > "${FIX_ROOT}/scripts/fixtures/icon-index-tags-kubernetes.tsv" <<'EOF'
pod	Pod	Smallest deployable unit	`workload`, `compute`
c-c-m	Cloud Controller Manager	Cloud-provider integration controller	`control-plane`, `cloud`
EOF
( cd "${FIX_ROOT}" && bash scripts/build_icon_index.sh kubernetes >/dev/null )
out_k="${FIX_ROOT}/dist/Kubernetes/INDEX.md"
test -f "${out_k}" \
  && pass "end-to-end Kubernetes: INDEX.md produced" \
  || fail "end-to-end Kubernetes: INDEX.md missing"

rows_k=$(grep -cE '^\| `dist/Kubernetes/png/' "${out_k}")
[ "${rows_k}" -eq 5 ] \
  && pass "end-to-end Kubernetes: 5 data rows for 5 PNG fixtures" \
  || fail "end-to-end Kubernetes: expected 5 rows, got ${rows_k}"

grep -qE '^\| `dist/Kubernetes/png/resources/labeled/pod-128\.png` \| Pod \| labeled \| 128 \|' "${out_k}" \
  && pass "end-to-end Kubernetes: labeled variant + per-stem TSV name" \
  || fail "end-to-end Kubernetes: labeled-variant row missing/malformed"

grep -qE '^\| `dist/Kubernetes/png/resources/unlabeled/pod-128\.png` \| Pod \| unlabeled \| 128 \|' "${out_k}" \
  && pass "end-to-end Kubernetes: unlabeled variant parsed" \
  || fail "end-to-end Kubernetes: unlabeled-variant row missing"

grep -qE '^\| `dist/Kubernetes/png/control_plane_components/labeled/c-c-m-128\.png` \| Cloud Controller Manager \| control-plane-labeled \| 128 \|' "${out_k}" \
  && pass "end-to-end Kubernetes: dashed stem (c-c-m) + control-plane variant" \
  || fail "end-to-end Kubernetes: dashed-stem row missing/malformed"

grep -qE '^\| `dist/Kubernetes/png/infrastructure_components/labeled/funky-128\.png` \| Funky \| infra-labeled \| 128 \| Kubernetes Funky \| `kubernetes`, `infra-labeled` \|$' "${out_k}" \
  && pass "end-to-end Kubernetes: heuristic fallback for unknown stem" \
  || fail "end-to-end Kubernetes: heuristic-fallback row not as expected"

# ---- end-to-end FluentUI: tiny fixture ----
mkdir -p "${FIX_ROOT}/dist/FluentUI/png"
touch "${FIX_ROOT}/dist/FluentUI/png/cloud_24_color.png"
touch "${FIX_ROOT}/dist/FluentUI/png/cloud_32_color.png"
touch "${FIX_ROOT}/dist/FluentUI/png/cloud_48_color.png"
touch "${FIX_ROOT}/dist/FluentUI/png/lock_shield_48_color.png"     # multi-word stem
touch "${FIX_ROOT}/dist/FluentUI/png/funky_widget_32_color.png"    # unknown stem → heuristic
cat > "${FIX_ROOT}/scripts/fixtures/icon-index-tags-fluentui.tsv" <<'EOF'
cloud	Cloud	Generic cloud affordance	`cloud`, `generic`
lock_shield	Lock Shield	Locked + protected	`security`, `lock`
EOF
( cd "${FIX_ROOT}" && bash scripts/build_icon_index.sh fluentui >/dev/null )
out_fu="${FIX_ROOT}/dist/FluentUI/INDEX.md"
test -f "${out_fu}" \
  && pass "end-to-end FluentUI: INDEX.md produced" \
  || fail "end-to-end FluentUI: INDEX.md missing"

rows_fu=$(grep -cE '^\| `dist/FluentUI/png/' "${out_fu}")
[ "${rows_fu}" -eq 5 ] \
  && pass "end-to-end FluentUI: 5 data rows for 5 PNG fixtures" \
  || fail "end-to-end FluentUI: expected 5 rows, got ${rows_fu}"

# Multi-size: cloud yields 3 rows at sizes 24, 32, 48.
n_cloud=$(grep -cE '^\| `dist/FluentUI/png/cloud_[0-9]+_color\.png` \| Cloud \|' "${out_fu}")
[ "${n_cloud}" -eq 3 ] \
  && pass "end-to-end FluentUI: per-stem cloud produces 3 size rows" \
  || fail "end-to-end FluentUI: expected 3 cloud rows, got ${n_cloud}"

# Multi-word stem parsed correctly (lock_shield).
grep -qE '^\| `dist/FluentUI/png/lock_shield_48_color\.png` \| Lock Shield \| 48 \| Locked \+ protected \| `security`, `lock` \|$' "${out_fu}" \
  && pass "end-to-end FluentUI: multi-word stem (lock_shield) parsed + per-stem TSV name" \
  || fail "end-to-end FluentUI: lock_shield row not as expected"

# Heuristic fallback for unknown stem: funky_widget → "Funky Widget".
grep -qE '^\| `dist/FluentUI/png/funky_widget_32_color\.png` \| Funky Widget \| 32 \| FluentUI Funky Widget \| `fluentui` \|$' "${out_fu}" \
  && pass "end-to-end FluentUI: heuristic fallback for unknown stem" \
  || fail "end-to-end FluentUI: heuristic-fallback row not as expected"

# ---- end-to-end Devicon: tiny fixture ----
mkdir -p "${FIX_ROOT}/dist/Devicon/png"
touch "${FIX_ROOT}/dist/Devicon/png/python-original_48.png"
touch "${FIX_ROOT}/dist/Devicon/png/docker-original_48.png"
touch "${FIX_ROOT}/dist/Devicon/png/dot-net-original_48.png"          # hyphenated stem
touch "${FIX_ROOT}/dist/Devicon/png/funky-tool-original_48.png"        # unknown stem → heuristic
touch "${FIX_ROOT}/dist/Devicon/png/redis-original_48.png"
cat > "${FIX_ROOT}/scripts/fixtures/icon-index-tags-devicon.tsv" <<'EOF'
key	name	category	description	tags
python	Python	language	Python programming language	`devicon`, `language`, `python`
docker	Docker	container	Docker container engine	`devicon`, `container`, `docker`
dot-net	.NET	web-framework	.NET (classic) framework	`devicon`, `web`, `backend`, `dotnet`
redis	Redis	database	Redis in-memory data store	`devicon`, `database`, `cache`, `redis`
EOF
( cd "${FIX_ROOT}" && bash scripts/build_icon_index.sh devicon >/dev/null )
out_d="${FIX_ROOT}/dist/Devicon/INDEX.md"
test -f "${out_d}" \
  && pass "end-to-end Devicon: INDEX.md produced" \
  || fail "end-to-end Devicon: INDEX.md missing"

rows_d=$(grep -cE '^\| `dist/Devicon/png/' "${out_d}")
[ "${rows_d}" -eq 5 ] \
  && pass "end-to-end Devicon: 5 data rows for 5 PNG fixtures" \
  || fail "end-to-end Devicon: expected 5 rows, got ${rows_d}"

# Per-stem TSV name for python.
grep -qE '^\| `dist/Devicon/png/python-original_48\.png` \| Python \| language \| Python programming language \| `devicon`, `language`, `python` \|$' "${out_d}" \
  && pass "end-to-end Devicon: per-stem TSV name + category (python)" \
  || fail "end-to-end Devicon: python row not as expected"

# Hyphenated stem parsed correctly (dot-net).
grep -qE '^\| `dist/Devicon/png/dot-net-original_48\.png` \| \.NET \| web-framework \| ' "${out_d}" \
  && pass "end-to-end Devicon: hyphenated stem (dot-net) parsed + TSV name" \
  || fail "end-to-end Devicon: dot-net row not as expected"

# Heuristic fallback for unknown stem: funky-tool → "Funky-tool" + uncategorized.
grep -qE '^\| `dist/Devicon/png/funky-tool-original_48\.png` \| Funky-tool \| uncategorized \| Devicon Funky-tool \| `devicon`, `uncategorized` \|$' "${out_d}" \
  && pass "end-to-end Devicon: heuristic fallback for unknown stem" \
  || fail "end-to-end Devicon: heuristic-fallback row not as expected"

# ---- summary ----
echo "---"
echo "Total: PASS=${PASSED} FAIL=${FAILED}"
[ "${FAILED}" -eq 0 ] && exit 0 || exit 1

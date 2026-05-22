# shellcheck shell=bash
# Shared library for icon build scripts. Source this file from build_*.sh
# and (later) from .github/workflows/update-icons.yml to consolidate the
# hardenings + safety gates introduced in the script-hardening sweep.
#
# Hardenings consolidated here:
#   - Locale pinning (LC_ALL=C) for deterministic sort + find order.
#   - Relative-drop threshold gate: refuse a build that would shrink the
#     icon count by more than N% unless an --allow-removals flag is set.
#   - Upstream-record persistence (single-line key=value file under dist/<vendor>/).
#   - Scoped find -delete that never matches the repo root by accident.
#
# Sourcing pattern (from build_azure.sh / build_fabric.sh):
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "${SCRIPT_DIR}/_lib_icon_build.sh"
#   set_locale_deterministic
#
# The lib does not call any of its exported functions at source time;
# the caller decides when each gate runs.

# Exit codes used across callers:
#   0 — success
#   1 — assertion/logic failure (build refused, drop threshold tripped, etc.)
#   2 — environment problem (missing tool, network failure, etc.)

# ----------------------------------------------------------------------
# set_locale_deterministic
#   No args. Exports LC_ALL=C so subsequent `sort` / `find` calls produce
#   byte-identical output across machines.
set_locale_deterministic() {
  export LC_ALL=C
}

# ----------------------------------------------------------------------
# assert_relative_drop_safe <old_count> <new_count> <threshold_pct> <allow_removals>
#   Refuses (exit 1) if (old - new) > old * threshold_pct / 100 and
#   <allow_removals> is not "1". Threshold default 10 if 3rd arg empty.
#   <allow_removals> default 0 if 4th arg empty.
#
#   Caller wires --allow-removals CLI flag / ALLOW_REMOVALS env var into
#   the 4th arg.
assert_relative_drop_safe() {
  local old_count="${1:?old_count required}"
  local new_count="${2:?new_count required}"
  local threshold_pct="${3:-10}"
  local allow_removals="${4:-0}"

  if [ "${old_count}" -le 0 ]; then
    # First build — nothing to compare against, accept.
    return 0
  fi
  local drop=$(( old_count - new_count ))
  local threshold=$(( old_count * threshold_pct / 100 ))
  if [ "${drop}" -gt "${threshold}" ] && [ "${allow_removals}" != "1" ]; then
    echo "ERROR: icon count would drop > ${threshold_pct}% (old=${old_count} new=${new_count}, drop=${drop})." >&2
    echo "Pass --allow-removals or set ALLOW_REMOVALS=1 to override." >&2
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# write_upstream_record <path> <line>
#   Writes <line> to <path>, overwriting. Intended for files like
#   dist/Azure/UPSTREAM-SHA.txt or dist/Fabric/UPSTREAM-VERSION.txt that
#   record what the build was sourced from.
write_upstream_record() {
  local path="${1:?path required}"
  local line="${2:?line required}"
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "${line}" > "${path}"
}

# ----------------------------------------------------------------------
# scoped_find_delete <root_dir> <name_pattern>
#   Runs `find "<root_dir>" -name "<name_pattern>" -delete` with two
#   safety guards:
#     - <root_dir> must be non-empty.
#     - <root_dir> must NOT equal "/".
#   Caller is responsible for confirming <root_dir> is inside the repo;
#   the lib only blocks the most catastrophic invocations.
scoped_find_delete() {
  local root_dir="${1:?root_dir required}"
  local name_pattern="${2:?name_pattern required}"
  if [ -z "${root_dir}" ] || [ "${root_dir}" = "/" ]; then
    echo "ERROR: scoped_find_delete refuses root_dir='${root_dir}'" >&2
    return 2
  fi
  if [ ! -d "${root_dir}" ]; then
    # Nothing to clean — silent success.
    return 0
  fi
  find "${root_dir}" -name "${name_pattern}" -delete
}

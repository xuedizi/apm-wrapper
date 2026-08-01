#!/usr/bin/env bash
# Apply every active downstream patch to the pinned upstream tag and run the
# regressions that must pass before any native release build starts.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
PATCH_DIR="$ROOT_DIR/patches"

command -v git >/dev/null || { echo "test-patched-apm.sh: git required" >&2; exit 1; }
command -v uv >/dev/null || { echo "test-patched-apm.sh: uv required" >&2; exit 1; }

APM_VERSION=$(cat "$PATCH_DIR/APM_VERSION")
[ -n "$APM_VERSION" ] || {
	echo "test-patched-apm.sh: $PATCH_DIR/APM_VERSION is empty" >&2
	exit 1
}

shopt -s nullglob
patch_candidates=("$PATCH_DIR"/*.patch)
active_patch_names=()
for patch_file in "${patch_candidates[@]}"; do
	[ -f "$patch_file" ] && [ ! -L "$patch_file" ] || {
		echo "test-patched-apm.sh: active patch must be a real regular file: $patch_file" >&2
		exit 1
	}
	active_patch_names+=("$(basename "$patch_file")")
done
if [ "${#active_patch_names[@]}" -gt 0 ]; then
	sorted_patch_names=()
	while IFS= read -r patch_name; do
		sorted_patch_names+=("$patch_name")
	done < <(printf '%s\n' "${active_patch_names[@]}" | LC_ALL=C sort)
	active_patch_names=("${sorted_patch_names[@]}")
fi

expected_patch_names=(
	"gitlab-policy-discovery.patch"
	"ide.patch"
	"literal-ref-refresh.patch"
)
actual_patch_names=$(printf '%s\n' "${active_patch_names[@]}")
expected_patch_names_text=$(printf '%s\n' "${expected_patch_names[@]}")
[ "$actual_patch_names" = "$expected_patch_names_text" ] || {
	echo "test-patched-apm.sh: expected exactly active gitlab-policy-discovery.patch, ide.patch, and literal-ref-refresh.patch; got: $actual_patch_names" >&2
	exit 1
}

active_patch_files=()
for patch_name in "${active_patch_names[@]}"; do
	active_patch_files+=("$PATCH_DIR/$patch_name")
done

WORK=$(mktemp -d -t apm-patch-tests.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
APM_GIT_URL="${TAC_APM_GIT_URL:-https://github.com/microsoft/apm.git}"

git -c http.version=HTTP/1.1 clone --depth 1 --branch "$APM_VERSION" \
	--single-branch "$APM_GIT_URL" "$WORK/src" >/dev/null

for patch_file in "${active_patch_files[@]}"; do
	echo ">> applying $(basename "$patch_file")"
	(cd "$WORK/src" && git apply "$patch_file")
done

(
	cd "$WORK/src"
	uv run --frozen --extra dev pytest -q \
		tests/unit/test_github_host.py \
		tests/unit/policy/test_cache_merged_effective.py \
		tests/unit/policy/test_discovery.py \
		tests/unit/policy/test_discovery_policy_resolution.py \
		tests/unit/policy/test_gitlab_discovery.py \
		tests/unit/core/test_scope.py \
		tests/unit/core/test_target_catalog.py \
		tests/unit/core/test_target_resolution_v2.py \
		tests/unit/install/phases/test_targets_phase.py \
		tests/unit/integration/test_base_integrator.py \
		tests/unit/integration/test_data_driven_dispatch.py \
		tests/unit/integration/test_targets.py \
		tests/unit/test_install_update_refs.py \
		tests/unit/install/phases/test_resolve_phase_spec_drift.py \
		tests/integration/test_literal_ref_refresh_convergence.py
)

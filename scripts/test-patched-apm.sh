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

WORK=$(mktemp -d -t apm-patch-tests.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
APM_GIT_URL="${TAC_APM_GIT_URL:-https://github.com/microsoft/apm.git}"

git -c http.version=HTTP/1.1 clone --depth 1 --branch "$APM_VERSION" \
	--single-branch "$APM_GIT_URL" "$WORK/src" >/dev/null

shopt -s nullglob
for patch_file in "$PATCH_DIR"/*.patch; do
	echo ">> applying $(basename "$patch_file")"
	(cd "$WORK/src" && git apply "$patch_file")
done

(
	cd "$WORK/src"
	uv run --frozen --extra dev pytest -q \
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

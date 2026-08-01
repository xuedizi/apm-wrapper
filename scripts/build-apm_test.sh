#!/usr/bin/env bash
# Tests for apm-wrapper's patched APM executable build script.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
cd "$ROOT_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[ -x scripts/build-apm.sh ] || fail "scripts/build-apm.sh must exist and be executable"
pass "build-apm.sh is executable"

[ -x scripts/test-patched-apm.sh ] \
	|| fail "scripts/test-patched-apm.sh must be an executable release gate"

[ -f patches/APM_VERSION ] || fail "patches/APM_VERSION must pin upstream microsoft/apm"
[ -f patches/ide.patch ] || fail "patches/ide.patch must carry TAC IDE target support"
[ -f patches/literal-ref-refresh.patch ] \
	|| fail "patches/literal-ref-refresh.patch must carry single-command literal ref refresh"
[ -f disabled-patches/README.md ] \
	|| fail "disabled-patches/README.md must document inactive patch policy"
[ -f disabled-patches/marketplace-provenance.patch ] \
	|| fail "disabled-patches must retain the Marketplace provenance backup"
[ ! -f patches/marketplace-provenance.patch ] \
	|| fail "Marketplace provenance patch must not be active"
[ "$(cat patches/APM_VERSION)" = "v0.26.0" ] \
	|| fail "patches/APM_VERSION must pin upstream v0.26.0"
[ ! -f patches/codebuddy.patch ] || fail "patches/codebuddy.patch should be renamed to patches/ide.patch"
patch_names=$(find patches -maxdepth 1 -type f -name '*.patch' -exec basename {} \; | sort)
[ "$patch_names" = "$(printf '%s\n' ide.patch literal-ref-refresh.patch)" ] \
	|| fail "expected exactly active ide.patch and literal-ref-refresh.patch, got: $patch_names"
pass "active and archived patch inputs are separated"

grep -q '"codebuddy"' patches/ide.patch \
	|| fail "ide.patch should keep CodeBuddy target support"
grep -q '"tc"' patches/ide.patch \
	|| fail "ide.patch should add tc target support"
grep -q '"tc": ".claude/"' patches/ide.patch \
	|| fail "tc target should deploy to .claude/"
grep -q 'return target in ("claude", "codebuddy", "tc", "all")' patches/ide.patch \
	|| fail "tc target should share the claude compile family"
grep -q 'tests/unit/core/test_scope.py' patches/ide.patch \
	|| fail "ide.patch should update upstream's exhaustive KNOWN_TARGETS test"
grep -q 'src/apm_cli/integration/base_integrator.py' patches/ide.patch \
	|| fail "ide.patch should preserve shared .claude partition routing for TC"
grep -q 'tests/unit/core/test_target_catalog.py' patches/ide.patch \
	|| fail "ide.patch should update upstream's complete target catalog characterization"
pass "ide.patch supports CodeBuddy and tc IDE targets"

grep -q 'src/apm_cli/drift.py' patches/literal-ref-refresh.patch \
	|| fail "literal ref refresh patch should own the canonical ref-recheck gate"
grep -q 'src/apm_cli/install/phases/resolve.py' patches/literal-ref-refresh.patch \
	|| fail "literal ref refresh patch should wire resolve-time hash expectations"
if grep -q 'src/apm_cli/install/phases/lockfile.py' patches/literal-ref-refresh.patch; then
	fail "literal ref refresh patch must not modify lockfile provenance"
fi
if grep -qi 'marketplace.provenance\|marketplace_provenance' patches/literal-ref-refresh.patch; then
	fail "literal ref refresh patch must not contain Marketplace provenance behavior"
fi
grep -q 'tests/integration/test_literal_ref_refresh_convergence.py' \
	patches/literal-ref-refresh.patch \
	|| fail "literal ref refresh patch should carry its hermetic convergence regression"
pass "literal ref refresh patch carries source and regression coverage"

grep -q 'src/apm_cli/install/phases/lockfile.py' \
	disabled-patches/marketplace-provenance.patch \
	|| fail "inactive Marketplace provenance archive should retain its source fix"
grep -q 'tests/unit/install/phases/test_lockfile_marketplace_provenance.py' \
	disabled-patches/marketplace-provenance.patch \
	|| fail "inactive Marketplace provenance archive should retain its regression"
if grep -q 'disabled-patches\|test_lockfile_marketplace_provenance' \
	scripts/build-apm.sh scripts/test-patched-apm.sh; then
	fail "build and patched-upstream regression scripts must not consume inactive patches"
fi
pass "Marketplace provenance patch is archived and inactive"

workflow=.github/workflows/release.yml
grep -q '^  patch-tests:$' "$workflow" \
	|| fail "release workflow must define a patch-tests job"
grep -q 'scripts/test-patched-apm.sh' "$workflow" \
	|| fail "release workflow patch-tests job must run the patched upstream regressions"
python3 - "$workflow" <<'PY'
from pathlib import Path
import re
import sys

workflow = Path(sys.argv[1]).read_text(encoding="utf-8")
build = re.search(r"(?ms)^  build:\n(?P<body>.*?)(?=^  [a-z][a-z-]*:\n)", workflow)
if build is None or re.search(r"(?m)^    needs: patch-tests$", build.group("body")) is None:
    raise SystemExit("FAIL: six-platform build must need the patch-tests release gate")
PY
pass "release workflow blocks native builds on patched upstream regressions"

for forbidden in safe-ensure SAFE_ENSURE --if-missing --expect-name \
	REGISTRY_CREATE_EVIDENCE REGISTRY_REWRITE_EVIDENCE WINDOWS_LOCK_EVIDENCE \
	AreAccessRulesProtected; do
	if grep -q -- "$forbidden" "$workflow"; then
		fail "release workflow must not depend on downstream APM contract: $forbidden"
	fi
done
pass "release workflow uses standard upstream APM contracts"

scripts/build-apm.sh --help | grep -qi "build-apm" \
	|| fail "build-apm.sh --help should print usage"
pass "--help prints usage"

if grep -q 'tac/apm-patches\|TAC_DIR/apm-patches' scripts/build-apm.sh; then
	fail "build-apm.sh should use apm-wrapper/patches, not TAC repo paths"
fi
grep -q 'pyinstaller' scripts/build-apm.sh \
	|| fail "build-apm.sh should use PyInstaller to build a sidecar executable"
grep -q -- '--python "$APM_BUILD_PYTHON"' scripts/build-apm.sh \
	|| fail "build-apm.sh should pin uv/PyInstaller Python through APM_BUILD_PYTHON"
grep -q 'apm_cli.cli' scripts/build-apm.sh \
	|| fail "build-apm.sh should package apm_cli.cli"
grep -q -- '--copy-metadata apm-cli' scripts/build-apm.sh \
	|| fail "build-apm.sh should copy apm-cli metadata so --version works"
pass "build-apm.sh is configured for standalone executable packaging"

python3 - <<'PY'
from pathlib import Path
import re

workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


matrix_match = re.search(
    r"(?ms)^\s{8}include:\s*\n(?P<body>.*?)(?=^\s{4}steps:\s*$)", workflow
)
if matrix_match is None:
    fail("release workflow must define an explicit build matrix")

items = []
for block in re.split(r"(?m)^\s{10}- ", matrix_match.group("body")):
    block = block.strip()
    if not block:
        continue
    values = {}
    for line in block.splitlines():
        match = re.fullmatch(r"(?:- )?([a-z_]+):\s*(\S+)", line.strip())
        if match:
            values[match.group(1)] = match.group(2)
    items.append(values)

expected_matrix = [
    {
        "platform": "linux/amd64",
        "runner": "ubuntu-24.04",
        "runner_arch": "X64",
        "python_machine": "x86_64",
        "exe": "apm",
        "artifact": "apm-linux-amd64",
    },
    {
        "platform": "linux/arm64",
        "runner": "ubuntu-24.04-arm",
        "runner_arch": "ARM64",
        "python_machine": "aarch64",
        "exe": "apm",
        "artifact": "apm-linux-arm64",
    },
    {
        "platform": "darwin/amd64",
        "runner": "macos-15-intel",
        "runner_arch": "X64",
        "python_machine": "x86_64",
        "exe": "apm",
        "artifact": "apm-darwin-amd64",
    },
    {
        "platform": "darwin/arm64",
        "runner": "macos-15",
        "runner_arch": "ARM64",
        "python_machine": "arm64",
        "exe": "apm",
        "artifact": "apm-darwin-arm64",
    },
    {
        "platform": "windows/amd64",
        "runner": "windows-2025",
        "runner_arch": "X64",
        "python_machine": "AMD64",
        "exe": "apm.exe",
        "artifact": "apm-windows-amd64",
    },
    {
        "platform": "windows/arm64",
        "runner": "windows-11-arm",
        "runner_arch": "ARM64",
        "python_machine": "ARM64",
        "exe": "apm.exe",
        "artifact": "apm-windows-arm64",
    },
]
if items != expected_matrix:
    fail(f"release workflow matrix mismatch: expected={expected_matrix!r}, got={items!r}")

required_fragments = [
    "uses: actions/setup-python@v6",
    'python-version: "3.13"',
    "uses: astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b # v8.1.0",
    "for tool in bash tar mktemp git python uv; do",
    'if [ "$RUNNER_ARCH" != "${{ matrix.runner_arch }}" ]; then',
    'python_machine=$(python -c \'import platform; print(platform.machine())\')',
    'if [ "$python_machine" != "${{ matrix.python_machine }}" ]; then',
    'echo "ARCH_EVIDENCE platform=${{ matrix.platform }} runner=$RUNNER_ARCH python=$python_machine"',
    'python scripts/verify-executable-arch.py',
    'echo "BINARY_EVIDENCE platform=${{ matrix.platform }} format=$format machine=$machine"',
    'echo "SMOKE_EVIDENCE platform=${{ matrix.platform }} version=$apm_version"',
    '"$binary" install ../package --target codebuddy',
    'test -f "$smoke_root/codebuddy/.codebuddy/skills/smoke/SKILL.md"',
    '"$binary" install ../package --target tc',
    'test -f "$smoke_root/tc/.claude/skills/smoke/SKILL.md"',
    "path: dist/downloads",
    "python3 scripts/verify-release.py --archives-only --downloads dist/downloads",
    "mkdir -p dist/release",
    'cp "dist/downloads/$artifact/$artifact.tar.gz" dist/release/',
    "python3 scripts/verify-release.py \\",
    "--manifest dist/release/apm-manifest.json \\",
    'gh release create "$version" dist/release/*',
]
for fragment in required_fragments:
    if fragment not in workflow:
        fail(f"release workflow missing required wiring: {fragment}")

if "merge-multiple: true" in workflow:
    fail("download-artifact must preserve per-artifact child directories")

ordered_fragments = [
    "uses: astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b # v8.1.0",
    "for tool in bash tar mktemp git python uv; do",
    'echo "ARCH_EVIDENCE platform=${{ matrix.platform }} runner=$RUNNER_ARCH python=$python_machine"',
    "scripts/build-apm.sh --out dist/raw",
    "python scripts/verify-executable-arch.py",
    'apm_version=$("dist/raw/${{ matrix.exe }}" --version)',
    '"$binary" install ../package --target codebuddy',
    '"$binary" install ../package --target tc',
    "scripts/package-release.sh \\",
    "uses: actions/upload-artifact@v4",
]
positions = []
for fragment in ordered_fragments:
    position = workflow.find(fragment)
    if position < 0:
        fail(f"release workflow missing ordered step: {fragment}")
    positions.append(position)
if positions != sorted(positions):
    fail("release build steps must follow install/tool/arch/build/header/smoke/package/upload order")

release_fragments = [
    "path: dist/downloads",
    "python3 scripts/verify-release.py --archives-only --downloads dist/downloads",
    'cp "dist/downloads/$artifact/$artifact.tar.gz" dist/release/',
    "scripts/generate-manifest.sh \\",
    "python3 scripts/verify-release.py \\",
    'gh release create "$version" dist/release/*',
]
release_positions = [workflow.find(fragment) for fragment in release_fragments]
if any(position < 0 for position in release_positions):
    fail("release workflow must wire archive, staging, manifest, and publish gates")
if release_positions != sorted(release_positions):
    fail("release aggregation must verify, stage, manifest, verify, then publish")

print("PASS: release workflow enforces the six-platform native release contract")
PY

echo "ALL PASS"

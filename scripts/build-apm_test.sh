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

[ -f patches/APM_VERSION ] || fail "patches/APM_VERSION must pin upstream microsoft/apm"
[ -f patches/ide.patch ] || fail "patches/ide.patch must carry TAC IDE target support"
[ ! -f patches/codebuddy.patch ] || fail "patches/codebuddy.patch should be renamed to patches/ide.patch"
pass "patch inputs exist"

grep -q '"codebuddy"' patches/ide.patch \
	|| fail "ide.patch should keep CodeBuddy target support"
grep -q '"tc"' patches/ide.patch \
	|| fail "ide.patch should add tc target support"
grep -q '"tc": ".claude/"' patches/ide.patch \
	|| fail "tc target should deploy to .claude/"
grep -q 'return target in ("claude", "codebuddy", "tc", "all")' patches/ide.patch \
	|| fail "tc target should share the claude compile family"
pass "ide.patch supports CodeBuddy and tc IDE targets"

scripts/build-apm.sh --help | grep -qi "build-apm" \
	|| fail "build-apm.sh --help should print usage"
pass "--help prints usage"

if grep -q 'tac/apm-patches\|TAC_DIR/apm-patches' scripts/build-apm.sh; then
	fail "build-apm.sh should use apm-wrapper/patches, not TAC repo paths"
fi
grep -q 'pyinstaller' scripts/build-apm.sh \
	|| fail "build-apm.sh should use PyInstaller to build a sidecar executable"
grep -q 'apm_cli.cli' scripts/build-apm.sh \
	|| fail "build-apm.sh should package apm_cli.cli"
grep -q -- '--copy-metadata apm-cli' scripts/build-apm.sh \
	|| fail "build-apm.sh should copy apm-cli metadata so --version works"
pass "build-apm.sh is configured for standalone executable packaging"

echo "ALL PASS"

#!/usr/bin/env bash
# Tests for apm-wrapper release artifact packaging.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
cd "$ROOT_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[ -x scripts/package-release.sh ] || fail "scripts/package-release.sh must exist and be executable"
[ -x scripts/generate-manifest.sh ] || fail "scripts/generate-manifest.sh must exist and be executable"
pass "release helper scripts are executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/in"
printf '#!/bin/sh\n' > "$tmp/in/apm"
chmod 0755 "$tmp/in/apm"

scripts/package-release.sh \
	--version v0.13.0-tac.v0.1.0 \
	--platform linux/amd64 \
	--input "$tmp/in/apm" \
	--out "$tmp/out"

[ -f "$tmp/out/apm-linux-amd64.tar.gz" ] \
	|| fail "expected apm-linux-amd64.tar.gz"
tar -tzf "$tmp/out/apm-linux-amd64.tar.gz" | grep -qx 'apm' \
	|| fail "linux archive should contain apm at archive root"
pass "package-release creates platform archive"

scripts/generate-manifest.sh \
	--version v0.13.0-tac.v0.1.0 \
	--upstream v0.13.0 \
	--dir "$tmp/out" \
	--out "$tmp/out/apm-manifest.json"

grep -q '"version": "v0.13.0-tac.v0.1.0"' "$tmp/out/apm-manifest.json" \
	|| fail "manifest should contain wrapper version"
grep -q '"upstream_apm": "v0.13.0"' "$tmp/out/apm-manifest.json" \
	|| fail "manifest should contain upstream APM version"
grep -q '"apm-linux-amd64.tar.gz"' "$tmp/out/apm-manifest.json" \
	|| fail "manifest should contain packaged artifact"
grep -q '"sha256":' "$tmp/out/apm-manifest.json" \
	|| fail "manifest should contain sha256"
pass "generate-manifest writes artifact metadata"

echo "ALL PASS"

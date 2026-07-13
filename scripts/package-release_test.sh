#!/usr/bin/env bash
# Tests for apm-wrapper release artifact packaging and verification.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
cd "$ROOT_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

expect_failure() {
	label=$1
	expected=$2
	shift 2
	if "$@" >"$tmp/negative.stdout" 2>"$tmp/negative.stderr"; then
		fail "$label should fail"
	fi
	grep -Fq "$expected" "$tmp/negative.stderr" \
		|| fail "$label should report '$expected'; got: $(cat "$tmp/negative.stderr")"
	if grep -Fq "Traceback" "$tmp/negative.stderr"; then
		fail "$label should not print a traceback; got: $(cat "$tmp/negative.stderr")"
	fi
	pass "$label is rejected"
}

[ -x scripts/package-release.sh ] || fail "scripts/package-release.sh must exist and be executable"
[ -x scripts/generate-manifest.sh ] || fail "scripts/generate-manifest.sh must exist and be executable"
pass "release helper scripts are executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

version=v0.13.0-tac.v0.1.2
upstream=v0.13.0
downloads="$tmp/downloads"
release_dir="$tmp/release"
mkdir -p "$tmp/in" "$downloads" "$release_dir"
printf '#!/bin/sh\n' > "$tmp/in/apm"
chmod 0755 "$tmp/in/apm"

platforms=(
	linux/amd64
	linux/arm64
	darwin/amd64
	darwin/arm64
	windows/amd64
	windows/arm64
)

for platform in "${platforms[@]}"; do
	artifact_name="apm-${platform//\//-}"
	mkdir -p "$downloads/$artifact_name"
	scripts/package-release.sh \
		--version "$version" \
		--platform "$platform" \
		--input "$tmp/in/apm" \
		--out "$downloads/$artifact_name"
	cp "$downloads/$artifact_name/$artifact_name.tar.gz" "$release_dir/"
done

python3 scripts/verify-release.py --archives-only --downloads "$downloads"
pass "complete six-platform archive set passes"

cp -R "$downloads" "$tmp/missing"
rm -rf "$tmp/missing/apm-linux-arm64"
expect_failure "missing artifact directory" "top-level artifact directories" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/missing"

cp -R "$downloads" "$tmp/extra"
mkdir -p "$tmp/extra/apm-linux-riscv64"
scripts/package-release.sh \
	--version "$version" \
	--platform linux/riscv64 \
	--input "$tmp/in/apm" \
	--out "$tmp/extra/apm-linux-riscv64"
expect_failure "extra artifact directory" "top-level artifact directories" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/extra"

cp -R "$downloads" "$tmp/wrong-windows-entry"
mkdir -p "$tmp/wrong-windows-package"
scripts/package-release.sh \
	--version "$version" \
	--platform linux/amd64 \
	--input "$tmp/in/apm" \
	--out "$tmp/wrong-windows-package"
mv "$tmp/wrong-windows-package/apm-linux-amd64.tar.gz" \
	"$tmp/wrong-windows-entry/apm-windows-amd64/apm-windows-amd64.tar.gz"
expect_failure "wrong Windows archive entry" "expected only 'apm.exe'" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/wrong-windows-entry"

cp -R "$downloads" "$tmp/duplicate"
mkdir -p "$tmp/duplicate/copied-artifact"
cp "$downloads/apm-linux-amd64/apm-linux-amd64.tar.gz" \
	"$tmp/duplicate/copied-artifact/apm-linux-amd64.tar.gz"
expect_failure "duplicate archive basename" "duplicate archive basename" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/duplicate"

cp -R "$downloads" "$tmp/nested-extra"
mkdir -p "$tmp/nested-extra/apm-linux-amd64/nested"
scripts/package-release.sh \
	--version "$version" \
	--platform linux/riscv64 \
	--input "$tmp/in/apm" \
	--out "$tmp/nested-extra/apm-linux-amd64/nested"
expect_failure "unique nested archive" "unexpected archive path" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/nested-extra"

cp -R "$downloads" "$tmp/truncated-gzip"
python3 -c 'from pathlib import Path; p=Path(__import__("sys").argv[1]); data=p.read_bytes(); p.write_bytes(data[:-8])' \
	"$tmp/truncated-gzip/apm-linux-amd64/apm-linux-amd64.tar.gz"
expect_failure "archive with truncated gzip trailer" "invalid gzip stream" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/truncated-gzip"

cp -R "$downloads" "$tmp/two-byte-gzip"
python3 -c 'from pathlib import Path; Path(__import__("sys").argv[1]).write_bytes(b"\x1f\x8b")' \
	"$tmp/two-byte-gzip/apm-linux-amd64/apm-linux-amd64.tar.gz"
expect_failure "two-byte gzip header" "invalid gzip stream" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/two-byte-gzip"

cp -R "$downloads" "$tmp/invalid-deflate"
python3 -c 'from pathlib import Path; Path(__import__("sys").argv[1]).write_bytes(bytes.fromhex("1f8b0800000000000003") + b"\x06" + b"\x00" * 8)' \
	"$tmp/invalid-deflate/apm-linux-amd64/apm-linux-amd64.tar.gz"
expect_failure "invalid gzip deflate stream" "invalid gzip stream" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/invalid-deflate"

cp -R "$downloads" "$tmp/symlink-directory"
rm -rf "$tmp/symlink-directory/apm-linux-amd64"
ln -s "$downloads/apm-linux-amd64" "$tmp/symlink-directory/apm-linux-amd64"
expect_failure "symlinked artifact directory" "artifact path must be a real directory" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/symlink-directory"

cp -R "$downloads" "$tmp/symlink-archive"
rm -f "$tmp/symlink-archive/apm-linux-amd64/apm-linux-amd64.tar.gz"
ln -s "$downloads/apm-linux-amd64/apm-linux-amd64.tar.gz" \
	"$tmp/symlink-archive/apm-linux-amd64/apm-linux-amd64.tar.gz"
expect_failure "symlinked archive" "archive path must be a regular file" \
	python3 scripts/verify-release.py --archives-only --downloads "$tmp/symlink-archive"

scripts/generate-manifest.sh \
	--version "$version" \
	--upstream "$upstream" \
	--dir "$release_dir" \
	--out "$release_dir/apm-manifest.json"
manifest="$release_dir/apm-manifest.json"

python3 scripts/verify-release.py \
	--manifest "$manifest" \
	--release-dir "$release_dir" \
	--version "$version" \
	--upstream "$upstream"
pass "complete six-platform manifest passes"

cp -R "$release_dir" "$tmp/symlink-release"
rm -f "$tmp/symlink-release/apm-linux-amd64.tar.gz"
ln -s "$release_dir/apm-linux-amd64.tar.gz" \
	"$tmp/symlink-release/apm-linux-amd64.tar.gz"
expect_failure "symlinked staged artifact" "release artifact must be a regular file" \
	python3 scripts/verify-release.py --manifest "$manifest" --release-dir "$tmp/symlink-release" --version "$version" --upstream "$upstream"

cp -R "$release_dir" "$tmp/unreadable-release"
chmod 000 "$tmp/unreadable-release/apm-linux-amd64.tar.gz"
expect_failure "unreadable staged artifact" "unable to read release artifact" \
	python3 scripts/verify-release.py --manifest "$manifest" --release-dir "$tmp/unreadable-release" --version "$version" --upstream "$upstream"
chmod 0644 "$tmp/unreadable-release/apm-linux-amd64.tar.gz"

cp "$manifest" "$tmp/duplicate-key.json"
python3 -c 'from pathlib import Path; p=Path(__import__("sys").argv[1]); s=p.read_text(); p.write_text(s.replace("  \"version\":", "  \"version\": \"duplicate\",\n  \"version\":", 1))' "$tmp/duplicate-key.json"
expect_failure "duplicate JSON key" "duplicate JSON key" \
	python3 scripts/verify-release.py --manifest "$tmp/duplicate-key.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/version-mismatch.json"
python3 -c 'from pathlib import Path; p=Path(__import__("sys").argv[1]); s=p.read_text(); p.write_text(s.replace(__import__("sys").argv[2], "v0.0.0", 1))' "$tmp/version-mismatch.json" "$version"
expect_failure "version mismatch" "version mismatch" \
	python3 scripts/verify-release.py --manifest "$tmp/version-mismatch.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/upstream-mismatch.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); d["upstream_apm"]="v0.0.0"; p.write_text(json.dumps(d))' "$tmp/upstream-mismatch.json"
expect_failure "upstream mismatch" "upstream mismatch" \
	python3 scripts/verify-release.py --manifest "$tmp/upstream-mismatch.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/extra-artifact.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); d["artifacts"]["apm-linux-riscv64.tar.gz"]={"sha256":"0"*64,"size":1}; p.write_text(json.dumps(d))' "$tmp/extra-artifact.json"
expect_failure "extra manifest artifact" "artifact keys" \
	python3 scripts/verify-release.py --manifest "$tmp/extra-artifact.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/invalid-sha.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); next(iter(d["artifacts"].values()))["sha256"]="not-a-sha"; p.write_text(json.dumps(d))' "$tmp/invalid-sha.json"
expect_failure "invalid artifact SHA" "invalid sha256" \
	python3 scripts/verify-release.py --manifest "$tmp/invalid-sha.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/zero-size.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); next(iter(d["artifacts"].values()))["size"]=0; p.write_text(json.dumps(d))' "$tmp/zero-size.json"
expect_failure "zero artifact size" "invalid size" \
	python3 scripts/verify-release.py --manifest "$tmp/zero-size.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/bool-size.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); next(iter(d["artifacts"].values()))["size"]=True; p.write_text(json.dumps(d))' "$tmp/bool-size.json"
expect_failure "boolean artifact size" "invalid size" \
	python3 scripts/verify-release.py --manifest "$tmp/bool-size.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/sha-mismatch.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); next(iter(d["artifacts"].values()))["sha256"]="0"*64; p.write_text(json.dumps(d))' "$tmp/sha-mismatch.json"
expect_failure "artifact SHA mismatch" "sha256 mismatch" \
	python3 scripts/verify-release.py --manifest "$tmp/sha-mismatch.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

cp "$manifest" "$tmp/size-mismatch.json"
python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); d=json.loads(p.read_text()); item=next(iter(d["artifacts"].values())); item["size"]+=1; p.write_text(json.dumps(d))' "$tmp/size-mismatch.json"
expect_failure "artifact size mismatch" "size mismatch" \
	python3 scripts/verify-release.py --manifest "$tmp/size-mismatch.json" --release-dir "$release_dir" --version "$version" --upstream "$upstream"

echo "ALL PASS"

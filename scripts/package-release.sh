#!/usr/bin/env bash
# Package one platform-specific APM executable as apm-<os>-<arch>.tar.gz.
set -euo pipefail

usage() {
	cat <<'EOF'
package-release.sh --version <version> --platform <os/arch> --input <apm-path> --out <dir>

Creates a release archive named apm-<os>-<arch>.tar.gz. The archive contains
the executable at its root as apm or apm.exe.
EOF
}

VERSION=""
PLATFORM=""
INPUT=""
OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--version) VERSION="$2"; shift 2 ;;
		--version=*) VERSION="${1#*=}"; shift ;;
		--platform) PLATFORM="$2"; shift 2 ;;
		--platform=*) PLATFORM="${1#*=}"; shift ;;
		--input) INPUT="$2"; shift 2 ;;
		--input=*) INPUT="${1#*=}"; shift ;;
		--out) OUT="$2"; shift 2 ;;
		--out=*) OUT="${1#*=}"; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "package-release.sh: unknown arg: $1" >&2; usage >&2; exit 2 ;;
	esac
done

[ -n "$VERSION" ] || { echo "package-release.sh: --version required" >&2; exit 2; }
[ -n "$PLATFORM" ] || { echo "package-release.sh: --platform required" >&2; exit 2; }
[ -n "$INPUT" ] || { echo "package-release.sh: --input required" >&2; exit 2; }
[ -n "$OUT" ] || { echo "package-release.sh: --out required" >&2; exit 2; }
[ -f "$INPUT" ] || { echo "package-release.sh: input not found: $INPUT" >&2; exit 1; }

os=${PLATFORM%/*}
arch=${PLATFORM#*/}
if [ "$os" = "$PLATFORM" ] || [ -z "$os" ] || [ -z "$arch" ]; then
	echo "package-release.sh: --platform must look like os/arch, got: $PLATFORM" >&2
	exit 2
fi

exe_name=apm
if [ "$os" = "windows" ]; then
	exe_name=apm.exe
fi

mkdir -p "$OUT"
stage=$(mktemp -d -t apm-package.XXXXXX)
trap 'rm -rf "$stage"' EXIT
cp "$INPUT" "$stage/$exe_name"
chmod 0755 "$stage/$exe_name" 2>/dev/null || true

archive="$OUT/apm-$os-$arch.tar.gz"
tar -C "$stage" -czf "$archive" "$exe_name"
echo ">> wrote $archive"

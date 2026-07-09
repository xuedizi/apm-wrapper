#!/usr/bin/env bash
# build-apm.sh — clone upstream microsoft/apm at the pinned version,
# apply patches/*.patch, build a standalone apm executable with
# PyInstaller, copy it to --out.
#
# Default upstream: https://github.com/microsoft/apm (public).
# Override with TAC_APM_GIT_URL when building behind a network
# that can't reach github.com (e.g., a future internal CI runner
# pointed at an internal mirror).
#
# Invoked by `make release` (via release.sh) at release time. The
# produced executable ships inside every tcli-<os>-<arch>.tar.gz so end
# users get TAC IDE target support without installing uv/Python locally.
#
# Usage:
#   scripts/build-apm.sh --out <dir>       # build, copy executable to <dir>
#   scripts/build-apm.sh --rebase          # apply patches to a fresh upstream
#                                          # checkout, drop into a shell so the
#                                          # operator can resolve conflicts,
#                                          # write the rebased patch back to
#                                          # patches/ide.patch
#   scripts/build-apm.sh --help            # this text

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
PATCH_DIR="$ROOT_DIR/patches"

usage() {
    cat <<'EOF'
build-apm.sh — clone upstream microsoft/apm + apply patches + build executable.

Used by `make release` at release time. The produced executable ships
inside every tcli-<os>-<arch>.tar.gz so end users get TAC IDE target support
without client-side uv/Python installation.

Usage:
  build-apm.sh --out <dir>       build, copy executable to <dir>
  build-apm.sh --rebase          apply patches to a fresh upstream
                                 checkout, drop into a shell so the
                                 operator can resolve conflicts, write
                                 the rebased patch back to disk
  build-apm.sh --help            this text
EOF
}

OUT=""
MODE=build
while [ $# -gt 0 ]; do
	case "$1" in
		--out)     OUT="$2"; shift 2 ;;
		--out=*)   OUT="${1#*=}"; shift ;;
		--rebase)  MODE=rebase; shift ;;
		-h|--help) usage; exit 0 ;;
		*)         echo "build-apm.sh: unknown arg: $1" >&2; usage >&2; exit 2 ;;
	esac
done

command -v uv >/dev/null   || { echo "build-apm.sh: uv required on release builder (install: curl -LsSf https://astral.sh/uv/install.sh | sh)" >&2; exit 1; }
command -v git >/dev/null  || { echo "build-apm.sh: git required" >&2; exit 1; }

APM_VERSION=$(cat "$PATCH_DIR/APM_VERSION")
[ -n "$APM_VERSION" ] || { echo "build-apm.sh: $PATCH_DIR/APM_VERSION is empty" >&2; exit 1; }
echo ">> build-apm.sh: upstream pin = $APM_VERSION"

WORK=$(mktemp -d -t apm-build.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

APM_GIT_URL="${TAC_APM_GIT_URL:-https://github.com/microsoft/apm.git}"
echo ">> cloning $APM_GIT_URL @ $APM_VERSION into $WORK/src"
git clone --depth 1 --branch "$APM_VERSION" \
	"$APM_GIT_URL" "$WORK/src" >/dev/null

echo ">> applying patches from $PATCH_DIR"
shopt -s nullglob
for p in "$PATCH_DIR"/*.patch; do
	echo "   - $(basename "$p")"
	(cd "$WORK/src" && git apply "$p")
done
BUILD_SHA=$(cd "$WORK/src" && git rev-parse --short HEAD)
python3 - "$WORK/src/src/apm_cli/version.py" "$APM_VERSION" "$BUILD_SHA" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
version = sys.argv[2].removeprefix("v")
sha = sys.argv[3]
text = path.read_text()
text = text.replace("__BUILD_VERSION__ = None", f"__BUILD_VERSION__ = {version!r}")
text = text.replace("__BUILD_SHA__ = None", f"__BUILD_SHA__ = {sha!r}")
path.write_text(text)
PY

if [ "$MODE" = rebase ]; then
	[ -t 0 ] || { echo "build-apm.sh: --rebase requires an interactive terminal (stdin is not a tty)" >&2; exit 1; }
	echo ">> --rebase: spawning shell in $WORK/src. Resolve conflicts, then:"
	echo "     git add -A && git diff --cached > $PATCH_DIR/ide.patch"
	echo "     exit"
	(cd "$WORK/src" && "$SHELL")
	echo ">> rebase shell exited; patch presumed updated on disk"
	exit 0
fi

[ -n "$OUT" ] || { echo "build-apm.sh: --out required for build mode" >&2; exit 2; }
mkdir -p "$OUT"
# Resolve to absolute path before the cd into $WORK/src.
OUT=$(cd "$OUT" && pwd -P)

cat > "$WORK/apm_launcher.py" <<'PY'
import sys

from apm_cli.cli import main

if __name__ == "__main__":
    sys.exit(main())
PY

echo ">> building standalone apm executable via pyinstaller"
PYI_DIST="$WORK/pyinstaller-dist"
PYI_BUILD="$WORK/pyinstaller-build"
(cd "$WORK/src" && uv run --with pyinstaller --with "$WORK/src" \
	pyinstaller --onefile --name apm \
		--distpath "$PYI_DIST" \
		--workpath "$PYI_BUILD" \
		--specpath "$WORK" \
		--copy-metadata apm-cli \
		--hidden-import apm_cli.cli \
		"$WORK/apm_launcher.py")

exe="$PYI_DIST/apm"
if [ -f "$PYI_DIST/apm.exe" ]; then
	exe="$PYI_DIST/apm.exe"
fi
[ -f "$exe" ] || { echo "build-apm.sh: pyinstaller produced no apm executable in $PYI_DIST" >&2; exit 1; }
chmod 0755 "$exe" 2>/dev/null || true
cp "$exe" "$OUT/$(basename "$exe")"
echo ">> executable in $OUT:"
ls -la "$OUT/$(basename "$exe")"

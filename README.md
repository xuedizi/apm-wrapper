# apm-wrapper

`apm-wrapper` builds TAC's patched `microsoft/apm` sidecar executables.

The release tag format is:

```text
v<upstream-apm-version>-tac.v<wrapper-version>
```

Example:

```text
v0.24.0-tac.v0.2.0
```

This means the sidecar is built from `microsoft/apm@v0.24.0`, with TAC patches
applied, as wrapper release `v0.2.0`.

## Layout

```text
patches/APM_VERSION       upstream microsoft/apm tag
patches/*.patch           TAC downstream patches
scripts/build-apm.sh      clone, patch, and PyInstaller-build apm / apm.exe
scripts/package-release.sh
scripts/generate-manifest.sh
.github/workflows/release.yml
```

## Local Smoke

```bash
bash scripts/build-apm_test.sh
bash scripts/package-release_test.sh
python3 scripts/verify-executable-arch_test.py

scripts/build-apm.sh --out dist/raw
scripts/package-release.sh \
  --version v0.24.0-tac.v0.2.0 \
  --platform "$(go env GOOS)/$(go env GOARCH)" \
  --input dist/raw/apm \
  --out dist/release
scripts/generate-manifest.sh \
  --version v0.24.0-tac.v0.2.0 \
  --upstream "$(cat patches/APM_VERSION)" \
  --dir dist/release \
  --out dist/release/apm-manifest.json
```

GitHub Actions publishes `apm-<os>-<arch>.tar.gz` archives plus
`apm-manifest.json`. TAC release jobs download these archives instead of
building PyInstaller sidecars locally.

## Release platforms

Each release contains one native executable archive for every supported
platform:

| Platform | GitHub-hosted runner | Executable |
| --- | --- | --- |
| `linux/amd64` | `ubuntu-24.04` | `apm` |
| `linux/arm64` | `ubuntu-24.04-arm` | `apm` |
| `darwin/amd64` | `macos-15-intel` | `apm` |
| `darwin/arm64` | `macos-15` | `apm` |
| `windows/amd64` | `windows-2025` | `apm.exe` |
| `windows/arm64` | `windows-11-arm` | `apm.exe` |

The GitHub-hosted Windows ARM runner is currently in public preview.

Every build records three independent architecture evidence layers before it
can be uploaded: the GitHub runner architecture and Python
`platform.machine()` value, the executable's native ELF/Mach-O/PE header, and
a native `apm --version` smoke test. The release job keeps downloaded artifacts
in their per-platform directories, verifies the exact six-archive set, stages
only those archives, generates and verifies the checksum/size manifest, and
only then creates the GitHub Release. This makes publishing atomic: a missing,
extra, malformed, mismatched, or corrupted artifact prevents the release from
being created.

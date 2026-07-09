# apm-wrapper

`apm-wrapper` builds TAC's patched `microsoft/apm` sidecar executables.

The release tag format is:

```text
v<upstream-apm-version>-tac.v<wrapper-version>
```

Example:

```text
v0.13.0-tac.v0.1.0
```

This means the sidecar is built from `microsoft/apm@v0.13.0`, with TAC patches
applied, as wrapper release `v0.1.0`.

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

scripts/build-apm.sh --out dist/raw
scripts/package-release.sh \
  --version v0.13.0-tac.v0.1.0 \
  --platform "$(go env GOOS)/$(go env GOARCH)" \
  --input dist/raw/apm \
  --out dist/release
scripts/generate-manifest.sh \
  --version v0.13.0-tac.v0.1.0 \
  --upstream "$(cat patches/APM_VERSION)" \
  --dir dist/release \
  --out dist/release/apm-manifest.json
```

GitHub Actions publishes `apm-<os>-<arch>.tar.gz` archives plus
`apm-manifest.json`. TAC release jobs download these archives instead of
building PyInstaller sidecars locally.

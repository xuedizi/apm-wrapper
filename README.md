# apm-wrapper

`apm-wrapper` builds TAC's minimally patched `microsoft/apm` sidecar
executables.

Release tags use:

```text
v<upstream-apm-version>-tac.v<wrapper-version>
```

For example, `v0.26.0-tac.v0.3.0` is built from
`microsoft/apm@v0.26.0` as wrapper release `v0.3.0`.

## Downstream scope

The wrapper intentionally carries two active downstream patches:

- `ide.patch` adds the `codebuddy` and `tc` targets that upstream APM 0.26
  does not provide. CodeBuddy deploys Claude-compatible assets under
  `.codebuddy/`; TC shares the Claude `.claude/` layout and is explicit-only
  so it cannot collide with Claude auto-detection or `all`.
- `literal-ref-refresh.patch` makes an explicit changed literal ref materialize
  before its manifest is traversed, so one `--refresh` command converges the
  transitive graph. It separately tracks declared ref drift and semver tag
  drift, preserving content-hash rejection when an unchanged tag moves.
Marketplace registration, package installation, audit, policy discovery,
frozen repair, and lockfile provenance replay use standard APM 0.26 behavior.
TCLI owns orchestration and invokes:

```bash
apm marketplace add SOURCE --name NAME
apm install KIT... --target TARGETS
```

During `tcli init`, the marketplace entry in TCLI's packaged defaults is
authoritative. Re-running init reconciles the configured alias through
standard APM replace-by-name semantics. TCLI does not require downstream
`--if-missing`, safe-inspection, registry, or lockfile extensions.

## Layout

```text
patches/APM_VERSION       upstream microsoft/apm tag
patches/ide.patch         codebuddy / tc target support
patches/literal-ref-refresh.patch
disabled-patches/marketplace-provenance.patch  inactive source archive
scripts/build-apm.sh      clone, patch, and PyInstaller-build apm / apm.exe
scripts/test-patched-apm.sh
scripts/package-release.sh
scripts/generate-manifest.sh
.github/workflows/release.yml
```

## Local smoke

```bash
bash scripts/build-apm_test.sh
bash scripts/package-release_test.sh
python3 scripts/verify-executable-arch_test.py
scripts/test-patched-apm.sh

scripts/build-apm.sh --out dist/raw
scripts/package-release.sh \
  --version v0.26.0-tac.v0.3.0 \
  --platform "$(go env GOOS)/$(go env GOARCH)" \
  --input dist/raw/apm \
  --out dist/release
scripts/generate-manifest.sh \
  --version v0.26.0-tac.v0.3.0 \
  --upstream "$(cat patches/APM_VERSION)" \
  --dir dist/release \
  --out dist/release/apm-manifest.json
```

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

Every build records three independent architecture evidence layers before
upload: the runner and Python architecture, the executable's native
ELF/Mach-O/PE header, and a native `apm --version` smoke test. The release job
verifies the exact six-archive set, stages only those archives, generates and
verifies the checksum/size manifest, and only then creates the GitHub Release.
Before the six native builds start, the `patch-tests` job applies all patches
to a clean pinned checkout and runs the IDE catalog/partitioning, literal-ref,
hash-integrity, and hermetic graph-convergence regressions.

Remove the active literal-ref behavior patch only after a released upstream tag
contains equivalent behavior and regression coverage. Rollback must restore the
complete previously verified wrapper commit/tag, including its matching
`APM_VERSION`, IDE patch, tests, and documentation; changing only the version
pin can leave an incompatible patch set. Inactive patches remain source
archives and require a reviewed change, full verification, and a new wrapper
release before they can affect a sidecar binary.

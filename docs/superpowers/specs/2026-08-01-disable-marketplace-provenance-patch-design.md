# Disable Marketplace Provenance Patch Design

## Context

`apm-wrapper` currently applies every `patches/*.patch` file when it builds the
APM sidecar. Release `v0.26.0-tac.v0.3.2` added
`marketplace-provenance.patch`, which preserves Marketplace metadata during a
lockfile rebuild when the resolved commit is unchanged.

The behavior has not caused a reported issue in normal TAC usage, and the
preferred product boundary is to avoid changing upstream APM lockfile behavior
without demonstrated operational need. The patch should remain available as
diagnostic and recovery material, but it must not affect future sidecar builds.

## Goals

- Stop applying `marketplace-provenance.patch` in all normal and release builds.
- Keep the complete patch available in a clearly inactive location.
- Make the active/inactive boundary mechanically testable.
- Document why the patch is inactive and how it may be reconsidered later.

## Non-goals

- Do not change the contents of the backup patch.
- Do not add a runtime, environment-variable, or build-flag opt-in.
- Do not change the remaining IDE or literal-ref-refresh behavior.
- Do not rewrite or replace the immutable `v0.26.0-tac.v0.3.2` release.
- Do not claim that an existing TAC release changes until TAC pins a subsequent
  wrapper release.

## Directory and Build Boundary

The wrapper repository will use two top-level directories with distinct roles:

```text
apm-wrapper/
├── patches/                   # active; build-apm.sh applies *.patch
│   ├── ide.patch
│   └── literal-ref-refresh.patch
└── disabled-patches/          # archival only; never read by build scripts
    ├── README.md
    └── marketplace-provenance.patch
```

`scripts/build-apm.sh` and `scripts/test-patched-apm.sh` will continue to glob
only `patches/*.patch`. No code path will scan `disabled-patches/`.

Keeping the disabled patch outside `patches/` avoids relying on filename
suffixes or non-recursive glob behavior for safety.

## Test and Documentation Changes

`scripts/build-apm_test.sh` will enforce that the active patch set is exactly
`ide.patch` and `literal-ref-refresh.patch`. It will also require the backup
patch and its README to exist under `disabled-patches/`, and will reject an
active `patches/marketplace-provenance.patch`.

`scripts/test-patched-apm.sh` will stop selecting the provenance regression
test because that test is supplied by the disabled patch and will no longer be
present in the patched upstream checkout.

The repository README and active patch README will describe only the two active
patches. `disabled-patches/README.md` will record:

- the observed lockfile metadata-loss scenario;
- the decision to prefer upstream behavior until operational evidence warrants
  a downstream fix;
- that the patch is not applied to builds, its behavioral regression is not
  selected by the active patch suite, and it is not embedded in platform
  sidecar archives; it remains present in repository source archives;
- that re-enabling it is a reviewed source change, not a file-copy shortcut.

Re-enabling requires moving the patch back into `patches/`, restoring its
focused regression to the release test list, updating the exact-set assertions
and documentation, running the complete patch and packaging verification, and
publishing a new wrapper version.

## Verification and Acceptance

The change is accepted when:

1. `patches/` contains exactly the two active patches.
2. `disabled-patches/marketplace-provenance.patch` is byte-for-byte identical
   to the previously active patch.
3. Build and patched-upstream regression scripts consume active patches only;
   the static contract test may reference `disabled-patches/` solely to assert
   that the inactive archive exists and cannot be mistaken for an active patch.
4. The wrapper static build contract passes.
5. The patched-upstream regression suite passes with only the active patches.
6. Package-release and executable-architecture self-tests remain green.
7. Repository searches find no documentation claiming that future builds apply
   the disabled patch.

## Risks

Future bare, frozen, or lockfile-only APM replays may still drop Marketplace
metadata while retaining the same resolved commit. That is an accepted upstream
behavior under this design. TAC lifecycle evidence should preserve the failure
details if it becomes operationally relevant; the archived patch then provides
a starting point for a new reviewed fix or upstream contribution.

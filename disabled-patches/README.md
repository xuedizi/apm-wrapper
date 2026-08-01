# disabled patches

Files in this directory are retained for investigation and recovery only.
`scripts/build-apm.sh` and `scripts/test-patched-apm.sh` do not scan this
directory, so these patches are not applied to or embedded in sidecar binaries.
They remain available in repository source archives.

## marketplace-provenance.patch

The patch preserves Marketplace lockfile provenance when a rebuild resolves the
same non-empty commit. It is inactive because normal TAC usage has not produced
an operational report that justifies changing upstream APM lockfile behavior.
Future bare, frozen, or lockfile-only replay may therefore continue to drop the
metadata; that upstream behavior is currently accepted.

Re-enable only through a reviewed wrapper change: move the patch to `patches/`,
restore its focused regression in `scripts/test-patched-apm.sh`, update the
exact active-set assertions and documentation, run the full wrapper
verification, and publish a new wrapper version. Do not enable it through a
runtime flag or by mutating an existing release.

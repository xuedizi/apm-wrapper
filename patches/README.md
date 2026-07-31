# patches

Out-of-tree patches against upstream `microsoft/apm`, applied by
`apm-wrapper/scripts/build-apm.sh`.

- `APM_VERSION` pins the upstream tag.
- `ide.patch` adds the `codebuddy` and `tc` targets missing from upstream APM
  0.26. CodeBuddy uses `.codebuddy/`; TC uses `.claude/` and is explicit-only
  (not auto-detected and not part of `all`). Both share the Claude compile
  family, appear in target validation/help, preserve Claude's legacy
  partition buckets despite TC's shared root, and are covered by upstream
  target-profile and partitioning tests.
- `literal-ref-refresh.patch` forces a changed literal ref through the
  materialization owner before traversing its manifest, then marks only
  declared ref changes or legitimate semver tag changes as expected content
  hash changes. Its hermetic tests cover one-command parent/child convergence,
  no redundant download, rejection of an unchanged moved tag, and frozen
  Marketplace provenance preservation.

No Marketplace, policy, registry, safe-install, or attestation behavior is
patched downstream. Those capabilities remain owned by standard APM 0.26,
while TCLI coordinates initialization with standard APM commands.

Delete the refresh patch only after an upstream release carries the same source
fix and regressions. To roll back, restore the complete prior wrapper baseline
commit/tag, including its v0.24-compatible IDE patch and tests; do not change
only `APM_VERSION`.

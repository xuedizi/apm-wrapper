# patches

Out-of-tree patches against upstream `microsoft/apm`, applied by
`apm-wrapper/scripts/build-apm.sh`.

- `APM_VERSION` pins the upstream tag.
- `ide.patch` adds the `codebuddy` and `tc` targets missing from upstream APM
  0.24. CodeBuddy uses `.codebuddy/`; TC uses `.claude/` and is explicit-only
  (not auto-detected and not part of `all`). Both share the Claude compile
  family, appear in target validation/help, and are covered by upstream
  target-profile tests.

No Marketplace, policy, registry, safe-install, attestation, or lockfile
behavior is patched downstream. Those capabilities remain owned by standard
APM 0.24, while TCLI coordinates initialization with standard APM commands.

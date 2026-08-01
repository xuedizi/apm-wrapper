# patches

Out-of-tree patches against upstream `microsoft/apm`, applied by
`apm-wrapper/scripts/build-apm.sh`.

- `APM_VERSION` pins the upstream tag.
- `gitlab-policy-discovery.patch` recognizes `gitlab.auto-pai.cn` by default and
  uses GitLab REST v4 for self-managed GitLab organization-policy discovery and
  same-host `extends` parents. It preserves the upstream candidate cascade,
  cache-only and stale-cache behavior, hash pins, warnings, and cross-host
  rejection.
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
  no redundant download, and rejection of an unchanged moved tag.
- `marketplace-provenance.patch` preserves Marketplace origin metadata when a
  lockfile rebuild resolves the dependency to the same non-empty commit. Its
  focused regression rejects inheritance for missing or changed commits.

General GitLab install, download, and Marketplace behavior remains owned by
upstream APM 0.26. The narrow downstream policy patch owns only self-managed
GitLab organization-policy discovery and same-host inheritance. Registry,
safe-install, and attestation behavior remains standard APM 0.26, while TCLI
coordinates initialization with standard APM commands.

Delete the GitLab policy patch only after an upstream release carries both its
source fix and regressions. Delete any other behavior patch only after upstream
carries its equivalent source fix and regressions. To roll back, restore the
complete prior wrapper baseline commit/tag, including its matching patches and
tests; do not change only `APM_VERSION`.

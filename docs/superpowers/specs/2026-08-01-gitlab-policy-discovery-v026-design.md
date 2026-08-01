# GitLab Policy Discovery for APM 0.26

## Problem

The wrapper releases based on APM 0.26 no longer carry the historical
`gitlab-policy-discovery.patch`. Upstream APM 0.26 still routes every non-Azure
DevOps organization-policy lookup through the GitHub Contents API. For a
self-managed GitLab remote such as `gitlab.auto-pai.cn`, APM requests
`/api/v3/repos/...`, receives a 404, and reports the organization policy as
absent. This silently skips policy enforcement.

General GitLab dependency, install, and Marketplace support is out of scope.
Only organization-policy auto-discovery is affected.

## Chosen Design

Add one independent `gitlab-policy-discovery.patch`, rebased onto upstream APM
`v0.26.0`. Do not modify `ide.patch`, `literal-ref-refresh.patch`, or
`marketplace-provenance.patch`.

The patch has two responsibilities:

1. Treat `gitlab.auto-pai.cn` as a default self-managed GitLab hostname while
   continuing to honor `GITLAB_HOST` and `APM_GITLAB_HOSTS`. GitHub Enterprise
   precedence and the existing conflict diagnostic remain consistent with
   upstream APM 0.26.
2. Route GitLab organization-policy candidates from `_auto_discover` to the
   GitLab REST v4 raw-file endpoint instead of `_fetch_from_repo` and the
   GitHub `/api/v3/repos` endpoint.

The GitLab fetch path must preserve current APM 0.26 semantics for candidate
ordering, `cache_only`, fresh/stale cache handling, policy parsing warnings,
hash-pin verification, fail-closed errors, and cache writes. It tries the
conventional `main` and `master` refs because the raw-file endpoint requires a
ref and the policy repository default branch is otherwise unknown. A 404 on
both refs means absent; authentication, authorization, redirect, timeout, and
other HTTP failures remain errors. Private-repository authentication reuses
APM's existing `_get_token_for_host(host)` resolver and sends the resolved
credential through GitLab's `PRIVATE-TOKEN` header; no credential or new token
source is introduced downstream.

## Tests and Release Gates

Tests are included inside the patch so they execute against the actual patched
upstream tree, not a wrapper-only imitation. Focused regressions cover:

- zero-configuration recognition of `gitlab.auto-pai.cn`;
- environment-configured GitLab hosts still being additive;
- routing organization-policy lookup to GitLab REST v4 rather than GitHub API;
- successful policy content, `main` to `master` fallback, and token header;
- 404 absence and fail-closed authentication/redirect failures;
- `cache_only` making no network request;
- preservation of current cache, hash, and warning behavior where exercised by
  the existing discovery helpers.

`scripts/test-patched-apm.sh` adds only the relevant upstream policy and host
test files. `scripts/build-apm_test.sh` changes its exact patch list from three
to four and verifies that the GitLab patch owns only policy discovery, hostname
recognition, and its focused tests. Documentation describes the narrow scope
and removes the inaccurate claim that standard APM 0.26 owns all policy
behavior.

The red/green proof is required: first add the focused regression to the
temporary upstream test tree without the source fix and observe the expected
failure; then generate the patch with the minimal source change and observe the
same test pass. Finally run the complete patched-upstream release gate and the
wrapper structural gate.

## Versioning and Rollout

Published artifacts are immutable:

- publish the corrected wrapper as `v0.26.0-tac.v0.3.3`;
- update TAC production pin fixtures, documentation, and release checks from
  `.3.2` to `.3.3` without unrelated TAC behavior changes;
- merge the TAC pin change through Gerrit;
- publish TAC as `v0.6.4`, leaving `.3.2` and TAC `v0.6.3` untouched.

Before either publication, verify target tag and Release absence. The wrapper
release must pass its patch gate and six-platform GitHub Actions build. TAC must
pass its full Go and release-contract tests, Direct and Marketplace lifecycle
checks, six-platform sidecar preflight, clean detached-source proof, local
release verification, and full remote verification.

## Non-goals

- No generic refactor of upstream policy discovery.
- No change to GitLab Marketplace, dependency resolver, clone, or download
  behavior.
- No new configuration surface.
- No overwrite or deletion of an existing tag or Release.
- No change to the other three downstream patches.

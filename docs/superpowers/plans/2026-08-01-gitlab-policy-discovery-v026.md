# GitLab Policy Discovery Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore self-managed GitLab organization-policy auto-discovery in the APM 0.26 sidecar with one independent, regression-tested downstream patch, then publish wrapper `.3.3`, pin it in TAC, merge through Gerrit, and publish TAC `v0.6.4` without overwriting prior releases.

**Architecture:** Treat the patch as the production artifact: prove the failure and fix in a clean `microsoft/apm@v0.26.0` checkout, then capture both source and focused tests in `gitlab-policy-discovery.patch`. Preserve APM 0.26 cache, hash, warnings, candidate cascade, and fail-closed semantics by mirroring the existing GitHub/ADO discovery helpers only where the transport differs. Publish wrapper and TAC only from reviewed canonical commits after destination-absence and complete verification gates.

**Tech Stack:** Python 3.13, pytest, requests, uv, Bash, Git/GitHub Actions, Go, Gerrit, GitLab Release API.

---

## File Map

Wrapper repository:

- Create `patches/gitlab-policy-discovery.patch`: GitLab policy behavior and upstream regressions.
- Modify `patches/README.md` and `README.md`: document the narrow downstream scope.
- Modify `scripts/build-apm_test.sh`: require the exact three-active-patch set and verify ownership.
- Modify `scripts/test-patched-apm.sh`: run the focused upstream regressions.
- Keep `ide.patch` and `literal-ref-refresh.patch` byte-identical to current
  `main`. Keep `disabled-patches/marketplace-provenance.patch` byte-identical to
  its former active copy at `6ea5b8b`, present, and inactive.

Upstream paths captured inside the new patch:

- Modify `src/apm_cli/utils/github_host.py`.
- Modify `src/apm_cli/policy/discovery.py`.
- Modify `tests/unit/test_github_host.py`.
- Create `tests/unit/policy/test_gitlab_discovery.py`.

TAC files must be discovered from fresh canonical Gerrit `master`. Modify only active `.3.2` production-pin contracts and new `v0.6.4` release documentation; preserve immutable historical records unless an active test consumes one as the current pin fixture.

### Task 1: Prove the APM 0.26 regression

- [ ] **Step 1: Create a disposable upstream checkout and apply current `main`'s two active patches**

```bash
UPSTREAM_WORK=$(mktemp -d /private/tmp/apm-v026-gitlab.XXXXXX)
git clone --depth 1 --branch v0.26.0 --single-branch https://github.com/microsoft/apm.git "$UPSTREAM_WORK/source"
for patch_file in patches/*.patch; do
  git -C "$UPSTREAM_WORK/source" apply "$(pwd)/$patch_file"
done
git -C "$UPSTREAM_WORK/source" status --short
```

Expected: only `ide.patch` and `literal-ref-refresh.patch` are present before
the GitLab patch is added. The Marketplace provenance patch remains under
`disabled-patches/` and is not applied. Record the active baseline diff so the
new patch cannot absorb those hunks.

- [ ] **Step 2: Write failing hostname and routing tests**

Add to upstream `tests/unit/test_github_host.py`:

```python
def test_is_gitlab_hostname_tac_default_without_env(monkeypatch):
    monkeypatch.delenv("GITHUB_HOST", raising=False)
    monkeypatch.delenv("GITLAB_HOST", raising=False)
    monkeypatch.delenv("APM_GITLAB_HOSTS", raising=False)
    assert github_host.is_gitlab_hostname("gitlab.auto-pai.cn")


def test_default_gitlab_host_keeps_environment_hosts_additive(monkeypatch):
    monkeypatch.setenv("APM_GITLAB_HOSTS", "extra.gitlab.example.org")
    assert github_host.is_gitlab_hostname("gitlab.auto-pai.cn")
    assert github_host.is_gitlab_hostname("extra.gitlab.example.org")
```

Create upstream `tests/unit/policy/test_gitlab_discovery.py`. Its first test patches `discovery._fetch_from_gitlab_repo` with `create=True`, makes `_extract_org_from_git_remote` return `("tc-platform", "gitlab.auto-pai.cn")`, and asserts `.github-private` is routed to the GitLab helper with `no_cache`, `expected_hash`, and `cache_only` forwarded while `_fetch_from_repo` is never called.

- [ ] **Step 3: Run focused tests and verify RED**

```bash
cd "$UPSTREAM_WORK/source"
uv run --frozen --extra dev pytest -q \
  tests/unit/test_github_host.py \
  tests/unit/policy/test_gitlab_discovery.py
```

Expected: assertion failures prove the company host is not recognized and discovery still routes through `_fetch_from_repo`. Syntax or collection errors are not acceptable RED evidence.

### Task 2: Implement the minimum APM 0.26 path with TDD

- [ ] **Step 1: Add default-host recognition and routing only**

In `github_host.py`, add:

```python
_DEFAULT_GITLAB_HOSTS = ("gitlab.auto-pai.cn",)
```

Make `_get_gitlab_hosts_list()` return an ordered union of environment entries and this tuple. Leave the existing `GITHUB_HOST` precedence branch unchanged; `has_github_gitlab_host_env_conflict()` continues to use the same list helper.

In `policy/discovery.py`, import `is_gitlab_hostname`, set `is_gitlab = not is_ado and is_gitlab_hostname(host)`, and add a sibling branch calling `_fetch_from_gitlab_repo` with the current candidate and unchanged `no_cache`, `expected_hash`, and `cache_only` values. Give the helper a `project_path` argument so the same transport can preserve nested GitLab project identities.

- [ ] **Step 2: Run the initial focused tests and verify GREEN**

Run the Task 1 pytest command. Expected: hostname and routing tests pass.

- [ ] **Step 3: Write failing repository and transport tests**

Expand `test_gitlab_discovery.py` with independent behavioral cases:

```text
_fetch_from_gitlab_repo:
  fresh cache hit returns without HTTP
  cache_only miss returns absent without HTTP
  successful YAML preserves source, warnings, and hash and writes cache
  404 returns absent
  401/403/redirect/timeout fail closed or use the existing stale fallback

_fetch_gitlab_contents:
  URL-encodes nested project and file paths
  sends PRIVATE-TOKEN from _get_token_for_host(host)
  tries main then master only after 404
  returns raw response text on 200
  refuses redirects and distinguishes authentication failures

_fetch_chain_parent / discover_policy_with_chain:
  same-host owner/repo parent retains the GitLab v4 backend
  explicit host-qualified parent retains the GitLab v4 backend
  cold leaf plus parent merge succeeds and the warm read makes no network call
  cross-host parent remains rejected before credentials or HTTP are consulted
```

Mock only HTTP, token, and cache boundaries. Assert `PolicyFetchResult` and URL/header behavior, not call count alone.

- [ ] **Step 4: Run expanded tests and verify RED**

Expected: explicit failed assertions because the two GitLab helpers are missing. Avoid collection errors by importing the discovery module and checking attributes at runtime.

- [ ] **Step 5: Implement the two minimal helpers**

Implement `_fetch_from_gitlab_repo` by following current `_fetch_from_ado_repo` for cache read, `cache_only`, stale fallback, garbage detection, hash verification, parser warnings, conditional cache write, and result construction. Accept `project_path` plus `host`; use `org:{host}/{project_path}` as the source/cache identity. Change only repository identity and transport.

Add the smallest GitLab branch to `_fetch_chain_parent`. Leave URL/file and ADO branches unchanged. For `extends: org`, retain normal auto-discovery. For a same-host `owner/repo` or explicit `gitlab-host/owner/repo` parent, normalize the project path, preserve the already validated `leaf_host`, and call `_fetch_from_gitlab_repo` with `cache_only` forwarded. Do not weaken `_validate_extends_host` or add cross-host support.

Implement `_fetch_gitlab_contents` with this core:

```python
project_path = f"{org}/{repo}"
api_base = f"https://{host}/api/v4"
encoded_project = quote(project_path, safe="")
encoded_file = quote(file_path, safe="")
headers = {"Accept": "application/json"}
token = _get_token_for_host(host)
if token:
    headers["PRIVATE-TOKEN"] = token
```

Request `main` then `master` using `timeout=10` and `allow_redirects=False`. Only 404 advances to the next ref. Return specific errors immediately for 401, 403, redirect, non-200, timeout, and connection failure. Never log or embed a token.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run the focused pytest command and require all cases to pass.

- [ ] **Step 7: Run existing policy regressions**

```bash
uv run --frozen --extra dev pytest -q \
  tests/unit/test_github_host.py \
  tests/unit/policy/test_discovery.py \
  tests/unit/policy/test_discovery_policy_resolution.py \
  tests/unit/policy/test_cache_merged_effective.py \
  tests/unit/policy/test_gitlab_discovery.py
```

Expected: all selected existing and new policy tests pass.

### Task 3: Capture the independent patch and wrapper gates

- [ ] **Step 1: Inspect only the new upstream diff**

```bash
git -C "$UPSTREAM_WORK/source" diff -- \
  src/apm_cli/utils/github_host.py \
  src/apm_cli/policy/discovery.py \
  tests/unit/test_github_host.py \
  tests/unit/policy/test_gitlab_discovery.py
```

Expected: no IDE, literal-ref, Marketplace, install, or lockfile hunk.

- [ ] **Step 2: Change wrapper structural tests first and verify RED**

Update `scripts/build-apm_test.sh` to require this exact lexical set:

```text
gitlab-policy-discovery.patch
ide.patch
literal-ref-refresh.patch
```

Require the two source and two test paths, `/api/v4/projects/`, `PRIVATE-TOKEN`, `cache_only`, and `gitlab.auto-pai.cn`. Reject Marketplace/install/lockfile paths. Assert that the archived Marketplace patch is present but inactive. Run the shell test before adding the patch and observe the missing-patch failure.

- [ ] **Step 3: Add the patch and release-test selection**

Add the inspected diff as `patches/gitlab-policy-discovery.patch` using `apply_patch`. Add these paths to `scripts/test-patched-apm.sh` while retaining all existing selections:

```text
tests/unit/test_github_host.py
tests/unit/policy/test_discovery.py
tests/unit/policy/test_gitlab_discovery.py
```

- [ ] **Step 4: Update wrapper documentation**

State that upstream owns general GitLab install/download/Marketplace support, while this patch owns only self-managed GitLab organization-policy discovery. Permit deletion only after upstream ships both source fix and regressions.

- [ ] **Step 5: Verify wrapper GREEN**

```bash
bash scripts/build-apm_test.sh
bash scripts/test-patched-apm.sh
git diff --check
```

- [ ] **Step 6: Prove active baselines and the inactive archive are byte-identical**

```bash
for patch_file in ide.patch literal-ref-refresh.patch; do
  cmp "patches/$patch_file" <(git show main:"patches/$patch_file")
done
cmp disabled-patches/marketplace-provenance.patch \
  <(git show 6ea5b8b:patches/marketplace-provenance.patch)
```

- [ ] **Step 7: Commit the wrapper implementation**

```bash
git add patches README.md scripts docs/superpowers
git commit -m "fix: restore GitLab policy discovery"
```

### Task 4: Review and publish wrapper `.3.3`

- [ ] **Step 1: Request independent code review**

Review `6ea5b8b4f5310c15a1dc85460c9486a948d9a13f..HEAD`. Resolve every Critical or Important issue and rerun affected tests.

- [ ] **Step 2: Run fresh final verification**

```bash
bash scripts/build-apm_test.sh
bash scripts/test-patched-apm.sh
git diff --check
git status --short
```

- [ ] **Step 3: Verify destination absence**

```bash
gh release view v0.26.0-tac.v0.3.3 --repo xuedizi/apm-wrapper
git ls-remote --tags origin refs/tags/v0.26.0-tac.v0.3.3
```

Require explicit absence; network errors are not absence.

- [ ] **Step 4: Integrate, tag, and publish**

Integrate the reviewed branch with the repository's existing fast-forward flow, push `main`, create `v0.26.0-tac.v0.3.3` on the reviewed commit, and push the tag. Never force-push or move an existing tag.

- [ ] **Step 5: Monitor and independently verify GitHub Actions**

Require the patch-test job, all six native platform builds, and Release job to succeed. Verify the non-draft/non-prerelease Release has six archives plus `apm-manifest.json`; verify manifest version/upstream, download Darwin ARM64, check SHA-256 and size, and run `apm --version`.

### Task 5: Update TAC production pin to wrapper `.3.3`

- [ ] **Step 1: Create an isolated worktree from fresh Gerrit master**

Fetch canonical master after `.3.3` is formally published. Do not base the pin on the user's stale root checkout or an unmerged review branch.

- [ ] **Step 2: Inventory and classify active pin contracts**

```bash
rg -n 'v0\.26\.0-tac\.v0\.3\.2|v0\.6\.3' tac README.md docs
```

Change only active contracts and new `v0.6.4` records; preserve historical immutable release records.

- [ ] **Step 3: Change exact pin tests first and verify RED**

Update fixtures/assertions to `.3.3` while leaving `tac/Makefile` at `.3.2`, then run:

```bash
bash scripts/install_test.sh
bash scripts/release_test.sh
python3 scripts/verify-published-release_test.py
bash scripts/asset-lifecycle/direct-e2e-test.sh
bash scripts/asset-lifecycle/marketplace-e2e-test.sh
```

Expected: failures showing the production source is still `.3.2`.

- [ ] **Step 4: Change the production source of truth**

Update `APM_SIDECAR_VERSION` in `tac/Makefile` to `v0.26.0-tac.v0.3.3`. Do not alter APM semantic version `0.26.0`, doctor logic, Direct behavior, or unrelated docs.

- [ ] **Step 5: Verify TAC pin and lifecycle gates**

```bash
go test ./...
bash scripts/install_test.sh
bash scripts/release_test.sh
python3 scripts/verify-published-release_test.py
bash scripts/asset-lifecycle/direct-e2e-test.sh
bash scripts/asset-lifecycle/marketplace-e2e-test.sh
make integration-test
make release-check VERSION=v0.6.4
```

Also run the real five-stage drivers with formal `.3.3`, preserving the Marketplace registry byte-for-byte:

```bash
make asset-lifecycle-e2e
make asset-lifecycle-marketplace-e2e
```

Run and record the real Marketplace gate even though Marketplace provenance is
inactive. Only the already-known Frozen missing-provenance mismatch may be
accepted for this rollout; registry mutation or any other failure still blocks
release.

- [ ] **Step 6: Verify minimal diff and commit**

Every changed file must be an active production-pin contract or new `v0.6.4` release record. Exclude generated artifacts, evidence, caches, and `__pycache__`. Commit with the required structured TAC message and `Change-Id`.

### Task 6: Merge the TAC pin through Gerrit

- [ ] **Step 1: Push the exact commit to `refs/for/master`**

Capture the Change URL and verify the server patchset equals the local commit.

- [ ] **Step 2: Review, vote, and submit using the established flow**

Inspect the server diff and evidence before voting. Do not bypass Gerrit or push directly to canonical master.

- [ ] **Step 3: Prove canonical merge**

Fetch master and verify its merged commit contains `.3.3` and no unrelated changes. Use this exact canonical SHA for release.

### Task 7: Publish TAC `v0.6.4`

- [ ] **Step 1: Verify destination absence and tag ownership**

Independently check that `tc-platform/tac-releases` has no `v0.6.4` Release or tag and WT590_TAC has no `refs/tags/v0.6.4`. Only explicit 404/empty ref proves absence.

- [ ] **Step 2: Create a clean detached canonical release worktree**

Verify tracked, untracked, and ignored status are all empty before release commands.

- [ ] **Step 3: Execute formal release**

```bash
make release-check VERSION=v0.6.4
GOCACHE=/private/tmp/tac-release-v064-go-cache \
  make release-all VERSION=v0.6.4 INSTALLER=1
```

Require canonical-source proof, tests, `.3.3` six-platform sidecar preflight, six-platform TAC build, strict local verification, destination preflight, publication, and full remote verification.

- [ ] **Step 4: Independently verify remote artifacts**

Verify 10 Release links; release-repository tag ownership; manifest version `v0.6.4`; source commit equals fresh Gerrit canonical SHA; sidecar is `.3.3`; six archive sizes and hashes; and remote/local manifest byte equality.

- [ ] **Step 5: Clean only successful temporary artifacts**

Remove the exact disposable release worktree only after full remote verification. Preserve evidence on partial/ambiguous failure. Never print process command lines containing credentials.

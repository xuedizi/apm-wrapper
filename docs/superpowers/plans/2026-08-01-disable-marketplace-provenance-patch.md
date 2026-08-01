# Disable Marketplace Provenance Patch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve `marketplace-provenance.patch` as an inactive source archive while ensuring future APM sidecar builds apply only the IDE and literal-ref-refresh patches.

**Architecture:** Keep `patches/` as the only executable patch input and add a sibling `disabled-patches/` archive that no build or patched-upstream test code scans. Enforce the boundary with an exact active-patch-set contract and explicit checks that the archived patch exists outside the active directory.

**Tech Stack:** Bash build/test scripts, unified diff patch files, Markdown documentation, Git.

---

## File Structure

- Create `disabled-patches/README.md`: explains inactive status, accepted risk, and reviewed re-enable procedure.
- Rename `patches/marketplace-provenance.patch` to `disabled-patches/marketplace-provenance.patch`: retains the backup patch byte-for-byte.
- Modify `scripts/build-apm_test.sh`: makes the active/inactive directory boundary an executable contract.
- Modify `scripts/test-patched-apm.sh`: removes the regression file supplied only by the inactive patch.
- Modify `README.md`: documents two active patches and the separate archive.
- Modify `patches/README.md`: documents only build-active patch behavior and points to the archive.

### Task 1: Add a Failing Active/Inactive Patch Contract

**Files:**
- Modify: `scripts/build-apm_test.sh:18-68`
- Test: `scripts/build-apm_test.sh`

- [ ] **Step 1: Replace the active provenance assertions with the desired archive boundary**

Require the archive and reject the old active path:

```bash
[ -f disabled-patches/README.md ] \
	|| fail "disabled-patches/README.md must document inactive patch policy"
[ -f disabled-patches/marketplace-provenance.patch ] \
	|| fail "disabled-patches must retain the Marketplace provenance backup"
[ ! -f patches/marketplace-provenance.patch ] \
	|| fail "Marketplace provenance patch must not be active"
```

Change the exact active patch set to:

```bash
[ "$patch_names" = "$(printf '%s\n' ide.patch literal-ref-refresh.patch)" ] \
	|| fail "expected exactly active ide.patch and literal-ref-refresh.patch, got: $patch_names"
```

Move the patch-content checks to the archive path and add a negative consumption
check:

```bash
grep -q 'src/apm_cli/install/phases/lockfile.py' \
	disabled-patches/marketplace-provenance.patch \
	|| fail "inactive Marketplace provenance archive should retain its source fix"
grep -q 'tests/unit/install/phases/test_lockfile_marketplace_provenance.py' \
	disabled-patches/marketplace-provenance.patch \
	|| fail "inactive Marketplace provenance archive should retain its regression"
if grep -q 'disabled-patches\|test_lockfile_marketplace_provenance' \
	scripts/build-apm.sh scripts/test-patched-apm.sh; then
	fail "build and patched-upstream regression scripts must not consume inactive patches"
fi
pass "Marketplace provenance patch is archived and inactive"
```

- [ ] **Step 2: Run the contract and verify it fails before implementation**

Run:

```bash
bash scripts/build-apm_test.sh
```

Expected: FAIL because `disabled-patches/README.md` or the archived patch does
not exist yet. This proves the new contract detects the current active layout.

### Task 2: Establish the Inactive Archive and Remove It from Active Tests

**Files:**
- Create: `disabled-patches/README.md`
- Rename: `patches/marketplace-provenance.patch` to `disabled-patches/marketplace-provenance.patch`
- Modify: `scripts/test-patched-apm.sh:32-45`
- Modify: `README.md:15-56,95-109`
- Modify: `patches/README.md:1-29`
- Test: `scripts/build-apm_test.sh`

- [ ] **Step 1: Move the patch without changing its bytes**

```bash
mkdir -p disabled-patches
git mv patches/marketplace-provenance.patch \
  disabled-patches/marketplace-provenance.patch
```

- [ ] **Step 2: Document the inactive archive**

Create `disabled-patches/README.md` with these explicit contracts:

```markdown
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
exact active-set assertions and documentation, run the full wrapper verification,
and publish a new wrapper version. Do not enable it through a runtime flag or by
mutating an existing release.
```

- [ ] **Step 3: Remove the inactive regression from the release test selection**

Delete this line from `scripts/test-patched-apm.sh`:

```bash
tests/unit/install/phases/test_lockfile_marketplace_provenance.py \
```

Do not change the `patches/*.patch` loop; the directory move is what makes the
patch inactive.

- [ ] **Step 4: Update active patch documentation**

In `README.md`:

- change “three downstream patches” to “two downstream patches”;
- remove the provenance patch from the active scope;
- add `disabled-patches/marketplace-provenance.patch` to the layout as inactive;
- remove Marketplace provenance from the release regression list;
- state that frozen/lockfile provenance follows standard upstream APM 0.26;
- explain that archived patches require a reviewed new release to re-enable.

In `patches/README.md`:

- list only `ide.patch` and `literal-ref-refresh.patch` as active;
- state that `build-apm.sh` applies only this directory's top-level patches;
- point readers to `../disabled-patches/README.md` for inactive archives;
- make removal/rollback guidance refer only to the active literal-ref behavior patch.

- [ ] **Step 5: Verify the archived file is byte-for-byte unchanged**

Run:

```bash
cmp \
  <(git show HEAD:patches/marketplace-provenance.patch) \
  disabled-patches/marketplace-provenance.patch
```

Expected: exit 0 with no output.

- [ ] **Step 6: Run the static contract and verify it passes**

Run:

```bash
bash scripts/build-apm_test.sh
```

Expected: `ALL PASS`, including “Marketplace provenance patch is archived and inactive”.

- [ ] **Step 7: Commit the active/inactive boundary**

```bash
git add README.md patches/README.md disabled-patches \
  scripts/build-apm_test.sh scripts/test-patched-apm.sh
git commit -m "build: archive inactive provenance patch"
```

### Task 3: Verify Only Active Patches Build and Test

**Files:**
- Verify: `scripts/build-apm.sh`
- Verify: `scripts/test-patched-apm.sh`
- Verify: `scripts/package-release_test.sh`
- Verify: `scripts/verify-executable-arch_test.py`

- [ ] **Step 1: Run patched-upstream regressions against the pinned upstream**

Run:

```bash
UV_CACHE_DIR=/tmp/apm-inactive-patch-uv-cache scripts/test-patched-apm.sh
```

Expected: output applies only `ide.patch` and `literal-ref-refresh.patch`; all
selected tests pass; output does not mention `marketplace-provenance.patch`.
The command uses the script's default fixed upstream source
`https://github.com/microsoft/apm.git` and may require network approval.

- [ ] **Step 2: Run packaging and architecture self-tests**

Run:

```bash
bash scripts/package-release_test.sh
python3 scripts/verify-executable-arch_test.py
```

Expected: both suites pass.

- [ ] **Step 3: Run repository consistency checks**

Run:

```bash
git diff --check HEAD^..HEAD
find patches -maxdepth 1 -type f -name '*.patch' -exec basename {} \; | sort
rg -n 'marketplace-provenance|Marketplace provenance' \
  README.md patches scripts .github disabled-patches
git status --short
```

Expected:

- no whitespace errors;
- active patch listing is exactly `ide.patch` and `literal-ref-refresh.patch`;
- provenance references describe the inactive archive or static boundary only;
- only the pre-existing untracked `.DS_Store` remains outside committed work.

- [ ] **Step 4: Record verification evidence**

Do not amend an existing release tag. Report the active patch set, archived
patch path, exact test commands, and results. Note that TAC must pin a newly
published wrapper version before its bundled sidecar behavior changes.

# patches

Out-of-tree patches against upstream `microsoft/apm`, applied by
`apm-wrapper/scripts/build-apm.sh` and shipped as platform-specific sidecar
archives such as `apm-linux-amd64.tar.gz`.

- `APM_VERSION`  pinned upstream git tag (one line, e.g. `v0.24.0`). Bumped
                 when we rebase patches onto a newer upstream.
- `*.patch`      `git apply`-compatible unified diffs. Order is **lexical**;
                 keep filenames numerically prefixed if order matters. The
                 current patches touch disjoint files, so order is irrelevant.
    - `ide.patch`                 adds `codebuddy` / `tc` compile targets
                                   (claude compile-family: `codebuddy` ->
                                   `.codebuddy/`, `tc` -> `.claude/`). Also
                                   lists both in the `--target` help text of the
                                   `compile`, `deps`, and `install` commands so
                                   they surface in `--help`.
    - `marketplace-manifest.patch` adds `apm marketplace add --manifest <path>`
                                   so a marketplace manifest can live at a
                                   custom directory / filename (e.g. a GitLab
                                   repo with `configs/my-catalog.json`) instead
                                   of only the auto-detected `marketplace.json`
                                   / `.github/plugin/` / `.claude-plugin/`
                                   locations.
    - `gitlab-policy-discovery.patch` makes org-policy auto-discovery work on
                                   self-managed GitLab. **Scope note:** upstream
                                   v0.20+ already supports GitLab broadly for
                                   dependency install / download and marketplace
                                   fetches (`install/gitlab_resolver.py`,
                                   `deps/git_file_transport.py`,
                                   `marketplace/client.py`, ...). This patch does
                                   NOT touch any of that. It fixes the one path
                                   upstream still omits: **org-policy
                                   auto-discovery** (`apm` fetching
                                   `<org>/.github/apm-policy.yml`). In v0.24.0
                                   `policy/discovery.py::_auto_discover` has only
                                   two branches -- Azure DevOps vs.
                                   `_fetch_from_repo` -- and `_fetch_from_repo`
                                   hardcodes the GitHub Enterprise
                                   `https://{host}/api/v3/repos/.../contents/`
                                   endpoint (with an `application/vnd.github.v3+
                                   json` header) for every non-github host. There
                                   is no GitLab branch, so a GitLab remote 404s
                                   and silently gets "no policy applied". Two
                                   changes fix this: (1)
                                   `github_host.py` bakes `gitlab.auto-pai.cn`
                                   into `is_gitlab_hostname()` as a default
                                   GitLab host so it is recognized with **zero
                                   config** (no `GITLAB_HOST` /
                                   `APM_GITLAB_HOSTS` needed; the env var is
                                   still honored and appended, not overridden);
                                   (2) `policy/discovery.py` routes GitLab
                                   remotes to a new `_fetch_from_gitlab_repo`
                                   that reads `<org>/.github/apm-policy.yml`
                                   over the GitLab REST v4 API
                                   (`/api/v4/projects/.../repository/files/.../raw`),
                                   instead of the GitHub Enterprise `/api/v3/`
                                   endpoint described above. As of the v0.24.0 rebase upstream
                                   `_auto_discover` iterates a candidate-repo
                                   cascade (`.github` / `.apm` / `_apm`) with a
                                   dedicated Azure DevOps branch; the GitLab
                                   route is wired in as a sibling `elif` inside
                                   that loop, mirroring the ADO branch. The
                                   baked-in default is also honored by
                                   `has_github_gitlab_host_env_conflict` so
                                   bare-FQDN shorthand disambiguation stays
                                   consistent. Add company GitLab hosts by
                                   editing `_DEFAULT_GITLAB_HOSTS` in the patch.
                                   Note: token for private policy repos still
                                   comes from the environment / credential
                                   helper (secrets are never baked in).

To rebase onto a newer upstream:

```bash
bash scripts/build-apm.sh --rebase
```

Resolve conflicts if any, then write the updated patch back to `patches/`.

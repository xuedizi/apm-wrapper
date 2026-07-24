# patches

Out-of-tree patches against upstream `microsoft/apm`, applied by
`apm-wrapper/scripts/build-apm.sh` and shipped as platform-specific sidecar
archives such as `apm-linux-amd64.tar.gz`.

- `APM_VERSION`  pinned upstream git tag (one line, e.g. `v0.13.0`). Bumped
                 when we rebase patches onto a newer upstream.
- `*.patch`      `git apply`-compatible unified diffs. Order is **lexical**;
                 keep filenames numerically prefixed if order matters. The
                 current patches touch disjoint files, so order is irrelevant.
    - `ide.patch`                 adds `codebuddy` / `tc` compile targets.
    - `marketplace-manifest.patch` adds `apm marketplace add --manifest <path>`
                                   so a marketplace manifest can live at a
                                   custom directory / filename (e.g. a GitLab
                                   repo with `configs/my-catalog.json`) instead
                                   of only the auto-detected `marketplace.json`
                                   / `.github/plugin/` / `.claude-plugin/`
                                   locations.

To rebase onto a newer upstream:

```bash
bash scripts/build-apm.sh --rebase
```

Resolve conflicts if any, then write the updated patch back to `patches/`.

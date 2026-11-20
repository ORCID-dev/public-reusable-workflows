# public-reusable-workflows

Reusable GitHub Actions workflows for ORCID's public repos.

| Workflow | Job | Permissions | Runs |
|---|---|---|---|
| `lint.yml` | `pre-commit` | `contents: read` | `pre-commit run --all-files` |
| `sast.yml` | `semgrep` | `contents: read` | `semgrep ci`, plus Maven dependency trees when `java-version` is set |

## Usage

```yaml
jobs:
  lint:
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/lint.yml@v1
```

Inputs and defaults:

- `lint.yml`: `python-version` (`3.13`), `timeout-minutes` (`15`).
- `sast.yml`: `java-version` (empty), `split` (`false`), `quiet` (`true`), `timeout-minutes` (`30`). Secret `semgrep-app-token`; without it the scan is skipped.

Check names are `<caller job> / <job>`, e.g. `lint / pre-commit`. Don't rename either while the check is required.

## Versioning

Releases are tagged `vX.Y.Z`. Callers use `v1`, which moves only after a release passes in ORCID-dev. Removing or renaming an input bumps the major.

## Rules

- Only `actions/*`, vendor-maintained actions and `step-security/harden-runner`, pinned by SHA. Anything else is a `run:` step or a composite action in this repo.
- Tool versions are pinned in the workflow. Renovate bumps them and the action SHAs.
- Workflows request least-privilege `permissions`. Callers set `concurrency`.
- Pass secrets by name, never `secrets: inherit`.

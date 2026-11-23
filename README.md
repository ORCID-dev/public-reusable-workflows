# public-reusable-workflows

Reusable GitHub Actions workflows for ORCID's public repos.

| Workflow | Job | Permissions | Runs |
|---|---|---|---|
| `lint.yml` | `pre-commit` | `contents: read` | `pre-commit run --all-files` |
| `sast.yml` | `semgrep` | `contents: read` | `semgrep ci`, plus Maven dependency trees when `java-version` is set |
| `version.yml` | `version` | `contents: read` | Next `vX.Y.Z` from the latest tag; outputs `version`, `tag`, `last-tag` |
| `build.yml` | from `name` | `contents: read` | Runs a script with Java, Node or Python and cached dependencies, one job per module |
| `docker.yml` | from `name` | `contents: read` | Builds images with buildx, one job per image; pushes the tag and the `:cache` build cache |
| `release.yml` | `release` | `contents: write` | Tags the commit and creates a GitHub Release with generated notes; optional Slack message |
| `pages.yml` | `publish` | `contents: write` | Publishes a built site from an artifact into a directory of the `gh-pages` branch |
| `transifex.yml` | `tx`, `pr` | `contents: read` | Pulls translations into a PR opened by a GitHub App, or pushes source strings |

## Usage

```yaml
jobs:
  lint:
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/lint.yml@v1
```

Inputs and defaults:

- `lint.yml`: `python-version` (`3.13`), `timeout-minutes` (`15`).
- `sast.yml`: `java-version` (empty), `split` (`false`), `quiet` (`true`), `timeout-minutes` (`30`). Secret `semgrep-app-token`; without it the scan is skipped.
- `version.yml`: `bump` (`patch`; `minor`, `major` or `none`), `version` (explicit, skips the bump). `#minor` or `#major` in a merged commit subject raises the bump.
- `build.yml`: `name` and `run` (required), `modules` (`[""]`), `fail-fast` (`true`), `version`, `java-version`, `node-version`, `node-version-file`, `python-version`, `cache` (`restore`; `save` in one job, `none`), `working-directory` (`.`), `upload` (path to upload as an artifact named after the job), `build-cache` (e.g. `.angular/cache`) and `build-cache-key` (`build`), `fetch-depth` (`1`), `timeout-minutes` (`30`). Secret `env-vars`: `KEY=value` lines, exported and masked.
- `docker.yml`: `name` and `images` (required; each `{"name", "file", "context", "build-args", "artifact", "artifact-path"}`), `context` (`.`), `version`, `build-args`, `push` (`false`), `timeout-minutes` (`45`). Per-image values override the shared ones. `artifact`, e.g. a jar from build.yml `upload`, is downloaded to `artifact-path` before the build. Context and file must be paths inside the repo. Secrets `registry`, `username`, `password`.
- `release.yml`: `tag` (required), `previous-tag`, `slack-channel`, `timeout-minutes` (`10`). Secret `slack-token`. Output `url`. Re-runs are safe; a tag that already points to another commit fails the job. Slack is used only in the ORCID org.
- `pages.yml`: `artifact` (required), `directory` (`.`), `keep`, `branch` (`gh-pages`), `environment`, `message`, `timeout-minutes` (`10`). Output `url`. The job only copies files, so no project code runs with the write token. Fork PRs are skipped.
- `transifex.yml`: `mode` (`pull` or `push`) and `resource` (required), `artifact` and `artifact-path` (push), `branch` (pull, `transifex`), `timeout-minutes` (`15`). Secrets `transifex-token`, `app-client-id`, `app-private-key`. The tx CLI is pinned by sha256. Without a token, nothing runs. Source strings are pushed only from the ORCID org.

Maven cache: key `maven-<os>-<pom hash>-<ISO week>`, restored by prefix, saved only by the `save` job on the default branch after a miss. `sast.yml` restores it too. `org/orcid` is never cached. Call `versions:set` with full plugin coordinates so no plugin version is resolved at run time.

Node: with `node-version` or `node-version-file` set, dependencies are installed before `run` with `pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile` or `npm ci`, without the `env-vars` secrets. pnpm is `PNPM_VERSION` from `build.yml`, or the version the project's `packageManager` pins. The download cache (pnpm store, yarn cache, `~/.npm`) is keyed on the lockfile and restored by prefix. yarn's `node_modules` is cached on an exact key: OS release, Node ABI and lockfile.

Docker: outside the ORCID org, images go under `vd_test/`, so a test can't overwrite a production tag. There is no push on pull_request events, and only a push logs in and reads or writes the `:cache` tag. BuildKit is pinned by digest.

Check names are `<caller job> / <job>`, e.g. `lint / pre-commit`. Don't rename either while the check is required.

## Versioning

Releases are tagged `vX.Y.Z`. Callers use `v1`, which moves only after a release passes in ORCID-dev. Removing or renaming an input bumps the major.

Only org admins can create or move `v*` tags:

```sh
gh release create vX.Y.Z --generate-notes
git fetch --tags && git tag -f v1 vX.Y.Z && git push -f origin v1
```

To roll back, point `v1` at the previous release. `v1` never gets a release of its own, since releases are immutable and would lock it.

## Rules

- Only `actions/*`, vendor-maintained actions and `step-security/harden-runner`, pinned by SHA. Anything else is a `run:` step or a composite action in this repo.
- Tool versions are pinned in the workflow. Renovate bumps them and the action SHAs.
- Workflows request least-privilege `permissions`. Callers set `concurrency`.
- Pass secrets by name, never `secrets: inherit`.

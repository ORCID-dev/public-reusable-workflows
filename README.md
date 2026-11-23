# public-reusable-workflows

Reusable workflows for ORCID's public repos. Consuming repos add a thin caller. The pipeline lives here.

| Workflow | Caller trigger | Does |
|---|---|---|
| `lint.yml` | `pull_request` | pre-commit |
| `sast.yml` | `pull_request`, `schedule` | Semgrep |
| `version.yml` | `push` | next `vX.Y.Z` |
| `build.yml` | `pull_request`, `push` | a project script with Java, Node or Python and cached dependencies |
| `docker.yml` | `push` | build and push images |
| `release.yml` | `push` | tag and GitHub Release |
| `pages.yml` | `push`, `pull_request` | publish a site to `gh-pages` |
| `transifex.yml` | `schedule`, `push` | pull translations into a PR, push source strings |

Inputs and defaults are at the top of each workflow file.

## Pull requests

```yaml
name: pr
on:
  pull_request:
jobs:
  lint:
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/lint.yml@v1

  test:
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/build.yml@v1
    with:
      name: test
      modules: '["orcid-core", "orcid-web"]'
      java-version: '21'
      run: mvn -T 1C verify --projects "$MODULE" --also-make
```

## Release

```yaml
name: release
on:
  push:
    branches: [main]
jobs:
  version:
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/version.yml@v1

  images:
    needs: version
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/docker.yml@v1
    with:
      name: images
      images: '[{"name": "orcid/registry/orcid-web", "file": "orcid-web/Dockerfile"}]'
      version: ${{ needs.version.outputs.version }}
      push: true
    secrets:
      registry: ${{ secrets.DOCKER_REGISTRY }}
      username: ${{ secrets.DOCKER_USER }}
      password: ${{ secrets.DOCKER_PASSWORD }}

  release:
    needs: [version, images]
    permissions:
      contents: write
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/release.yml@v1
    with:
      tag: ${{ needs.version.outputs.tag }}
      previous-tag: ${{ needs.version.outputs.last-tag }}
```

## Pages

```yaml
name: pages
on:
  push:
    branches: [main]
jobs:
  build:
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/build.yml@v1
    with:
      name: build
      node-version-file: .nvmrc
      run: npm run build
      upload: dist

  publish:
    needs: build
    permissions:
      contents: write
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/pages.yml@v1
    with:
      artifact: build
      directory: qa
```

## SAST

```yaml
name: sast
on:
  pull_request:
  schedule:
    - cron: '45 6 * * 0'
jobs:
  sast:
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/sast.yml@v1
    with:
      java-version: '21'
    secrets:
      semgrep-app-token: ${{ secrets.SEMGREP_APP_TOKEN }}
```

## Transifex

```yaml
name: pull-translations
on:
  schedule:
    - cron: '0 0,12 * * *'
jobs:
  transifex:
    permissions:
      contents: read
    uses: ORCID-dev/public-reusable-workflows/.github/workflows/transifex.yml@v1
    with:
      mode: pull
      resource: orcid-angular.messages-xlf
    secrets:
      transifex-token: ${{ secrets.TRANSIFEX_TOKEN }}
      app-client-id: ${{ secrets.GH_APP_CLIENT_ID }}
      app-private-key: ${{ secrets.GH_APP_PRIVATE_KEY }}
```

## Good to know

- Node dependencies are installed from the lockfile before `run`.
- `upload` is a path or glob under `working-directory`, and `{module}` stands for the matrix entry. The artifact starts at the directory before the first wildcard, so `{module}/target/*.jar` restores into `<module>/target`.
- Caches are saved only by the job with `cache: save`, on the default branch.
- Secrets for `run` go in `env-vars` as `KEY=value` lines. They are masked.
- Outside the ORCID org, images go under `vd_test/`, and Slack and Transifex pushes are skipped.
- Check names are `<caller job> / <job>`. Renaming either breaks a required check.
- Callers set `concurrency`. Don't cancel a running release.

## Versioning

Callers use `v1`, which moves only after a release passes in ORCID-dev. Removing or renaming an input bumps the major. Only org admins can create or move `v*` tags:

```sh
gh release create vX.Y.Z --generate-notes
git fetch --tags && git tag -f v1 vX.Y.Z && git push -f origin v1
```

## Rules

- Only `actions/*`, vendor-maintained actions and `step-security/harden-runner`, pinned by SHA.
- Tool versions are pinned in the workflows. Renovate bumps them.
- Least-privilege `permissions`. Secrets are passed by name, never `secrets: inherit`.

#!/usr/bin/env bash
# Runs the version step of .github/workflows/version.yml against throwaway repos.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script=$(python3 "$root/tests/extract-version-script.py" "$root/.github/workflows/version.yml")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

new_repo() {
  repo=$(mktemp -d "$work/repo.XXXX")
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  git init -q --bare "$repo.git"
  git -C "$repo" remote add origin "$repo.git"
  git -C "$repo" commit -q --allow-empty -m init
}
merge() { # merge "<subject of the PR commit>"
  git -C "$repo" switch -q -c "pr-$RANDOM"
  git -C "$repo" commit -q --allow-empty -m "$1"
  git -C "$repo" switch -q main
  git -C "$repo" merge -q --no-ff -m "Merge pull request from ORCID/branch" -
}
tag() { git -C "$repo" tag "$1"; git -C "$repo" push -q origin "$1"; }

run() { # run <expected tag or FAIL> [VAR=value ...]
  local want=$1 got
  shift
  if got=$(cd "$repo" && env VERSION= BUMP=patch "$@" GITHUB_OUTPUT=/dev/stdout bash -eo pipefail -c "$script" 2>/dev/null | sed -n 's/^tag=//p'); then :; else got=FAIL; fi
  if [ "$got" = "$want" ]; then
    echo "ok   ${*:-defaults} -> $got"
  else
    echo "FAIL ${*:-defaults}: got '$got', want '$want'"
    failed=1
  fi
}

new_repo
run v0.0.1

tag v1.2.3
merge "fix a bug"
run v1.2.4
run v1.2.3 BUMP=none
run v1.3.0 BUMP=minor
run v2.0.0 BUMP=major
run v3.25.10-p1 VERSION=3.25.10-p1
run v4.0.0 VERSION=v4.0.0
run FAIL VERSION=1.2
run FAIL BUMP=huge

merge "add a feature #minor"
run v1.3.0
run v1.2.3 BUMP=none

merge "breaking change #major"
run v2.0.0

merge "plain fix"
run v1.2.4

tag v1.3.0-rc1
run v1.2.4

exit "$failed"

#!/usr/bin/env bash
# Runs the image step of .github/workflows/docker.yml for owners, events and versions.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/docker.yml" image)
failed=0

check() { # check <"ref push file" or FAIL> [VAR=value ...]
  local want=$1 out got
  shift
  if out=$(env NAME=orcid/registry/orcid-web FILE= CONTEXT=. VERSION=1.2.3 PUSH=true REGISTRY=reg.example \
    OWNER=ORCID EVENT=push "$@" GITHUB_OUTPUT=/dev/stdout bash -e -c "$script" 2>/dev/null); then
    got="$(sed -n 's/^ref=//p' <<< "$out") $(sed -n 's/^push=//p' <<< "$out") $(sed -n 's/^file=//p' <<< "$out")"
  else
    got=FAIL
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   ${*:-defaults} -> $got"
  else
    echo "FAIL ${*:-defaults}: got '$got', want '$want'"
    failed=1
  fi
}

check "reg.example/orcid/registry/orcid-web true Dockerfile"
check "reg.example/vd_test/orcid/registry/orcid-web true Dockerfile" OWNER=ORCID-dev
check "reg.example/vd_test/orcid/registry/orcid-web true Dockerfile" OWNER=someone
check "reg.example/orcid/registry/orcid-web false Dockerfile" EVENT=pull_request
check "reg.example/orcid/registry/orcid-web false Dockerfile" EVENT=pull_request_target
check "reg.example/orcid/registry/orcid-web false orcid-web/Dockerfile" PUSH=false FILE=orcid-web/Dockerfile
check "vd_test/fixture/hello false fixtures/docker/Dockerfile" OWNER=ORCID-dev REGISTRY= PUSH=false NAME=fixture/hello CONTEXT=fixtures/docker
check "reg.example/ui-2 false ui-2/Dockerfile" PUSH=false NAME=ui-2 CONTEXT=ui-2
check "reg.example/userservice2 false user-service-2/src/main/docker/Dockerfile" PUSH=false NAME=userservice2 \
  CONTEXT=user-service-2 FILE=user-service-2/src/main/docker/Dockerfile
check FAIL CONTEXT=../x
check FAIL CONTEXT=/
check FAIL FILE=a/../b
check FAIL FILE=/etc/passwd
check FAIL REGISTRY=
check FAIL VERSION=
check FAIL "VERSION=1.0 bad"
check FAIL NAME=Bad/Name

exit "$failed"

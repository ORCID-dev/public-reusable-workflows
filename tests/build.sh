#!/usr/bin/env bash
# Runs the run step of .github/workflows/build.yml with sample env-vars.
# shellcheck disable=SC2016 # RUN scripts expand inside the step
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/build.yml" run)
nl=$'\n'
failed=0

check() { # check <name> <want> <env-vars> <run>; <want> ends with "exit <status>" when the step fails
  local got status=0
  got=$(ENV_VARS=$3 RUN=$4 bash -e -c "$script" 2>&1) || status=$?
  if [ "$status" != 0 ]; then got="${got:+$got$nl}exit $status"; fi
  if [ "$got" = "$2" ]; then
    echo "ok   $1"
  else
    printf 'FAIL %s\n--- got\n%s\n--- want\n%s\n' "$1" "$got" "$2"
    failed=1
  fi
}

check "exports and masks" $'::add-mask::1\n::add-mask::x=y\n::add-mask::a b\n1|x=y||a b|unset' \
  $'A=1\n\nB=x=y\nC=\nD=a b' 'echo "$A|$B|$C|$D|${ENV_VARS-unset}"'
check "no env-vars" ok '' 'echo ok'
check "line without =" $'::add-mask::1\n::error::env-vars line 2 is not KEY=value\nexit 1' $'A=1\nTOKEN' 'echo ran'
check "invalid key" $'::error::env-vars line 1 is not KEY=value\nexit 1' '1A=x' 'echo ran'
check "pipefail" 'exit 1' '' 'false | true; echo after'
check "exit status" 'exit 3' '' 'exit 3'

exit "$failed"

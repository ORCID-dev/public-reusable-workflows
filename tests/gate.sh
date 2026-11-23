#!/usr/bin/env bash
# Runs the gate step of .github/workflows/gate.yml with sample needs contexts.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/gate.yml" gate)
nl=$'\n'
failed=0

check() { # check <name> <want> <needs json>; <want> ends with "exit <status>" when the step fails
  local got status=0
  got=$(NEEDS=$3 bash -e -c "$script" 2>&1) || status=$?
  if [ "$status" != 0 ]; then got="${got:+$got$nl}exit $status"; fi
  if [ "$got" = "$2" ]; then
    echo "ok   $1"
  else
    printf 'FAIL %s\n--- got\n%s\n--- want\n%s\n' "$1" "$got" "$2"
    failed=1
  fi
}

check "all green" '' '{"lint":{"result":"success"},"test":{"result":"success"}}'
check "skipped is fine" '' '{"lint":{"result":"success"},"docker":{"result":"skipped"}}'
check "no jobs" '' '{}'
check "a failure" $'::error::Not green: test=failure\nexit 1' '{"lint":{"result":"success"},"test":{"result":"failure"}}'
check "cancelled is not green" $'::error::Not green: lint=cancelled\nexit 1' '{"lint":{"result":"cancelled"},"test":{"result":"success"}}'
check "lists every problem on one line" $'::error::Not green: lint=failure test=cancelled\nexit 1' '{"lint":{"result":"failure"},"ok":{"result":"success"},"test":{"result":"cancelled"}}'

# Unreadable input must fail closed, whatever the jq version says about it.
status=0
NEEDS='not json' bash -e -c "$script" > /dev/null 2>&1 || status=$?
if [ "$status" != 0 ]; then echo "ok   invalid json fails"; else echo "FAIL invalid json passed"; failed=1; fi

exit "$failed"

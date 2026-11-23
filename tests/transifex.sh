#!/usr/bin/env bash
# Runs the gate, install, pull and open steps of .github/workflows/transifex.yml with stub tx and gh commands.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
wf="$root/.github/workflows/transifex.yml"
gate=$(python3 "$root/tests/extract-run.py" "$wf" gate)
install=$(python3 "$root/tests/extract-run.py" "$wf" install)
pull=$(python3 "$root/tests/extract-run.py" "$wf" pull)
open=$(python3 "$root/tests/extract-run.py" "$wf" open)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
failed=0

check() { # check <name> <want> <got>
  if [ "$3" = "$2" ]; then
    echo "ok   $1"
  else
    printf 'FAIL %s\n--- got\n%s\n--- want\n%s\n' "$1" "$3" "$2"
    failed=1
  fi
}
step() { # step <script> [VAR=value ...]; prints outputs, annotations and the exit status
  local script=$1
  shift
  env PATH="$work/bin:$PATH" GITHUB_OUTPUT=/dev/stdout RUNNER_TEMP="$work/runner" "$@" \
    bash -e -c "$script" 2>&1 | grep -E '^([a-z]+=|::|exit )' || true
}

mkdir -p "$work/bin" "$work/runner"
check "pull runs in ORCID-dev" "run=true" "$(step "$gate" MODE=pull RESOURCE=r HAS_TOKEN=true OWNER=ORCID-dev)"
check "push runs in ORCID" "run=true" "$(step "$gate" MODE=push RESOURCE=r HAS_TOKEN=true OWNER=ORCID)"
check "push is skipped outside ORCID" "::notice::Source strings are pushed only from the ORCID org
run=false" "$(step "$gate" MODE=push RESOURCE=r HAS_TOKEN=true OWNER=ORCID-dev)"
check "no token" "::notice::No Transifex token, skipped
run=false" "$(step "$gate" MODE=pull RESOURCE=r HAS_TOKEN=false OWNER=ORCID)"
check "invalid mode" "::error::Invalid mode: sync" "$(step "$gate" MODE=sync RESOURCE=r HAS_TOKEN=true OWNER=ORCID)"
check "invalid resource" "::error::Invalid resource: ../r" "$(step "$gate" MODE=pull RESOURCE=../r HAS_TOKEN=true OWNER=ORCID)"
check "resource can't be an option" "::error::Invalid resource: -r" "$(step "$gate" MODE=pull RESOURCE=-r HAS_TOKEN=true OWNER=ORCID)"

# The real CLI is a linux-amd64 binary: the install step runs on CI runners only.
if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
  tx_env=$(sed -n 's/^ *\(TX_VERSION\|TX_SHA256\): /\1=/p' "$wf")
  # shellcheck disable=SC2086 # two VAR=value words
  step "$install" $tx_env GITHUB_PATH="$work/path" > /dev/null
  check "install verifies and unpacks tx" "1" "$("$work/runner/bin/tx" --version > /dev/null && echo 1)"
  rm -rf "$work/runner/bin"
  # shellcheck disable=SC2086
  step "$install" $tx_env TX_SHA256=0000000000000000000000000000000000000000000000000000000000000000 GITHUB_PATH="$work/path" > /dev/null
  check "install refuses a bad checksum" "missing" "$([ -e "$work/runner/bin/tx" ] && echo present || echo missing)"
else
  echo "skip install (needs Linux x86_64)"
fi

# Origin with a main branch, and a checkout of it as the workspace.
"$real_git" init -q --bare "$work/origin.git"
"$real_git" clone -q "$work/origin.git" "$work/ws" 2> /dev/null
mkdir -p "$work/ws/src/locale"
echo source > "$work/ws/src/locale/messages.xlf"
"$real_git" -C "$work/ws" add -A
"$real_git" -C "$work/ws" -c user.name=x -c user.email=x@example.com commit -qm init
"$real_git" -C "$work/ws" push -q origin HEAD:refs/heads/main
cat > "$work/bin/tx" <<'EOF'
#!/bin/sh
if [ -n "${FAKE_TRANSLATION:-}" ]; then echo "$FAKE_TRANSLATION" > src/locale/messages.fr.xlf; fi
EOF
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo main ;;
  "auth setup-git") ;;
  "pr list") echo "${FAKE_PR:-}" ;;
  "pr create") shift 2; echo "pr create $*" >> "$FAKE_LOG" ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$work/bin/tx" "$work/bin/gh"

cd "$work/ws"
check "pull without changes" "changed=false" "$(step "$pull" RESOURCE=r)"
check "pull with changes" "changed=true" "$(step "$pull" RESOURCE=r FAKE_TRANSLATION=bonjour)"
check "  patch has the file" "1" "$(grep -c '^+++ b/src/locale/messages.fr.xlf' "$work/runner/translations.patch")"
mkdir -p "$work/runner/patch"
mv "$work/runner/translations.patch" "$work/runner/patch/"
"$real_git" reset -q --hard
"$real_git" clean -qfd

opened() { # opened [VAR=value ...]; runs the open step from a fresh main checkout
  "$real_git" checkout -q -f main 2> /dev/null || "$real_git" checkout -q -f -B main origin/main
  : > "$work/log"
  step "$open" GITHUB_REPOSITORY=o/r SLUG=orcid-ci BRANCH=transifex RESOURCE=r FAKE_LOG="$work/log" "$@"
  cat "$work/log"
}
on_branch() { "$real_git" --git-dir "$work/origin.git" log --format=%s main..transifex 2> /dev/null | tr '\n' ' '; }

check "open creates the branch and the PR" "pr create --base main --head transifex --title chore(i18n): update r translations --body " "$(opened)"
check "  one commit on top of main" "chore(i18n): pull r translations " "$(on_branch)"
check "  file on the branch" "bonjour" "$("$real_git" --git-dir "$work/origin.git" show transifex:src/locale/messages.fr.xlf)"
check "re-run with an open PR" "" "$(opened FAKE_PR=12)"
check "  still one commit on top of main" "chore(i18n): pull r translations " "$(on_branch)"
main_before=$("$real_git" --git-dir "$work/origin.git" rev-parse main)
check "never force-pushes the default branch" "::error::Invalid branch: main" "$(opened BRANCH=main)"
check "  main unchanged" "$main_before" "$("$real_git" --git-dir "$work/origin.git" rev-parse main)"
check "invalid branch" "::error::Invalid branch: -f" "$(opened BRANCH=-f)"

exit "$failed"

#!/usr/bin/env bash
# Runs the publish step of .github/workflows/pages.yml against a local bare repository.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/pages.yml" publish)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
failed=0

mkdir -p "$work/bin" "$work/server/o"
"$real_git" init -q --bare "$work/server/o/r.git"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/gh"
# With RACE set, someone else publishes right before our first push.
cat > "$work/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = push ] && [ -n "\${RACE:-}" ] && [ ! -e "$work/raced" ]; then
  touch "$work/raced"
  "$real_git" clone -q --branch gh-pages "file://$work/server/o/r.git" "$work/other"
  echo other > "$work/other/other.txt"
  "$real_git" -C "$work/other" add other.txt
  "$real_git" -C "$work/other" -c user.name=x -c user.email=x@example.com commit -qm other
  "$real_git" -C "$work/other" push -q origin gh-pages
fi
exec "$real_git" "\$@"
EOF
chmod +x "$work/bin/gh" "$work/bin/git"

mkdir -p "$work/v1/assets" "$work/v2" "$work/evil/.git"
echo a > "$work/v1/index.html"
echo b > "$work/v1/assets/app.js"
echo c > "$work/v2/index.html"
echo d > "$work/evil/index.html"
echo x > "$work/evil/.git/config"

publish() { # publish <content> [VAR=value ...]; prints url, annotations and exit status
  local content=$1
  shift
  rm -rf "$work/runner" && mkdir -p "$work/runner"
  env PATH="$work/bin:$PATH" GITHUB_SERVER_URL="file://$work/server" GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=O \
    GITHUB_SHA=0123456789abcdef GITHUB_OUTPUT=/dev/stdout GITHUB_STEP_SUMMARY=/dev/null RUNNER_TEMP="$work/runner" \
    CONTENT="$content" DIRECTORY=. KEEP= BRANCH=gh-pages MESSAGE= EVENT=push HEAD_REPO= "$@" \
    bash -e -c "$script" 2>&1 | grep -E '^(url=|::)' || true
}
files() { "$real_git" --git-dir "$work/server/o/r.git" ls-tree -r --name-only gh-pages 2> /dev/null | tr '\n' ' '; }
check() { # check <name> <want> <got>
  if [ "$3" = "$2" ]; then
    echo "ok   $1"
  else
    printf 'FAIL %s\n--- got\n%s\n--- want\n%s\n' "$1" "$3" "$2"
    failed=1
  fi
}

check "first publish creates the branch" "url=https://o.github.io/r/qa/" "$(publish "$work/v1" DIRECTORY=qa)"
check "  files" ".nojekyll qa/assets/app.js qa/index.html " "$(files)"
publish "$work/v1" DIRECTORY=prod > /dev/null
check "second directory leaves the first" ".nojekyll prod/assets/app.js prod/index.html qa/assets/app.js qa/index.html " "$(files)"
publish "$work/v2" DIRECTORY=qa > /dev/null
check "republish removes stale files" ".nojekyll prod/assets/app.js prod/index.html qa/index.html " "$(files)"
commits=$("$real_git" --git-dir "$work/server/o/r.git" rev-list --count gh-pages)
check "no change, no commit" "::notice::Nothing changed
url=https://o.github.io/r/qa/" "$(publish "$work/v2" DIRECTORY=qa)"
check "  commit count" "$commits" "$("$real_git" --git-dir "$work/server/o/r.git" rev-list --count gh-pages)"
publish "$work/v2" DIRECTORY=runway/PD-1 EVENT=pull_request HEAD_REPO=o/r > /dev/null
check "PR preview" ".nojekyll prod/assets/app.js prod/index.html qa/index.html runway/PD-1/index.html " "$(files)"
check "fork PR is refused" "::notice::No publish from a fork" "$(publish "$work/v1" DIRECTORY=runway/X EVENT=pull_request HEAD_REPO=fork/r)"
publish "$work/v1" DIRECTORY=. KEEP=runway > /dev/null
check "root publish keeps runway only" ".nojekyll assets/app.js index.html runway/PD-1/index.html " "$(files)"
publish "$work/evil" DIRECTORY=evil > /dev/null
check "artifact .git is not copied" ".nojekyll assets/app.js evil/index.html index.html runway/PD-1/index.html " "$(files)"
RACE=1 publish "$work/v2" DIRECTORY=race > /dev/null
check "concurrent publish is retried" ".nojekyll assets/app.js evil/index.html index.html other.txt race/index.html runway/PD-1/index.html " "$(files)"
for dir in ../x .git a/../b /abs qa/.git -rf qa/-x; do
  check "invalid directory $dir" "::error::Invalid directory: $dir" "$(publish "$work/v1" "DIRECTORY=$dir")"
done
check "invalid keep entry" "::error::Invalid keep entry: ../x" "$(publish "$work/v1" DIRECTORY=. KEEP=../x)"

exit "$failed"

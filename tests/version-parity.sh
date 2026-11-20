#!/usr/bin/env bash
# Replays release history: for each vX.Y.Z tag, runs the version step on the commit
# that was built (the parent of the "vX changelog update" commit) with the previous
# tag as LAST_TAG, and compares with the real tag.
# usage: tests/version-parity.sh <clone of an app repo> [number of tags]
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
src=$(cd "$1" && pwd)
count=${2:-150}
script=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/version.yml" version)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone -q --bare --shared "$src" "$work/repo.git"
export GIT_DIR=$work/repo.git

tags=()
while IFS= read -r t; do tags+=("$t"); done < <(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n "$((count + 1))")
same=0
diff=0
for i in $(seq 1 $((${#tags[@]} - 1))); do
  prev=${tags[i - 1]}
  cur=${tags[i]}
  built=$(git rev-list -n1 "$cur")
  if git log -1 --format=%s "$built" | grep -q 'changelog update'; then built=$(git rev-parse "$built^"); fi
  git update-ref --no-deref HEAD "$built"
  got=$(env LAST_TAG="$prev" VERSION= BUMP=patch GITHUB_OUTPUT=/dev/stdout bash -eo pipefail -c "$script" 2>/dev/null | sed -n 's/^tag=//p')
  if [ "$got" = "$cur" ]; then
    same=$((same + 1))
  else
    diff=$((diff + 1))
    echo "DIFF $prev -> real $cur, computed $got ($(git log -1 --format='%h %s' "$built" | cut -c1-80))"
  fi
done
echo "same=$same diff=$diff of $((same + diff))"

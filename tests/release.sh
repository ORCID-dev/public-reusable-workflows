#!/usr/bin/env bash
# Runs the release and slack steps of .github/workflows/release.yml against stub gh and curl commands.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
release=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/release.yml" release)
slack=$(python3 "$root/tests/extract-run.py" "$root/.github/workflows/release.yml" slack)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

# gh: FAKE_TAG_SHA is where the tag points (unset: no tag), FAKE_PREV=1 if the previous tag exists,
# FAKE_RELEASE=1 if the release exists. Release creations are logged.
cat > "$work/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "api repos/o/r/git/ref/tags/"*) [ "${FAKE_PREV:-0}" = 1 ] ;;
  "api repos/o/r/commits/"*)
    # Like the real gh: an unknown tag is a 422 with the error body on stdout and exit status 1.
    if [ -n "${FAKE_TAG_SHA:-}" ]; then echo "$FAKE_TAG_SHA"; else echo "{\"message\":\"No commit found for SHA: ${2##*/}\",\"status\":\"422\"}"; exit 1; fi ;;
  "release view")
    if [ "$4" = --json ]; then echo "https://example.test/releases/$3"; else [ "${FAKE_RELEASE:-0}" = 1 ]; fi ;;
  "release create") shift 2; echo "create $*" >> "$FAKE_LOG" ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
EOF
# curl: saves the --data payload, prints FAKE_RESPONSE, exits with FAKE_CURL_EXIT.
cat > "$work/curl" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = --data ]; then printf '%s' "$2" > "$FAKE_PAYLOAD"; shift; fi
  shift
done
echo "${FAKE_RESPONSE:-}"
exit "${FAKE_CURL_EXIT:-0}"
EOF
chmod +x "$work/gh" "$work/curl"

run() { # run <step script> [VAR=value ...]; prints the step output, then the gh log
  local script=$1
  shift
  : > "$work/log"
  env PATH="$work:$PATH" GH_REPO=o/r TAG=v1.2.3 PREVIOUS=v1.2.2 SHA=abc FAKE_LOG="$work/log" \
    FAKE_PAYLOAD="$work/payload" GITHUB_OUTPUT=/dev/stdout "$@" bash -e -c "$script" 2>&1 || echo "exit $?"
  cat "$work/log"
}

check() { # check <name> <want> <step script> [VAR=value ...]
  local name=$1 want=$2 got
  shift 2
  got=$(run "$@")
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    printf 'FAIL %s\n--- got\n%s\n--- want\n%s\n' "$name" "$got" "$want"
    failed=1
  fi
}

url=https://example.test/releases/v1.2.3
check "new tag" "url=$url
create v1.2.3 --target abc --title v1.2.3 --generate-notes --notes-start-tag v1.2.2" "$release" FAKE_PREV=1
check "first release, no previous tag" "url=$url
create v1.2.3 --target abc --title v1.2.3 --generate-notes" "$release" PREVIOUS=v0.0.0
check "re-run, release exists" "::notice::Release v1.2.3 already exists
url=$url" "$release" FAKE_PREV=1 FAKE_TAG_SHA=abc FAKE_RELEASE=1
check "tag exists, release missing" "url=$url
create v1.2.3 --verify-tag --title v1.2.3 --generate-notes --notes-start-tag v1.2.2" "$release" FAKE_PREV=1 FAKE_TAG_SHA=abc
check "tag on another commit" "::error::v1.2.3 already points to def, not abc
exit 1" "$release" FAKE_TAG_SHA=def
check "invalid tag" "::error::Invalid tag: 1.2.3
exit 1" "$release" TAG=1.2.3

check "slack ok" "" "$slack" CHANNEL=tech-release 'TEXT=o/r v1.2.3 released "quoted"' FAKE_RESPONSE='{"ok": true}'
want='{"channel":"tech-release","text":"o/r v1.2.3 released \"quoted\""}'
if [ "$(jq -c . "$work/payload")" = "$want" ]; then echo "ok   slack payload"; else echo "FAIL slack payload: $(cat "$work/payload")"; failed=1; fi
check "slack api error" "::warning::Slack notification failed: channel_not_found" "$slack" CHANNEL=x TEXT=y \
  FAKE_RESPONSE='{"ok": false, "error": "channel_not_found"}'
check "slack unreachable" "::warning::Slack notification failed: request failed" "$slack" CHANNEL=x TEXT=y FAKE_CURL_EXIT=7

exit "$failed"

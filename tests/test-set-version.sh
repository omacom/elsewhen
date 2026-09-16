#!/usr/bin/env bash
set -euo pipefail

# Exercises scripts/set-version.sh against a disposable copy of the tracked
# tree: bump manifest.json to a throwaway prerelease version, prove
# scripts/check-manifest.sh accepts it, restore the original version, and
# prove the round trip is a byte-for-byte no-op. Then the versions the
# script must refuse. Needs jq and git; nothing else, and no network.

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'test-set-version: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null || fail "jq is required"
command -v git >/dev/null || fail "git is required"

original_version=$(jq -r '.version' "$repo_root/manifest.json")

work_root=$(mktemp -d "${TMPDIR:-/tmp}/elsewhen-set-version-test.XXXXXX")
trap 'rm -rf -- "$work_root"' EXIT

copy="$work_root/copy"
mkdir -p -- "$copy"
(cd "$repo_root" && git ls-files -z | tar --null -T - -cf -) | tar -C "$copy" -xf -

# Snapshot the pristine copy in its own throwaway index, so every "nothing
# else moved" claim below is a plain `git diff --exit-code`.
(cd "$copy" && git init -q && git add -A)

test_version="9.9.9-rc.1"
(cd "$copy" && ./scripts/set-version.sh "$test_version")
(cd "$copy" && ./scripts/check-manifest.sh)

actual=$(jq -r '.version' "$copy/manifest.json")
[[ $actual == "$test_version" ]] \
  || fail "manifest.json .version reads '$actual', expected '$test_version'"

# Surgical: exactly one line of one file changed.
numstat=$(cd "$copy" && git diff --numstat | tr '\t' ' ')
[[ $numstat == "1 1 manifest.json" ]] \
  || fail "expected exactly one changed line in manifest.json, got: ${numstat:-nothing}"

# A second run with the same version is a no-op and says so.
again=$(cd "$copy" && ./scripts/set-version.sh "$test_version")
[[ $again == *"already at $test_version"* ]] \
  || fail "second run with the same version was not reported as a no-op: $again"

(cd "$copy" && ./scripts/set-version.sh "$original_version")

if ! (cd "$copy" && git diff --exit-code >/dev/null); then
  (cd "$copy" && git diff --stat) >&2
  fail "restoring $original_version did not reproduce the original tree byte-for-byte"
fi

# Versions the script must refuse, each leaving the copy untouched: a
# "."-introduced suffix, a leading v, too few components, empty, and a
# dangling "-".
for bad in 1.2.3.rc1 v1.2.3 1.2 "" 1.2.3-; do
  if (cd "$copy" && ./scripts/set-version.sh "$bad" 2>/dev/null); then
    fail "accepted invalid version '$bad'"
  fi
  (cd "$copy" && git diff --exit-code >/dev/null) \
    || fail "rejected '$bad' but changed the tree"
done

printf 'set-version round trip: ok\n'

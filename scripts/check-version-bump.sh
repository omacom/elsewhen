#!/usr/bin/env bash
set -euo pipefail

# Refuses a release version that would not move forward. release.yml runs this
# before it writes anything: the version must be strictly above every existing
# v* tag and not below the version manifest.json already carries. Without it
# a mistyped dispatch (0.4.0 after 1.0.0) would tag, publish, and become the
# repository's "latest" release while main's manifest walked backwards.

usage() {
  cat <<'USAGE'
Usage: scripts/check-version-bump.sh X.Y.Z[-pre]

Exit 0 when the version is strictly greater than every existing v* tag and
not lower than the version in manifest.json; exit 1 otherwise. Reads tags
from the checkout it lives in, so fetch them first.
USAGE
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'check-version-bump: %s\n' "$*" >&2
  exit 1
}

if [[ $# -eq 1 && ($1 == -h || $1 == --help) ]]; then
  usage
  exit 0
fi
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

version=$1
semver_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'
[[ $version =~ $semver_re ]] || fail "not a semantic version: '$version'"

command -v jq >/dev/null || fail "jq is required"
command -v git >/dev/null || fail "git is required"

# GNU sort -V puts "0.2.0-rc.1" after "0.2.0", the opposite of SemVer. The
# Debian convention sorts right: "~" orders before the end of the string, so
# with "-" swapped for "~" a prerelease lands just below its release.
highest() {
  tr -- '-' '~' | sort -V | tail -n 1 | tr -- '~' '-'
}

# Only tags shaped like releases take part; anything else under v* is not a
# version this repository cut.
latest=$(git -C "$repo_root" tag --list 'v*' | sed 's/^v//' | grep -E "$semver_re" | highest || true)
if [[ -n $latest ]]; then
  top=$(printf '%s\n%s\n' "$latest" "$version" | highest)
  [[ $top == "$version" && $version != "$latest" ]] \
    || fail "version $version is not above the latest tag v$latest"
fi

current=$(jq -r '.version' "$repo_root/manifest.json")
top=$(printf '%s\n%s\n' "$current" "$version" | highest)
[[ $top == "$version" ]] \
  || fail "version $version is below the $current that manifest.json already carries"

if [[ -n $latest ]]; then
  printf 'check-version-bump: %s is above v%s and manifest %s\n' "$version" "$latest" "$current"
else
  printf 'check-version-bump: %s is the first release (manifest %s)\n' "$version" "$current"
fi

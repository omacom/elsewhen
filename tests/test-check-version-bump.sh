#!/usr/bin/env bash
set -euo pipefail

# Exercises scripts/check-version-bump.sh against a disposable copy of the
# tracked tree with tags of our own making: releases, prereleases, and a
# manifest ahead of the tags. Needs jq and git; no network.

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'test-check-version-bump: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null || fail "jq is required"
command -v git >/dev/null || fail "git is required"

work_root=$(mktemp -d "${TMPDIR:-/tmp}/elsewhen-version-bump-test.XXXXXX")
trap 'rm -rf -- "$work_root"' EXIT

copy="$work_root/copy"
mkdir -p -- "$copy"
(cd "$repo_root" && git ls-files -z | tar --null -T - -cf -) | tar -C "$copy" -xf -
(
  cd "$copy"
  git init -q
  git -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m "root"
)

accepts() {
  local version="$1" why="$2"
  (cd "$copy" && ./scripts/check-version-bump.sh "$version" >/dev/null 2>&1) \
    || fail "refused $version: $why"
}

refuses() {
  local version="$1" why="$2"
  if (cd "$copy" && ./scripts/check-version-bump.sh "$version" >/dev/null 2>&1); then
    fail "accepted $version: $why"
  fi
}

set_manifest() {
  (cd "$copy" && ./scripts/set-version.sh "$1" >/dev/null)
}

# No tags yet: anything at or above the manifest is the first release.
set_manifest 0.1.0
accepts 0.1.0 "the first release may equal the manifest"
accepts 0.2.0 "the first release may be above the manifest"
refuses 0.0.9 "the first release may not be below the manifest"
refuses v0.2.0 "a leading v is not a version"
refuses 0.2 "two components are not a version"

# Tags exist: the version must be strictly above the highest release-shaped
# one, whatever order the tags were created in, and odd v* tags are ignored.
(cd "$copy" && git tag v0.2.0 && git tag v0.1.0 && git tag v0.2.0-rc.1 && git tag vendor-drop)
accepts 0.2.1 "a patch above the latest tag"
accepts 0.3.0-rc.1 "a prerelease above the latest tag"
accepts 0.10.0 "a numeric, not lexical, comparison"
refuses 0.2.0 "the latest tag itself"
refuses 0.2.0-rc.2 "a prerelease of an already released version"
refuses 0.1.5 "below the latest tag"

# A prerelease tag on top: its release and later prereleases go forward, the
# earlier ones do not.
(cd "$copy" && git tag v0.3.0-rc.1)
accepts 0.3.0 "the release of the latest prerelease"
accepts 0.3.0-rc.2 "a later prerelease"
refuses 0.3.0-rc.1 "the latest prerelease itself"
refuses 0.2.5 "below the latest prerelease"

# The manifest may run ahead of the tags, but a release never pulls it back.
set_manifest 0.4.0
accepts 0.4.0 "the manifest's own version"
accepts 0.5.0 "above the manifest"
refuses 0.3.5 "below the manifest even though above the tags"

printf 'check-version-bump: ok\n'

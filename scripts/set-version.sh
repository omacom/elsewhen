#!/usr/bin/env bash
set -euo pipefail

# Sets the Elsewhen release version. manifest.json is the only version pin in
# this repository: `git grep -n '"version"'` finds nothing else (no
# package.json, no lockfile, no version constant in the QML or JS), so there
# is exactly one line to rewrite. Idempotent: a second run with the same
# version changes nothing. Runs entirely offline.

usage() {
  cat <<'USAGE'
Usage: scripts/set-version.sh X.Y.Z[-pre]

Rewrite the "version" field of manifest.json to the given semantic version
(no leading v). Idempotent: running it again with the same version leaves the
tree unchanged. Runs entirely offline.
USAGE
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/manifest.json"

fail() {
  printf 'set-version: %s\n' "$*" >&2
  exit 1
}

if [[ $# -eq 1 && ($1 == -h || $1 == --help) ]]; then
  usage
  exit 0
fi
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

version=$1
# SemVer-style: major.minor.patch with an optional "-"-introduced pre-release
# suffix. No leading "v", no "."-introduced suffix and no build metadata, so
# release.yml's `*-*` prerelease test (and omarchy-pkgs' "latest
# non-prerelease" lookup) can't be fooled by a version like "1.2.3.rc1".
semver_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'
[[ $version =~ $semver_re ]] || fail "not a semantic version: '$version' (want X.Y.Z or X.Y.Z-pre, no leading v)"

command -v jq >/dev/null || fail "jq is required"
[[ -f "$manifest" ]] || fail "missing manifest.json"
jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"

current=$(jq -r '.version' "$manifest")
if [[ $current == "$version" ]]; then
  printf 'set-version: already at %s (no changes)\n' "$version"
  exit 0
fi

# manifest.json is hand-formatted (two-space indent, one array element per
# line); `jq` would reflow it, so the one "version" line is patched with sed
# rather than rewriting the whole document. Refuse if that line is not
# unique, so a "version" key added deeper in the schema can never be hit.
pins=$(grep -c -E '^[[:space:]]*"version": "[^"]*",?$' "$manifest" || true)
[[ $pins == 1 ]] || fail "expected exactly one \"version\" line in manifest.json, found $pins"
sed -E -i 's/^([[:space:]]*"version": ")[^"]*(",?)$/\1'"$version"'\2/' "$manifest"

jq -e . "$manifest" >/dev/null || fail "manifest.json does not parse after the edit"
[[ $(jq -r '.version' "$manifest") == "$version" ]] \
  || fail "failed to update the version in manifest.json"

printf 'set-version: set version to %s (was %s)\n' "$version" "$current"
printf '  updated manifest.json\n'

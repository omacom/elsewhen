#!/usr/bin/env bash
set -euo pipefail

# The same checks `omarchy plugin validate` runs: schema version, required
# fields, a well-formed id outside the reserved namespace, entry points that
# are safe relative paths and exist, and no symlinks in the tree. CI runs
# this on every push; release.yml runs it before it tags and again before it
# publishes. Runs from any directory.

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo_root"

fail() {
  printf 'check-manifest: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null || fail "jq is required"
jq -e . manifest.json >/dev/null || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' manifest.json
for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' manifest.json >/dev/null
done
jq -e '.id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")' manifest.json
jq -e '.id | (startswith("omarchy.") | not) and (contains("..") | not)' manifest.json
jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' manifest.json
jq -e '(.entryPoints | type) == "object"' manifest.json
jq -e '.barWidget.defaultSection as $s | $s == null or (["left","center","right"] | index($s)) != null' manifest.json
jq -r '.entryPoints[]' manifest.json | while IFS= read -r ep; do
  case "$ep" in
    /*|*..*) echo "unsafe entry point: $ep"; exit 1 ;;
  esac
  test -f "$ep" || { echo "missing entry point: $ep"; exit 1; }
done
for kind in bar bar-widget menu overlay panel service; do
  jq -e --arg k "$kind" '(.kinds | index($k)) == null' manifest.json >/dev/null && continue
  key="$kind"; [[ $kind == bar-widget ]] && key=barWidget
  jq -e --arg k "$key" '.entryPoints | has($k)' manifest.json >/dev/null \
    || { echo "kind '$kind' has no entryPoints.$key"; exit 1; }
done
link=$(find . -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || { echo "symlink in plugin tree: $link"; exit 1; }

# manifest.json is the release version (see scripts/set-version.sh); this
# checks its shape, not a value. SemVer-style only: X.Y.Z with an optional
# "-"-introduced pre-release suffix, no "."-introduced suffix and no build
# metadata, so release.yml's `*-*` prerelease test can't be fooled by a
# version like "1.2.3.rc1".
jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$")' manifest.json >/dev/null \
  || fail "manifest version is not a semantic version: $(jq -r '.version' manifest.json)"

printf 'check-manifest: ok\n'

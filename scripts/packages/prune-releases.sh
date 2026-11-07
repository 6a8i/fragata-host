#!/bin/sh
# Deletes the package releases of a version that no channel uses any more: each build of a channel publishes its
# packages in a release of its own (packages-<version>-<build>, at most 1000 files in a release on GitHub), the
# channels name theirs in release.txt (none: the first release, packages-<version>).
#
# usage: prune-releases.sh <owner/repository> <version, e.g. 8.3> <gh-pages checkout>
# needs: gh (authenticated)
set -eu
REPO=$1
VERSION=$2
SITE=$3
used=$(for channel in "$VERSION" "$VERSION-testing"; do
  [ -d "$SITE/$channel" ] || continue
  cat "$SITE/$channel/release.txt" 2>/dev/null || echo "packages-$VERSION"
done | sort -u)
gh release list -R "$REPO" --json tagName --jq '.[].tagName' | grep -x "packages-$VERSION\(-.*\)\?" | while read -r tag; do
  printf '%s\n' "$used" | grep -qxF "$tag" && continue
  # its files first: GitHub fails (HTTP 502) to delete a release of hundreds of files at once
  id=$(gh api "repos/$REPO/releases/tags/$tag" --jq .id)
  gh api --paginate "repos/$REPO/releases/$id/assets?per_page=100" --jq '.[].id' | while read -r asset; do
    gh api -X DELETE "repos/$REPO/releases/assets/$asset" >/dev/null
  done
  gh release delete "$tag" -R "$REPO" --cleanup-tag --yes
  echo "deleted the release $tag"
done

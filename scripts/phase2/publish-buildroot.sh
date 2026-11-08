#!/bin/sh
# Publishes the buildroot repository of Fragata Host on GitHub: the rebuilt packages the channel does not ship
# (development packages, build tools, the other subpackages of its source packages), which the builds of the
# channel in CI install their build dependencies from, next to the channel itself.
# - the packages as assets of the release `buildroot-<version>` (unsigned: a repository for builds only, read over
#   HTTPS from GitHub; a release holds at most 1000 files);
# - the metadata on the `gh-pages` branch, under buildroot-<version>/x86_64/ (the channel: <version>/x86_64/).
# A published file keeps its content: a package already published is skipped (and described by the metadata with
# the new ones, so a run may bring only the new packages).
#
# usage: publish-buildroot.sh <rebuilt RPMs dir, flat> <rebuilt.txt of the channel> <owner/repository> <version>
#   rebuilt.txt: the packages of the channel taken from their rebuild (their files, named .fragata.rpm): the
#     buildroot repository has the others
# needs: gh (authenticated), git, createrepo_c (or createrepo); GH_TOKEN, when set, authenticates the push (CI)
set -eu
RPMS=$(cd "$1" && pwd)
CHANNEL_REBUILT=$2
REPO=$3
VERSION=$4
TAG=buildroot-$VERSION
REMOTE=https://${GH_TOKEN:+x-access-token:$GH_TOKEN@}github.com/$REPO.git
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# the packages of the buildroot: the rebuilt packages the channel does not ship (same asset naming as the channel)
mkdir "$WORK/packages"
sed 's/\.fragata\.rpm$/.rpm/' "$CHANNEL_REBUILT" | sort >"$WORK/channel.txt"
for file in "$RPMS"/*.rpm; do
  name=$(basename "$file" | sed -e 's/[^A-Za-z0-9._-]/./g' -e 's/\.\.*/./g')
  case $name in *.src.rpm | *-debuginfo-*) continue ;; esac
  grep -qxF "$name" "$WORK/channel.txt" || ln -s "$file" "$WORK/packages/$name"
done
count=$(ls "$WORK/packages" | wc -l)
[ "$count" -le 1000 ] || { echo "$count packages: a release holds at most 1000 files" >&2; exit 1; }

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 ||
  gh release create "$TAG" -R "$REPO" --title "Fragata Host $VERSION buildroot" \
    --notes "Packages rebuilt from their sources that the Fragata Host $VERSION repositories do not ship: the build dependencies of the builds of the channel. Use the buildroot repository, not these files directly."
RELEASE_ID=$(gh api "repos/$REPO/releases/tags/$TAG" --jq .id)
existing=$(gh api --paginate "repos/$REPO/releases/$RELEASE_ID/assets?per_page=100" --jq '.[].name')
new=0
for link in "$WORK/packages"/*.rpm; do
  name=$(basename "$link")
  printf '%s\n' "$existing" | grep -qxF "$name" && continue
  # the asset takes the name of the link, not of its target: a copy
  cp "$(readlink "$link")" "$WORK/$name"
  gh release upload "$TAG" -R "$REPO" "$WORK/$name"
  rm -f "$WORK/$name"
  new=$((new + 1))
done
echo "$new packages uploaded"
# the metadata describe every package of the release: those published before (by a run given only the new
# packages, e.g. CI) are downloaded for them
URL=https://github.com/$REPO/releases/download/$TAG/
mkdir "$WORK/repo"
mkdir "$WORK/published"
printf '%s\n' "$existing" | while read -r name; do
  [ -n "$name" ] && [ ! -e "$WORK/packages/$name" ] || continue
  curl -sfL -o "$WORK/published/$name" "$URL$name"
  ln -s "$WORK/published/$name" "$WORK/packages/$name"
done
echo "$(ls "$WORK/packages" | wc -l) packages in the buildroot"

# metadata: the packages are downloaded from the release
if command -v createrepo_c >/dev/null; then createrepo_c -q --baseurl "$URL" --outputdir "$WORK/repo" "$WORK/packages"
else createrepo -q --baseurl "$URL" --outputdir "$WORK/repo" "$WORK/packages"; fi
git clone -q --depth 1 -b gh-pages "$REMOTE" "$WORK/site"
mkdir -p "$WORK/site/$TAG/x86_64"
rm -rf "$WORK/site/$TAG/x86_64/repodata"
cp -r "$WORK/repo/repodata" "$WORK/site/$TAG/x86_64/"
git -C "$WORK/site" add -A
git -C "$WORK/site" -c user.name="Fragata Host" -c user.email="fragata-host@users.noreply.github.com" \
  commit -q -m "Repository metadata of the buildroot of $VERSION" || echo "metadata unchanged"
git -C "$WORK/site" push -q origin gh-pages
echo "published: https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/$TAG/x86_64/"

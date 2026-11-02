#!/bin/sh
# Publishes the Fragata Host package repository made by build-repo.sh on GitHub:
# - the packages as assets of the release `packages-<version>` of the updates repository (only the new ones are
#   uploaded);
# - the metadata and the public key on its `gh-pages` branch, served by GitHub Pages under <version>/x86_64/.
#
# usage: publish-repo.sh <build-repo output dir> <owner/repository> <version, e.g. 8.3> [testing]
# needs: gh (authenticated), git
set -eu
SRC=$(cd "$1" && pwd)
REPO=$2
VERSION=$3
CHANNEL=$VERSION${4:+-$4}
TAG=packages-$CHANNEL

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 ||
  gh release create "$TAG" -R "$REPO" --title "Fragata Host $CHANNEL packages" \
    --notes "Signed packages of the Fragata Host $CHANNEL repository. Use the repository, not these files directly."

existing=$(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name')
new=0
for file in "$SRC"/packages/*.rpm; do
  name=$(basename "$file")
  if ! printf '%s\n' "$existing" | grep -qxF "$name"; then
    gh release upload "$TAG" -R "$REPO" "$file"
    new=$((new + 1))
  fi
done
echo "$new packages uploaded"
# the metadata point at the file names: every package must be an asset of that name
existing=$(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name')
for file in "$SRC"/packages/*.rpm; do
  printf '%s\n' "$existing" | grep -qxF "$(basename "$file")" || { echo "missing asset: $(basename "$file")" >&2; exit 1; }
done

# metadata on GitHub Pages
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if ! git clone -q --depth 1 -b gh-pages "https://github.com/$REPO.git" "$WORK/site" 2>/dev/null; then
  git init -q -b gh-pages "$WORK/site"
  git -C "$WORK/site" remote add origin "https://github.com/$REPO.git"
fi
mkdir -p "$WORK/site/$CHANNEL/x86_64"
rm -rf "$WORK/site/$CHANNEL/x86_64/repodata"
cp -r "$SRC/repo/repodata" "$WORK/site/$CHANNEL/x86_64/"
cp "$SRC/repo/RPM-GPG-KEY-fragata" "$WORK/site/"
touch "$WORK/site/.nojekyll"
cat >"$WORK/site/index.html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<title>Fragata Host updates</title>
<h1>Fragata Host updates</h1>
<p>Package repositories of Fragata Host, used by the hosts through <code>/etc/yum.repos.d/fragata.repo</code>.</p>
<p>Packages and metadata are signed by the <a href="RPM-GPG-KEY-fragata">Fragata Host key</a>.</p>
EOF
git -C "$WORK/site" add -A
git -C "$WORK/site" -c user.name="Fragata Host" -c user.email="fragata-host@users.noreply.github.com" \
  commit -q -m "Repository metadata of $CHANNEL" || echo "metadata unchanged"
git -C "$WORK/site" push -q origin gh-pages

gh api "repos/$REPO/pages" >/dev/null 2>&1 ||
  gh api -X POST "repos/$REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null
echo "published: https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/$CHANNEL/x86_64/"

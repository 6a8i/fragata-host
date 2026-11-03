#!/bin/sh
# Publishes the Fragata Host package repository made by build-repo.sh on GitHub:
# - the packages as assets of the release `packages-<version>` of the updates repository (only the new ones are
#   uploaded), shared by the channels of the version: a package keeps its name, a new version has a new name;
# - the metadata, the selection and the manifest of the signed packages (what the next update starts from) and the
#   public key on its `gh-pages` branch, served by GitHub Pages under <channel>/x86_64/.
#
# usage: publish-repo.sh <build-repo output dir> <owner/repository> <version, e.g. 8.3> [testing]
#   testing: the channel <version>-testing (repository fragata-testing of the hosts), promoted with promote-channel.sh
# needs: gh (authenticated), git; GH_TOKEN, when set, also authenticates the push of gh-pages (CI)
set -eu
SRC=$(cd "$1" && pwd)
REPO=$2
VERSION=$3
CHANNEL=$VERSION${4:+-$4}
TAG=packages-$VERSION
REMOTE=https://${GH_TOKEN:+x-access-token:$GH_TOKEN@}github.com/$REPO.git

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 ||
  gh release create "$TAG" -R "$REPO" --title "Fragata Host $VERSION packages" \
    --notes "Signed packages of the Fragata Host $VERSION repositories. Use the repositories, not these files directly."

# assets: "<name> sha256:<digest>"
RELEASE_ID=$(gh api "repos/$REPO/releases/tags/$TAG" --jq .id)
assets() { gh api --paginate "repos/$REPO/releases/$RELEASE_ID/assets?per_page=100" --jq '.[] | .name + " " + .digest'; }
existing=$(assets)
new=0
for file in "$SRC"/packages/*.rpm; do
  name=$(basename "$file")
  # a package rebuilt or signed again keeps its name: its asset is replaced
  if ! printf '%s\n' "$existing" | grep -qxF "$name sha256:$(sha256sum "$file" | cut -d' ' -f1)"; then
    gh release upload --clobber "$TAG" -R "$REPO" "$file"
    new=$((new + 1))
  fi
done
echo "$new packages uploaded"
# the metadata point at the file names and checksums: every package must be an asset of that name and content
existing=$(assets)
for file in "$SRC"/packages/*.rpm; do
  name=$(basename "$file")
  printf '%s\n' "$existing" | grep -qxF "$name sha256:$(sha256sum "$file" | cut -d' ' -f1)" ||
    { echo "missing or different asset: $name" >&2; exit 1; }
done

# metadata on GitHub Pages
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if ! git clone -q --depth 1 -b gh-pages "$REMOTE" "$WORK/site" 2>/dev/null; then
  git init -q -b gh-pages "$WORK/site"
  git -C "$WORK/site" remote add origin "$REMOTE"
fi
mkdir -p "$WORK/site/$CHANNEL/x86_64"
rm -rf "$WORK/site/$CHANNEL/x86_64/repodata"
cp -r "$SRC/repo/repodata" "$WORK/site/$CHANNEL/x86_64/"
for state in selection.tsv signed.tsv own.txt; do
  [ ! -f "$SRC/$state" ] || cp "$SRC/$state" "$WORK/site/$CHANNEL/"
done
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
  gh api -X POST "repos/$REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 ||
  true # GitHub may enable Pages by itself on the first push of gh-pages
echo "published: https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/$CHANNEL/x86_64/"

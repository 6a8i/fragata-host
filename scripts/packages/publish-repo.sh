#!/bin/sh
# Publishes the Fragata Host package repository made by build-repo.sh on GitHub:
# - the packages as assets of the release of this build, `packages-<version>-<build>` (release.txt of the build,
#   the metadata point there; a release holds at most 1000 files on GitHub, so each build has its own), then the
#   releases no channel uses any more are deleted (prune-releases.sh);
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
TAG=$(cat "$SRC/release.txt")
REMOTE=https://${GH_TOKEN:+x-access-token:$GH_TOKEN@}github.com/$REPO.git
case $TAG in packages-$VERSION-?*) ;; *) echo "the build is for the release $TAG, not packages-$VERSION-<build>" >&2; exit 1 ;; esac

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 ||
  gh release create "$TAG" -R "$REPO" --title "Fragata Host $VERSION packages, build ${TAG#packages-$VERSION-}" \
    --notes "Signed packages of the Fragata Host $VERSION repositories. Use the repositories, not these files directly."

# assets: "<name> sha256:<digest>"
RELEASE_ID=$(gh api "repos/$REPO/releases/tags/$TAG" --jq .id)
assets() { gh api --paginate "repos/$REPO/releases/$RELEASE_ID/assets?per_page=100" --jq '.[] | .name + " " + .digest'; }
existing=$(assets)
new=0
for file in "$SRC"/packages/*.rpm; do
  name=$(basename "$file")
  if ! printf '%s\n' "$existing" | grep -qxF "$name sha256:$(sha256sum "$file" | cut -d' ' -f1)"; then
    # a published file keeps its content: another one would break a channel whose metadata describe the published
    # one (REPLACE_ASSETS=1 to replace it anyway, e.g. to put a published file back)
    if printf '%s\n' "$existing" | grep -q "^$name " && [ "${REPLACE_ASSETS:-}" != 1 ]; then
      echo "$name is published with another content: a published file keeps its content" >&2
      exit 1
    fi
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
for state in release.txt selection.tsv signed.tsv own.txt rebuilt.txt; do
  rm -f "$WORK/site/$CHANNEL/$state"
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
# the releases of the builds the channels no longer use
sh "$(dirname "$0")/prune-releases.sh" "$REPO" "$VERSION" "$WORK/site"

gh api "repos/$REPO/pages" >/dev/null 2>&1 ||
  gh api -X POST "repos/$REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 ||
  true # GitHub may enable Pages by itself on the first push of gh-pages
echo "published: https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/$CHANNEL/x86_64/"

#!/bin/sh
# Promotes the testing channel of a version to its stable channel: the metadata of <version>-testing (and the
# selection and manifest it was made from) become those of <version>. The packages are shared by the two channels
# (release packages-<version>), only the metadata are copied.
#
# usage: promote-channel.sh <owner/repository> <version, e.g. 8.3>
# needs: git; GH_TOKEN, when set, authenticates the push of gh-pages (CI)
set -eu
REPO=$1
VERSION=$2
REMOTE=https://${GH_TOKEN:+x-access-token:$GH_TOKEN@}github.com/$REPO.git
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone -q --depth 1 -b gh-pages "$REMOTE" "$WORK/site"
cd "$WORK/site"
[ -f "$VERSION-testing/x86_64/repodata/repomd.xml.asc" ] || { echo "no testing channel for $VERSION" >&2; exit 1; }
if cmp -s "$VERSION-testing/x86_64/repodata/repomd.xml" "$VERSION/x86_64/repodata/repomd.xml"; then
  echo "$VERSION is already $VERSION-testing"
  exit 0
fi
mkdir -p "$VERSION/x86_64"
rm -rf "$VERSION/x86_64/repodata"
cp -r "$VERSION-testing/x86_64/repodata" "$VERSION/x86_64/"
for state in selection.tsv signed.tsv own.txt; do
  [ ! -f "$VERSION-testing/$state" ] || cp "$VERSION-testing/$state" "$VERSION/"
done
git add -A
git -c user.name="Fragata Host" -c user.email="fragata-host@users.noreply.github.com" \
  commit -q -m "Promote $VERSION-testing to $VERSION"
git push -q origin gh-pages
echo "promoted: https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/$VERSION/x86_64/"

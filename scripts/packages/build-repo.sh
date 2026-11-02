#!/bin/sh
# Builds the Fragata Host package repository, inside the XCP-ng 8.3 build environment:
# - downloads the selected upstream packages (select-packages.py), checking their checksum and their
#   upstream signature;
# - replaces the release packages of XCP-ng by the Fragata ones;
# - signs every package and the repository metadata with the Fragata Host key.
#
# usage (in the container): build-repo.sh <selection TSV> <Fragata RPMs dir> <key dir> <output dir> <packages URL>
#   key dir: RPM-GPG-KEY-fragata, fragata-signing.secret.asc, passphrase.txt
#   packages URL: where the packages are downloaded from (the metadata point there)
# output: <output>/upstream (downloads), <output>/packages/*.rpm (signed), <output>/repo/repodata (repomd.xml signed in repomd.xml.asc)
set -eu
SELECTION=$1
OWN=$2
KEYS=$3
OUT=$4
PACKAGES_URL=$5
UPSTREAM=https://updates.xcp-ng.org/8/8.3

yum -q -y install rpm-sign createrepo expect >/dev/null

mkdir -p "$OUT/upstream" "$OUT/packages" "$OUT/repo"
export GNUPGHOME=$(mktemp -d)
gpg2 --batch -q --import "$KEYS/fragata-signing.secret.asc"
FPR=$(gpg2 --list-secret-keys --with-colons --with-fingerprint | awk -F: '/^fpr/ {print $10; exit}')

# upstream packages: checksum of the metadata, then signature of XCP-ng
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-xcpng
XCPNG_KEY=3fd3ac9e
# packages built by Fragata replace the upstream ones of the same name
OWN_NAMES=$(for f in "$OWN"/*.rpm; do rpm -qp --qf '%{NAME}\n' "$f" 2>/dev/null; done | sort -u)
is_own() { printf '%s\n' "$OWN_NAMES" | grep -qxF "$1"; }
while IFS="$(printf '\t')" read -r name repo location size sha; do
  case $name in xcp-ng-release | xcp-ng-release-*) continue ;; esac
  is_own "$name" && continue
  file="$OUT/upstream/$(basename "$location")"
  if [ ! -f "$file" ] || ! echo "$sha  $file" | sha256sum -c --status; then
    curl -sfL -o "$file" "$UPSTREAM/$repo/x86_64/$location"
    echo "$sha  $file" | sha256sum -c --status || { echo "checksum mismatch: $location" >&2; exit 1; }
    rpm -Kv "$file" | grep -q "key ID $XCPNG_KEY: OK" || { echo "not signed by XCP-ng: $location" >&2; exit 1; }
  fi
done <"$SELECTION"

# signed copies: the downloads are kept unsigned, a later run only downloads what changed
rm -f "$OUT"/packages/*.rpm
cut -f1,3 "$SELECTION" | while IFS="$(printf '\t')" read -r name location; do
  case $name in xcp-ng-release | xcp-ng-release-*) continue ;; esac
  is_own "$name" && continue
  cp "$OUT/upstream/$(basename "$location")" "$OUT/packages/"
done

# Fragata packages
cp "$OWN"/*.x86_64.rpm "$OWN"/*.noarch.rpm "$OUT/packages/" 2>/dev/null || true

# signatures
sh "$(dirname "$0")/sign-rpms.sh" "$KEYS" "$OUT"/packages/*.rpm

# metadata: the packages are downloaded from PACKAGES_URL
rm -rf "$OUT/repo/repodata"
createrepo -q --baseurl "$PACKAGES_URL" --outputdir "$OUT/repo" "$OUT/packages"
gpg2 --batch -q --yes --passphrase-file "$KEYS/passphrase.txt" -u "$FPR" --armor --detach-sign "$OUT/repo/repodata/repomd.xml"
cp "$KEYS/RPM-GPG-KEY-fragata" "$OUT/repo/"
rm -rf "$GNUPGHOME"

echo "$(ls "$OUT"/packages/*.rpm | wc -l) packages, $(du -sh "$OUT/packages" | cut -f1)"

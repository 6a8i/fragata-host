#!/bin/sh
# Builds the Fragata Host installation ISO from the XCP-ng 8.3 ISO, with the Fragata Host brand in the boot
# menus, the installer and the identity written on the installed host.
#
# With a package directory and a key directory, the ISO installs the packages of the Fragata Host repository
# (scripts/packages/build-repo.sh), signed by the Fragata Host key, instead of the upstream ones: the installed
# host then only uses the Fragata Host update channel.
#
# usage (as root, on Linux): build-iso.sh <upstream ISO> <output ISO> [<signed packages dir> <key dir>]
#   key dir: RPM-GPG-KEY-fragata, fragata-signing.secret.asc, passphrase.txt
# needs: xorriso cpio bzip2 python3, and createrepo_c gpg with packages
set -eu

UPSTREAM=$1
OUTPUT=$2
PACKAGES=${3:-}
KEYS=${4:-}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

VERSION=$(xorriso -osirrox on -indev "$UPSTREAM" -extract /.treeinfo "$WORK/treeinfo.orig" >/dev/null 2>&1 &&
  sed -n 's/^version = \([0-9.]*\)$/\1/p' "$WORK/treeinfo.orig" | tail -1)
echo "upstream version: $VERSION"

# identity of the product, read by the installer and written in the inventory of the installed host
sed \
  -e '/^\[branding\]/,/^\[/ s/^name = .*/name = Fragata Host/' \
  -e '/^\[system-v1\]/,/^\[/ s/^product_name = .*/product_name = Fragata Host/' \
  -e '/^\[general\]/,/^\[/ s/^name = .*/name = Fragata-Host-'"$VERSION"'/' \
  -e '/^\[general\]/,/^\[/ s/^family = .*/family = Fragata Host/' \
  "$WORK/treeinfo.orig" >"$WORK/treeinfo"

# boot menus: text only, the splash image carries the upstream logo
xorriso -osirrox on -indev "$UPSTREAM" \
  -extract /boot/isolinux/pg_main "$WORK/pg_main" \
  -extract /boot/isolinux/pg_help "$WORK/pg_help" \
  -extract /install.img "$WORK/install.img.orig" >/dev/null 2>&1
for f in pg_main pg_help; do
  sed -i -e '/^splash\.lss/d' -e 's/Welcome to XCP-ng/Welcome to Fragata Host/' "$WORK/$f"
done

# installer: brand of its screens and of the values it writes on the host
mkdir "$WORK/installimg"
(cd "$WORK/installimg" && bzcat ../install.img.orig | cpio -idm --quiet)
python3 "$HERE/brand-installer.py" "$WORK/installimg/opt/xensource/installer/version.py"
# with the Fragata Host packages, the installer imports the keys of the Fragata Host channel
[ -z "$PACKAGES" ] || python3 "$HERE/channel-installer.py" "$WORK/installimg/opt/xensource/installer/backend.py"
(cd "$WORK/installimg" && find . | cpio -o -H newc --quiet | bzip2 -9 >"$WORK/install.img")

set -- \
  -map "$WORK/treeinfo" /.treeinfo \
  -map "$WORK/pg_main" /boot/isolinux/pg_main \
  -map "$WORK/pg_help" /boot/isolinux/pg_help \
  -map "$WORK/install.img" /install.img

if [ -n "$PACKAGES" ]; then
  # packages of the Fragata Host repository; the installer checks them with the key named in .treeinfo
  mkdir -p "$WORK/repo/Packages"
  cp "$PACKAGES"/*.rpm "$WORK/repo/Packages/"
  # the yum of the installer (CentOS 7) reads gzip metadata, not zstd
  createrepo_c -q --general-compress-type gz "$WORK/repo"
  export GNUPGHOME="$WORK/gnupg"
  mkdir -m 700 "$GNUPGHOME"
  gpg --batch -q --import "$KEYS/fragata-signing.secret.asc"
  gpg --batch -q --yes --pinentry-mode loopback --passphrase-file "$KEYS/passphrase.txt" \
    --armor --detach-sign "$WORK/repo/repodata/repomd.xml"
  sed -i '/^\[keys\]/,/^\[/ s/^key1 = .*/key1 = RPM-GPG-KEY-fragata/' "$WORK/treeinfo"
  set -- "$@" \
    -rm_r /Packages /repodata /RPM-GPG-KEY-xcpng -- \
    -map "$WORK/repo/Packages" /Packages \
    -map "$WORK/repo/repodata" /repodata \
    -map "$KEYS/RPM-GPG-KEY-fragata" /RPM-GPG-KEY-fragata
fi

rm -f "$OUTPUT"
xorriso -indev "$UPSTREAM" -outdev "$OUTPUT" -boot_image any replay \
  -volid "FRAGATA HOST $VERSION" "$@" 2>&1 | tail -1

sha256sum "$OUTPUT" >"$OUTPUT.sha256"
cat "$OUTPUT.sha256"

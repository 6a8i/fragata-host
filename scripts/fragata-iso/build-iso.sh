#!/bin/sh
# Builds the Fragata Host installation ISO from the XCP-ng 8.3 ISO: same packages, update channel and signing keys,
# with the Fragata Host brand in the boot menus, the installer and the identity written on the installed host.
#
# usage (as root, on Linux): build-iso.sh <upstream ISO> <output ISO>
# needs: xorriso cpio bzip2
set -eu

UPSTREAM=$1
OUTPUT=$2
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
(cd "$WORK/installimg" && find . | cpio -o -H newc --quiet | bzip2 -9 >"$WORK/install.img")

rm -f "$OUTPUT"
xorriso -indev "$UPSTREAM" -outdev "$OUTPUT" -boot_image any replay \
  -volid "FRAGATA HOST $VERSION" \
  -map "$WORK/treeinfo" /.treeinfo \
  -map "$WORK/pg_main" /boot/isolinux/pg_main \
  -map "$WORK/pg_help" /boot/isolinux/pg_help \
  -map "$WORK/install.img" /install.img 2>&1 | tail -1

sha256sum "$OUTPUT" >"$OUTPUT.sha256"
cat "$OUTPUT.sha256"

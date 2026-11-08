#!/bin/sh
# Builds python2-xapi-storage (python2-xapi-storage/SPECS) from the sources of the xapi SRPM of XCP-ng 8.3 that
# shipped it, in the buildroot of Fragata Host: xapi 24.19.2 no longer builds with the current OCaml libraries,
# this library (Python written by the generator of xapi-storage) does.
#
# usage: build-python2-xapi-storage.sh <xapi-24.19.2 SRPM> <output directory>
# needs podman (or docker) and the image fragata-build-env:8.3 (make-buildroot.sh) with its repository (BUILDROOT_RPMS)
set -eu
export MSYS_NO_PATHCONV=1
SRPM=$(cd "$(dirname "$1")" && { pwd -W 2>/dev/null || pwd; })/$(basename "$1")
OUT=$(mkdir -p "$2" && cd "$2" && { pwd -W 2>/dev/null || pwd; })
HERE=$(cd "$(dirname "$0")" && { pwd -W 2>/dev/null || pwd; })
BUILDROOT_RPMS=$(cd "$BUILDROOT_RPMS" && { pwd -W 2>/dev/null || pwd; })
ENGINE=${ENGINE:-podman}
"$ENGINE" run --rm -e TERM=xterm -v "$SRPM:/srpm.rpm:ro" -v "$HERE/python2-xapi-storage:/src:ro" \
  -v "$BUILDROOT_RPMS:/buildroot:ro" -v "$OUT:/out" "${FRAGATA_IMAGE:-fragata-build-env:8.3}" sh -ec '
  rpm -K /srpm.rpm | grep -qi pgp || { echo "the SRPM is not signed"; exit 1; }
  mkdir -p ~/rpmbuild/SPECS ~/rpmbuild/SOURCES
  cp /src/SPECS/*.spec ~/rpmbuild/SPECS/
  (cd ~/rpmbuild/SOURCES && rpm2cpio /srpm.rpm | cpio -idm --quiet "xen-api-*.tar.gz")
  spec=$(ls ~/rpmbuild/SPECS/*.spec)
  sudo yum-builddep -q -y "$spec" >/dev/null
  # the OCaml toolchain of xs-opam-repo sets itself up in profile.d
  for profile in /etc/profile.d/*.sh; do . $profile; done
  rpmbuild -ba "$spec" 2>&1 | tail -15
  cp ~/rpmbuild/RPMS/*/*.rpm ~/rpmbuild/SRPMS/*.rpm /out/
'
ls -1 "$OUT"

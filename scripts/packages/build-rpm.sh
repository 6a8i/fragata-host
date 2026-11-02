#!/bin/sh
# Builds the RPMs of a package repository (SPECS/ and SOURCES/) in the XCP-ng 8.3 build environment.
# usage: build-rpm.sh <package repository> <output directory>
# needs podman (or docker) and the image ghcr.io/xcp-ng/xcp-ng-build-env:8.3
set -eu
SRC=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
ENGINE=${ENGINE:-podman}
"$ENGINE" run --rm -v "$SRC:/src:ro" -v "$OUT:/out" ghcr.io/xcp-ng/xcp-ng-build-env:8.3 sh -ec '
  mkdir -p ~/rpmbuild/SPECS ~/rpmbuild/SOURCES
  cp /src/SPECS/*.spec ~/rpmbuild/SPECS/
  cp /src/SOURCES/* ~/rpmbuild/SOURCES/
  spec=$(ls ~/rpmbuild/SPECS/*.spec)
  sudo yum-builddep -q -y "$spec" >/dev/null
  rpmbuild -ba "$spec" 2>&1 | tail -5
  cp ~/rpmbuild/RPMS/*/*.rpm ~/rpmbuild/SRPMS/*.rpm /out/
'
ls -1 "$OUT"

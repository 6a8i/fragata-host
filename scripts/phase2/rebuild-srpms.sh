#!/bin/sh
# Phase 2 of Fragata Host: rebuilds the SRPMs of the channel (select-sources.py) in the XCP-ng 8.3 build
# environment, one container per SRPM. Each SRPM is checked (checksum, XCP-ng signature) before its build; the
# binaries land in <output>/rpms/<srpm>/, the result of each build in <output>/results.tsv (srpm, status, seconds),
# its log in <output>/logs/. A SRPM already built is skipped, one that failed is built again.
#
# The build environment only has the build dependencies of the XCP-ng packages: the buildroot adds CentOS 7.9 and
# EPEL 7 (archives), below the XCP-ng repositories (yum priorities), when the XCP-ng repositories lack some. The
# metadata of the repositories are downloaded once, in <output>/yumcache.
#
# usage: rebuild-srpms.sh <sources TSV> <output dir> [<binary package name>...]
#   names: only the SRPMs of these binary packages (a pilot); default: every SRPM
#   TIMEOUT: seconds a build may take (default 3600), so a hung test does not stop the rebuild
#   BUILD_CPUS, BUILD_MEMORY: parallel jobs (default 8) and memory (default 8g) of a build: the memory of a VM
#   (podman machine, WSL) grows with the builds, and so does the swap of its host
# needs podman (or docker) and the image ghcr.io/xcp-ng/xcp-ng-build-env:8.3
set -eu
SOURCES=$1
mkdir -p "$2"
OUT_DIR=$(cd "$2" && pwd)
# the directory as the engine sees it: a Windows path from Git Bash
OUT=$(cd "$2" && { pwd -W 2>/dev/null || pwd; })
shift 2
ENGINE=${ENGINE:-podman}
TIMEOUT=${TIMEOUT:-3600}
BUILD_CPUS=${BUILD_CPUS:-8}
BUILD_MEMORY=${BUILD_MEMORY:-8g}
mkdir -p "$OUT_DIR/srpms" "$OUT_DIR/rpms" "$OUT_DIR/logs" "$OUT_DIR/yumcache"
touch "$OUT_DIR/results.tsv"

cat >"$OUT_DIR/buildroot.repo" <<'EOF'
[fragata-buildroot-centos]
name=CentOS 7.9 (build dependencies)
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/os/$basearch/
# its libglvnd conflicts with the older mesa of XCP-ng
exclude=libglvnd*
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=50

[fragata-buildroot-centos-updates]
name=CentOS 7.9 updates (build dependencies)
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/updates/$basearch/
# its libglvnd conflicts with the older mesa of XCP-ng
exclude=libglvnd*
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=50

[fragata-buildroot-centos-extras]
name=CentOS 7.9 extras (build dependencies)
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/extras/$basearch/
# its libglvnd conflicts with the older mesa of XCP-ng
exclude=libglvnd*
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=50

[fragata-buildroot-epel]
name=EPEL 7 (build dependencies)
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
priority=60
EOF

while IFS="$(printf '\t')" read -r srpm repo location size sha binaries; do
  if [ $# -gt 0 ]; then
    wanted=
    for name in "$@"; do
      case ",$binaries," in *",$name,"*) wanted=1 ;; esac
    done
    [ -n "$wanted" ] || continue
  fi
  # exact names: a SRPM name may hold regular expression characters (kernel-alt-4.19.322+1)
  awk -F'\t' -v srpm="$srpm" '$1 == srpm && $2 ~ /^ok(-nocheck)?$/ { found = 1 } END { exit !found }' \
    "$OUT_DIR/results.tsv" && continue
  file="$OUT_DIR/srpms/$srpm"
  if [ ! -f "$file" ] || ! echo "$sha  $file" | sha256sum -c --status; then
    # --ssl-no-revoke: the curl of Windows fails when it cannot reach the revocation servers (no-op elsewhere)
    curl -sfL --ssl-no-revoke -o "$file" "$repo$location" || { printf '%s\tdownload\t0\n' "$srpm" >>"$OUT_DIR/results.tsv"; continue; }
    echo "$sha  $file" | sha256sum -c --status || { printf '%s\tchecksum\t0\n' "$srpm" >>"$OUT_DIR/results.tsv"; continue; }
  fi
  start=$(date +%s)
  rm -rf "$OUT_DIR/rpms/$srpm" && mkdir -p "$OUT_DIR/rpms/$srpm"
  # the CentOS packages regenerate their configure with the autoconf of CentOS 7 (2.69), not the newer one of
  # the XCP-ng updates
  builddep_opts=
  case $srpm in *.el7*) builddep_opts=--setopt=xcp-ng-updates.exclude=autoconf ;; esac
  # Git Bash on Windows: no conversion of the container paths
  if MSYS_NO_PATHCONV=1 "$ENGINE" run --rm --memory "$BUILD_MEMORY" -e RPM_BUILD_NCPUS="$BUILD_CPUS" -v "$OUT:/work" -v "$OUT/yumcache:/var/cache/yum" ghcr.io/xcp-ng/xcp-ng-build-env:8.3 sh -ec "
      rpm -K /work/srpms/$srpm | grep -qi 'pgp' || { echo 'not signed'; exit 1; }
      # the XCP-ng repositories first: the buildroot only for the build dependencies they lack (a failed
      # transaction installs nothing)
      if ! sudo yum-builddep -y $builddep_opts /work/srpms/$srpm; then
        echo 'build dependencies missing from the XCP-ng repositories: adding the buildroot'
        sudo cp /work/buildroot.repo /etc/yum.repos.d/
        sudo yum-builddep -y $builddep_opts /work/srpms/$srpm
      fi
      # build dependencies may set up their tools in profile.d (the OCaml toolchain of xs-opam-repo)
      for profile in /etc/profile.d/*.sh; do . \$profile; done
      if ! timeout $TIMEOUT rpmbuild --rebuild /work/srpms/$srpm; then
        # the tests of some packages depend on the build machine (e.g. file descriptors or IPv6 in a container), or
        # hang there: when the build reached %check, the package is built again without them, and recorded as such
        grep -q 'Executing(%check)' /work/logs/$srpm.log 2>/dev/null || exit 1
        timeout $TIMEOUT rpmbuild --rebuild --nocheck /work/srpms/$srpm
        touch /work/rpms/$srpm/.nocheck
      fi
      # the channel never ships debuginfo packages
      for rpm in ~/rpmbuild/RPMS/*/*.rpm; do
        case \$rpm in *-debuginfo-*) ;; *) cp \$rpm /work/rpms/$srpm/ ;; esac
      done
    " >"$OUT_DIR/logs/$srpm.log" 2>&1; then
    status=ok
    [ ! -f "$OUT_DIR/rpms/$srpm/.nocheck" ] || status=ok-nocheck
  else
    status=failed
  fi
  # the last result of a SRPM replaces the previous ones
  awk -F'\t' -v srpm="$srpm" '$1 != srpm' "$OUT_DIR/results.tsv" >"$OUT_DIR/results.tsv.new"
  printf '%s\t%s\t%s\n' "$srpm" "$status" $(($(date +%s) - start)) >>"$OUT_DIR/results.tsv.new"
  mv "$OUT_DIR/results.tsv.new" "$OUT_DIR/results.tsv"
  echo "$srpm: $status ($(($(date +%s) - start)) s)"
done <"$SOURCES"

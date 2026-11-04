#!/bin/sh
# Phase 2 of Fragata Host: rebuilds the SRPMs of the channel (select-sources.py) in the XCP-ng 8.3 build
# environment, one container per SRPM. Each SRPM is checked (checksum, XCP-ng signature) before its build; the
# binaries land in <output>/rpms/<srpm>/, the result of each build in <output>/results.tsv (srpm, status, seconds),
# its log in <output>/logs/. A SRPM already built is skipped, one that failed is built again.
#
# The packages of XCP-ng build in its build environment, which only has their build dependencies: the buildroot adds
# CentOS 7.9 and EPEL 7 (archives), below the XCP-ng repositories (yum priorities), when the XCP-ng repositories lack
# some. The packages of CentOS 7 build in a clean CentOS 7.9 from the same archives, as CentOS built them. The metadata
# of the repositories are downloaded once, in <output>/yumcache and <output>/yumcache-centos.
#
# usage: rebuild-srpms.sh <sources TSV> <output dir> [<binary package name>...]
#   names: only the SRPMs of these binary packages (a pilot); default: every SRPM
#   TIMEOUT: seconds a build may take (default 3600), so a hung test does not stop the rebuild
#   BUILD_CPUS, BUILD_MEMORY: parallel jobs (default 8) and memory (default 8g) of a build: the memory of a VM
#   (podman machine, WSL) grows with the builds, and so does the swap of its host
# needs podman (or docker), the images ghcr.io/xcp-ng/xcp-ng-build-env:8.3 and quay.io/centos/centos:centos7, and the
# EPEL 7 key in <output>/RPM-GPG-KEY-EPEL-7 (from /etc/pki/rpm-gpg of the build environment)
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

# builds $srpm in a buildroot (centos, xcpng), its output appended to its log
build_in() {
  # the release tag the package of CentOS 7 or EPEL 7 was built with (el7, el7_9, el7.centos)
  dist=$(echo "$srpm" | grep -oE '\.el7(_[0-9]+)?(\.centos)?' | head -1)
  case $1 in
    centos)
      image=quay.io/centos/centos:centos7
      setup="
        rm -f /etc/yum.repos.d/*.repo
        sed '/^exclude=/d' /work/buildroot.repo >/etc/yum.repos.d/buildroot.repo
        cp /work/RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg/
        echo keepcache=1 >>/etc/yum.conf
        # the build group of CentOS 7
        yum install -y bzip2 cpio diffutils findutils gawk gcc gcc-c++ make patch redhat-rpm-config rpm-build sed tar \
          unzip util-linux which xz yum-utils
        # the packages of EPEL build with its macros (python36-...), which yum-builddep needs installed
        if rpm -qp --qf '%{vendor}' /work/srpms/$srpm | grep -q Fedora; then
          yum install -y epel-rpm-macros python3-rpm-macros
        fi
        yum-builddep -y /work/srpms/$srpm"
      cache=yumcache-centos
      rpmbuild_opts="--define 'dist $dist'"
      ;;
    xcpng)
      image=ghcr.io/xcp-ng/xcp-ng-build-env:8.3
      # what the build environment holds differs from the buildroot the package was built in
      fixes=
      case $srpm in
        # autoconf 2.70 and later compile in C11, where the initializer of a mask is not constant
        irqbalance-*) builddep_opts=--setopt=xcp-ng-updates.exclude=autoconf ;;
        # the autoconf of its configure (2.69), gtkdocize, and no C++ library (built when g++ is there)
        gnutls-*) builddep_opts=--setopt=xcp-ng-updates.exclude=autoconf
          fixes='sudo yum install -y gtk-doc && sudo rpm -e --nodeps gcc-c++' ;;
        # a cmocka older than 1.1.3: samba builds and ships its own
        samba-*) builddep_opts=
          fixes='sudo yum downgrade -y libcmocka-1.1.2-1.el7 libcmocka-devel-1.1.2-1.el7' ;;
        # the packages of CentOS regenerate their configure with the autoconf of CentOS 7 (2.69)
        *.el7*) builddep_opts=--setopt=xcp-ng-updates.exclude=autoconf ;;
        *) builddep_opts= ;;
      esac
      setup="
        # the XCP-ng repositories first: the buildroot only for the build dependencies they lack (a failed
        # transaction installs nothing)
        if ! sudo yum-builddep -y $builddep_opts /work/srpms/$srpm; then
          echo 'build dependencies missing from the XCP-ng repositories: adding the buildroot'
          sudo cp /work/buildroot.repo /etc/yum.repos.d/
          sudo yum-builddep -y $builddep_opts /work/srpms/$srpm
        fi
        $fixes
        # the rpm of EL7 cannot generate the build dependencies of the pyproject macros: pip builds the wheel
        if rpm -qp --requires /work/srpms/$srpm | grep -qE '^(pyproject-rpm-macros|python3-wheel)'; then
          sudo yum install -y python3-pip
        fi
        # build dependencies may set up their tools in profile.d (the OCaml toolchain of xs-opam-repo)
        for profile in /etc/profile.d/*.sh; do . \$profile; done"
      cache=yumcache
      # the cmake macros of the build environment build out of the source tree, the specs written for the cmake of
      # EL7 run make in it
      rpmbuild_opts="--define '__cmake_in_source_build 1'"
      [ -z "$dist" ] || rpmbuild_opts="$rpmbuild_opts --define 'dist $dist'"
      ;;
  esac
  mkdir -p "$OUT_DIR/$cache"
  # Git Bash on Windows: no conversion of the container paths
  # the builds run as root (configure of tar, coreutils) without a terminal (ncurses)
  MSYS_NO_PATHCONV=1 "$ENGINE" run --rm --memory "$BUILD_MEMORY" -e RPM_BUILD_NCPUS="$BUILD_CPUS" \
    -e FORCE_UNSAFE_CONFIGURE=1 -e TERM=xterm -v "$OUT:/work" -v "$OUT/$cache:/var/cache/yum" "$image" sh -ec "
      rpm -K /work/srpms/$srpm | grep -qi 'pgp' || { echo 'not signed'; exit 1; }
      $setup
      if ! timeout $TIMEOUT rpmbuild --rebuild $rpmbuild_opts --define '_smp_mflags -j$BUILD_CPUS' /work/srpms/$srpm; then
        # the tests of some packages depend on the build machine (e.g. file descriptors or IPv6 in a container), or
        # hang there: when the build reached %check, the package is built again without them, and recorded as such
        grep -q 'Executing(%check)' /work/logs/$srpm.log 2>/dev/null || exit 1
        timeout $TIMEOUT rpmbuild --rebuild --nocheck $rpmbuild_opts --define '_smp_mflags -j$BUILD_CPUS' /work/srpms/$srpm
        touch /work/rpms/$srpm/.nocheck
      fi
      # the channel never ships debuginfo packages
      for rpm in ~/rpmbuild/RPMS/*/*.rpm; do
        case \$rpm in *-debuginfo-*) ;; *) cp \$rpm /work/rpms/$srpm/ ;; esac
      done
    " >>"$OUT_DIR/logs/$srpm.log" 2>&1 || return 1
  echo "$1" >"$OUT_DIR/rpms/$srpm/.buildroot"
}

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
  : >"$OUT_DIR/logs/$srpm.log"
  # the status of the build, kept apart from set -e
  rc=0
  case $srpm in
    # a package of CentOS 7 or EPEL 7: the channel ships the binary they built, against CentOS 7 (OpenSSL 1.0.2,
    # curl 7.29, the kernel headers of 3.10), so it is built in a clean CentOS 7.9; those it no longer builds with (a
    # package of CentOS 7.5 that needs the bind of its time) build in the XCP-ng build environment, whose base is
    # CentOS 7.5
    *.el7*) { build_in centos || { echo '*** the CentOS 7.9 buildroot failed: the XCP-ng build environment'
      build_in xcpng; }; } >>"$OUT_DIR/logs/$srpm.log" 2>&1 || rc=1 ;;
    *) build_in xcpng || rc=1 ;;
  esac
  if [ $rc -eq 0 ]; then
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

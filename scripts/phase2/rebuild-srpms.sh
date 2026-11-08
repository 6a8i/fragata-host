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
#   BUILD_ENV: xcpng (default) builds the packages of XCP-ng in the XCP-ng 8.3 build environment; fragata in the
#   buildroot of Fragata Host (make-buildroot.sh, image FRAGATA_IMAGE), with the rebuilt packages of BUILDROOT_RPMS
#   (the rpms directory of a previous run, with its repository) instead of the XCP-ng repositories; without
#   BUILDROOT_RPMS, the image reads the published repositories it was made with (BUILDROOT_URLS of make-buildroot.sh)
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
BUILD_ENV=${BUILD_ENV:-xcpng}
FRAGATA_IMAGE=${FRAGATA_IMAGE:-fragata-build-env:8.3}
if [ "$BUILD_ENV" = fragata ] && [ -n "${BUILDROOT_RPMS:-}" ]; then
  # the rebuilt packages with their repository (make-buildroot.sh), as the engine sees them
  BUILDROOT_RPMS=$(cd "$BUILDROOT_RPMS" && { pwd -W 2>/dev/null || pwd; })
fi
mkdir -p "$OUT_DIR/srpms" "$OUT_DIR/rpms" "$OUT_DIR/logs" "$OUT_DIR/yumcache"
touch "$OUT_DIR/results.tsv"

# the repositories of the buildroot, as the builds and the image (make-buildroot.sh) read them
cp "$(cd "$(dirname "$0")" && pwd)/buildroot.repo" "$OUT_DIR/buildroot.repo"

# builds $srpm in a buildroot (centos, xcpng), its output appended to its log
build_in() {
  # the release tag the package of CentOS 7 or EPEL 7 was built with (el7, el7_9, el7.centos)
  dist=$(echo "$srpm" | grep -oE '\.el7(_[0-9]+)?(\.centos)?' | head -1)
  # the C++ of dyninst and the profiled bootstrap of the gcc of devtoolset-10 take more memory per job than a build
  # has: their compilers crash with 8 jobs
  cpus=$BUILD_CPUS
  case $srpm in dyninst-*|devtoolset-10-gcc-*) [ "$cpus" -le 2 ] || cpus=2 ;; esac
  case $1 in
    centos)
      image=quay.io/centos/centos:centos7
      # what the buildroot of CentOS 7.9 holds differs from the one the package was built in
      case $srpm in
        # the gcc 3.2 of RHEL 7.0 was built with the bison of RHEL 7.0 (2.7): the parser of gcc 3.2 uses the YYLEX macro
        # that bison 3 (RHEL 7.1 and later) dropped
        compat-gcc-32-*) fixes='curl -sfLo /tmp/bison.rpm https://archive.kernel.org/centos-vault/7.0.1406/os/x86_64/Packages/bison-2.7-4.el7.x86_64.rpm &&
          rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 && rpm -K /tmp/bison.rpm && rpm -Uvh --oldpackage /tmp/bison.rpm' ;;
        *) fixes= ;;
      esac
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
        # the packages of devtoolset-10 (CentOS SCLo) build with the macros of their collection (devtoolset-10-build,
        # built before them in this output: without it their names lack the prefix of the collection), the gcc with
        # the binutils of its collection and its 32-bit libraries too (the glibc of i686, which CentOS has)
        case $srpm in
          devtoolset-10-[0-9]*) ;;
          devtoolset-10-*) yum install -y /work/rpms/devtoolset-10-[0-9]*.src.rpm/devtoolset-10-build-*.rpm \
            /work/rpms/devtoolset-10-[0-9]*.src.rpm/devtoolset-10-runtime-*.rpm
            case $srpm in devtoolset-10-gcc-*)
              # yum-builddep does not resolve its file requirements (/lib/libc.so.6, /usr/lib/libc.so)
              yum install -y /work/rpms/devtoolset-10-binutils-*.src.rpm/devtoolset-10-binutils-[0-9]*.rpm \
                glibc.i686 glibc-devel.i686 ;;
            esac ;;
        esac
        yum-builddep -y /work/srpms/$srpm
        $fixes"
      cache=yumcache-centos
      mounts=
      rpmbuild_opts="--define 'dist $dist'"
      ;;
    xcpng)
      if [ "$BUILD_ENV" = fragata ]; then
        # the buildroot of Fragata Host (make-buildroot.sh): its repositories hold the build dependencies
        image=$FRAGATA_IMAGE
        tools=fragata
        cache=yumcache-fragata
        mounts=${BUILDROOT_RPMS:+-v $BUILDROOT_RPMS:/buildroot:ro}
        # its repositories already include the buildroot
        add_buildroot=false
      else
        image=ghcr.io/xcp-ng/xcp-ng-build-env:8.3
        tools=xcp-ng-updates
        add_buildroot='sudo cp /work/buildroot.repo /etc/yum.repos.d/'
        cache=yumcache
        mounts=
      fi
      # what the build environment holds differs from the buildroot the package was built in
      fixes=
      case $srpm in
        # autoconf 2.70 and later compile in C11, where the initializer of a mask is not constant
        irqbalance-*) builddep_opts=--setopt=$tools.exclude=autoconf ;;
        # binutils and gcc check for exactly autoconf 2.69
        devtoolset-*) builddep_opts=--setopt=$tools.exclude=autoconf ;;
        # the autoconf of its configure (2.69), gtkdocize, and no C++ library (built when g++ is there)
        gnutls-*) builddep_opts=--setopt=$tools.exclude=autoconf
          fixes='sudo yum install -y gtk-doc && sudo rpm -e --nodeps gcc-c++' ;;
        # a cmocka older than 1.1.3 (a build tool of the buildroot of Fragata Host): samba builds and ships its own
        samba-*) builddep_opts=
          if [ "$BUILD_ENV" = fragata ]; then repo_opts=; else repo_opts=--disablerepo=$tools; fi
          fixes="sudo yum downgrade -y $repo_opts libcmocka-1.1.2-1.el7 libcmocka-devel-1.1.2-1.el7" ;;
        # the coccinelle of EPEL 7 runs on the OCaml of CentOS 7 (4.05), not on the OCaml of XCP-ng
        kmod-drbd-*) builddep_opts="--setopt=$tools.exclude=ocaml*" ;;
        # its SRPM asks for the python3 of EPEL of its time (python34); the spec builds with the python3 of the
        # buildroot (the channel only ships python2-psutil)
        python-psutil-*) builddep_opts=--setopt=$tools.exclude=autoconf
          fixes='sudo yum install -y python3-devel' ;;
        # the packages of CentOS regenerate their configure with the autoconf of CentOS 7 (2.69)
        *.el7*) builddep_opts=--setopt=$tools.exclude=autoconf ;;
        *) builddep_opts= ;;
      esac
      setup="
        # the XCP-ng repositories first: the buildroot only for the build dependencies they lack (a failed
        # transaction installs nothing)
        if ! sudo yum-builddep -y $builddep_opts /work/srpms/$srpm; then
          echo 'build dependencies missing from the XCP-ng repositories: adding the buildroot'
          $add_buildroot
          sudo yum-builddep -y $builddep_opts /work/srpms/$srpm
        fi
        $fixes
        # the rpm of EL7 cannot generate the build dependencies of the pyproject macros: pip builds the wheel
        if rpm -qp --requires /work/srpms/$srpm | grep -qE '^(pyproject-rpm-macros|python3-wheel)'; then
          sudo yum install -y python3-pip
        fi
        # build dependencies may set up their tools in profile.d (the OCaml toolchain of xs-opam-repo)
        for profile in /etc/profile.d/*.sh; do . \$profile; done
        # the cmake macros of the build environment build out of the source tree; the specs written for the cmake
        # of EL7 run make in it: those that use none of the out-of-source macros build in the source tree
        if ! rpm2cpio /work/srpms/$srpm | cpio -i --quiet --to-stdout '*.spec' |
            grep -qE '_vpath_builddir|%\\{?cmake3?_(build|install)|__cmake3?_builddir'; then
          echo '%__cmake_in_source_build 1' >>~/.rpmmacros
        fi"
      rpmbuild_opts=
      [ -z "$dist" ] || rpmbuild_opts="--define 'dist $dist'"
      # the install of glusterfs makes fusermount-glusterfs setuid root when it runs as root, as the builds here do;
      # the upstream package, built as a user, is not
      case $srpm in
        glusterfs-*) rpmbuild_opts="$rpmbuild_opts --define '__spec_install_post chmod u-s \
%{buildroot}/usr/bin/fusermount-glusterfs; %{?__debug_package:%{__debug_install_post}} %{__arch_install_post} \
%{__os_install_post}'" ;;
      esac
      ;;
  esac
  case $srpm in
    # LINBIT built it with the manual pages of its tarball (the build requirements of its SRPM name no po4a nor
    # xsltproc); the spec, as written, regenerates them
    drbd-*) rpmbuild_opts="$rpmbuild_opts --with prebuiltman" ;;
  esac
  mkdir -p "$OUT_DIR/$cache"
  # Git Bash on Windows: no conversion of the container paths
  # the builds run as root (configure of tar, coreutils) without a terminal (ncurses)
  MSYS_NO_PATHCONV=1 "$ENGINE" run --rm --memory "$BUILD_MEMORY" -e RPM_BUILD_NCPUS="$cpus" \
    -e FORCE_UNSAFE_CONFIGURE=1 -e TERM=xterm -v "$OUT:/work" -v "$OUT/$cache:/var/cache/yum" $mounts "$image" sh -ec "
      rpm -K /work/srpms/$srpm | grep -qi 'pgp' || { echo 'not signed'; exit 1; }
      $setup
      if ! timeout $TIMEOUT rpmbuild --rebuild $rpmbuild_opts --define '_smp_mflags -j$cpus' /work/srpms/$srpm; then
        # the tests of some packages depend on the build machine (e.g. file descriptors or IPv6 in a container), or
        # hang there: when the build reached %check, the package is built again without them, and recorded as such
        grep -q 'Executing(%check)' /work/logs/$srpm.log 2>/dev/null || exit 1
        timeout $TIMEOUT rpmbuild --rebuild --nocheck $rpmbuild_opts --define '_smp_mflags -j$cpus' /work/srpms/$srpm
        touch /work/rpms/$srpm/.nocheck
      fi
      # the channel never ships debuginfo packages
      for rpm in ~/rpmbuild/RPMS/*/*.rpm; do
        case \$rpm in *-debuginfo-*) ;; *) cp \$rpm /work/rpms/$srpm/ ;; esac
      done
    " >>"$OUT_DIR/logs/$srpm.log" 2>&1 || return 1
  if [ "$1" = xcpng ] && [ "$BUILD_ENV" = fragata ]; then echo fragata; else echo "$1"; fi >"$OUT_DIR/rpms/$srpm/.buildroot"
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

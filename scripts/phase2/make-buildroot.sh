#!/bin/sh
# Phase 2 of Fragata Host: the buildroot image of its own (fragata-build-env:8.3), the counterpart of the XCP-ng 8.3
# build environment without the XCP-ng repositories. Its packages (buildroot-packages.txt, the packages of the XCP-ng
# build environment) come from the rebuilt packages of rebuild-srpms.sh, a repository made in <output>/rpms, and from
# the CentOS 7.9 and EPEL 7 archives for the others; the builds install their build dependencies the same way
# (rebuild-srpms.sh with BUILD_ENV=fragata mounts the repository at /buildroot).
# usage: make-buildroot.sh <output dir of rebuild-srpms.sh> [<image name>]
#   BUILDROOT_URLS: the published repositories of the rebuilt packages (the channel and the buildroot repository of
#   publish-buildroot.sh, space separated) instead of <output>/rpms: the image then reads them (CI), and
#   rebuild-srpms.sh needs no BUILDROOT_RPMS
# needs podman (or docker), the image quay.io/centos/centos:centos7, <output>/buildroot.repo and
# <output>/RPM-GPG-KEY-EPEL-7 (written and needed by rebuild-srpms.sh)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
OUT_DIR=$(cd "$1" && pwd)
OUT=$(cd "$1" && { pwd -W 2>/dev/null || pwd; })
IMAGE=${2:-fragata-build-env:8.3}
ENGINE=${ENGINE:-podman}

grep -v '^#' "$here/buildroot-packages.txt" >"$OUT_DIR/buildroot-packages.txt"
# the repositories of the buildroot: the rebuilt packages above CentOS and EPEL (yum priorities); the libglvnd of
# CentOS 7.9 stays excluded, it conflicts with the mesa of CentOS 7.5
{
  if [ -n "${BUILDROOT_URLS:-}" ]; then
    n=0
    for url in $BUILDROOT_URLS; do
      n=$((n + 1))
      printf '[fragata-%s]\nname=Fragata Host (rebuilt packages, %s)\nbaseurl=%s\ngpgcheck=0\npriority=10\n\n' $n "$url" "$url"
    done
  else
    printf '[fragata]\nname=Fragata Host (rebuilt packages)\nbaseurl=file:///buildroot/\ngpgcheck=0\npriority=10\n'
    # a local repository, updated by the builds: read again by each
    printf 'metadata_expire=0\n\n'
  fi
  # the packages of the channel are those of CentOS 7.5 (the base of XCP-ng 8.3): the other packages of that release
  # match them, CentOS 7.9 only adds those it lacks
  for repo in os updates extras; do
    printf '[fragata-buildroot-centos75-%s]\nname=CentOS 7.5 %s (build dependencies)\n' $repo $repo
    printf 'baseurl=https://archive.kernel.org/centos-vault/7.5.1804/%s/$basearch/\n' $repo
    printf 'gpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7\npriority=40\n\n'
  done
  cat "$OUT_DIR/buildroot.repo"
} >"$OUT_DIR/buildroot-fragata.repo"

mkdir -p "$OUT_DIR/rpms" "$OUT_DIR/yumcache-centos"
MSYS_NO_PATHCONV=1 "$ENGINE" run --rm -v "$OUT:/work" -v "$OUT/rpms:/buildroot" -v "$OUT/yumcache-centos:/var/cache/yum" \
  -e BUILDROOT_URLS="${BUILDROOT_URLS:-}" quay.io/centos/centos:centos7 sh -ec '
    rm -f /etc/yum.repos.d/*.repo
    sed "/^exclude=/d" /work/buildroot.repo >/etc/yum.repos.d/buildroot.repo
    cp /work/RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg/
    echo keepcache=1 >>/etc/yum.conf
    yum install -y createrepo yum-plugin-priorities yum-utils
    # the repository of the rebuilt packages
    [ -n "$BUILDROOT_URLS" ] || createrepo -q --update --workers 4 /buildroot
    # the image: an empty root, only the repositories of the buildroot (yum reads its configuration as given)
    { printf "[main]\nkeepcache=1\ncachedir=/var/cache/yum/\$basearch/\$releasever\nreposdir=/nonexistent\n";
      printf "plugins=1\ntsflags=nodocs\noverride_install_langs=en_US.utf8\n\n"; cat /work/buildroot-fragata.repo; } \
      >/tmp/yum.conf
    yum -y -c /tmp/yum.conf --installroot=/fs --releasever=7 install $(cat /work/buildroot-packages.txt)
    # the release package names the XCP-ng repositories: the buildroot has its own
    rm -f /fs/etc/yum.repos.d/*.repo
    cp /work/buildroot-fragata.repo /fs/etc/yum.repos.d/buildroot.repo
    cp /work/RPM-GPG-KEY-EPEL-7 /fs/etc/pki/rpm-gpg/
    echo keepcache=1 >>/fs/etc/yum.conf
    # the packages it holds, from where
    for f in /fs/var/lib/yum/yumdb/*/*/from_repo; do
      d=${f%/from_repo}
      printf "%s\t%s\n" "${d##*/}" "$(cat $f)"
    done | sed "s/^[0-9a-f]*-//" | sort >/work/buildroot-image.tsv
    rm -rf /fs/var/cache/yum/*
    tar -C /fs -cf /work/buildroot-fs.tar .
  '
"$ENGINE" import "$OUT/buildroot-fs.tar" "$IMAGE"
rm -f "$OUT_DIR/buildroot-fs.tar"
echo "$IMAGE: $(wc -l <"$OUT_DIR/buildroot-image.tsv") packages, $(grep -cE '	fragata(-[0-9]+)?$' "$OUT_DIR/buildroot-image.tsv" || true) of them rebuilt"

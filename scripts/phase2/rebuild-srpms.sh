#!/bin/sh
# Phase 2 of Fragata Host: rebuilds the SRPMs of the channel (select-sources.py) in the XCP-ng 8.3 build
# environment, one container per SRPM. Each SRPM is checked (checksum, XCP-ng signature) before its build; the
# binaries land in <output>/rpms/<srpm>/, the result of each build in <output>/results.tsv (srpm, status, seconds),
# its log in <output>/logs/. A SRPM already built is skipped.
#
# usage: rebuild-srpms.sh <sources TSV> <output dir> [<binary package name>...]
#   names: only the SRPMs of these binary packages (a pilot); default: every SRPM
# needs podman (or docker) and the image ghcr.io/xcp-ng/xcp-ng-build-env:8.3
set -eu
SOURCES=$1
mkdir -p "$2"
OUT_DIR=$(cd "$2" && pwd)
# the directory as the engine sees it: a Windows path from Git Bash
OUT=$(cd "$2" && { pwd -W 2>/dev/null || pwd; })
shift 2
ENGINE=${ENGINE:-podman}
mkdir -p "$OUT_DIR/srpms" "$OUT_DIR/rpms" "$OUT_DIR/logs"
touch "$OUT_DIR/results.tsv"

while IFS="$(printf '\t')" read -r srpm repo location size sha binaries; do
  if [ $# -gt 0 ]; then
    wanted=
    for name in "$@"; do
      case ",$binaries," in *",$name,"*) wanted=1 ;; esac
    done
    [ -n "$wanted" ] || continue
  fi
  grep -qE "^$srpm	ok(-nocheck)?	" "$OUT_DIR/results.tsv" && continue
  file="$OUT_DIR/srpms/$srpm"
  if [ ! -f "$file" ] || ! echo "$sha  $file" | sha256sum -c --status; then
    # --ssl-no-revoke: the curl of Windows fails when it cannot reach the revocation servers (no-op elsewhere)
    curl -sfL --ssl-no-revoke -o "$file" "$repo$location" || { printf '%s\tdownload\t0\n' "$srpm" >>"$OUT_DIR/results.tsv"; continue; }
    echo "$sha  $file" | sha256sum -c --status || { printf '%s\tchecksum\t0\n' "$srpm" >>"$OUT_DIR/results.tsv"; continue; }
  fi
  start=$(date +%s)
  rm -rf "$OUT_DIR/rpms/$srpm" && mkdir -p "$OUT_DIR/rpms/$srpm"
  # Git Bash on Windows: no conversion of the container paths
  if MSYS_NO_PATHCONV=1 "$ENGINE" run --rm -v "$OUT:/work" ghcr.io/xcp-ng/xcp-ng-build-env:8.3 sh -ec "
      rpm -K /work/srpms/$srpm | grep -qi 'pgp' || { echo 'not signed'; exit 1; }
      sudo yum-builddep -y /work/srpms/$srpm
      # build dependencies may set up their tools in profile.d (the OCaml toolchain of xs-opam-repo)
      for profile in /etc/profile.d/*.sh; do . \$profile; done
      if ! rpmbuild --rebuild /work/srpms/$srpm; then
        # the tests of some packages depend on the build machine (e.g. file descriptors in a container): when only
        # %check failed, the package is built again without them, and recorded as such
        grep -q 'Bad exit status from .* (%check)' /work/logs/$srpm.log 2>/dev/null || exit 1
        rpmbuild --rebuild --nocheck /work/srpms/$srpm
        touch /work/rpms/$srpm/.nocheck
      fi
      cp ~/rpmbuild/RPMS/*/*.rpm /work/rpms/$srpm/
    " >"$OUT_DIR/logs/$srpm.log" 2>&1; then
    status=ok
    [ ! -f "$OUT_DIR/rpms/$srpm/.nocheck" ] || status=ok-nocheck
  else
    status=failed
  fi
  printf '%s\t%s\t%s\n' "$srpm" "$status" $(($(date +%s) - start)) >>"$OUT_DIR/results.tsv"
  echo "$srpm: $status ($(($(date +%s) - start)) s)"
done <"$SOURCES"

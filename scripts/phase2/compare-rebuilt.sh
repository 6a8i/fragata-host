#!/bin/bash
# Compares the rebuilt packages (rebuild-srpms.sh) with the upstream binaries they replace: version, arch, files with
# their modes and owners, requires, provides, scriptlets.
# usage (anywhere rpm runs, e.g. the XCP-ng 8.3 build environment):
#   compare-rebuilt.sh <upstream RPMs dir> <rebuilt rpms dir> <output dir> [<name>...]
#   upstream RPMs dir: the upstream/ directory of build-repo.sh; rebuilt rpms dir: <output>/rpms of rebuild-srpms.sh
#   without names, every upstream package is compared.
# Writes <output dir>/compare.tsv (name, status, what differs) and <output dir>/diffs/<name>.diff.
# status: same, differ, missing (no rebuilt package of that name).
set -e
UPSTREAM=$1
REBUILT=$2
OUT=$3
shift 3
mkdir -p "$OUT/diffs" "$OUT/dump"
rm -f "$OUT"/diffs/*.diff
# the keys of the packages are not imported: only their headers are read
rpm() { command rpm --nosignature "$@"; }

# the information of a package, one section per aspect, sorted so that the order of the build does not matter
dump() {
  echo '## version'
  rpm -qp --qf '%{VERSION}-%{RELEASE} %{ARCH}\n' "$1"
  echo '## files'
  rpm -qp --qf '[%{FILEMODES:perms} %{FILEUSERNAME} %{FILEGROUPNAME} %{FILENAMES}\n]' "$1" | sort
  echo '## requires'
  # the rpmlib features depend on the rpm that built the package, not on the package
  rpm -qp --requires "$1" | grep -v '^rpmlib(' | sort -u
  echo '## provides'
  rpm -qp --provides "$1" | sort -u
  echo '## scripts'
  rpm -qp --scripts "$1"
}

# the rebuilt binaries by package name
declare -A rebuilt
for f in "$REBUILT"/*/*.rpm; do
  case $f in *.src.rpm) continue ;; esac
  rebuilt[$(rpm -qp --qf '%{NAME}' "$f")]=$f
done

if [ $# -eq 0 ]; then
  set -- $(for f in "$UPSTREAM"/*.rpm; do rpm -qp --qf '%{NAME}\n' "$f"; done | sort -u)
fi

: >"$OUT/compare.tsv"
for n in "$@"; do
  re=${rebuilt[$n]}
  # the upstream package of the rebuilt version, else the newest (a channel may keep older versions)
  up=
  want=$([ -z "$re" ] || rpm -qp --qf '%{VERSION}-%{RELEASE}' "$re")
  for f in $(ls "$UPSTREAM"/$n-[0-9]*.rpm 2>/dev/null | sort -V); do
    [ "$(rpm -qp --qf '%{NAME}' "$f")" = "$n" ] || continue
    up=$f
    [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$f")" != "$want" ] || break
  done
  if [ -z "$up" ] || [ -z "$re" ]; then
    printf '%s\tmissing\t%s\n' "$n" "$([ -n "$up" ] && echo rebuilt || echo upstream)" >>"$OUT/compare.tsv"
    continue
  fi
  dump "$up" >"$OUT/dump/upstream"
  dump "$re" >"$OUT/dump/rebuilt"
  what=
  : >"$OUT/diffs/$n.diff"
  for s in version files requires provides scripts; do
    # the lines of one section
    section() { awk -v s="$s" '/^## /{p=($2==s); next} p' "$1"; }
    if ! diff -u --label "upstream $s" --label "rebuilt $s" <(section "$OUT/dump/upstream") \
      <(section "$OUT/dump/rebuilt") >>"$OUT/diffs/$n.diff"; then
      what=${what:+$what,}$s
    fi
  done
  if [ -z "$what" ]; then
    rm "$OUT/diffs/$n.diff"
    printf '%s\tsame\t\n' "$n" >>"$OUT/compare.tsv"
  else
    printf '%s\tdiffer\t%s\n' "$n" "$what" >>"$OUT/compare.tsv"
  fi
done
rm -rf "$OUT/dump"
cut -f2 "$OUT/compare.tsv" | sort | uniq -c

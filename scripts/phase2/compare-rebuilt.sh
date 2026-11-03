#!/bin/bash
# Compares rebuilt packages (rebuild-srpms.sh) with the upstream binaries they replace: files, requires, provides.
# usage (in the XCP-ng 8.3 build environment): compare-rebuilt.sh <upstream RPMs dir> <rebuilt rpms dir> <name>...
#   upstream RPMs dir: e.g. the upstream/ directory of build-repo.sh; rebuilt rpms dir: <output>/rpms of rebuild-srpms.sh
UPSTREAM=$1
REBUILT=$2
shift 2
status=0
for n in "$@"; do
  up=$(ls "$UPSTREAM"/$n-[0-9]*.rpm 2>/dev/null | head -1)
  re=$(ls "$REBUILT"/*/$n-[0-9]*.rpm 2>/dev/null | grep -v '\.src\.rpm$' | head -1)
  [ -n "$up" ] && [ -n "$re" ] || { echo "== $n: missing"; status=1; continue; }
  echo "== $n $(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$up") vs $(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$re")"
  for query in --list --requires --provides; do
    d=$(diff <(rpm -qp $query "$up" 2>/dev/null | sort) <(rpm -qp $query "$re" 2>/dev/null | sort))
    if [ -z "$d" ]; then
      echo "  $query: same"
    else
      echo "  $query: differ"
      echo "$d" | head -6 | sed 's/^/    /'
      status=1
    fi
  done
done
exit $status

# Phase 2: Fragata Host built from its sources

Phase 1 ships the XCP-ng 8.3 binaries, checked and signed again. Phase 2 rebuilds every package of the channel from
its source package (SRPM), in the XCP-ng 8.3 build environment, so that the channel no longer depends on the
binaries of the upstream project.

```
# the SRPMs of the channel: for each package of the selection, the SRPM it was built from
select-sources.py <selection.tsv of the channel> sources.tsv
# rebuild them (a pilot: only the SRPMs of some binary packages), one container per SRPM
rebuild-srpms.sh sources.tsv <output dir> [<binary package name>...]
```

`rebuild-srpms.sh` checks each SRPM (checksum of the Source repository, upstream signature) before its build, keeps
the binaries in `<output>/rpms/<srpm>/` and records the result of each build in `<output>/results.tsv`; a SRPM
already built is skipped, so a run can be resumed.

The packages of LINBIT for XOSTOR (`linstor-*`, `drbd-reactor`) have no published SRPM: they stay binaries.

Next steps: build against the rebuilt packages instead of the upstream repositories (a build root of its own), then
let `build-repo.sh` take the rebuilt binaries as Fragata packages.

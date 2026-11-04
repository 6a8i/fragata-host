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
already built is skipped, so a run can be resumed, and one that failed is built again.

The build environment only has the build dependencies of the XCP-ng packages; a buildroot of CentOS 7.9 and EPEL 7
archives, below the XCP-ng repositories (yum priorities), adds those they lack. The channel also has packages of
CentOS 7 and EPEL 7 (`.el7` releases): the channel ships the binaries CentOS and EPEL built, against OpenSSL 1.0.2,
curl 7.29 and the kernel headers of 3.10, not the newer ones of XCP-ng, so they build in a clean CentOS 7.9 from the
same archives, with their own release tag. The packages that need something else of their buildroot (an older
autoconf or cmocka, no g++) say so in the script. A build that
hangs stops after `TIMEOUT` seconds; one whose tests fail or hang in the container (`%check`) is built again without
them, recorded as `ok-nocheck`. The cmake of the build environment builds out of the source tree, the specs written
for the cmake of EL7 do not: the builds run in the source tree. The rpm of EL7 cannot generate the build dependencies
of the pyproject macros: pip is installed for the packages that use them.

```
# compare the rebuilt packages with the binaries of the channel (rpm only: e.g. a CentOS 7 container)
compare-rebuilt.sh <upstream/ of build-repo.sh> <output>/rpms <compare dir>
```

`compare-rebuilt.sh` compares each package of the channel with its rebuild: version, files with their modes and owners,
requires (without the rpmlib features), provides and scriptlets; `<compare dir>/compare.tsv` says what differs,
`<compare dir>/diffs/` how. The expected differences:

- packages of XCP-ng whose binaries in the channel were built against OpenSSL 1.0.2 (glusterfs, zfs) link to
  OpenSSL 3 now, as their current builds do: the channel has both;
- newer symbol versions of OpenSSL, nss, p11-kit and dbus in the requires (libcurl, python, trousers, nss-pem, gnutls,
  avahi): the channel has those versions;
- psmisc links to ncurses 5 of the buildroot instead of 6: the channel has both;
- kbd has keymaps of the newer xkeyboard-config of CentOS 7.9; python3-setuptools takes the date of its build in its
  version tag; the EPEL macros add python3 provides to python36-bitarray; the perl dependency generator no longer
  makes perl require the `perl(ExtUtils::Constant)` it provides.

The builds run as root: an install that makes a file setuid only as root (glusterfs) is undone in the script.

The packages of LINBIT for XOSTOR (`linstor-*`, `drbd-reactor`) have no published SRPM: they stay binaries.

Next steps: build against the rebuilt packages instead of the upstream repositories (a build root of its own), then
let `build-repo.sh` take the rebuilt binaries as Fragata packages.

# Fragata Host update channel

The hosts only use the Fragata Host repository (`/etc/yum.repos.d/fragata.repo`, from the `fragata-release`
package), served by GitHub:

- metadata and public key on GitHub Pages: `https://6a8i.github.io/fragata-host-updates/8.3/x86_64/`;
- packages as assets of a release of `6a8i/fragata-host-updates`, one per build of a channel
  (`packages-8.3-<build>`; the metadata point there, `release.txt` names it).

Every package and the metadata (`repomd.xml.asc`) are signed by the Fragata Host key; the hosts only trust that
key (`RPM-GPG-KEY-fragata`).

## Channels

- `8.3` (repository `fragata` of the hosts): the stable channel;
- `8.3-testing` (repository `fragata-testing`, disabled on the hosts): the updates waiting for a test.

Each build of a channel publishes its packages in a release of its own (GitHub holds at most 1000 files in a
release), so a promotion only copies metadata; the releases no channel uses any more are deleted
(`prune-releases.sh`). A published file keeps its content (`publish-repo.sh` refuses to replace one); a package
rebuilt from its sources has the name and version of the upstream binary, so its file is named apart
(`.fragata.rpm`). Next to the metadata of a channel are the state it was made from: `selection.tsv` (the
upstream packages), `signed.tsv` (source checksum → signed package, so a package is signed once and stays the bytes
the metadata describe) and `own.txt` (the Fragata packages).

## Content (phase 1)

- packages built by Fragata (they replace the upstream ones of the same name, and those they obsolete):
  - `fragata-release` (repository 6a8i/fragata-release): brand, channel, keys and console messages of the host;
  - `xcp-ng-xapi-plugins` (repository 6a8i/fragata-xapi-plugins): the updater queries the Fragata channel;
  - `fragata-plymouth-theme` (repository 6a8i/fragata-plymouth-theme): the boot theme;
- the packages of the XCP-ng 8.3 ISO (`base-packages.txt`) and the optional ones (`extras.txt`: XOSTOR, ZFS,
  SMAPIv3, GlusterFS, tools), at their latest version in XCP-ng base, updates and LINSTOR, with the closure of their
  dependencies, checked (checksum and XCP-ng signature) before being signed by the Fragata Host key.

## Content (phase 2)

Phase 2 rebuilds the packages from their sources (`../phase2`), in a buildroot of its own. `build-repo.sh` takes a
directory of the rebuilt packages: a selected package whose file is there is shipped from there, at the same
version, instead of the binary of XCP-ng; `rebuilt.txt` next to the metadata lists them. At the same version, yum
does not update an installed package to its rebuild: the hosts installed before get the rebuilt packages with the
next version of each, or with `yum reinstall`; the ISO installs them. The packages that do not
build yet stay the upstream binaries: `compat-libstdc++-33` and `python2-xapi-storage` (required by
`xcp-ng-deps`), `python2-psutil` (SMAPIv3), `drbd*` and `kmod-drbd` (XOSTOR, with the packages of LINBIT that
have no sources). The rebuilt packages come from a build run by hand (the workflow of the updates channel has
none: the packages XCP-ng publishes after a build are shipped as binaries until the next one).

## Updates

The workflow "Update the testing channel" of 6a8i/fragata-host-updates runs every day: when XCP-ng published new
packages, it lists them in its summary and, if the signing key is in its secrets (`FRAGATA_SIGNING_KEY`,
`FRAGATA_SIGNING_PASSPHRASE`), builds, signs and publishes the `8.3-testing` channel. Once tested on a host
(`yum --enablerepo=fragata-testing update`), the workflow "Promote the testing channel" (`promote-channel.sh`)
makes it the `8.3` channel.

## Making a release of the channel by hand

```
# 1. packages to ship: the packages of the ISO (or base-packages.txt), the extras and their dependencies
select-packages.py base-packages.txt selection.tsv extras.txt
# 2. own packages
build-rpm.sh <package repository> own/
# 3. repository: download, check, sign (in the XCP-ng 8.3 build environment); only new packages are signed;
#    the rebuilt packages (../phase2, all of them in one directory) replace the upstream binaries
podman run --rm -v $PWD:/scripts:ro -v <build dir>:/build -v <key dir>:/keys:ro \
  ghcr.io/xcp-ng/xcp-ng-build-env:8.3 sh /scripts/build-repo.sh /build/selection.tsv /build/own /keys \
  /build/repo-8.3 https://github.com/6a8i/fragata-host-updates/releases/download/packages-8.3-$(date -u +%Y%m%d%H%M)/ \
  [/build/rebuilt]
# 4. publish in the testing channel, test on a host, promote
publish-repo.sh <build dir>/repo-8.3 6a8i/fragata-host-updates 8.3 testing
promote-channel.sh 6a8i/fragata-host-updates 8.3
```

`sign-rpms.sh` signs single packages. The key directory holds `fragata-signing.secret.asc`,
`passphrase.txt` and `RPM-GPG-KEY-fragata`; it never goes in a repository.

The ISO built with the signed packages (`../fragata-iso/build-iso.sh <ISO> <out> <packages> <keys>`) installs
hosts that only know the Fragata channel.

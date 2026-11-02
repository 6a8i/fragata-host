# Fragata Host update channel

The hosts only use the Fragata Host repository (`/etc/yum.repos.d/fragata.repo`, from the `fragata-release`
package), served by GitHub:

- metadata and public key on GitHub Pages: `https://6a8i.github.io/fragata-host-updates/8.3/x86_64/`;
- packages as assets of the release `packages-8.3` of `6a8i/fragata-host-updates` (the metadata point there).

Every package and the metadata (`repomd.xml.asc`) are signed by the Fragata Host key; the hosts only trust that
key (`RPM-GPG-KEY-fragata`).

## Content (phase 1)

- packages built by Fragata (they replace the upstream ones of the same name):
  - `fragata-release` (repository 6a8i/fragata-release): brand, channel and key of the host;
  - `xcp-ng-xapi-plugins` (repository 6a8i/fragata-xapi-plugins): the updater queries the Fragata channel;
- the other packages of the release: binaries of XCP-ng 8.3 (base + updates), at their latest version,
  checked (checksum and XCP-ng signature) before being signed by the Fragata Host key.

Phase 2 rebuilds these packages from their sources.

## Making a release of the channel

```
# 1. packages to ship: the packages of the ISO and the closure of their dependencies
select-packages.py <XCP-ng ISO> selection.tsv
# 2. own packages
build-rpm.sh <package repository> own/
# 3. repository: download, check, sign (in the XCP-ng 8.3 build environment)
podman run --rm -v $PWD:/scripts:ro -v <build dir>:/build -v <key dir>:/keys:ro \
  ghcr.io/xcp-ng/xcp-ng-build-env:8.3 sh /scripts/build-repo.sh /build/selection.tsv /build/own /keys \
  /build/repo-8.3 https://github.com/6a8i/fragata-host-updates/releases/download/packages-8.3/
# 4. test on a host (test channel), then publish
publish-repo.sh <build dir>/repo-8.3 6a8i/fragata-host-updates 8.3
```

`sign-rpms.sh` signs single packages. The key directory holds `fragata-signing.secret.asc`,
`passphrase.txt` and `RPM-GPG-KEY-fragata`; it never goes in a repository.

The ISO built with the signed packages (`../fragata-iso/build-iso.sh <ISO> <out> <packages> <keys>`) installs
hosts that only know the Fragata channel.

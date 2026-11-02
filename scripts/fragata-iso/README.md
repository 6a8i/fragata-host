# Fragata Host ISO

`build-iso.sh` makes the Fragata Host installation ISO from the XCP-ng ISO of the same version, until the
packages are built from the Fragata forks:

- identity of the product (`.treeinfo`): the installed host reports `Fragata Host` as its brand;
- boot menus (text, without the upstream splash) and volume id;
- installer screens and the values it writes on the host (`opt/xensource/installer/version.py`, through
  `brand-installer.py`).

The packages, the update channel and the signing keys stay the upstream ones: the host is updated like an
XCP-ng host, and the orchestrator handles both brands the same way.

```
sudo ./build-iso.sh xcp-ng-8.3.0-20260806.iso fragata-host-8.3.0-20260806.iso
```

Needs `xorriso`, `cpio`, `bzip2` and `python3`.

Not branded yet (they come from packages): the text console (`xsconsole`), the login banner and the
`/etc/os-release` of the installed host.

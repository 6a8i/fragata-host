#!/usr/bin/env python3
# Makes the installer (opt/xensource/installer/backend.py) import the keys of the Fragata Host channel at the end of
# the installation: the GPG key of the metadata of the fragata repositories (repo_gpgcheck, upstream only does it
# for the xcp-ng ones) and the package key in the RPM database.
import sys

REPLACEMENTS = (
    ("if repo.id.startswith('xcp-ng'):", "if repo.id.startswith(('fragata', 'xcp-ng')):"),
    ("'/etc/pki/rpm-gpg/RPM-GPG-KEY-xcpng'", "'/etc/pki/rpm-gpg/RPM-GPG-KEY-fragata'"),
)

path = sys.argv[1]
with open(path) as f:
    source = f.read()

for old, new in REPLACEMENTS:
    if source.count(old) != 1:
        sys.exit('%s: %r not found once' % (path, old))
    source = source.replace(old, new)

with open(path, 'w') as f:
    f.write(source)
print('channel keys', path)

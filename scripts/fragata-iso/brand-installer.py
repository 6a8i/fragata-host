#!/usr/bin/env python3
# Rewrites the brand constants of the installer (opt/xensource/installer/version.py).
# The platform values (PLATFORM_*) and the product name used internally (PRODUCT_NAME) are kept: XAPI and the
# packages depend on them.
import re
import sys

BRAND = {
    'BRAND_CONSOLE': 'Fragata',
    'BRAND_CONSOLE_URL': 'https://github.com/6a8i/fragata-orchestrator',
    'BRAND_SERVER': 'Fragata Host',
    'BRAND_SERVERS': 'Fragata Hosts',
    'COMPANY': 'The Fragata project',
    'COMPANY_DOMAIN': 'github.com/6a8i',
    'COMPANY_NAME': 'The Fragata project',
    # credit to the projects Fragata Host is built from
    'COMPANY_NAME_LEGAL': 'The Fragata project, based on XCP-ng (Vates, XenServer and others)',
    'COMPANY_NAME_SHORT': 'Fragata',
    'COMPANY_PRODUCT_BRAND': 'Fragata Host',
    'COMPANY_WEBSITE': 'https://github.com/6a8i/fragata-host',
    'ISO_PV_TOOLS_COPYRIGHT': 'The Fragata project',
    'ISO_PV_TOOLS_LABEL': 'Fragata VM Tools',
    'ISO_PV_TOOLS_PUBLISHER': 'The Fragata project',
    'PRODUCT_BRAND': 'Fragata Host',
    'PRODUCT_BRAND_DASHED': 'Fragata-Host',
}

path = sys.argv[1]
with open(path) as f:
    source = f.read()

for key, value in BRAND.items():
    source, count = re.subn(r"^%s = .*$" % key, "%s = %r" % (key, value), source, flags=re.M)
    if count != 1:
        sys.exit('%s: %s not found' % (path, key))

with open(path, 'w') as f:
    f.write(source)
print('branded', path)

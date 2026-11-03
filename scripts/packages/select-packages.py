#!/usr/bin/env python3
# Packages of the Fragata Host repository: the packages of the ISO and the optional ones (extras.txt), at their latest
# version in the XCP-ng repositories (base, updates, LINSTOR), and the closure of their dependencies.
# usage: select-packages.py <upstream ISO> <output TSV: name, repository URL, location, size, sha256> [<extras list>]
import gzip, subprocess, sys, urllib.request, xml.etree.ElementTree as ET, re
NS = {'r': 'http://linux.duke.edu/metadata/repo', 'c': 'http://linux.duke.edu/metadata/common', 'rpm': 'http://linux.duke.edu/metadata/rpm'}
ISO, OUTPUT = sys.argv[1], sys.argv[2]
EXTRAS = sys.argv[3] if len(sys.argv) > 3 else None
REPOS = (
    'https://updates.xcp-ng.org/8/8.3/base/x86_64/',
    'https://updates.xcp-ng.org/8/8.3/updates/x86_64/',
    'https://repo.vates.tech/xcp-ng/8/8.3/linstor/x86_64/',
)
# release packages of the upstream repositories: the hosts only use the Fragata Host channel
EXCLUDED = {'xcp-ng-release-linstor'}

def parts(s): return [int(x) if x.isdigit() else x for x in re.findall(r'\d+|[a-zA-Z]+', s)]
def vercmp(a, b):
    for x, y in zip(parts(a), parts(b)):
        if x == y: continue
        if isinstance(x, int) and isinstance(y, int): return (x > y) - (x < y)
        return 1 if isinstance(x, int) else -1 if isinstance(y, int) else (x > y) - (x < y)
    return (len(parts(a)) > len(parts(b))) - (len(parts(a)) < len(parts(b)))
def newer(a, b):
    if a[0] != b[0]: return a[0] > b[0]
    c = vercmp(a[1], b[1])
    return c > 0 if c else vercmp(a[2], b[2]) > 0

latest = {}
for url in REPOS:
    repo = url
    repomd = ET.fromstring(urllib.request.urlopen(url + 'repodata/repomd.xml').read())
    href = [d.find('r:location', NS).get('href') for d in repomd.findall('r:data', NS) if d.get('type') == 'primary'][0]
    root = ET.fromstring(gzip.decompress(urllib.request.urlopen(url + href).read()))
    for p in root.findall('c:package', NS):
        name, arch = p.find('c:name', NS).text, p.find('c:arch', NS).text
        if arch == 'src':
            continue
        v = p.find('c:version', NS)
        evr = (int(v.get('epoch') or 0), v.get('ver'), v.get('rel'))
        fmt = p.find('c:format', NS)
        prov = [e.get('name') for e in fmt.findall('rpm:provides/rpm:entry', NS)] + [f.text for f in fmt.findall('c:file', NS)]
        req = [e.get('name') for e in fmt.findall('rpm:requires/rpm:entry', NS)]
        pkg = dict(name=name, arch=arch, evr=evr, repo=repo, loc=p.find('c:location', NS).get('href'),
                   size=int(p.find('c:size', NS).get('package')), sha=p.find('c:checksum', NS).text, prov=prov, req=req)
        # by name only: a package can change arch between versions (x86_64 -> noarch)
        old = latest.get(name)
        if old is None or newer(evr, old['evr']):
            latest[name] = pkg

providers = {}
for pkg in latest.values():
    for cap in pkg['prov'] + [pkg['name']]:
        providers.setdefault(cap, []).append(pkg)

iso_names = subprocess.run(['xorriso', '-osirrox', 'on', '-indev', ISO, '-find', '/Packages', '-name', '*.rpm'],
                           capture_output=True, text=True).stdout.split()
names = {re.sub(r'-[^-]+-[^-]+\.[^.]+\.rpm$', '', n.strip("'").split('/')[-1]) for n in iso_names}
iso_count = len(names)
if EXTRAS:
    extras = {l.strip() for l in open(EXTRAS) if l.strip() and not l.startswith('#')}
    unknown = extras - {p['name'] for p in latest.values()}
    if unknown:
        sys.exit('extras not found upstream: %s' % ' '.join(sorted(unknown)))
    names |= extras
latest = {k: p for k, p in latest.items() if p['name'] not in EXCLUDED}
providers = {cap: [p for p in pkgs if p['name'] not in EXCLUDED] for cap, pkgs in providers.items()}
queue = [p for p in latest.values() if p['name'] in names]
needed, missing = {}, set()
while queue:
    pkg = queue.pop()
    key = (pkg['name'], pkg['arch'])
    if key in needed:
        continue
    needed[key] = pkg
    for cap in pkg['req']:
        if cap.startswith('rpmlib('):
            continue
        cands = providers.get(cap)
        if not cands:
            missing.add(cap)
            continue
        if not any((c['name'], c['arch']) in needed for c in cands):
            queue.append(cands[0])
with open(OUTPUT, 'w') as f:
    for p in sorted(needed.values(), key=lambda p: p['name']):
        f.write('%s\t%s\t%s\t%d\t%s\n' % (p['name'], p['repo'], p['loc'], p['size'], p['sha']))
print('ISO names: %d, extras: %d, needed: %d packages, %.2f GB' % (
    iso_count, len(names) - iso_count, len(needed), sum(p['size'] for p in needed.values()) / 1e9))
print('unresolved requirements (provided by the ISO or the system):', len(missing), sorted(missing)[:8])

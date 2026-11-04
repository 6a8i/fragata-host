#!/usr/bin/env python3
# The selection (as select-packages.py writes it) of the build tools of build-tools.txt: the newest package of each
# name in the XCP-ng 8.3 base and updates repositories, for select-sources.py.
# usage: select-build-tools.py <build-tools.txt> <output selection TSV: name, repository URL, location, size, sha256>
import gzip, re, sys, urllib.request, xml.etree.ElementTree as ET
NS = {'r': 'http://linux.duke.edu/metadata/repo', 'c': 'http://linux.duke.edu/metadata/common'}
REPOS = ['https://updates.xcp-ng.org/8/8.3/base/x86_64/', 'https://updates.xcp-ng.org/8/8.3/updates/x86_64/']


def primary(url):
    repomd = ET.fromstring(urllib.request.urlopen(url + 'repodata/repomd.xml').read())
    href = [d.find('r:location', NS).get('href') for d in repomd.findall('r:data', NS) if d.get('type') == 'primary'][0]
    return ET.fromstring(gzip.decompress(urllib.request.urlopen(url + href).read())).findall('c:package', NS)


def key(version):
    # epoch, version and release compared by their numeric and alphabetic parts, as rpm does for these packages
    return [(int(e), e) if e.isdigit() else (-1, e) for v in version for e in re.findall(r'\d+|[a-zA-Z]+', v)]


names = [line.strip() for line in open(sys.argv[1]) if line.strip() and not line.startswith('#')]
best = {}
for repo in REPOS:
    for p in primary(repo):
        name = p.find('c:name', NS).text
        if name not in names or p.find('c:arch', NS).text == 'src':
            continue
        v = p.find('c:version', NS)
        version = (v.get('epoch') or '0', v.get('ver'), v.get('rel'))
        if name not in best or key(version) > key(best[name][0]):
            best[name] = (version, repo, p.find('c:location', NS).get('href'), p.find('c:size', NS).get('package'),
                          p.find('c:checksum', NS).text)
# LF lines on every platform (rebuild-srpms.sh reads them with sh)
with open(sys.argv[2], 'w', newline='\n') as f:
    for name in names:
        if name not in best:
            print('not found: ' + name)
            continue
        version, repo, location, size, sha = best[name]
        f.write('%s\t%s\t%s\t%s\t%s\n' % (name, repo, location, size, sha))
        print('%s %s-%s' % (name, version[1], version[2]))

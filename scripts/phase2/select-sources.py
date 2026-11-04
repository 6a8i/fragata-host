#!/usr/bin/env python3
# Phase 2 of Fragata Host: the source packages (SRPMs) of the channel, to rebuild every package from its sources.
# For each package of a selection (select-packages.py), finds the SRPM it was built from in the Source repository
# next to its binary repository (XCP-ng base, updates, LINSTOR).
# usage: select-sources.py <selection TSV> <output TSV: srpm name, Source repository URL, location, size, sha256, binaries>
import gzip, sys, urllib.request, xml.etree.ElementTree as ET
NS = {'r': 'http://linux.duke.edu/metadata/repo', 'c': 'http://linux.duke.edu/metadata/common',
      'rpm': 'http://linux.duke.edu/metadata/rpm'}
SELECTION, OUTPUT = sys.argv[1], sys.argv[2]


def primary(url):
    repomd = ET.fromstring(urllib.request.urlopen(url + 'repodata/repomd.xml').read())
    href = [d.find('r:location', NS).get('href') for d in repomd.findall('r:data', NS) if d.get('type') == 'primary'][0]
    return ET.fromstring(gzip.decompress(urllib.request.urlopen(url + href).read())).findall('c:package', NS)


selection = [line.rstrip('\n').split('\t') for line in open(SELECTION)]
srpm_of = {}  # (binary repository, binary location) -> srpm file name
sources = {}  # (Source repository, srpm file name) -> (location, size, sha256)
for repo in sorted({repo for _, repo, *_ in selection}):
    for p in primary(repo):
        srpm_of[(repo, p.find('c:location', NS).get('href'))] = p.find('c:format/rpm:sourcerpm', NS).text
    source = repo.replace('/x86_64/', '/Source/')
    for p in primary(source):
        location = p.find('c:location', NS).get('href')
        sources[(source, location.split('/')[-1])] = (location, int(p.find('c:size', NS).get('package')),
                                                     p.find('c:checksum', NS).text)

needed, missing = {}, []
for name, repo, location, *_ in selection:
    srpm = srpm_of.get((repo, location))
    source = repo.replace('/x86_64/', '/Source/')
    if not srpm or (source, srpm) not in sources:
        missing.append('%s (%s)' % (name, srpm))
        continue
    needed.setdefault((source, srpm), []).append(name)

# LF lines on every platform (rebuild-srpms.sh reads them with sh)
with open(OUTPUT, 'w', newline='\n') as f:
    for (source, srpm), binaries in sorted(needed.items(), key=lambda item: item[0][1]):
        location, size, sha = sources[(source, srpm)]
        f.write('%s\t%s\t%s\t%d\t%s\t%s\n' % (srpm, source, location, size, sha, ','.join(sorted(binaries))))
print('%d packages from %d SRPMs, %.2f GB of sources' % (
    len(selection) - len(missing), len(needed), sum(sources[k][1] for k in needed) / 1e9))
print('without SRPM: %d %s' % (len(missing), missing[:10]))

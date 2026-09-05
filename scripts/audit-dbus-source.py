#!/usr/bin/env python3
"""Isolated source-to-retained-intake evidence; does not execute maintainer hooks."""
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.request

from auzix.lifecycle_intake import normalize_lifecycle

out = Path('/audit')
downloads = out / 'downloads'
downloads.mkdir()
base = 'https://deb.debian.org/debian/pool/main/d/dbus/'
dsc_name = 'dbus_1.16.2-2.dsc'
data = urllib.request.urlopen(base + dsc_name, timeout=30).read()
(downloads / dsc_name).write_bytes(data)
hashes = {dsc_name: hashlib.sha256(data).hexdigest()}
block = data.decode().split('Checksums-Sha256:\n', 1)[1]
for line in block.splitlines():
    if not line.startswith(' '):
        break
    digest, size, name = line.split()
    assert Path(name).name == name
    payload = urllib.request.urlopen(base + name, timeout=60).read()
    assert len(payload) == int(size) and hashlib.sha256(payload).hexdigest() == digest
    (downloads / name).write_bytes(payload)
    hashes[name] = digest
(out / 'download-sha256.json').write_text(json.dumps(hashes, indent=2))
result = subprocess.run(['dpkg-source', '-x', str(downloads / dsc_name), str(out / 'source')], text=True, capture_output=True)
(out / 'dpkg-source.log').write_text(result.stdout + result.stderr)
result.check_returncode()
index = json.loads(Path('/baseline/inputs/index.json').read_text())
record = next(r for r in index['packages'] if r['name'] == 'DBus')
archive = Path('/baseline/inputs/packages') / record['package']
with archive.open('rb') as handle:
    assert hashlib.file_digest(handle, 'sha256').hexdigest() == record['sha256']
stage = out / 'intake-stage'
stage.mkdir()
with tarfile.open(archive) as archive_file:
    archive_file.extractall(stage, filter='data')
receipt_file, = (stage / 'System/PackageDB').glob('*.json')
receipt = json.loads(receipt_file.read_text())
program = stage / receipt['prefix'].lstrip('/')
source_hook = (out / 'source/debian/dbus.postinst').read_text()
binary_hook = (program / 'Metadata/debian-control-dir/postinst').read_text()
(out / 'source-to-binary-postinst.diff').write_text(''.join(difflib.unified_diff(
    source_hook.splitlines(True), binary_hook.splitlines(True),
    fromfile='source/debian/dbus.postinst', tofile='retained/control/postinst')))
intake = normalize_lifecycle(stage, receipt, out / 'normalization')
helper = program / 'RootFS/usr/lib/dbus-1.0/dbus-daemon-launch-helper'
stat = helper.stat()
summary = {'package': record['name'], 'version': record['version'],
           'intake_input_sha256': record['sha256'], 'status': intake['status'],
           'findings': intake['findings'], 'helper_mode': oct(stat.st_mode & 0o7777),
           'helper_uid': stat.st_uid, 'helper_gid': stat.st_gid,
           'source_build_executed': False, 'maintainer_hooks_executed': False,
           'signature_status': 'consult dpkg-source.log; checksum verification is not signature verification'}
(out / 'audit-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2), flush=True)

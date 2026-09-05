#!/usr/bin/env python3
"""Freeze all records from a retained release index without changing versions."""
import hashlib
import json
from pathlib import Path
import shutil
import sys


def prepare(base, destination, roots):
    if destination.exists():
        raise ValueError('refusing existing candidate input directory')
    index = json.loads((base / 'index.json').read_text())
    profile = json.loads((base / 'profile.json').read_text())
    selected = []
    names = set()
    for record in index['packages']:
        if record['name'] in names:
            raise ValueError('duplicate package identity: ' + record['name'])
        names.add(record['name'])
        filename = record['package']
        if Path(filename).name != filename:
            raise ValueError('unsafe archive filename')
        source = None
        for root in [base, *roots]:
            candidate = root / 'packages' / filename
            if candidate.is_file():
                with candidate.open('rb') as handle:
                    digest = hashlib.file_digest(handle, 'sha256').hexdigest()
                if digest == record['sha256']:
                    source = candidate
                    break
        if source is None:
            raise ValueError('no matching retained archive: ' + record['name'])
        selected.append((record, source))
    destination.mkdir(parents=True)
    (destination / 'packages').mkdir()
    origins = []
    for record, source in selected:
        shutil.copyfile(source, destination / 'packages' / record['package'])
        origins.append({'name': record['name'], 'source': str(source), 'sha256': record['sha256']})
    profile['name'] = 'alpha-full-retained-repackage'
    profile['packages'] = [record['name'] for record, _ in selected]
    (destination / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    (destination / 'profile.json').write_text(json.dumps(profile, indent=2) + '\n')
    (destination / 'input-origins.json').write_text(json.dumps(origins, indent=2) + '\n')
    print(f'FULL-INPUTS-VERIFIED count={len(selected)}', flush=True)


if __name__ == '__main__':
    prepare(*(Path(arg) for arg in sys.argv[1:3]), [Path(arg) for arg in sys.argv[3:]])

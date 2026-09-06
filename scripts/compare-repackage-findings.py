#!/usr/bin/env python3
"""Compare rerun packages only, without implying untouched packages were tested."""
import json
from pathlib import Path
import sys

before, after = [json.loads(Path(p).read_text()) for p in sys.argv[1:]]
old = {p['name']: p for p in before['packages']}
rows = []
for package in after['packages']:
    prior = old[package['name']]
    rows.append({'name': package['name'], 'before': prior['status'], 'after': package['status'],
                 'findings_before': len(prior.get('intake', {}).get('findings', [])),
                 'findings_after': len(package.get('intake', {}).get('findings', [])),
                 'legacy_after': len(package.get('intake', {}).get('legacy_findings', []))})
print(json.dumps({
    'rerun': len(rows),
    'untouched': len(old) - len(rows),
    'newly_verified': [
        p['name'] for p in rows
        if p['before'] == 'needs-review' and p['after'] in ('passed', 'static')
    ],
    'newly_regressed': [
        p['name'] for p in rows
        if p['before'] in ('passed', 'static') and p['after'] == 'needs-review'
    ],
    'findings_before': sum(p['findings_before'] for p in rows),
    'findings_after': sum(p['findings_after'] for p in rows),
    'legacy_after': sum(p['legacy_after'] for p in rows),
    'packages': rows,
}, indent=2))

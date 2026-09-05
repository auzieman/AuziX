#!/usr/bin/env python3
"""Batch receipts for held packages; never equate conversion with installation."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import difflib
import hashlib
import json
from pathlib import Path
import subprocess


def proof_path(value, repository):
    relative = Path(value).relative_to('/proof/repository')
    target = (repository / relative).resolve()
    target.relative_to(repository.resolve())
    return target


def run_package(package, output, repository, source, image):
    name = package['name']
    if not name.isalnum():
        raise ValueError('invalid native package name: ' + name)
    work = output / name
    work.mkdir()
    intake = package.get('intake', {})
    row = {'name': name, 'version': package.get('version'),
           'input_sha256': package.get('sha256'),
           'conversion': package['status'], 'findings': intake.get('findings', []),
           'operations': intake.get('operations', []),
           'component': 'not-implemented', 'apk_install': 'not-tested',
           'status': 'blocked', 'hooks': []}
    try:
        originals = {item['source']: item for item in intake.get('donor_objects', [])}
        for script in intake.get('scripts', []):
            original = originals.get(script['source'])
            candidate = proof_path(script['candidate'], repository)
            after = candidate.read_text()
            before = ''
            if original:
                before = proof_path(original['original'], repository).read_text()
            stage = script['stage']
            (work / (stage + '.original')).write_text(before)
            (work / (stage + '.candidate')).write_text(after)
            (work / (stage + '.diff')).write_text(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=script['source'], tofile=script['candidate'])))
            row['hooks'].append({'stage': stage,
                'original_sha256': hashlib.sha256(before.encode()).hexdigest(),
                'candidate_sha256': hashlib.sha256(after.encode()).hexdigest()})
        # Explicit reviewed dispatch, not execution of arbitrary donor text.
        if name == 'DBus':
            command = ['docker', 'run', '--rm', '--network', 'none',
                       '-e', 'PYTHONDONTWRITEBYTECODE=1',
                       '-v', str(source) + ':/workspace:ro', '-w', '/workspace',
                       image, 'python3', 'scripts/test-dbus-helper-permissions.py']
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (work / 'component.log').write_text(result.stdout + result.stderr)
            row['component'] = 'passed' if result.returncode == 0 else 'failed'
            row['component_scope'] = 'helper permissions only; fixture, not installed APK'
        row['next'] = ('Translate remaining donor effects and add install/replay proof; '
                       'component success alone cannot release this package.')
    except Exception as error:
        row['error'] = str(error)
        row['component'] = 'error'
    (work / 'result.json').write_text(json.dumps(row, indent=2) + '\n')
    print(f"EFFECT-RESULT {name} conversion={row['conversion']} "
          f"component={row['component']} apk-install=not-tested status=blocked", flush=True)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('proof', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--image', default='auzix/trixie-builder:lab')
    args = parser.parse_args()
    proof = json.loads(args.proof.read_text())
    packages = proof['packages']
    names = [p['name'] for p in packages]
    if len(set(names)) != len(names) or any(not n.isalnum() for n in names):
        raise ValueError('duplicate or unsafe package identities')
    args.output.mkdir()  # Never overwrite completed evidence.
    with ThreadPoolExecutor(max_workers=8) as pool:
        rows = list(pool.map(lambda p: run_package(p, args.output,
                    args.proof.parent, args.source.resolve(), args.image), packages))
    summary = {'packages': rows, 'total': len(rows), 'accepted': 0,
               'component_passed': sum(r['component'] == 'passed' for r in rows),
               'missing_component_tests': [r['name'] for r in rows
                                           if r['component'] == 'not-implemented'],
               'status': 'blocked', 'source': str(args.source)}
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f"EFFECT-SUMMARY total={len(rows)} accepted=0 "
          f"component-passed={summary['component_passed']} status=blocked", flush=True)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Root-only isolated component proof; not APK or service acceptance."""
import json
import os
from pathlib import Path
import pwd
import grp
import subprocess
import tempfile

script = Path(__file__).resolve().parents[1] / 'packaging/dbus-helper-permissions.sh'
assert os.geteuid() == 0, 'run in the disposable R730 builder, not the workstation'
account = 'auzix-dbus-proof'
try:
    pwd.getpwnam(account)
except KeyError:
    pass
else:
    raise RuntimeError('proof account already exists; require fresh container')

with tempfile.TemporaryDirectory(prefix='dbus-hook-') as directory:
    helper = Path(directory) / 'helper'
    helper.write_text('fixture, deliberately not an executable service\n')
    helper.chmod(0o755)

    def invoke(path=helper, override='absent', success=True):
        result = subprocess.run(['sh', str(script), str(path), account, override],
                                text=True, capture_output=True)
        print(result.stdout + result.stderr, end='', flush=True)
        assert (result.returncode == 0) == success, result

    def state():
        value = helper.stat()
        return value.st_uid, value.st_gid, value.st_mode & 0o7777

    initial = state()
    invoke(success=False)
    assert state() == initial
    subprocess.run(['groupadd', '--system', account], check=True)
    subprocess.run(['useradd', '--system', '--gid', account, '--no-create-home',
                    '--shell', '/usr/sbin/nologin', account], check=True)
    expected = (0, grp.getgrnam(account).gr_gid, 0o4754)
    invoke()
    assert state() == expected
    invoke()
    assert state() == expected
    helper.chmod(0o750)
    custom = state()
    invoke(override='present')
    assert state() == custom
    invoke(override='unknown', success=False)
    assert state() == custom
    link = Path(directory) / 'symlink'
    link.symlink_to(helper)
    invoke(link, success=False)
    assert state() == custom
print(json.dumps({'component': 'dbus-helper-permissions', 'status': 'passed',
                  'checks': ['missing-account', 'apply', 'replay', 'override',
                             'unknown-policy', 'symlink-rejection'],
                  'apk_install_tested': False, 'service_activation_tested': False}))

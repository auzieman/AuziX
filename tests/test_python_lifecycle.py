import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from auzix.python_lifecycle import adapt_python_prerm
from auzix.lifecycle_intake import normalize_lifecycle
from auzix.archive_fpm import _automatic_library_definition


class PythonLifecycleTests(unittest.TestCase):
    def test_reviewed_donors_cleanup_only_owned_caches_and_replay(self):
        for suffix, package in [('minimal', 'Libpython313Minimal'), ('stdlib', 'Libpython313Stdlib')]:
            with self.subTest(package=package), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                donor = (Path(__file__).parent / 'fixtures/python-donor' / (suffix + '.prerm')).read_text()
                script = adapt_python_prerm(donor, package, 'before_remove')
                self.assertIsNotNone(script)
                owned = root / 'owned'
                deleted = owned / 'RootFS/usr/lib/python3.13/__pycache__/example.cpython-313.pyc'
                retained = [owned / 'RootFS/usr/lib/python3.13/example.py',
                            owned / 'RootFS/usr/lib/python3/dist-packages/__pycache__/third.pyc',
                            root / 'neighbor/__pycache__/other.pyc']
                for path in [deleted, *retained]:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('keep')
                (owned / 'RootFS/external').symlink_to(root / 'neighbor', target_is_directory=True)
                env = {**os.environ, 'AUZIX_PACKAGE_ROOT': str(owned)}
                for _ in range(2):
                    subprocess.run(['sh', '-eu', '-c', script], env=env, check=True)
                self.assertFalse(deleted.exists())
                self.assertTrue(all(path.read_text() == 'keep' for path in retained))
                self.assertIsNone(adapt_python_prerm(donor + '\necho changed\n', package, 'before_remove'))
                self.assertIsNone(adapt_python_prerm(donor, 'OtherPackage', 'before_remove'))
                self.assertIsNone(adapt_python_prerm(donor, package, 'after_install'))

    def test_real_donor_intake_keeps_evidence_and_emits_hook(self):
        for suffix, package in [('minimal', 'Libpython313Minimal'), ('stdlib', 'Libpython313Stdlib')]:
            with self.subTest(package=package), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                prefix = '/Programs/' + package + '/1'
                control = root / prefix.lstrip('/') / 'Metadata/debian-control-dir/prerm'
                control.parent.mkdir(parents=True)
                control.write_text((Path(__file__).parent / 'fixtures/python-donor' / (suffix + '.prerm')).read_text())
                receipt = {'name': package, 'version': '1', 'prefix': prefix}
                result = normalize_lifecycle(root, receipt, root / 'review', _automatic_library_definition(receipt))
                self.assertEqual(result['status'], 'ready', result['findings'])
                self.assertEqual(len(result['donor_objects']), 1)
                self.assertEqual(result['scripts'][0]['stage'], 'before_remove')
                self.assertIn('reviewed-python-owned-bytecode-cleanup', [r['id'] for r in result['rules']])

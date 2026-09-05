import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from auzix.archive_fpm import convert_archive_profile
from auzix.contracts import ContractError


class ArchiveWorkerTests(unittest.TestCase):
    def test_isolated_workers_aggregate_and_preserve_existing_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            verifier = root / 'apk'
            verifier.touch()
            plan = {'profile': 'test', 'packages': [
                {'name': name, 'apk_name': name, 'apk_version': '1-r0',
                 'archive': name, 'description': name, 'apk_depends': []}
                for name in ['one', 'two']]}
            stages = []
            barrier = threading.Barrier(2)

            def run(argv):
                if argv[1] == '-xzf':
                    stage = Path(argv[-1])
                    receipts = stage / 'System/PackageDB'
                    receipts.mkdir(parents=True)
                    (receipts / 'receipt.json').write_text(json.dumps({'name': argv[2]}))

            def normalize(stage, receipt, review, definition):
                stages.append(stage)
                barrier.wait(timeout=5)
                return {'status': 'static', 'scripts': []}

            with patch('auzix.archive_fpm.shutil.which', return_value='/fpm'), \
                 patch('auzix.archive_fpm.archive_profile_plan', return_value=plan), \
                 patch('auzix.archive_fpm.run', side_effect=run), \
                 patch('auzix.archive_fpm.normalize_lifecycle', side_effect=normalize), \
                 patch('auzix.archive_fpm.promote_auzix_package', return_value=({}, [])), \
                 patch('auzix.archive_fpm.subprocess.run', return_value=SimpleNamespace(returncode=0)):
                result = convert_archive_profile(root, root / 'profile', root / 'out', apk_command=str(verifier), workers=2)
                self.assertEqual(result['summary'], {'static': 2})
                self.assertEqual(len(set(stages)), 2)
                proof = root / 'out/conversion-proof.json'
                before = proof.read_bytes()
                with self.assertRaisesRegex(ContractError, 'refusing to overwrite'):
                    convert_archive_profile(root, root / 'profile', root / 'out', apk_command=str(verifier))
                self.assertEqual(proof.read_bytes(), before)

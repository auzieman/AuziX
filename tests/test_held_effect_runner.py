import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('held_effects',
    Path(__file__).resolve().parents[1] / 'scripts/test-held-package-effects.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class HeldEffectsTests(unittest.TestCase):
    def test_missing_test_is_blocked_even_when_conversion_passed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = runner.run_package({'name': 'Example', 'status': 'passed'},
                                        root, root, root, 'not-used')
            self.assertEqual(result['status'], 'blocked')
            self.assertEqual(result['component'], 'not-implemented')
            self.assertEqual(result['apk_install'], 'not-tested')
            self.assertTrue((root / 'Example/result.json').is_file())

    def test_missing_evidence_records_failure_and_continues(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = runner.run_package({'name': 'Example', 'status': 'needs-review',
                'intake': {'scripts': [{'source': '/missing', 'stage': 'after_install',
                    'candidate': '/proof/repository/missing'}]}}, root, root, root, 'unused')
            self.assertEqual(result['component'], 'error')
            self.assertTrue((root / 'Example/result.json').is_file())

    def test_path_escape_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                runner.proof_path('/proof/repository/../../outside', Path(temporary))

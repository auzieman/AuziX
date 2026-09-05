import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('full_repackage', Path(__file__).parents[1] / 'scripts/prepare-full-repackage.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FullRepackageTests(unittest.TestCase):
    def test_expands_only_index_and_matches_hash_without_overwriting(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base, supplement, out = root / 'base', root / 'supplement', root / 'out'
            for path in [base, supplement]:
                (path / 'packages').mkdir(parents=True)
            records = [{'name': name, 'package': name + '.tar.gz',
                        'sha256': hashlib.sha256(name.encode()).hexdigest()}
                       for name in ['One', 'Two']]
            (base / 'index.json').write_text(json.dumps({'packages': records}))
            (base / 'profile.json').write_text(json.dumps({'packages': ['One'], 'external_providers': {'X': 'x'}}))
            (base / 'packages/One.tar.gz').write_text('One')
            (base / 'packages/Two.tar.gz').write_text('stale')
            with self.assertRaisesRegex(ValueError, 'no matching'):
                module.prepare(base, out, [supplement])
            self.assertFalse(out.exists())
            (supplement / 'packages/Two.tar.gz').write_text('Two')
            module.prepare(base, out, [supplement])
            profile = json.loads((out / 'profile.json').read_text())
            self.assertEqual(profile['packages'], ['One', 'Two'])
            self.assertEqual(profile['external_providers'], {'X': 'x'})
            self.assertEqual((out / 'packages/Two.tar.gz').read_text(), 'Two')
            with self.assertRaisesRegex(ValueError, 'existing'):
                module.prepare(base, out, [supplement])

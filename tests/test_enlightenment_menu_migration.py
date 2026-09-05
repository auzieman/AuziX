import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class MenuMigrationTests(unittest.TestCase):
    def test_preserves_configuration_and_rejects_conflicts(self):
        script = Path(__file__).parents[1] / 'packaging/packages/enlightenment-data/lifecycle/before-install'
        with tempfile.TemporaryDirectory() as temporary:
            menus = Path(temporary) / 'xdg/menus'
            menus.mkdir(parents=True)
            old, new = menus / 'enlightenment-applications.menu', menus / 'e-applications.menu'
            def run():
                return subprocess.run(['sh', str(script)], env=dict(os.environ, AUZIX_SETTINGS=temporary), capture_output=True)
            self.assertEqual(run().returncode, 0)
            old.write_text('custom menu')
            self.assertEqual(run().returncode, 0)
            self.assertFalse(old.exists())
            self.assertEqual(new.read_text(), 'custom menu')
            self.assertEqual(run().returncode, 0)
            old.write_text('different menu')
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(old.read_text(), 'different menu')
            self.assertEqual(new.read_text(), 'custom menu')
            old.unlink()
            old.symlink_to(new)
            self.assertNotEqual(run().returncode, 0)

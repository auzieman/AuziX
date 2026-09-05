import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from auzix.lifecycle_intake import normalize_lifecycle


class DebianMigrationBmlTests(unittest.TestCase):
    def normalize(self, name, stage, fixture):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        prefix = '/Programs/' + name + '/1'
        script = root / prefix.lstrip('/') / 'Metadata/debian-control-dir' / stage
        script.parent.mkdir(parents=True)
        script.write_text((Path(__file__).parent / 'fixtures/debian-migrations' / fixture).read_text())
        result = normalize_lifecycle(root, {'name': name, 'version': '1', 'prefix': prefix}, root / 'review')
        return root, result, Path(result['scripts'][0]['candidate'])

    def test_xml_nested_multiline_purge_preserves_valid_shell(self):
        root, result, script = self.normalize('XMLCore', 'postrm', 'xml-core.postrm')
        self.assertEqual(result['status'], 'ready', result['findings'])
        subprocess.run(['sh', '-n', str(script)], check=True)
        self.assertNotIn('rm -f', script.read_text())

    def test_unversioned_migration_preserves_file_and_replays(self):
        root, result, script = self.normalize('XdgUserDirs', 'preinst', 'xdg-user-dirs.preinst')
        self.assertEqual(result['status'], 'ready', result['findings'])
        settings = root / 'settings'
        old = settings / 'X11/Xsession.d/60xdg-user-dirs-update'
        old.parent.mkdir(parents=True)
        env = {**os.environ, 'AUZIX_SETTINGS': str(settings)}
        subprocess.run(['sh', str(script)], env=env, check=True)  # fresh install
        old.write_text('user configuration')
        subprocess.run(['sh', str(script)], env=env, check=True)
        backup = Path(str(old) + '.auzix-bak')
        self.assertEqual(backup.read_text(), 'user configuration')
        subprocess.run(['sh', str(script)], env=env, check=True)  # replay
        old.write_text('new local configuration')
        self.assertNotEqual(subprocess.run(['sh', str(script)], env=env, capture_output=True).returncode, 0)
        self.assertEqual(old.read_text(), 'new local configuration')
        self.assertEqual(backup.read_text(), 'user configuration')
        old.unlink()
        old.symlink_to(backup)
        self.assertNotEqual(subprocess.run(['sh', str(script)], env=env, capture_output=True).returncode, 0)
        self.assertEqual(backup.read_text(), 'user configuration')

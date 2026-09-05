import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "alpha_inputs", Path(__file__).parents[1] / "scripts/prepare-auzix-alpha-archives.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AlphaArchiveInputsTests(unittest.TestCase):
    def test_selected_payloads_keep_primary_repairs_and_provider_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            primary, supplement = root / "primary", root / "supplement"
            for spool, names in ((primary, ["App"]), (supplement, ["App", "Lib", "Other"])):
                (spool / "entries").mkdir(parents=True)
                (spool / "packages").mkdir()
                for name in names:
                    filename = name + ".tar.gz"
                    (spool / "entries" / (name + ".json")).write_text(json.dumps(
                        {"name": name, "package": filename}))
                    (spool / "packages" / filename).write_text(spool.name)
            base, extra = root / "base.json", root / "extra.json"
            base.write_text(json.dumps({"packages": ["App"], "external_providers": {"Core": "runtime"}}))
            extra.write_text(json.dumps({"packages": ["Lib"], "package_names": {"Lib": "lib-real"}}))
            output = root / "output"
            module.prepare(primary, supplement, base, extra, output)
            self.assertEqual((output / "packages/App.tar.gz").read_text(), "primary")
            self.assertFalse((output / "packages/Other.tar.gz").exists())
            self.assertEqual(len(json.loads((output / "index.json").read_text())["packages"]), 3)
            profile = json.loads((output / "profile.json").read_text())
            self.assertEqual(profile["packages"], ["App", "Lib"])
            self.assertEqual(profile["external_providers"], {"Core": "runtime"})
            with self.assertRaises(FileExistsError):
                module.prepare(primary, supplement, base, extra, output)

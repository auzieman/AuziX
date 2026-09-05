import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import os
import subprocess
from auzix.lifecycle_intake import normalize_lifecycle

spec = importlib.util.spec_from_file_location(
    "alpha_inputs", Path(__file__).parents[1] / "scripts/prepare-auzix-alpha-archives.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AlphaArchiveInputsTests(unittest.TestCase):
    def test_kmod_adapter_accounts_for_donor_protocol(self):
        package = json.loads((Path(__file__).parents[1] /
            "packaging/packages/kmod/package.json").read_text())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "root"
            prefix = "/Programs/Kmod/34.2-2"
            control = root / prefix.lstrip("/") / "Metadata/debian-control-dir"
            control.mkdir(parents=True)
            (control / "postinst").write_text(
                '#!/bin/sh\ndpkg --compare-versions "$2" lt 34-3~\nupdate-rc.d kmod remove\n')
            (control / "triggers").write_text("activate-noawait update-initramfs\n")
            receipt = {"name": "Kmod", "version": "34.2-2", "prefix": prefix,
                "maintainer_surfaces": [prefix + "/Metadata/debian-control-dir/" + name
                                        for name in ("postinst", "triggers")]}
            result = normalize_lifecycle(root, receipt, Path(temporary) / "review", package)
            self.assertEqual(result["findings"], [])
            self.assertEqual(len(result["scripts"]), 1)
            rendered = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("update-rc.d", rendered)
            self.assertIn("preserve-existing", str(result["operations"]))

    def test_kmod_configuration_is_created_once_and_preserved(self):
        script = Path(__file__).parents[1] / "packaging/packages/kmod/lifecycle/after-install"
        with tempfile.TemporaryDirectory() as temporary:
            settings = Path(temporary)
            env = dict(os.environ, AUZIX_SETTINGS=temporary)
            subprocess.run(["sh", str(script), "34.2-2"], env=env, check=True)
            self.assertTrue((settings / "modules-load.d").is_dir())
            self.assertIn("obsolete", (settings / "modules").read_text())
            (settings / "modules").write_text("virtio_net\n")
            subprocess.run(["sh", str(script), "34.2-2"], env=env, check=True)
            self.assertEqual((settings / "modules").read_text(), "virtio_net\n")

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
                        {"name": name, "package": filename, "depends": ["Libgtk3Common"]}))
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
            apks = root / "apks"
            apks.mkdir()
            (apks / "libgtk-3-common-0.123-r0.apk").touch()
            mapped = root / "mapped"
            module.prepare(primary, supplement, base, extra, mapped, apks)
            mapped_profile = json.loads((mapped / "profile.json").read_text())
            self.assertEqual(mapped_profile["external_providers"]["Libgtk3Common"], "libgtk-3-common")

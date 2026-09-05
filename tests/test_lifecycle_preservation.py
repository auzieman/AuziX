import tempfile
import unittest
from pathlib import Path

from auzix.archive_fpm import _automatic_library_definition
from auzix.lifecycle_intake import normalize_lifecycle


class LifecyclePreservationTests(unittest.TestCase):
    def normalize(self, script, adapter=True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name) / "root"
        control = root / "Programs/LibExample/1/Metadata/debian-control-dir"
        control.mkdir(parents=True)
        (control / "postinst").write_text(script)
        receipt = {"name": "LibExample", "version": "1",
                   "prefix": "/Programs/LibExample/1", "maintainer_surfaces": []}
        definition = _automatic_library_definition(receipt) if adapter else None
        return normalize_lifecycle(root, receipt, Path(temporary.name) / "review", definition)

    def test_discovers_control_without_receipt_annotation(self):
        result = self.normalize("#!/bin/sh\nmkdir -p /var/lib/example\n", False)
        self.assertNotEqual(result["status"], "static")
        self.assertEqual(len(result["scripts"]), 1)
        self.assertEqual(len(result["donor_objects"]), 1)

    def test_library_adapter_preserves_donor_script(self):
        result = self.normalize("#!/bin/sh\nmkdir -p /var/lib/example\n")
        self.assertEqual(result["adapter"]["disposition"], "augmented-by-package-adapter")
        self.assertEqual(len(result["scripts"]), 1)
        self.assertIn("mkdir", Path(result["scripts"][0]["candidate"]).read_text())

    def test_library_adapter_does_not_hide_unresolved_effect(self):
        result = self.normalize("#!/bin/sh\nfiles=$(dpkg -L libpython)\n")
        self.assertEqual(result["status"], "needs-review")
        self.assertTrue(result["findings"])
        self.assertEqual(len(result["scripts"]), 1)

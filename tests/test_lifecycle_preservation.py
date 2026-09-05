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

    def _stage_helper(self, script):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name) / "root"
        prefix = root / "Programs/LibExample/1"
        control = prefix / "Metadata/debian-control-dir"
        control.mkdir(parents=True)
        helper = prefix / "RootFS/usr/lib/example/helper"
        helper.parent.mkdir(parents=True)
        helper.write_text("fixture\n")
        helper.chmod(0o755)
        (control / "postinst").write_text(script)
        receipt = {
            "name": "LibExample",
            "version": "1",
            "prefix": "/Programs/LibExample/1",
            "maintainer_surfaces": [],
        }
        return normalize_lifecycle(root, receipt, Path(temporary.name) / "review")

    def test_imports_debian_statoverride_add_without_package_adapter(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            "ACCOUNT=examplebus\n"
            "HELPER=/usr/lib/example/helper\n"
            'if ! dpkg-statoverride --list "$HELPER" >/dev/null; then\n'
            '    dpkg-statoverride --update --add root "$ACCOUNT" 4754 "$HELPER"\n'
            "fi\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("auzix_apply_statoverride", rendered)
        self.assertNotIn("dpkg-statoverride", rendered)
        self.assertTrue(
            any(item.get("type") == "apply-statoverride" for item in result["operations"])
        )
        self.assertFalse(
            any(finding.get("kind") == "dpkg-helper" for finding in result["findings"])
        )

    def test_rewrite_paths_sed_fills_unowned_script_gaps(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            "HELPER=/usr/lib/example/helper\n"
            "pidof /bin/dbus-daemon /usr/bin/dbus-daemon >/dev/null || true\n"
            "[ -S /var/run/dbus/system_bus_socket ] || true\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("${AUZIX_PACKAGE_ROOT}/RootFS/usr/lib/example/helper", rendered)
        self.assertIn("/System/Compatibility/bin/dbus-daemon", rendered)
        self.assertIn("${AUZIX_RUN}/dbus/system_bus_socket", rendered)
        self.assertFalse(
            any(finding.get("kind") == "unmapped-path" for finding in result["findings"])
        )

    def test_conffiles_use_shared_rewrite_table(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name) / "root"
        prefix = root / "Programs/LibExample/1"
        control = prefix / "Metadata/debian-control-dir"
        control.mkdir(parents=True)
        payload = prefix / "RootFS/etc/example/foo.conf"
        payload.parent.mkdir(parents=True)
        payload.write_text("owned\n")
        (control / "conffiles").write_text("/etc/example/foo.conf\n")
        receipt = {
            "name": "LibExample",
            "version": "1",
            "prefix": "/Programs/LibExample/1",
            "maintainer_surfaces": [],
        }
        result = normalize_lifecycle(root, receipt, Path(temporary.name) / "review")
        self.assertIn("${AUZIX_SETTINGS}/example/foo.conf", result["configuration"])
        self.assertFalse(
            any(finding.get("kind") == "unmapped-path" for finding in result["findings"])
        )

    def test_imports_debian_system_account_without_package_adapter(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            "ACCOUNT=examplebus\n"
            "if command -v systemd-sysusers >/dev/null; then\n"
            '    systemd-sysusers ${DPKG_ROOT:+--root="$DPKG_ROOT"} example.conf\n'
            "else\n"
            '    adduser --system --quiet --group "$ACCOUNT"\n'
            "fi\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("auzix_ensure_system_account \"$ACCOUNT\"", rendered)
        self.assertNotIn("systemd-sysusers", rendered)
        self.assertNotIn("dpkg-statoverride", rendered)
        self.assertTrue(
            any(item.get("type") == "ensure-system-account" for item in result["operations"])
        )
        self.assertFalse(
            any(
                finding.get("kind") in {"package-account-helper", "donor-root-variable"}
                for finding in result["findings"]
            )
        )

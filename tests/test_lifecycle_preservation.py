import tempfile
import unittest
from pathlib import Path

import json

from auzix.archive_fpm import _automatic_library_definition
from auzix.lifecycle_intake import normalize_lifecycle, promote_auzix_package


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
        self.assertIn("/usr/bin/dbus-daemon", rendered)
        self.assertIn("/bin/dbus-daemon", rendered)
        self.assertIn("${AUZIX_RUN}/dbus/system_bus_socket", rendered)
        paths = [
            match
            for finding in result["findings"]
            if finding.get("kind") == "unmapped-path"
            for match in finding["matches"]
        ]
        self.assertIn("/usr/bin/dbus-daemon", paths)
        self.assertIn("/bin/dbus-daemon", paths)

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

    def test_imports_in_sysroot_account_and_drops_dpkg_root(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            "MESSAGEUSER=examplebus\n"
            "in_sysroot () {\n"
            '    if [ -z "${DPKG_ROOT:-}" ]; then\n'
            '        "$@"\n'
            "    else\n"
            '        chroot "${DPKG_ROOT}" "$@"\n'
            "    fi\n"
            "}\n"
            "if command -v systemd-sysusers >/dev/null; then\n"
            '    systemd-sysusers ${DPKG_ROOT:+--root="$DPKG_ROOT"} example.conf\n'
            "else\n"
            '    in_sysroot adduser --system --quiet --group "$MESSAGEUSER"\n'
            "fi\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("auzix_ensure_system_account", rendered)
        self.assertNotIn("in_sysroot", rendered)
        self.assertNotIn("DPKG_ROOT", rendered)
        self.assertFalse(
            any(finding.get("kind") == "donor-root-variable" for finding in result["findings"])
        )

    def test_compare_versions_is_upgrade_protocol(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            'if [ "$1" = configure -a -n "$2" ]; then\n'
            '    if dpkg --compare-versions "$2" lt "2012.1"; then\n'
            "        :\n"
            "    fi\n"
            "fi\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("auzix_upgrade_cmp", rendered)
        self.assertNotIn("dpkg --compare-versions \"$2\"", rendered)
        self.assertTrue(
            any(item.get("type") == "upgrade-compare" for item in result["operations"])
        )
        self.assertFalse(
            any(finding.get("kind") == "dpkg-helper" for finding in result["findings"])
        )

    def test_invoke_rc_restart_owns_services_run(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            "case \"$1\" in\n"
            "        configure)\n"
            "                invoke-rc.d acpid restart >/dev/null || true\n"
            "                ;;\n"
            "esac\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("/Services/acpid/run", rendered)
        self.assertNotIn("invoke-rc.d", rendered)
        self.assertNotIn("auzix_reload_service", rendered)
        self.assertTrue(
            any(
                item.get("type") == "own-service" and item.get("path") == "/Services/acpid/run"
                for item in result["operations"]
            )
        )
        self.assertFalse(
            any(finding.get("kind") == "debian-service-helper" for finding in result["findings"])
        )

    def test_sysctl_system_becomes_apply_sysctl(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            "if command -v sysctl > /dev/null; then\n"
            "    sysctl --quiet --pattern '^kernel.unprivileged_userns_clone$' --system || :\n"
            "fi\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("auzix_apply_sysctl", rendered)
        self.assertNotIn("if command -v sysctl", rendered.split("auzix_maintainer_main", 1)[-1])
        self.assertTrue(
            any(item.get("type") == "apply-sysctl" for item in result["operations"])
        )
        self.assertFalse(
            any(finding.get("kind") == "package-trigger-helper" for finding in result["findings"])
        )

    def test_recovered_hook_attaches_to_apk_script_slot(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name) / "root"
        prefix = root / "Programs/LibExample/1"
        control = prefix / "Metadata/debian-control-dir"
        control.mkdir(parents=True)
        (control / "postinst").write_text(
            "#!/bin/sh\ninvoke-rc.d acpid restart >/dev/null || true\n"
        )
        receipt_path = root / "System/PackageDB/LibExample-1.json"
        receipt_path.parent.mkdir(parents=True)
        receipt = {
            "name": "LibExample",
            "version": "1",
            "prefix": "/Programs/LibExample/1",
            "maintainer_surfaces": [],
        }
        receipt_path.write_text(json.dumps(receipt))
        intake = normalize_lifecycle(root, receipt, Path(temporary.name) / "review")
        package_json, scripts = promote_auzix_package(root, receipt_path, intake, None)
        self.assertEqual(package_json["lifecycle"]["after_install"], "/Programs/LibExample/1/Package/Scripts/after-install")
        self.assertTrue(any(flag == "--after-install" for flag, _ in scripts))
        hook = root / "Programs/LibExample/1/Package/Scripts/after-install"
        self.assertTrue(hook.is_file())
        self.assertIn("/Services/acpid/run", hook.read_text())
        self.assertNotIn("auzix_reload_service", hook.read_text())
        service = root / "Services/acpid/run"
        self.assertTrue(service.is_file())
        self.assertIn("NAME=acpid", service.read_text())

    def test_generated_systemd_scaffold_owns_services_run(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            'if [ -z "$DPKG_ROOT" ] && [ -d /run/systemd/system ]; then\n'
            "    systemctl --system daemon-reload >/dev/null || true\n"
            "    deb-systemd-invoke $_dh_action 'example.service' >/dev/null || true\n"
            "fi\n"
            'if [ -z "$DPKG_ROOT" ] && [ -x /etc/init.d/example ]; then\n'
            "    update-rc.d example defaults >/dev/null\n"
            "    invoke-rc.d --skip-systemd-native example start || exit 1\n"
            "fi\n"
            "deb-systemd-helper enable 'example.service' >/dev/null || true\n"
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("/Services/example/run", rendered)
        self.assertNotIn("auzix_reload_service", rendered)
        self.assertNotIn("auzix_enable_service", rendered)
        self.assertNotIn("DPKG_ROOT", rendered)
        self.assertNotIn("invoke-rc.d", rendered)
        self.assertNotIn("deb-systemd-invoke", rendered)
        self.assertNotIn("deb-systemd-helper", rendered)
        self.assertTrue(
            any(
                item.get("type") == "own-service" and item.get("path") == "/Services/example/run"
                for item in result["operations"]
            )
        )
        self.assertFalse(
            any(
                finding.get("kind") in {
                    "donor-root-variable",
                    "debian-service-helper",
                    "foreign-service-manager",
                }
                for finding in result["findings"]
            )
        )

    def test_dpkg_root_etc_rewrites_to_settings(self):
        result = self._stage_helper(
            "#!/bin/sh\n"
            'sed -E -i "${DPKG_ROOT}/etc/nsswitch.conf" -e "/^passwd:/ s/$/ systemd/"\n'
        )
        rendered = Path(result["scripts"][0]["candidate"]).read_text()
        self.assertIn("${AUZIX_SETTINGS}/nsswitch.conf", rendered)
        self.assertNotIn("DPKG_ROOT", rendered)
        self.assertFalse(
            any(finding.get("kind") == "donor-root-variable" for finding in result["findings"])
        )

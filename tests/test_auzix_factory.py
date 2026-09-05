import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from auzix.contracts import ContractError
from auzix.model_review import validate_proposal

from auzix.activation.base import activate_base
from auzix.package_graph import compose_profile
from auzix.targets import compose_target
from auzix.names import apk_name, apk_version
from auzix.package_graph import load_packages
from auzix.layout import activate_layout
from auzix.apk import compose_apk_layers
from auzix.staging import stage_package
from auzix.fpm import emit_apk, receipt_fpm_metadata
from auzix.archive_fpm import (
    _archive_apk_name, _archive_layout_domain, _automatic_library_definition,
    _with_automatic_library_publication, _review_summary,
)
from auzix.lifecycle_intake import normalize_lifecycle, promote_auzix_package
from auzix.intake_ir import account_donor_script, grok_donor_script


class FactoryTests(unittest.TestCase):
    def test_native_package_depends_on_declared_archive_provider(self):
        package = {
            "name": "DesktopAssets", "version": "1.0", "source": {},
            "dependencies": {
                "runtime": ["BusyBox", "Enlightenment"],
                "apk_providers": {"Enlightenment": "enlightenment"},
            },
        }
        with tempfile.TemporaryDirectory() as work, \
                patch("auzix.fpm.shutil.which", return_value="/usr/bin/fpm"), \
                patch("auzix.fpm.validate_staged_payload"):
            argv = emit_apk(package, Path(work), Path(work) / "out", dry_run=True)
        dependencies = [argv[i + 1] for i, item in enumerate(argv) if item == "--depends"]
        self.assertEqual(dependencies, ["auzix-busy-box", "enlightenment"])

    def test_donor_intake_accounts_for_every_line(self):
        source = "#!/bin/sh\n# donor note\nmkdir -p /var/lib/example\ndpkg-query -W example\n"
        accounted = account_donor_script("control/postinst", source)
        self.assertEqual(accounted["lines"], 4)
        self.assertEqual(
            [hunk["lines"] for hunk in accounted["hunks"]],
            [[1, 1], [2, 2], [3, 3], [4, 4]],
        )
        self.assertEqual(accounted["hunks"][2]["disposition"], "preserve")
        self.assertEqual(accounted["hunks"][3]["disposition"], "requires-translation")

    def test_extended_grok_extracts_python_effects_with_exact_evidence(self):
        source = r"""#!/bin/sh
files=$(dpkg -L libpython3.13-minimal:amd64 \\
    | sed -n '/python3.13\/.*\\.py$/p')
/usr/bin/python3.13 -E -S /usr/lib/python3.13/py_compile.py $files
for hook in /usr/share/python3/runtime.d/*.rtinstall; do
    $hook rtinstall python3.13
done
update-binfmts --import python3.13
mkdir -p /usr/local/lib/python3.13
"""
        effects = grok_donor_script("control/postinst", source)
        by_type = {effect["type"]: effect for effect in effects}
        self.assertEqual(by_type["package-payload-query"]["target"], "libpython3.13-minimal:amd64")
        self.assertEqual(by_type["package-payload-query"]["evidence"]["lines"], [2, 3])
        self.assertEqual(by_type["python-bytecode-compile"]["disposition"], "portable-intent")
        self.assertEqual(by_type["python-bytecode-compile"]["target"], "/usr/bin/python3.13")
        self.assertEqual(by_type["runtime-hook-dispatch"]["disposition"], "donor-protocol")
        self.assertEqual(by_type["binfmt-registration"]["disposition"], "deferred-boot-action")
        self.assertEqual(by_type["filesystem-effect"]["command"], "mkdir")

    def test_extended_grok_ignores_shell_case_and_helper_probe(self):
        effects = grok_donor_script(
            "control/postinst",
            "case \"$1\" in\n  install) : ;;\nesac\n"
            "if command -v update-binfmts >/dev/null; then\n  :\nfi\n",
        )
        self.assertEqual(effects, [])

    def test_extended_grok_connects_function_call_arguments(self):
        effects = grok_donor_script(
            "control/prerm",
            "remove_bytecode()\n{\n  pkg=$1\n  dpkg -L $pkg\n}\n"
            "remove_bytecode libpython3.13-stdlib:amd64\n",
        )
        query = next(effect for effect in effects if effect["type"] == "package-payload-query")
        dispatch = next(effect for effect in effects if effect["type"] == "function-dispatch")
        self.assertEqual(query["target"], "$pkg")
        self.assertEqual(dispatch["function"], "remove_bytecode")
        self.assertEqual(dispatch["arguments"], "libpython3.13-stdlib:amd64")
        self.assertEqual(dispatch["disposition"], "unresolved-relationship")
        self.assertEqual(
            len([effect for effect in effects if effect["type"] == "function-dispatch"]),
            1,
        )

    def test_lifecycle_manifest_keeps_grok_candidates_out_of_approved_operations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Python/1/Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\nfiles=$(dpkg -L libpython)\n")
            result = normalize_lifecycle(root, {
                "name": "Python", "version": "1", "prefix": "/Programs/Python/1",
                "maintainer_surfaces": ["/Programs/Python/1/Metadata/control/postinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "needs-review")
            self.assertEqual(result["operations"], [])
            self.assertEqual(result["effect_candidates"][0]["type"], "package-payload-query")
            self.assertEqual(result["effect_candidates"][0]["stage"], "after_install")

    def test_lifecycle_intake_separates_donor_ir_and_rendered_script(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\nmkdir -p /var/lib/example\n")
            review = Path(directory) / "review"
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postinst"],
            }, review)
            self.assertTrue((review / "~deb_inst/postinst.original").is_file())
            self.assertTrue((review / "~deb_inst/postinst.hunks.json").is_file())
            self.assertTrue((review / "auzix/lifecycle.json").is_file())
            self.assertEqual(Path(result["scripts"][0]["candidate"]).parent, review / "rendered")
            self.assertEqual(result["donor_objects"][0]["lines"], 2)

    def test_review_summary_groups_semantics_and_keeps_outlier_order(self):
        summary = _review_summary([
            {
                "name": "Mixed", "apk_name": "mixed", "status": "needs-review",
                "intake": {
                    "scripts": [{}, {}],
                    "rules": [{"id": "generated-service-scaffold", "state": "recognized"}],
                    "residual_findings": [
                        {"kind": "debian-service-helper", "semantic_class": "service-intent"},
                        {"kind": "unmapped-path", "semantic_class": "unresolved-path-side-effect"},
                    ],
                },
            },
            {
                "name": "Simple", "apk_name": "simple", "status": "needs-review",
                "intake": {
                    "scripts": [{}], "rules": [],
                    "residual_findings": [{"kind": "maintainer-surface"}],
                },
            },
        ])
        self.assertEqual(summary["packages"], 2)
        self.assertEqual(summary["outliers"][0]["name"], "Mixed")
        self.assertEqual(summary["by_rule"][0]["rule"], "generated-service-scaffold")
        self.assertEqual(summary["by_semantic_class"][0]["count"], 1)

    def test_lifecycle_intake_normalizes_known_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\nmkdir -p /etc/example /var/lib/example /run/example\n")
            receipt = {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postinst"],
            }
            result = normalize_lifecycle(root, receipt, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("${AUZIX_SETTINGS}/example", candidate)
            self.assertIn("${AUZIX_STATE}/example", candidate)
            self.assertIn("${AUZIX_RUN}/example", candidate)

    def test_lifecycle_intake_queues_unknown_helpers_without_stopping_wave(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/preinst"
            script.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\ndpkg-maintscript-helper rm_conffile /etc/example\n")
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/preinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "needs-review")
            self.assertIn("dpkg-helper", {finding["kind"] for finding in result["findings"]})

    def test_lifecycle_intake_wraps_donor_action_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\n[ \"$1\" = configure ] && touch /etc/example\n")
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertNotIn("lifecycle-arguments", {finding["kind"] for finding in result["findings"]})
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("auzix_maintainer_main 'configure' ''", candidate)
            self.assertIn('[ "$1" = configure ]', candidate)
            self.assertEqual(result["rules"][0]["state"], "transformed")

    def test_lifecycle_intake_only_rewrites_package_owned_usr_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package = root / "Programs/Example/1"
            script = package / "Metadata/control/postinst"
            owned = package / "RootFS/usr/bin/example"
            script.parent.mkdir(parents=True)
            owned.parent.mkdir(parents=True)
            owned.touch()
            script.write_text("#!/bin/sh\n/usr/bin/example\n/usr/bin/external-helper\n")
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "needs-review")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("${AUZIX_PACKAGE_ROOT}/RootFS/usr/bin/example", candidate)
            self.assertIn("/usr/bin/external-helper", candidate)
            paths = [
                match for finding in result["findings"] if finding["kind"] == "unmapped-path"
                for match in finding["matches"]
            ]
            self.assertEqual(paths, ["/usr/bin/external-helper"])

    def test_python_runtime_cache_inherits_existing_payload_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package = root / "Programs/Python3Minimal/1"
            script = package / "Metadata/control/prerm"
            payload_parent = package / "RootFS/usr/share/python3/debpython"
            script.parent.mkdir(parents=True)
            payload_parent.mkdir(parents=True)
            script.write_text(
                "#!/bin/sh\n"
                "rm -rf /usr/share/python3/__pycache__\n"
                "rm -rf /usr/share/python3/debpython/__pycache__\n"
                "rm -rf /usr/share/external/__pycache__\n"
            )
            result = normalize_lifecycle(root, {
                "name": "Python3Minimal", "version": "1",
                "prefix": "/Programs/Python3Minimal/1",
                "maintainer_surfaces": ["/Programs/Python3Minimal/1/Metadata/control/prerm"],
            }, Path(directory) / "review")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn(
                "${AUZIX_PACKAGE_ROOT}/RootFS/usr/share/python3/__pycache__", candidate
            )
            self.assertIn(
                "${AUZIX_PACKAGE_ROOT}/RootFS/usr/share/python3/debpython/__pycache__", candidate
            )
            self.assertIn("/usr/share/external/__pycache__", candidate)
            self.assertEqual(result["status"], "needs-review")
            self.assertEqual(result["findings"][0]["matches"], [
                "/usr/share/external/__pycache__"
            ])

    def test_static_intake_promotes_native_package_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package_root = root / "Programs/Example/1"
            receipt_path = root / "System/PackageDB/Example-1.auzix.json"
            (package_root / "Metadata/debian-control-dir").mkdir(parents=True)
            receipt_path.parent.mkdir(parents=True)
            (package_root / "Metadata/debian-control.txt").write_text("donor\n")
            receipt_path.write_text(json.dumps({
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "source": {"type": "debian-binary-package"}, "direct_depends": ["Donor"],
                "maintainer_surfaces": [],
            }))
            intake = normalize_lifecycle(root, json.loads(receipt_path.read_text()), Path(directory) / "review")
            package_json, scripts = promote_auzix_package(root, receipt_path, intake, None)
            self.assertEqual(scripts, [])
            self.assertEqual(package_json["lifecycle"]["after_install"], None)
            self.assertEqual(
                (root / "Programs/Example/current").readlink(),
                Path("/Programs/Example/1"),
            )
            self.assertFalse((package_root / "Metadata/debian-control-dir").exists())
            self.assertFalse((package_root / "Metadata/debian-control.txt").exists())
            promoted_receipt = json.loads(receipt_path.read_text())
            self.assertNotIn("source", promoted_receipt)
            self.assertNotIn("direct_depends", promoted_receipt)

    def test_non_script_maintainer_surface_enters_review_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            trigger = root / "Programs/Example/1/Metadata/control/triggers"
            trigger.parent.mkdir(parents=True)
            trigger.write_text("interest example-cache\n")
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/triggers"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "needs-review")
            self.assertEqual(result["findings"][0]["kind"], "maintainer-surface")
            self.assertTrue((Path(directory) / "review/evidence/triggers").is_file())

    def test_plain_conffiles_are_translated_into_native_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package = root / "Programs/Example/1"
            conffiles = package / "Metadata/control/conffiles"
            payload = package / "RootFS/etc/example.conf"
            conffiles.parent.mkdir(parents=True)
            payload.parent.mkdir(parents=True)
            payload.write_text("setting=yes\n")
            conffiles.write_text("/etc/example.conf\n")
            receipt = {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/conffiles"],
            }
            result = normalize_lifecycle(root, receipt, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["configuration"], ["${AUZIX_SETTINGS}/example.conf"])
            self.assertEqual(result["rules"][0]["state"], "transformed")
            receipt_path = root / "System/PackageDB/Example-1.json"
            receipt_path.parent.mkdir(parents=True)
            receipt_path.write_text(json.dumps(receipt))
            package_json, _ = promote_auzix_package(root, receipt_path, result, None)
            self.assertTrue((root / "System/Settings/example.conf").is_file())
            self.assertFalse(payload.exists())
            self.assertEqual(
                package_json["configuration"]["protected_paths"],
                ["${AUZIX_SETTINGS}/example.conf"],
            )

    def test_conffile_directives_remain_in_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package = root / "Programs/Example/1"
            conffiles = package / "Metadata/control/conffiles"
            conffiles.parent.mkdir(parents=True)
            conffiles.write_text("remove-on-upgrade /etc/example.conf\n")
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/conffiles"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "needs-review")
            self.assertEqual(result["findings"][0]["kind"], "conffile-directive")
            self.assertEqual(result["rules"][0]["state"], "residual")

    def test_exact_trigger_is_named_but_remains_residual_until_implemented(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            trigger = root / "Programs/Example/1/Metadata/control/triggers"
            library = root / "Programs/Example/1/RootFS/usr/lib/x86_64-linux-gnu/libexample.so.1"
            trigger.parent.mkdir(parents=True)
            library.parent.mkdir(parents=True)
            library.write_bytes(b"shared-object-placeholder")
            trigger.write_text("# generated\nactivate-noawait ldconfig\n")
            receipt_data = {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/triggers"],
            }
            result = normalize_lifecycle(root, receipt_data, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["rules"][0]["id"], "ldconfig-trigger")
            self.assertEqual(result["rules"][0]["state"], "transformed")
            self.assertEqual(result["residual_findings"], result["findings"])
            receipt = root / "System/PackageDB/Example-1.json"
            receipt.parent.mkdir(parents=True)
            receipt.write_text(json.dumps(receipt_data))
            package_json, _ = promote_auzix_package(root, receipt, result, None)
            owned = root / "Libraries/Packages/Example/1/libexample.so.1"
            public = root / "Libraries/libexample.so.1"
            self.assertTrue(owned.is_file())
            self.assertEqual(public.readlink(), Path("Packages/Example/1/libexample.so.1"))
            self.assertEqual(package_json["libraries"]["public"], ["/Libraries/libexample.so.1"])

    def test_python_cleanup_drops_dpkg_database_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/PythonLeaf/1/Metadata/control/prerm"
            payload = root / "Programs/PythonLeaf/1/RootFS/usr/lib/python3/dist-packages"
            script.parent.mkdir(parents=True)
            payload.mkdir(parents=True)
            script.write_text("""#!/bin/sh
# Automatically added by dh_python3
if command -v py3clean >/dev/null 2>&1; then
    py3clean -p python3-leaf
else
    dpkg -L python3-leaf | sed -En -e '/py$/d'
    find /usr/lib/python3/dist-packages/ -type d -name __pycache__ -empty -print0 | xargs --null --no-run-if-empty rmdir
fi
""")
            result = normalize_lifecycle(root, {
                "name": "PythonLeaf", "version": "1", "prefix": "/Programs/PythonLeaf/1",
                "maintainer_surfaces": ["/Programs/PythonLeaf/1/Metadata/control/prerm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["rules"][0]["id"], "python-bytecode-cleanup")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("dpkg -L", candidate)
            self.assertIn("-name '*.pyc'", candidate)

    def test_self_package_python_cache_cleanup_is_root_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Libstdc6/1/Metadata/control/prerm"
            script.parent.mkdir(parents=True)
            script.write_text("""#!/bin/sh
files=$(dpkg -L libstdc++6:amd64 | awk '/.py$/ {print}')
rm -f $files
dirs=$(dpkg -L libstdc++6:amd64 | awk '/.py$/ {print}')
find $dirs -name __pycache__ -type d -empty | xargs -r rmdir
""")
            result = normalize_lifecycle(root, {
                "name": "Libstdc6", "version": "1", "prefix": "/Programs/Libstdc6/1",
                "maintainer_surfaces": ["/Programs/Libstdc6/1/Metadata/control/prerm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("dpkg -L", candidate)
            self.assertIn('find "/Programs/Libstdc6/1/RootFS"', candidate)
            self.assertIn("-name '*.pyc'", candidate)
            self.assertIn("-name __pycache__ -empty -delete", candidate)

    def test_libreoffice_ucf_cleanup_keeps_native_filesystem_effect(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/LibreOfficeWriter/1/Metadata/control/preinst"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
set -e
if [ "$1" = "upgrade" ] && dpkg --compare-versions "$2" lt 4:25.2.1~rc1-3; then
\trm -f /etc/libreoffice/registry/writer.xcd
\tucf --purge /etc/libreoffice/registry/writer.xcd
\tucfr --force --purge libreoffice-writer /etc/libreoffice/registry/writer.xcd
elif [ "$1" = "install" ] && [ -f /etc/libreoffice/registry/writer.xcd ]; then
\trm -f /etc/libreoffice/registry/writer.xcd
\tucf --purge /etc/libreoffice/registry/writer.xcd
\tucfr --force --purge libreoffice-writer /etc/libreoffice/registry/writer.xcd
fi
''')
            result = normalize_lifecycle(root, {
                "name": "LibreOfficeWriter", "version": "1",
                "prefix": "/Programs/LibreOfficeWriter/1",
                "maintainer_surfaces": [str(script.relative_to(root)).join(("/", ""))],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["migrations"][0]["operation"], "remove-obsolete-managed-configuration")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("rm -f ${AUZIX_SETTINGS}/libreoffice/registry/writer.xcd", candidate)
            self.assertNotIn("dpkg", candidate)
            self.assertNotIn("ucf", candidate)

    def test_var_spool_maps_to_mutable_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postrm"
            script.parent.mkdir(parents=True)
            script.write_text('#!/bin/sh\nrm -rf /var/spool/example\n')
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postrm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("rm -rf ${AUZIX_STATE}/spool/example", candidate)

    def test_libreoffice_registry_loop_becomes_native_migrations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/LibreOfficeDraw/1/Metadata/control/preinst"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
set -e
if [ "$1" = "upgrade" ] && dpkg --compare-versions "$2" lt 4:25.2.1~rc1-3; then
\tfor i in draw.xcd graphicfilter.xcd; do
\t\trm -f /etc/libreoffice/registry/$i
\t\tucf --purge /etc/libreoffice/registry/$i
\t\tucfr --force --purge libreoffice-draw /etc/libreoffice/registry/$i
\tdone
elif [ "$1" = "install" ] && [ -f /etc/libreoffice/registry/draw.xcd ]; then
\tfor i in draw.xcd graphicfilter.xcd; do
\t\trm -f /etc/libreoffice/registry/$i
\t\tucf --purge /etc/libreoffice/registry/$i
\t\tucfr --force --purge libreoffice-draw /etc/libreoffice/registry/$i
\tdone
fi
''')
            result = normalize_lifecycle(root, {
                "name": "LibreOfficeDraw", "version": "1",
                "prefix": "/Programs/LibreOfficeDraw/1",
                "maintainer_surfaces": ["/Programs/LibreOfficeDraw/1/Metadata/control/preinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(len(result["migrations"]), 2)
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("for i in draw.xcd graphicfilter.xcd", candidate)
            self.assertNotIn("dpkg", candidate)
            self.assertNotIn("ucfr", candidate)

    def test_after_remove_prunes_nested_purge_only_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postrm"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
set -e
if [ "$1" = "purge" ] && ! [ -e /etc/example.conf ]; then
    if [ -d /var/cache/example ]; then
        rm -f /var/cache/example/generated.cache
    fi
fi
''')
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postrm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("generated.cache", candidate)
            self.assertIn("purge-only effects", candidate)

    def test_after_remove_prunes_two_line_purge_only_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Fonts/1/Metadata/control/postrm"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
if [ "$1" = "purge" ]
then
    rm -f /usr/share/fonts/X11/fonts.scale
fi
''')
            result = normalize_lifecycle(root, {
                "name": "Fonts", "version": "1", "prefix": "/Programs/Fonts/1",
                "maintainer_surfaces": ["/Programs/Fonts/1/Metadata/control/postrm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("/usr/share/fonts", candidate)
            self.assertIn("purge-only effects", candidate)

    def test_after_remove_keeps_real_remove_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postrm"
            script.parent.mkdir(parents=True)
            script.write_text('#!/bin/sh\nif [ "$1" = "remove" ]; then\n rm -f /var/cache/example/live\nfi\n')
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postrm"],
            }, Path(directory) / "review")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("${AUZIX_CACHE}/example/live", candidate)

    def test_purge_pruning_removes_transitively_unused_path_variables(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Xserver/1/Metadata/control/postrm"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
CONFIG_DIR=/etc/X11
CONFIG_FILE="$CONFIG_DIR/xorg.conf"
THIS_SERVER=/usr/bin/Xorg
if [ "$1" = "purge" ]; then
  rm -f "$CONFIG_FILE"
fi
''')
            result = normalize_lifecycle(root, {
                "name": "Xserver", "version": "1", "prefix": "/Programs/Xserver/1",
                "maintainer_surfaces": ["/Programs/Xserver/1/Metadata/control/postrm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("/usr/bin/Xorg", candidate)
            self.assertNotIn("xorg.conf", candidate)

    def test_statoverride_wrapper_keeps_guarded_chmod(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Xinit/1/Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
if [ "$1" = configure ]; then
    if dpkg --compare-versions "$2" lt-nl "1.3.4-2~"; then
        if ! dpkg-statoverride --list /etc/X11/xinit/xinitrc >/dev/null 2>&1 && \\
            [ -e /etc/X11/xinit/xinitrc ]; then
            chmod 0755 /etc/X11/xinit/xinitrc
        fi
    fi
fi
''')
            result = normalize_lifecycle(root, {
                "name": "Xinit", "version": "1", "prefix": "/Programs/Xinit/1",
                "maintainer_surfaces": ["/Programs/Xinit/1/Metadata/control/postinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("chmod 0755 ${AUZIX_SETTINGS}/X11/xinit/xinitrc", candidate)
            self.assertNotIn("dpkg", candidate)

    def test_comment_paths_are_not_runtime_findings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postrm"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/bin/sh\n# License: /usr/share/common-licenses/GPL\nexit 0\n"
            )
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postrm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")

    def test_constant_false_debconf_surface_is_architecture_inapplicable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            control = root / "Programs/Calc/1/Metadata/control"
            control.mkdir(parents=True)
            body = '''#!/bin/sh
. /usr/share/debconf/confmodule
if [ "amd64" = "riscv64" ]; then
    db_get calc/warning
fi
'''
            (control / "config").write_text(body)
            (control / "templates").write_text("Template: calc/warning\nType: note\n")
            (control / "postinst").write_text(body)
            result = normalize_lifecycle(root, {
                "name": "Calc", "version": "1", "prefix": "/Programs/Calc/1",
                "maintainer_surfaces": [
                    "/Programs/Calc/1/Metadata/control/config",
                    "/Programs/Calc/1/Metadata/control/templates",
                    "/Programs/Calc/1/Metadata/control/postinst",
                ],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("confmodule", candidate)
            self.assertNotIn("db_get", candidate)

    def test_alternative_library_becomes_payload_owned_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package = root / "Programs/Blas/1"
            provider = package / "RootFS/usr/lib/x86_64-linux-gnu/blas/libblas.so.3"
            provider.parent.mkdir(parents=True)
            provider.write_bytes(b"provider")
            script = package / "Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so.3 \\
 libblas.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/blas/libblas.so.3 10
''')
            receipt_data = {
                "name": "Blas", "version": "1", "prefix": "/Programs/Blas/1",
                "maintainer_surfaces": ["/Programs/Blas/1/Metadata/control/postinst"],
            }
            result = normalize_lifecycle(root, receipt_data, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["library_publications"][0]["public"], "/Libraries/libblas.so.3")
            receipt = root / "System/PackageDB/Blas-1.json"
            receipt.parent.mkdir(parents=True)
            receipt.write_text(json.dumps(receipt_data))
            promote_auzix_package(root, receipt, result, None)
            public = root / "Libraries/libblas.so.3"
            self.assertEqual(public.readlink(), Path("../Programs/Blas/1/RootFS/usr/lib/x86_64-linux-gnu/blas/libblas.so.3"))
            self.assertTrue(provider.is_file())

    def test_alternative_command_uses_highest_package_priority(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package = root / "Programs/Xterm/1"
            for command in ("xterm", "lxterm"):
                target = package / f"RootFS/usr/bin/{command}"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(command.encode())
            script = package / "Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text('''#!/bin/sh
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/xterm 20
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/lxterm 30
''')
            result = normalize_lifecycle(root, {
                "name": "Xterm", "version": "1", "prefix": "/Programs/Xterm/1",
                "maintainer_surfaces": ["/Programs/Xterm/1/Metadata/control/postinst"],
            }, Path(directory) / "review")
            publication = result["library_publications"][0]
            self.assertEqual(publication["public"], "/System/Compatibility/usr/bin/x-terminal-emulator")
            self.assertTrue(publication["source"].endswith("/usr/bin/lxterm"))

    def test_dependency_package_python_cache_query_stays_in_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Python/1/Metadata/control/prerm"
            script.parent.mkdir(parents=True)
            script.write_text("""#!/bin/sh
files=$(dpkg -L libpython:amd64 | awk '/.py$/ {print}')
rm -f $files
dirs=$(dpkg -L libpython:amd64 | awk '/.py$/ {print}')
find $dirs -name __pycache__ -type d -empty | xargs -r rmdir
""")
            result = normalize_lifecycle(root, {
                "name": "Python", "version": "1", "prefix": "/Programs/Python/1",
                "maintainer_surfaces": ["/Programs/Python/1/Metadata/control/prerm"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "needs-review")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("dpkg -L libpython:amd64", candidate)

    def test_rm_conffile_helper_becomes_native_migration_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/2/Metadata/control/preinst"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/bin/sh\n"
                "dpkg-maintscript-helper rm_conffile /etc/example.old 1.5 example -- \"$@\"\n"
            )
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "2", "prefix": "/Programs/Example/2",
                "maintainer_surfaces": ["/Programs/Example/2/Metadata/control/preinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["migrations"], [{
                "operation": "remove-obsolete-conffile",
                "path": "${AUZIX_SETTINGS}/example.old",
                "prior_version": "1.5",
                "stage": "before_install",
                "donor_package": "example",
            }])
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("dpkg-maintscript-helper", candidate)

    def test_dpkg_root_prefix_is_replaced_without_losing_effect_body(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/postinst"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/bin/sh\n"
                "old=${DPKG_ROOT:-}/var/lib/example/data\n"
                "new=\"$DPKG_ROOT\"/var/log/example/data\n"
                "mkdir -p \"$(dirname \"$new\")\"\n"
                "[ -f \"$old\" ] && mv \"$old\" \"$new\"\n"
            )
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/postinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertIn("old=${AUZIX_STATE}/example/data", candidate)
            self.assertIn("new=${AUZIX_LOGS}/example/data", candidate)
            self.assertIn('mv "$old" "$new"', candidate)

    def test_usrmerge_diversion_is_recorded_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            script = root / "Programs/Example/1/Metadata/control/preinst"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/bin/sh\n"
                "dpkg-divert --package example --no-rename \\\n"
                "  --divert /lib/libexample.so.1.usr-is-merged --add /lib/libexample.so.1\n"
            )
            result = normalize_lifecycle(root, {
                "name": "Example", "version": "1", "prefix": "/Programs/Example/1",
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/control/preinst"],
            }, Path(directory) / "review")
            self.assertEqual(result["status"], "ready")
            self.assertEqual(result["migrations"][0]["operation"], "debian-usrmerge-diversion")
            candidate = Path(result["scripts"][0]["candidate"]).read_text()
            self.assertNotIn("dpkg-divert", candidate)

    def test_debian_archive_packages_keep_native_apk_names(self):
        self.assertEqual(
            _archive_apk_name({"name": "Libncursesw6", "source": {"package": "libncursesw6"}}),
            "libncursesw6",
        )
        self.assertEqual(_archive_apk_name({"name": "Htop", "source": {"package": "htop"}}), "htop")
        self.assertEqual(_archive_apk_name({"name": "CustomTool"}), "custom-tool")

    def test_archive_library_layout_uses_native_metadata_not_legacy_kind(self):
        self.assertEqual(
            _archive_layout_domain({
                "name": "Libncursesw6", "kind": "staging",
                "prefix": "/Programs/Libncursesw6/6.5", "source": {"package": "libncursesw6"},
            }),
            "library",
        )

    def test_formulaic_library_adapter_keeps_manifest_dependencies(self):
        definition = _automatic_library_definition({"depends": ["Libc6", "Zlib1g"]})
        self.assertEqual(definition["dependencies"]["runtime"], ["Libc6", "Zlib1g"])
        self.assertTrue(definition["intake_adapter"]["publish_libraries"])

    def test_formulaic_library_publication_preserves_custom_adapter(self):
        original = {
            "dependencies": {"runtime": ["Libc6"]},
            "intake_adapter": {
                "format": "auzix-lifecycle-adapter-v1",
                "template_dir": "tests/fixtures/apk-trigger",
                "configuration": [],
                "scripts": {"after_install": "after-install"},
                "operations": [{"type": "custom-operation"}],
            },
        }
        merged = _with_automatic_library_publication({"depends": []}, original)
        self.assertEqual(merged["intake_adapter"]["scripts"], original["intake_adapter"]["scripts"])
        self.assertEqual(merged["intake_adapter"]["operations"][0]["type"], "custom-operation")
        self.assertTrue(merged["intake_adapter"]["publish_libraries"])
        self.assertNotIn("publish_libraries", original["intake_adapter"])
        self.assertEqual(
            _archive_layout_domain({"name": "NcursesBase", "kind": "staging", "source": {"package": "ncurses-base"}}),
            "library",
        )

    def test_package_json_maps_lifecycle_script_to_fpm_without_rewriting_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt = root / "System/PackageDB/OpensshServer-1.json"
            postinst = root / "Programs/OpensshServer/1/Package/Scripts/after-install"
            receipt.parent.mkdir(parents=True)
            postinst.parent.mkdir(parents=True)
            original = "#!/bin/sh\nmkdir -p /System/Settings/ssh /System/State/run/sshd\n"
            postinst.write_text(original, encoding="utf-8")
            receipt.write_text(json.dumps({"lifecycle": {"after_install": str(postinst)}}), encoding="utf-8")
            package = {
                "name": "OpensshServer",
                "version": "1",
                "lifecycle": {
                    "before_install": None,
                    "after_install": "/Programs/OpensshServer/${version}/Package/Scripts/after-install",
                    "before_remove": None,
                    "after_remove": None,
                },
            }
            _, lifecycle = receipt_fpm_metadata(
                {**package, "source": {"receipt_glob": "System/PackageDB/OpensshServer-*.json"},
                 "dependencies": {"runtime": []}},
                root,
            )
            self.assertEqual(lifecycle, [("--after-install", postinst)])
            self.assertEqual(postinst.read_text(encoding="utf-8"), original)

    def test_adapter_trigger_is_promoted_and_passed_to_fpm(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            receipt_path = root / "System/PackageDB/CacheOwner-1.json"
            surface = root / "Programs/CacheOwner/1/Metadata/control/triggers"
            surface.parent.mkdir(parents=True)
            receipt_path.parent.mkdir(parents=True)
            surface.write_text("interest /System/Compatibility/usr/share/cache-input\n")
            receipt_path.write_text(json.dumps({
                "name": "CacheOwner",
                "version": "1",
                "prefix": "/Programs/CacheOwner/1",
                "maintainer_surfaces": [
                    "/Programs/CacheOwner/1/Metadata/control/triggers"
                ],
            }))
            package_definition = {
                "dependencies": {"runtime": []},
                "intake_adapter": {
                    "format": "auzix-lifecycle-adapter-v1",
                    "template_dir": "tests/fixtures/apk-trigger",
                    "configuration": [],
                    "scripts": {},
                    "triggers": [{
                        "template": "auzix-cache.trigger",
                        "paths": ["/System/Compatibility/usr/share/cache-input"],
                    }],
                },
            }
            intake = normalize_lifecycle(
                root, json.loads(receipt_path.read_text()), Path(directory) / "review",
                package_definition,
            )
            self.assertEqual(intake["status"], "ready")
            package_json, fpm_metadata = promote_auzix_package(
                root, receipt_path, intake, package_definition
            )
            self.assertEqual(
                package_json["triggers"][0]["paths"],
                ["/System/Compatibility/usr/share/cache-input"],
            )
            self.assertEqual(fpm_metadata[0][0], "--apk-trigger")
            self.assertTrue(
                str(fpm_metadata[0][1]).endswith(
                    "=/System/Compatibility/usr/share/cache-input"
                )
            )

    def test_adapter_is_applied_when_legacy_receipt_has_no_maintainer_surfaces(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            (root / "Programs/CacheOwner/1").mkdir(parents=True)
            receipt = {
                "name": "CacheOwner",
                "version": "1",
                "prefix": "/Programs/CacheOwner/1",
                "maintainer_surfaces": [],
            }
            package_definition = {
                "dependencies": {"runtime": []},
                "intake_adapter": {
                    "format": "auzix-lifecycle-adapter-v1",
                    "template_dir": "tests/fixtures/apk-trigger",
                    "configuration": [],
                    "scripts": {},
                    "triggers": [{
                        "template": "auzix-cache.trigger",
                        "paths": ["/System/Compatibility/usr/share/cache-input"],
                    }],
                },
            }
            intake = normalize_lifecycle(
                root, receipt, Path(directory) / "review", package_definition,
            )
            self.assertEqual(intake["status"], "ready")
            self.assertIsNotNone(intake["adapter"])
            self.assertEqual(len(intake["triggers"]), 1)

    def test_adapter_publishes_runtime_loader_as_package_owned_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            package_root = root / "Programs/Libc6/1"
            loader = package_root / "RootFS/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
            loader.parent.mkdir(parents=True)
            loader.write_bytes(b"loader")
            receipt_path = root / "System/PackageDB/Libc6-1.json"
            receipt_path.parent.mkdir(parents=True)
            receipt = {
                "name": "Libc6", "version": "1", "prefix": "/Programs/Libc6/1",
                "maintainer_surfaces": [],
            }
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            package_definition = {
                "dependencies": {"runtime": []},
                "intake_adapter": {
                    "format": "auzix-lifecycle-adapter-v1",
                    "template_dir": "tests/fixtures/apk-trigger",
                    "configuration": [], "scripts": {}, "publish_libraries": True,
                    "compatibility_links": [{
                        "path": "/System/Compatibility/lib64/ld-linux-x86-64.so.2",
                        "target": "/Libraries/ld-linux-x86-64.so.2",
                    }],
                },
            }
            intake = normalize_lifecycle(
                root, receipt, Path(directory) / "review", package_definition,
            )
            package_json, _ = promote_auzix_package(
                root, receipt_path, intake, package_definition,
            )
            self.assertTrue((root / "Libraries/ld-linux-x86-64.so.2").is_symlink())
            self.assertEqual(
                (root / "System/Compatibility/lib64/ld-linux-x86-64.so.2").readlink(),
                Path("../../../Libraries/ld-linux-x86-64.so.2"),
            )
            self.assertEqual(len(package_json["libraries"]["compatibility_links"]), 1)

    def test_package_json_drives_fpm_dependencies_and_lifecycle(self):
        package = {
            "name": "Example",
            "version": "1",
            "source": {"receipt_glob": "System/PackageDB/Example-*.json"},
            "dependencies": {"runtime": ["WrongFallback"]},
            "lifecycle": {
                "before_install": None,
                "after_install": "/Programs/Example/${version}/Metadata/debian-control-dir/postinst",
                "before_remove": None,
                "after_remove": None,
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt = root / "System/PackageDB/Example-1.json"
            postinst = root / "Programs/Example/1/Metadata/debian-control-dir/postinst"
            receipt.parent.mkdir(parents=True)
            postinst.parent.mkdir(parents=True)
            postinst.write_text("#!/bin/sh\n", encoding="utf-8")
            receipt.write_text(json.dumps({
                "direct_depends": ["RuntimeGlibc", "Libpam0g"],
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/debian-control-dir/postinst"],
            }), encoding="utf-8")
            dependencies, lifecycle = receipt_fpm_metadata(package, root)
            self.assertEqual(dependencies, ["WrongFallback"])
            self.assertEqual(lifecycle, [("--after-install", postinst)])

    def test_retained_scripts_without_package_annotation_fail_closed(self):
        package = {
            "name": "Example", "version": "1",
            "source": {"receipt_glob": "System/PackageDB/Example-*.json"},
            "dependencies": {"runtime": []},
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "Programs/Example/1/Metadata/debian-control-dir/postinst"
            receipt = root / "System/PackageDB/Example-1.json"
            script.parent.mkdir(parents=True)
            receipt.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\n", encoding="utf-8")
            receipt.write_text(json.dumps({
                "maintainer_surfaces": ["/Programs/Example/1/Metadata/debian-control-dir/postinst"]
            }), encoding="utf-8")
            with self.assertRaisesRegex(ContractError, "no lifecycle annotation"):
                receipt_fpm_metadata(package, root)

    def test_bootstrap_layout_is_dependency_free_and_staged_from_definition(self):
        packages = load_packages()
        package = packages["BaseLayout"][1]
        self.assertEqual(package["dependencies"]["runtime"], [])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage_package(package, root)
            self.assertTrue((root / "System/Settings").is_dir())
            self.assertFalse((root / "etc").exists())

    def test_apk_layer_composition_is_last_layer_wins_and_locked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = root / "old"
            current = root / "current"
            output = root / "output"
            old.mkdir()
            current.mkdir()
            (old / "shared-1-r0.apk").write_bytes(b"old")
            (old / "old-only-1-r0.apk").write_bytes(b"old-only")
            (current / "shared-1-r0.apk").write_bytes(b"current")
            result = compose_apk_layers([old, current], output)
            self.assertEqual(result["count"], 2)
            self.assertEqual((output / "shared-1-r0.apk").read_bytes(), b"current")
            self.assertTrue((output / "layer-lock.json").is_file())

    def test_bootstrap_profile_contains_the_package_script_runtime(self):
        lock = compose_profile("bootstrap-base")
        self.assertEqual(
            [item["name"] for item in lock["packages"]],
            ["BaseLayout", "BusyBox", "ApkTools"],
        )

    def test_layout_activation_adopts_apk_state_before_aliasing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for absolute in (
                "Programs", "Services", "System/Compatibility/lib", "System/Settings",
                "System/State", "Users/root", "Work/Temp", "lib/apk/db", "etc/apk", "var/cache/apk",
            ):
                (root / absolute).mkdir(parents=True, exist_ok=True)
            (root / "lib/apk/db/installed").touch()
            activate_layout(root)
            self.assertEqual((root / "etc").readlink(), Path("/System/Settings"))
            self.assertEqual((root / "lib").readlink(), Path("/System/Compatibility/lib"))
            self.assertEqual((root / "run").readlink(), Path("/System/Run"))
            self.assertTrue((root / "System/State/apk/db/installed").is_file())
            self.assertEqual(
                (root / "System/Compatibility/lib/apk").readlink(), Path("/System/State/apk")
            )

    def test_apk_names_are_stable_lowercase_atoms(self):
        self.assertEqual(apk_name("BusyBox"), "auzix-busy-box")
        self.assertEqual(apk_name("LibgccS1"), "auzix-libgcc-s1")
        self.assertEqual(apk_name("RuntimeGlibc"), "auzix-runtime-glibc")
        self.assertRegex(apk_version("trixie-r5"), r"^0\.\d+-r0$")
        self.assertRegex(apk_version("14.2.0-19"), r"^0\.\d+-r0$")
        self.assertEqual(apk_version("1.36.1"), "1.36.1-r0")
        self.assertEqual(apk_version("2.14.10-r0"), "2.14.10-r0")

    def test_pilot_lock_is_deterministic(self):
        first = compose_profile("pilot-core")
        second = compose_profile("pilot-core")
        self.assertEqual(first, second)
        self.assertEqual(first["format"], "auzix-profile-lock-v1")
        self.assertEqual(len(first["content_sha256"]), 64)

    def test_runtime_precedes_dynamic_consumers(self):
        lock = compose_profile("pilot-core")
        names = [package["name"] for package in lock["packages"]]
        runtime = names.index("RuntimeGlibc")
        self.assertLess(runtime, names.index("OpenSSH"))
        self.assertLess(runtime, names.index("Xorg"))
        self.assertLess(runtime, names.index("Enlightenment"))

    def test_runtime_spine_has_no_external_providers(self):
        lock = compose_profile("runtime-spine")
        self.assertEqual(
            [item["name"] for item in lock["packages"]],
            ["LibgccS1", "RuntimeGlibc", "BusyBox", "ApkTools"],
        )
        self.assertTrue(all(item["kind"] == "auzix-package" for item in lock["packages"]))

    def test_netinstall_profile_is_a_direct_apk_root(self):
        lock = compose_profile("netinstall-hdd")
        names = [item["name"] for item in lock["packages"]]
        self.assertEqual(len(names), 12)
        self.assertNotIn("Parted", names)
        self.assertNotIn("E2fsprogs", names)
        self.assertNotIn("Curl", names)
        self.assertNotIn("AuzixPackageTools", names)
        self.assertNotIn("AuzixInstaller", names)
        packages = load_packages()
        self.assertIn("/Services/ssh", packages["OpenSSH"][1]["payload"]["surfaces"])

    def test_base_netinstall_target_is_deterministic_and_headless(self):
        first = compose_target("base-netinstall-hdd")
        second = compose_target("base-netinstall-hdd")
        self.assertEqual(first, second)
        names = [package["name"] for package in first["profile_lock"]["packages"]]
        self.assertIn("ApkTools", names)
        self.assertIn("LibgccS1", names)
        self.assertIn("OpenSSH", names)
        self.assertNotIn("Xorg", names)
        self.assertNotIn("Enlightenment", names)
        self.assertEqual(first["media"]["kind"], "raw-hdd")

    def test_base_activation_only_wires_package_owned_surfaces(self):
        plan = compose_target("base-netinstall-hdd")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            required = [
                "/Programs/BusyBox/1.36.1/Commands/busybox",
                "/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2",
                "/System/Libraries/Runtime/glibc/libc.so.6",
                "/System/Libraries/Runtime/glibc/libm.so.6",
                "/System/Libraries/Runtime/glibc/libgcc_s.so.1",
                "/Programs/OpenSSH/host/Commands/sshd",
                "/Services/ssh/run",
                "/System/Settings/ssh/sshd_config",
                "/System/Compatibility/etc/ssl/certs/ca-certificates.crt",
            ]
            for absolute in required:
                path = root / absolute.lstrip("/")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            for absolute in ("/lib/apk/db", "/etc/apk", "/var/cache/apk"):
                (root / absolute.lstrip("/")).mkdir(parents=True, exist_ok=True)
            (root / "lib/apk/db/installed").touch()
            (root / "etc/apk/world").touch()
            receipt = activate_base(root, plan)
            self.assertEqual(receipt["status"], "passed")
            self.assertTrue((root / "System/Boot/StartSequence").is_file())
            self.assertEqual((root / "lib").readlink(), Path("/System/Compatibility/lib"))
            self.assertTrue((root / "System/State/apk/db/installed").is_file())
            self.assertTrue((root / "System/Settings/apk/world").is_file())
            self.assertTrue((root / "System/State/cache/apk").is_dir())
            self.assertEqual((root / "etc").readlink(), Path("/System/Settings"))
            self.assertEqual((root / "var").readlink(), Path("/System/State"))
            self.assertEqual(
                (root / "System/Compatibility/lib64/ld-linux-x86-64.so.2").readlink(),
                Path("/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2"),
            )
            self.assertFalse((root / "Programs/Enlightenment").exists())
            stored = json.loads((root / "System/State/install/activation-receipt.json").read_text())
            self.assertEqual(stored, receipt)

    def test_activation_preserves_proven_dotted_netmask_logic(self):
        from auzix.activation.base import START_SEQUENCE

        self.assertIn('ifconfig "$interface" "$ip" netmask "$subnet"', START_SEQUENCE)
        self.assertNotIn('${mask:-24}', START_SEQUENCE)

    def test_model_review_accepts_only_constrained_proposals(self):
        proposal = {
            "operations": [],
            "scripts": [],
            "payload_rewrites": [
                {"path": "RootFS/usr/bin/tool", "old": "/etc/tool", "new": "/System/Settings/tool", "expected": 1}
            ],
            "discarded": [],
            "risks": [],
        }
        self.assertEqual(validate_proposal(proposal), proposal)
        with self.assertRaises(ContractError):
            validate_proposal({**proposal, "patch": "do something"})
        with self.assertRaises(ContractError):
            validate_proposal({**proposal, "payload_rewrites": [{"path": "x"}]})


if __name__ == "__main__":
    unittest.main()

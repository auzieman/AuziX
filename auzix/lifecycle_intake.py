from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .contracts import ContractError
from .intake_ir import write_donor_object
from .paths import REPOSITORY_ROOT


LIFECYCLE_STAGES = {
    "preinst": ("before_install", "--before-install"),
    "postinst": ("after_install", "--after-install"),
    "prerm": ("before_remove", "--before-remove"),
    "postrm": ("after_remove", "--after-remove"),
}

PATH_VARIABLES = {
    "/var/cache": "${AUZIX_CACHE}",
    "/var/lib": "${AUZIX_STATE}",
    "/var/log": "${AUZIX_LOGS}",
    "/etc": "${AUZIX_SETTINGS}",
    "/run": "${AUZIX_RUN}",
    "/tmp": "${AUZIX_TMP}",
    "/root": "${AUZIX_ROOT_USER}",
}

PACKAGE_OWNED_ROOTS = ("/usr", "/sbin", "/bin", "/lib64", "/lib")

ENVIRONMENT = """AUZIX_PACKAGE_ROOT=${AUZIX_PACKAGE_ROOT:-__PACKAGE_ROOT__}
AUZIX_SETTINGS=${AUZIX_SETTINGS:-/System/Settings}
AUZIX_STATE=${AUZIX_STATE:-/System/State}
AUZIX_CACHE=${AUZIX_CACHE:-/System/Cache}
AUZIX_LOGS=${AUZIX_LOGS:-/System/Logs}
AUZIX_RUN=${AUZIX_RUN:-/System/Run}
AUZIX_TMP=${AUZIX_TMP:-/Work/Temp}
AUZIX_ROOT_USER=${AUZIX_ROOT_USER:-/Users/root}
export AUZIX_PACKAGE_ROOT AUZIX_SETTINGS AUZIX_STATE AUZIX_CACHE AUZIX_LOGS
export AUZIX_RUN AUZIX_TMP AUZIX_ROOT_USER
"""

UNSUPPORTED_PATTERNS = {
    "dpkg-helper": re.compile(r"\bdpkg(?:-(?:maintscript-helper|statoverride|divert))?\b"),
    "donor-root-variable": re.compile(r"\bDPKG_ROOT\b"),
    "lifecycle-arguments": re.compile(r"(?:\$\{?1\}?|\$\{?2\}?)"),
    "debconf": re.compile(r"(?:/|\b)(?:debconf|ucf|ucfr)(?:/|\b)"),
    "debian-service-helper": re.compile(
        r"\b(?:deb-systemd-helper|deb-systemd-invoke|invoke-rc\.d|update-rc\.d)\b"
    ),
    "foreign-service-manager": re.compile(r"\b(?:systemctl|service|runit-helper)\b"),
    "package-account-helper": re.compile(r"\b(?:adduser|useradd|groupadd|addgroup)\b"),
    "package-trigger-helper": re.compile(
        r"\b(?:update-alternatives|update-menus|ldconfig|sysctl|update-desktop-database|update-mime-database|gtk-update-icon-cache)\b"
    ),
}

FINDING_RULES = {
    "dpkg-helper": "maintscript-file-migration",
    "donor-root-variable": "donor-root-variable",
    "lifecycle-arguments": "lifecycle-action-arguments",
    "debconf": "debconf-default-materialization",
    "debian-service-helper": "generated-service-scaffold",
    "foreign-service-manager": "generated-service-scaffold",
    "package-account-helper": "package-account-management",
    "package-trigger-helper": "command-trigger",
    "unmapped-path": "package-path-resolution",
}

FINDING_SEMANTICS = {
    "dpkg-helper": "donor-protocol-or-versioned-migration",
    "donor-root-variable": "guard-around-side-effect",
    "lifecycle-arguments": "donor-protocol",
    "debconf": "configuration-preservation",
    "debian-service-helper": "service-intent",
    "foreign-service-manager": "service-intent",
    "package-account-helper": "account-side-effect",
    "package-trigger-helper": "deferred-side-effect",
    "unmapped-path": "unresolved-path-side-effect",
    "maintainer-surface": "untranslated-package-metadata",
}

EXACT_TRIGGER_RULES = {
    "activate-noawait ldconfig": "ldconfig-trigger",
    "activate-noawait update-initramfs": "initramfs-trigger",
    "interest update-ca-certificates\ninterest update-ca-certificates-fresh": "ca-trust-trigger",
}

PYTHON_CLEAN_BLOCK = re.compile(
    r"if command -v py3clean >/dev/null 2>&1; then\n"
    r"\s*py3clean[^\n]*\n"
    r"else\n"
    r"\s*dpkg -L[^\n]*\n"
    r"\s*find \$\{AUZIX_PACKAGE_ROOT\}/RootFS/usr/lib/python3/dist-packages/[^\n]*\n"
    r"fi"
)

RM_CONFFILE_LINE = re.compile(
    r"^(?P<indent>\s*)dpkg-maintscript-helper\s+rm_conffile\s+"
    r"(?P<path>\S+)\s+(?P<prior_version>\S+)"
    r"(?:\s+(?P<package>\S+))?\s+--\s+\"\$@\"\s*$",
    re.MULTILINE,
)
DIR_TO_SYMLINK_LINE = re.compile(
    r"^(?P<indent>\s*)dpkg-maintscript-helper\s+dir_to_symlink\s+"
    r"(?P<path>\S+)\s+(?P<old_path>\S+)\s+(?P<prior_version>\S+)"
    r"(?:\s+(?P<package>\S+))?\s+--\s+\"\$@\"\s*$",
    re.MULTILINE,
)
DPKG_DIVERT_COMMAND = re.compile(
    r"(?m)^(?P<indent>[ \t]*)dpkg-divert\b(?:[^\n]*\\\n)*[^\n]*"
)


def _extract_maintscript_migrations(
    text: str, lifecycle_name: str
) -> tuple[str, list[dict[str, str]]]:
    migrations: list[dict[str, str]] = []

    def replace(match: re.Match[str]) -> str:
        migration = {
            "operation": "remove-obsolete-conffile",
            "path": match.group("path"),
            "prior_version": match.group("prior_version"),
            "stage": lifecycle_name,
        }
        package = match.group("package")
        if package:
            migration["donor_package"] = package
        migrations.append(migration)
        return match.group("indent") + ": # AUZiX migration recorded in Package/package.json"

    text = RM_CONFFILE_LINE.sub(replace, text)

    def replace_dir_to_symlink(match: re.Match[str]) -> str:
        migration = {
            "operation": "directory-to-symlink",
            "path": match.group("path"),
            "old_path": match.group("old_path"),
            "prior_version": match.group("prior_version"),
            "stage": lifecycle_name,
            "disposition": "recorded-donor-migration",
        }
        package = match.group("package")
        if package:
            migration["donor_package"] = package
        migrations.append(migration)
        return match.group("indent") + ": # AUZiX directory migration recorded in Package/package.json"

    text = DIR_TO_SYMLINK_LINE.sub(replace_dir_to_symlink, text)

    def replace_usrmerge_diversion(match: re.Match[str]) -> str:
        command = match.group(0)
        if ".usr-is-merged" not in command:
            return command
        migrations.append({
            "operation": "debian-usrmerge-diversion",
            "stage": lifecycle_name,
            "disposition": "not-applicable-auzix-libraries-layout",
            "donor_command": " ".join(
                line.strip().rstrip("\\").strip() for line in command.splitlines()
            ),
        })
        return match.group("indent") + ": # Debian usrmerge diversion is not applicable to /Libraries"

    return DPKG_DIVERT_COMMAND.sub(replace_usrmerge_diversion, text), migrations


def _apply_generated_script_rules(text: str) -> tuple[str, list[str]]:
    rules: list[str] = []
    if "# Automatically added by dh_python3" in text:
        replacement = """if command -v py3clean >/dev/null 2>&1; then
\tpy3clean "${AUZIX_PACKAGE_ROOT}/RootFS/usr/lib/python3/dist-packages" || true
else
\tfind "${AUZIX_PACKAGE_ROOT}/RootFS/usr/lib/python3/dist-packages" -type f \\
\t\t\\( -name '*.pyc' -o -name '*.pyo' \\) -delete
\tfind "${AUZIX_PACKAGE_ROOT}/RootFS/usr/lib/python3/dist-packages" \\
\t\t-type d -name __pycache__ -empty -delete
fi"""
        text, count = PYTHON_CLEAN_BLOCK.subn(replacement, text)
        if count > 1:
            raise ContractError(f"python bytecode cleanup rule matched {count} blocks")
        if count == 1:
            rules.append("python-bytecode-cleanup")
    return text, rules


DONOR_ACTIONS = {
    "before_install": "install",
    "after_install": "configure",
    "before_remove": "remove",
    "after_remove": "remove",
}


def _wrap_lifecycle_arguments(text: str, lifecycle_name: str) -> tuple[str, bool]:
    if not UNSUPPORTED_PATTERNS["lifecycle-arguments"].search(text):
        return text, False
    lines = text.splitlines(keepends=True)
    shebang = lines[0] if lines and lines[0].startswith("#!") else "#!/bin/sh\n"
    body = "".join(lines[1:]) if lines and lines[0].startswith("#!") else text
    action = DONOR_ACTIONS[lifecycle_name]
    wrapped = (
        shebang
        + "auzix_maintainer_main() {\n"
        + body
        + ("\n" if body and not body.endswith("\n") else "")
        + "}\n"
        + f"auzix_maintainer_main {action!r} ''\n"
    )
    return wrapped, True

ABSOLUTE_PATH = re.compile(
    r"(?<![A-Za-z0-9_${}])/(?:etc|var|run|usr|bin|sbin|lib64?|tmp|root)(?:/[A-Za-z0-9._+@%:=,~-]+)*"
)


def _runtime_cache_is_package_owned(package_root: Path, absolute: str) -> bool:
    parts = Path(absolute).parts
    if "__pycache__" not in parts:
        return False
    cache_index = parts.index("__pycache__")
    parent = Path(*parts[1:cache_index])
    payload_parent = package_root / "RootFS" / parent
    return payload_parent.is_dir()


def _normalize_conffiles(
    source: Path, package_root: Path, source_path: str
) -> tuple[list[str], list[dict[str, Any]]]:
    """Translate a plain conffiles manifest without importing donor directives."""
    paths: list[str] = []
    findings: list[dict[str, Any]] = []
    for line_number, raw in enumerate(source.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        if not entry.startswith("/") or any(character.isspace() for character in entry):
            findings.append({
                "stage": "package",
                "kind": "conffile-directive",
                "matches": [entry],
                "source": source_path,
                "line": line_number,
            })
            continue
        payload = package_root / "RootFS" / entry.lstrip("/")
        if not (payload.exists() or payload.is_symlink()):
            findings.append({
                "stage": "package",
                "kind": "missing-conffile-payload",
                "matches": [entry],
                "source": source_path,
                "line": line_number,
            })
            continue
        translated = entry
        for donor, replacement in sorted(PATH_VARIABLES.items(), key=lambda item: len(item[0]), reverse=True):
            if entry == donor or entry.startswith(donor + "/"):
                translated = replacement + entry[len(donor):]
                break
        paths.append(translated)
    return paths, findings


def _public_library_plan(package_root: Path, name: str, version: str) -> list[dict[str, str]]:
    """Plan publication of shared objects from conventional donor library directories."""
    roots: list[Path] = []
    rootfs = package_root / "RootFS"
    for relative in ("lib", "lib64", "usr/lib", "usr/lib64"):
        candidate = rootfs / relative
        if candidate.is_dir():
            roots.append(candidate)
            roots.extend(
                child for child in candidate.iterdir()
                if child.is_dir() and child.name.endswith("-linux-gnu")
            )
    plan: list[dict[str, str]] = []
    seen: set[str] = set()
    for directory in roots:
        for source in sorted(directory.glob("*.so*")):
            if not (source.is_file() or source.is_symlink()):
                continue
            if source.name in seen:
                raise ContractError(f"{name}: duplicate public library basename: {source.name}")
            seen.add(source.name)
            owned = f"/Libraries/Packages/{name}/{version}/{source.name}"
            plan.append({
                "source": "/" + str(source.relative_to(package_root.parent.parent.parent)),
                "owned": owned,
                "public": f"/Libraries/{source.name}",
            })
    return plan


def _replace_paths(text: str, package_root: Path) -> str:
    lines = text.splitlines(keepends=True)
    shebang = lines[0] if lines and lines[0].startswith("#!") else ""
    result = "".join(lines[1:]) if shebang else text
    donor_root_forms = (r"\$\{DPKG_ROOT:-\}", r'"\$DPKG_ROOT"', r"\$DPKG_ROOT")
    for donor, replacement in sorted(PATH_VARIABLES.items(), key=lambda item: len(item[0]), reverse=True):
        for donor_root in donor_root_forms:
            result = re.sub(
                donor_root + re.escape(donor) + r"(?=/|[^A-Za-z0-9_]|$)",
                lambda _match, value=replacement: value,
                result,
            )
    for donor, replacement in sorted(PATH_VARIABLES.items(), key=lambda item: len(item[0]), reverse=True):
        result = re.sub(
            rf"(?<![A-Za-z0-9_${{}}]){re.escape(donor)}(?=/|[^A-Za-z0-9_]|$)",
            lambda _match, value=replacement: value,
            result,
        )
    def replace_owned(match: re.Match[str]) -> str:
        absolute = match.group(0)
        if not any(absolute == root or absolute.startswith(root + "/") for root in PACKAGE_OWNED_ROOTS):
            return absolute
        payload = package_root / "RootFS" / absolute.lstrip("/")
        if (
            payload.exists()
            or payload.is_symlink()
            or _runtime_cache_is_package_owned(package_root, absolute)
        ):
            return "${AUZIX_PACKAGE_ROOT}/RootFS" + absolute
        return absolute

    result = ABSOLUTE_PATH.sub(replace_owned, result)
    return shebang + result


def _insert_environment(text: str, package_root: str) -> str:
    environment = ENVIRONMENT.replace("__PACKAGE_ROOT__", package_root)
    lines = text.splitlines(keepends=True)
    if lines and lines[0].startswith("#!"):
        return lines[0] + environment + "".join(lines[1:])
    return "#!/bin/sh\n" + environment + text


def normalize_lifecycle(
    stage: Path,
    receipt: dict[str, Any],
    output_dir: Path,
    package_definition: dict[str, Any] | None = None,
) -> dict[str, Any]:
    surfaces = receipt.get("maintainer_surfaces", [])
    if not isinstance(surfaces, list) or not all(isinstance(item, str) for item in surfaces):
        raise ContractError("maintainer_surfaces must be a string array")
    retained = [path for path in surfaces if Path(path).name in LIFECYCLE_STAGES]
    other_surfaces = [path for path in surfaces if Path(path).name not in LIFECYCLE_STAGES]
    if not retained and not other_surfaces:
        return {
            "status": "static", "scripts": [], "configuration": [],
            "library_publications": [], "rules": [], "effect_candidates": [],
            "residual_findings": [], "findings": [],
        }

    prefix = receipt.get("prefix")
    if not isinstance(prefix, str) or not prefix.startswith("/Programs/"):
        raise ContractError("receipt has no AUZiX program prefix")
    output_dir.mkdir(parents=True, exist_ok=True)
    scripts: list[dict[str, str]] = []
    donor_objects: list[dict[str, Any]] = []
    effect_candidates: list[dict[str, Any]] = []
    operations: list[dict[str, Any]] = []
    findings: list[dict[str, Any]] = []
    configuration: list[str] = []
    library_publications: list[dict[str, str]] = []
    migrations: list[dict[str, str]] = []
    rules: dict[str, dict[str, Any]] = {}
    evidence_dir = output_dir / "evidence"
    donor_dir = output_dir / "~deb_inst"
    rendered_dir = output_dir / "rendered"
    for surface_path in other_surfaces:
        source = stage / surface_path.lstrip("/")
        name = Path(surface_path).name
        if name == "conffiles" and source.is_file():
            normalized, conffile_findings = _normalize_conffiles(
                source, stage / prefix.lstrip("/"), surface_path
            )
            configuration.extend(normalized)
            operations.extend(
                {"type": "install-configuration", "destination": path}
                for path in normalized
            )
            findings.extend(conffile_findings)
            rules["plain-conffiles"] = {
                "id": "plain-conffiles",
                "state": "transformed" if not conffile_findings else "residual",
                "source": surface_path,
                "outputs": normalized,
            }
            continue
        if name == "triggers" and source.is_file():
            trigger_body = "\n".join(
                line.strip()
                for line in source.read_text(encoding="utf-8", errors="replace").splitlines()
                if line.strip() and not line.lstrip().startswith("#")
            )
            rule_id = EXACT_TRIGGER_RULES.get(trigger_body)
            if rule_id:
                if rule_id == "ldconfig-trigger":
                    library_publications = _public_library_plan(
                        stage / prefix.lstrip("/"),
                        str(receipt.get("name")),
                        str(receipt.get("version")),
                    )
                    if library_publications:
                        operations.extend(
                            {
                                "type": "publish-library",
                                "source": item["source"],
                                "owned": item["owned"],
                                "public": item["public"],
                            }
                            for item in library_publications
                        )
                        rules[rule_id] = {
                            "id": rule_id,
                            "state": "transformed",
                            "source": surface_path,
                            "matches": trigger_body.splitlines(),
                            "outputs": [item["public"] for item in library_publications],
                        }
                        continue
                rules[rule_id] = {
                    "id": rule_id,
                    "state": "recognized",
                    "source": surface_path,
                    "matches": trigger_body.splitlines(),
                }
        finding: dict[str, Any] = {
            "stage": "package",
            "kind": "maintainer-surface",
            "matches": [name],
            "source": surface_path,
        }
        if source.is_file():
            evidence_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, evidence_dir / name)
        else:
            finding["message"] = "declared maintainer surface is missing"
        findings.append(finding)
    seen: set[str] = set()
    for source_path in retained:
        donor_name = Path(source_path).name
        lifecycle_name, fpm_flag = LIFECYCLE_STAGES[donor_name]
        if lifecycle_name in seen:
            raise ContractError(f"duplicate lifecycle stage: {lifecycle_name}")
        seen.add(lifecycle_name)
        source = stage / source_path.lstrip("/")
        if not source.is_file():
            raise ContractError(f"retained lifecycle script is missing: {source_path}")
        original = source.read_text(encoding="utf-8", errors="replace")
        donor_object = write_donor_object(donor_dir, donor_name, source_path, original)
        for effect in donor_object["effect_candidates"]:
            effect["stage"] = lifecycle_name
            effect_candidates.append(effect)
        donor_objects.append(donor_object)
        normalized_body = _replace_paths(original, stage / prefix.lstrip("/"))
        normalized_body, script_migrations = _extract_maintscript_migrations(
            normalized_body, lifecycle_name
        )
        migrations.extend(script_migrations)
        operations.extend({"type": "migration", **item} for item in script_migrations)
        if script_migrations:
            rule = rules.setdefault(
                "maintscript-file-migration",
                {"id": "maintscript-file-migration", "state": "transformed", "stages": []},
            )
            rule["stages"].append(lifecycle_name)
        normalized_body, applied_script_rules = _apply_generated_script_rules(normalized_body)
        normalized_body, wrapped_arguments = _wrap_lifecycle_arguments(
            normalized_body, lifecycle_name
        )
        if wrapped_arguments:
            applied_script_rules.append("lifecycle-action-arguments")
        for rule_id in applied_script_rules:
            rule = rules.setdefault(
                rule_id, {"id": rule_id, "state": "transformed", "stages": []}
            )
            rule["stages"].append(lifecycle_name)
        candidate_text = _insert_environment(normalized_body, prefix)
        rendered_dir.mkdir(parents=True, exist_ok=True)
        candidate = rendered_dir / lifecycle_name.replace("_", "-")
        candidate.write_text(candidate_text, encoding="utf-8")
        candidate.chmod(0o755)

        script_findings = []
        for kind, pattern in UNSUPPORTED_PATTERNS.items():
            if kind == "lifecycle-arguments" and wrapped_arguments:
                continue
            matches = sorted(set(pattern.findall(normalized_body)))
            if matches:
                script_findings.append({
                    "kind": kind,
                    "semantic_class": FINDING_SEMANTICS.get(kind, "unresolved"),
                    "matches": matches,
                })
        scan_body = "\n".join(normalized_body.splitlines()[1:])
        remaining_paths = sorted(set(ABSOLUTE_PATH.findall(scan_body)))
        if remaining_paths:
            script_findings.append({"kind": "unmapped-path", "matches": remaining_paths})
        syntax = subprocess.run(
            ["/bin/sh", "-n", str(candidate)], capture_output=True, text=True
        )
        if syntax.returncode:
            script_findings.append({"kind": "shell-syntax", "message": syntax.stderr.strip()})
        findings.extend(
            {"stage": lifecycle_name, **finding} for finding in script_findings
        )
        for finding in script_findings:
            rule_id = FINDING_RULES.get(finding["kind"])
            if rule_id:
                rule = rules.setdefault(
                    rule_id, {"id": rule_id, "state": "recognized", "stages": []}
                )
                stages = rule.setdefault("stages", [])
                if lifecycle_name not in stages:
                    stages.append(lifecycle_name)
        scripts.append({
            "stage": lifecycle_name,
            "flag": fpm_flag,
            "source": source_path,
            "candidate": str(candidate),
        })

    adapter = package_definition.get("intake_adapter") if package_definition else None
    adapter_record = None
    donor_findings: list[dict[str, Any]] = []
    if adapter is not None:
        if adapter.get("format") != "auzix-lifecycle-adapter-v1":
            raise ContractError("unsupported lifecycle intake adapter format")
        template_dir = REPOSITORY_ROOT / adapter.get("template_dir", "")
        if not template_dir.is_dir():
            raise ContractError(f"lifecycle adapter template directory is missing: {template_dir}")
        configured = adapter.get("configuration", [])
        if not isinstance(configured, list) or not all(isinstance(path, str) for path in configured):
            raise ContractError("lifecycle adapter configuration must be a string array")
        configuration = configured
        package_root = stage / prefix.lstrip("/")
        operations = [
            {"type": "install-configuration", "destination": path}
            for path in configuration
        ] + list(adapter.get("operations", []))
        for rewrite in adapter.get("payload_rewrites", []):
            if not isinstance(rewrite, dict):
                raise ContractError("lifecycle adapter payload rewrite must be an object")
            relative = rewrite.get("path")
            old = rewrite.get("old")
            new = rewrite.get("new")
            expected = rewrite.get("expected")
            if (
                not isinstance(relative, str)
                or relative.startswith("/")
                or ".." in Path(relative).parts
                or not isinstance(old, str)
                or not old
                or not isinstance(new, str)
                or not isinstance(expected, int)
                or expected < 1
            ):
                raise ContractError("invalid lifecycle adapter payload rewrite")
            target = package_root / relative
            if not target.is_file():
                raise ContractError(f"adapter payload rewrite target is missing: {target}")
            original = target.read_text(encoding="utf-8", errors="strict")
            count = original.count(old)
            if count != expected:
                raise ContractError(
                    f"adapter payload rewrite expected {expected} matches but found {count}: "
                    f"{target}: {old!r}"
                )
            target.write_text(
                original.replace(
                    old,
                    new.replace("@PACKAGE_ROOT@", prefix).replace(
                        "@VERSION@", str(receipt.get("version"))
                    ),
                ),
                encoding="utf-8",
            )
        donor_findings = findings
        findings = []
        scripts = []
        rendered_dir.mkdir(parents=True, exist_ok=True)
        for lifecycle_name, template_name in adapter.get("scripts", {}).items():
            if lifecycle_name not in DONOR_ACTIONS:
                raise ContractError(f"unknown adapter lifecycle stage: {lifecycle_name}")
            template = template_dir / template_name
            if not template.is_file():
                raise ContractError(f"lifecycle adapter template is missing: {template}")
            candidate = rendered_dir / lifecycle_name.replace("_", "-")
            candidate.write_text(
                template.read_text(encoding="utf-8")
                .replace("@PACKAGE_ROOT@", prefix)
                .replace("@VERSION@", str(receipt.get("version"))),
                encoding="utf-8",
            )
            candidate.chmod(0o755)
            syntax = subprocess.run(
                ["/bin/sh", "-n", str(candidate)], capture_output=True, text=True
            )
            if syntax.returncode:
                raise ContractError(
                    f"adapter script has invalid shell syntax: {template}: {syntax.stderr.strip()}"
                )
            flag = next(flag for stage_name, flag in LIFECYCLE_STAGES.values() if stage_name == lifecycle_name)
            scripts.append({
                "stage": lifecycle_name,
                "flag": flag,
                "source": str(template),
                "candidate": str(candidate),
            })
        adapter_record = {
            "format": adapter["format"],
            "template_dir": str(template_dir),
            "disposition": "replaced-by-package-adapter",
            "donor_residual_findings": donor_findings,
            "retained_state": adapter.get("retained_state", []),
        }

    status = "needs-review" if findings else "ready"
    manifest = {
        "format": "auzix-lifecycle-intake-v1",
        "package": receipt.get("name"),
        "version": receipt.get("version"),
        "status": status,
        "scripts": scripts,
        "donor_objects": donor_objects,
        "effect_candidates": effect_candidates,
        "operations": operations,
        "adapter": adapter_record,
        "configuration": sorted(set(configuration)),
        "library_publications": library_publications,
        "migrations": migrations,
        "rules": sorted(rules.values(), key=lambda rule: rule["id"]),
        "residual_findings": findings,
        "donor_residual_findings": donor_findings,
        "findings": findings,
    }
    (output_dir / "lifecycle.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    native_ir = {
        "format": "auzix-lifecycle-ir-v1",
        "package": receipt.get("name"),
        "version": receipt.get("version"),
        "operations": operations,
        "effect_candidates": effect_candidates,
        "adapter": adapter_record,
        "migrations": migrations,
        "configuration": sorted(set(configuration)),
        "library_publications": library_publications,
        "rendered_scripts": scripts,
        "residual_findings": findings,
        "donor_residual_findings": donor_findings,
    }
    native_ir_dir = output_dir / "auzix"
    native_ir_dir.mkdir(parents=True, exist_ok=True)
    (native_ir_dir / "lifecycle.json").write_text(
        json.dumps(native_ir, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def promote_auzix_package(
    stage: Path,
    receipt_path: Path,
    intake: dict[str, Any],
    package_definition: dict[str, Any] | None,
) -> tuple[dict[str, Any], list[tuple[str, Path]]]:
    """Replace donor evidence with the native AUZiX package contract in-place."""
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    prefix = receipt["prefix"]
    package_root = stage / prefix.lstrip("/")
    native_dir = package_root / "Package"
    scripts_dir = native_dir / "Scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    for publication in intake.get("library_publications", []):
        source = stage / publication["source"].lstrip("/")
        owned = stage / publication["owned"].lstrip("/")
        public = stage / publication["public"].lstrip("/")
        if not (source.is_file() or source.is_symlink()):
            raise ContractError(
                f"{receipt.get('name')}: public library disappeared before promotion: {source}"
            )
        owned.parent.mkdir(parents=True, exist_ok=True)
        public.parent.mkdir(parents=True, exist_ok=True)
        if owned.exists() or owned.is_symlink() or public.exists() or public.is_symlink():
            raise ContractError(
                f"{receipt.get('name')}: public library destination already exists: {publication}"
            )
        shutil.move(str(source), str(owned))
        public.symlink_to(publication["owned"])
    for protected_path in intake.get("configuration", []):
        settings_prefix = "${AUZIX_SETTINGS}/"
        if not protected_path.startswith(settings_prefix):
            raise ContractError(
                f"{receipt.get('name')}: unsupported configuration destination: {protected_path}"
            )
        relative = protected_path.removeprefix(settings_prefix)
        source = package_root / "RootFS/etc" / relative
        destination = stage / "System/Settings" / relative
        if not (source.is_file() or source.is_symlink()):
            raise ContractError(
                f"{receipt.get('name')}: accepted conffile disappeared before promotion: {source}"
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() or destination.is_symlink():
            raise ContractError(
                f"{receipt.get('name')}: configuration destination already exists: {destination}"
            )
        shutil.move(str(source), str(destination))
    lifecycle = {
        "before_install": None,
        "after_install": None,
        "before_remove": None,
        "after_remove": None,
    }
    fpm_scripts: list[tuple[str, Path]] = []
    for script in intake["scripts"]:
        destination = scripts_dir / Path(script["candidate"]).name
        shutil.copy2(script["candidate"], destination)
        absolute = "/" + str(destination.relative_to(stage))
        lifecycle[script["stage"]] = absolute
        fpm_scripts.append((script["flag"], destination))

    dependencies = []
    if package_definition is not None:
        dependencies = list(package_definition.get("dependencies", {}).get("runtime", []))
    package_json = {
        "format": "auzix-package-intake-v1",
        "name": receipt.get("name"),
        "version": receipt.get("version"),
        "prefix": prefix,
        "dependencies": {"runtime": dependencies},
        "configuration": {"protected_paths": intake.get("configuration", [])},
        "libraries": {
            "public": [item["public"] for item in intake.get("library_publications", [])]
        },
        "migrations": intake.get("migrations", []),
        "lifecycle": lifecycle,
    }
    native_dir.mkdir(parents=True, exist_ok=True)
    (native_dir / "package.json").write_text(
        json.dumps(package_json, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (native_dir / "lifecycle.json").write_text(
        json.dumps({"format": "auzix-lifecycle-v1", **lifecycle}, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )

    metadata = package_root / "Metadata"
    if metadata.is_dir():
        for donor in metadata.glob("debian-*"):
            if donor.is_dir():
                shutil.rmtree(donor)
            else:
                donor.unlink()
    for key in (
        "depends", "direct_depends", "recommends", "maintainer_surfaces",
        "debian_package_db", "source", "migration_stage", "notes",
    ):
        receipt.pop(key, None)
    receipt["dependencies"] = {"runtime": dependencies}
    receipt["configuration"] = {"protected_paths": intake.get("configuration", [])}
    receipt["libraries"] = {
        "public": [item["public"] for item in intake.get("library_publications", [])]
    }
    receipt["migrations"] = intake.get("migrations", [])
    receipt["lifecycle"] = lifecycle
    receipt["package_contract"] = prefix + "/Package/package.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return package_json, fpm_scripts

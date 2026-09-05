from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from functools import lru_cache
from pathlib import Path
from typing import Any

from .contracts import ContractError
from .intake_ir import write_donor_object
from .paths import REPOSITORY_ROOT
from .python_lifecycle import adapt_python_prerm


LIFECYCLE_STAGES = {
    "preinst": ("before_install", "--before-install"),
    "postinst": ("after_install", "--after-install"),
    "prerm": ("before_remove", "--before-remove"),
    "postrm": ("after_remove", "--after-remove"),
}

# Hook-exported runtime leftovers. Translation uses packaging/rewrite-paths.sed.

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
auzix_ensure_system_account() {
	account=$1
	id "$account" >/dev/null 2>&1 && return 0
	if command -v adduser >/dev/null 2>&1; then
		adduser --system --quiet --group "$account" || true
	fi
	id "$account" >/dev/null 2>&1 && return 0
	groupadd --system "$account" 2>/dev/null || true
	useradd --system --gid "$account" --no-create-home --shell /usr/sbin/nologin "$account"
}
auzix_apply_statoverride() {
	user=$1
	group=$2
	mode=$3
	path=$4
	[ -n "$path" ] && [ ! -L "$path" ] && [ -e "$path" ] || return 0
	id "$group" >/dev/null 2>&1 || return 1
	chown "$user:$group" "$path"
	chmod "$mode" "$path"
}
auzix_upgrade_cmp() {
	previous=$1
	_operator=$2
	_than=$3
	[ -n "$previous" ] || return 1
	return 1
}
auzix_reload_service() {
	name=$1
	if command -v rc-service >/dev/null 2>&1; then
		rc-service "$name" restart >/dev/null 2>&1 || true
		return 0
	fi
	if [ -x "/Services/$name/run" ]; then
		return 0
	fi
	return 0
}
auzix_apply_sysctl() {
	pattern=$1
	command -v sysctl >/dev/null 2>&1 || return 0
	sysctl --quiet --pattern "$pattern" --system || true
}
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

DPKG_SELF_PYTHON_CACHE_BLOCK = re.compile(
    r"(?m)^(?P<indent>[ \t]*)files=\$\(dpkg -L (?P<package>[^\s|]+)[^\n]*\n"
    r"(?P=indent)rm -f \$files\n"
    r"(?P=indent)dirs=\$\(dpkg -L (?P=package)[^\n]*\n"
    r"(?P=indent)find \$dirs[^\n]*$"
)

DPKG_STATOVERRIDE_MODE_BLOCK = re.compile(
    r'(?P<indent>[ \t]*)if dpkg --compare-versions "\$2" [^\n]+; then\n'
    r'[ \t]+if ! dpkg-statoverride --list (?P<path>\S+) >/dev/null 2>&1 && \\\n'
    r'[ \t]+\[ -e (?P=path) \]; then\n'
    r'[ \t]+chmod (?P<mode>[0-7]{3,4}) (?P=path)\n'
    r'[ \t]+fi\n'
    r'[ \t]+fi'
)

DPKG_STATOVERRIDE_ADD_BLOCK = re.compile(
    r'(?P<indent>[ \t]*)if ! dpkg-statoverride --list (?P<listpath>\S+) >/dev/null(?: 2>&1)?; then\n'
    r'(?P=indent)[ \t]*dpkg-statoverride --update --add (?P<user>\S+) (?P<group>\S+) (?P<mode>[0-7]{3,4}) (?P<path>\S+)\n'
    r'(?P=indent)fi'
)

DPKG_STATOVERRIDE_ADD_LINE = re.compile(
    r'(?P<indent>[ \t]*)dpkg-statoverride --update --add (?P<user>\S+) (?P<group>\S+) (?P<mode>[0-7]{3,4}) (?P<path>\S+)\n'
)

SYSTEM_ACCOUNT_SYSUSERS_BLOCK = re.compile(
    r'(?P<indent>[ \t]*)if command -v systemd-sysusers >/dev/null; then\n'
    r'(?P=indent)[ \t]*systemd-sysusers[^\n]+\n'
    r'(?P=indent)else\n'
    r'(?P=indent)[ \t]*(?:in_sysroot )?adduser --system --quiet --group (?P<account>\S+)\n'
    r'(?P=indent)fi'
)

SYSTEM_ACCOUNT_ADDUSER_LINE = re.compile(
    r'(?P<indent>[ \t]*)(?:in_sysroot )?adduser --system --quiet --group (?P<account>\S+)\n'
)

IN_SYSROOT_FUNCTION = re.compile(
    r"in_sysroot\s*\(\)\s*\{\n"
    r"(?:[ \t]+[^\n]*\n)*"
    r"\}\n"
)

DPKG_COMPARE_VERSIONS = re.compile(
    r"dpkg --compare-versions (?P<left>\S+) (?P<op>'?[a-z]{2}'?) (?P<right>\S+)"
)

INVOKE_RC_LINE = re.compile(
    r"(?P<indent>[ \t]*)invoke-rc\.d\s+(?P<name>\S+)\s+"
    r"(?P<action>restart|reload|try-restart|force-reload|start)\b[^\n]*\n"
)

DEB_SYSTEMD_INVOKE_LINE = re.compile(
    r"(?P<indent>[ \t]*)deb-systemd-invoke\s+"
    r"(?P<action>restart|reload|try-restart|start)\s+(?P<name>\S+)[^\n]*\n"
)

SYSCTL_SYSTEM_BLOCK = re.compile(
    r"(?P<indent>[ \t]*)if command -v sysctl > /dev/null; then\n"
    r"(?P=indent)[ \t]*sysctl --quiet --pattern (?P<pattern>\S+) --system \|\| :\n"
    r"(?P=indent)fi\n"
)

UCF_OBSOLETE_REGISTRY_BLOCK = re.compile(
    r'if \[ "\$1" = "upgrade" \] && dpkg --compare-versions "\$2" lt '
    r'(?P<prior>[^;]+); then\n'
    r'(?P<body>(?:[ \t]+(?:rm -f (?P<path>\$\{AUZIX_SETTINGS\}/[^\n]+)|ucf [^\n]+|ucfr [^\n]+)\n)+)'
    r'elif \[ "\$1" = "install" \] && \[ -f (?P=path) \]; then\n'
    r'(?P<body2>(?:[ \t]+(?:rm -f (?P=path)|ucf [^\n]+|ucfr [^\n]+)\n)+)'
    r'fi',
)

UCF_OBSOLETE_REGISTRY_LOOP = re.compile(
    r'if \[ "\$1" = "upgrade" \] && dpkg --compare-versions "\$2" lt '
    r'(?P<prior>[^;]+); then\n'
    r'\tfor i in (?P<items>[^;]+); do\n'
    r'\t\trm -f (?P<directory>\$\{AUZIX_SETTINGS\}/[^$\n]+)/\$i\n'
    r'\t\tucf --purge (?P=directory)/\$i\n'
    r'\t\tucfr --force --purge (?P<package>\S+) (?P=directory)/\$i\n'
    r'\tdone\n'
    r'elif \[ "\$1" = "install" \] && \[ -f (?P=directory)/[^\]]+ \]; then\n'
    r'\tfor i in (?P=items); do\n'
    r'\t\trm -f (?P=directory)/\$i\n'
    r'\t\tucf --purge (?P=directory)/\$i\n'
    r'\t\tucfr --force --purge (?P=package) (?P=directory)/\$i\n'
    r'\tdone\n'
    r'fi',
)

RM_CONFFILE_LINE = re.compile(
    r"^(?P<indent>\s*)dpkg-maintscript-helper\s+rm_conffile\s+"
    r"(?P<path>\S+)(?:[ \t]+(?P<prior_version>(?!--)\S+)"
    r"(?:[ \t]+(?P<package>(?!--)\S+))?)?[ \t]+--[ \t]+\"\$@\"[ \t]*$",
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
UPDATE_ALTERNATIVE_INSTALL = re.compile(
    r"update-alternatives\s+(?:--quiet\s+)?--install\s+"
    r"(?P<destination>\S+)\s+(?P<name>\S+)\s+(?P<source>\S+)\s+(?P<priority>\d+)"
)
UPDATE_ALTERNATIVES_COMMAND = re.compile(
    r"(?m)^(?P<indent>[ \t]*)update-alternatives\b(?:[^\n]*\\\n)*[^\n]*"
)
EMPTY_DPKG_VERSION_IF = re.compile(
    r'(?ms)^(?P<indent>[ \t]*)if \[ "\$1" = "?upgrade"? \] && '
    r'dpkg --compare-versions[^\n]+\nthen\n(?P=indent)[ \t]+:\s*'
    r'# AUZiX provider publication is package-owned\n(?P=indent)fi\n?'
)


def _extract_maintscript_migrations(
    text: str, lifecycle_name: str
) -> tuple[str, list[dict[str, str]]]:
    migrations: list[dict[str, str]] = []

    def replace(match: re.Match[str]) -> str:
        if match.group("prior_version") is None:
            path = match.group("path")
            # Do not turn arbitrary shell arguments into executable migration.
            if not re.fullmatch(r"\$\{AUZIX_SETTINGS\}/[A-Za-z0-9_./-]+", path) or ".." in path.split("/"):
                return match.group(0)
            migrations.append({
                "operation": "remove-obsolete-conffile", "path": path,
                "prior_version": None, "stage": lifecycle_name,
                "disposition": "preserve-as-auzix-bak-before-install",
            })
            if lifecycle_name != "before_install":
                return match.group("indent") + ": # obsolete configuration handled before install"
            return f'''auzix_obsolete="{path}"
if [ -L "$auzix_obsolete" ]; then
    echo "Refusing obsolete configuration symlink: $auzix_obsolete" >&2
    exit 1
fi
if [ -e "$auzix_obsolete" ]; then
    [ -f "$auzix_obsolete" ] || exit 1
    if [ -e "$auzix_obsolete.auzix-bak" ] || [ -L "$auzix_obsolete.auzix-bak" ]; then
        echo "Obsolete configuration backup already exists" >&2
        exit 1
    fi
    mv -- "$auzix_obsolete" "$auzix_obsolete.auzix-bak"
fi'''
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

    def replace_ucf_registry(match: re.Match[str]) -> str:
        path = match.group("path")
        migrations.append({
            "operation": "remove-obsolete-managed-configuration",
            "path": path,
            "prior_version": match.group("prior").strip(),
            "stage": lifecycle_name,
            "disposition": "native-filesystem-effect-without-donor-registry",
        })
        return f'if [ -f {path} ]; then\n\trm -f {path}\nfi'

    text = UCF_OBSOLETE_REGISTRY_BLOCK.sub(replace_ucf_registry, text)

    def replace_ucf_registry_loop(match: re.Match[str]) -> str:
        directory = match.group("directory")
        items = match.group("items").split()
        migrations.extend({
            "operation": "remove-obsolete-managed-configuration",
            "path": f"{directory}/{item}",
            "prior_version": match.group("prior").strip(),
            "stage": lifecycle_name,
            "disposition": "native-filesystem-effect-without-donor-registry",
        } for item in items)
        return (
            f"for i in {' '.join(items)}; do\n"
            f'\t[ ! -f "{directory}/$i" ] || rm -f "{directory}/$i"\n'
            "done"
        )

    text = UCF_OBSOLETE_REGISTRY_LOOP.sub(replace_ucf_registry_loop, text)

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


def _package_atom(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.split(":", 1)[0].casefold())


def _apply_generated_script_rules(
    text: str, package_name: str, package_root: str
) -> tuple[str, list[str], list[dict[str, Any]]]:
    rules: list[str] = []
    operations: list[dict[str, Any]] = []
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

    def replace_self_cache(match: re.Match[str]) -> str:
        if _package_atom(match.group("package")) != _package_atom(package_name):
            return match.group(0)
        indent = match.group("indent")
        root = f'"{package_root}/RootFS"'
        return (
            f"{indent}find {root} -type f -path '*/__pycache__/*' "
            "\\( -name '*.pyc' -o -name '*.pyo' \\) -delete\n"
            f"{indent}find {root} -type d -name __pycache__ -empty -delete"
        )

    text, count = DPKG_SELF_PYTHON_CACHE_BLOCK.subn(replace_self_cache, text)
    if count > 1:
        raise ContractError(f"self-package Python cache rule matched {count} blocks")
    if count == 1 and "dpkg -L" not in text:
        rules.append("self-package-python-bytecode-cleanup")

    def replace_statoverride_mode(match: re.Match[str]) -> str:
        indent = match.group("indent")
        path = match.group("path")
        mode = match.group("mode")
        return f'{indent}[ ! -e {path} ] || chmod {mode} {path}'

    text, count = DPKG_STATOVERRIDE_MODE_BLOCK.subn(replace_statoverride_mode, text)
    if count > 1:
        raise ContractError(f"statoverride mode rule matched {count} blocks")
    if count == 1:
        rules.append("native-existing-path-mode")

    def replace_statoverride_add(match: re.Match[str]) -> str:
        operations.append({
            "type": "apply-statoverride",
            "user": match.group("user").strip("\"'"),
            "group": match.group("group").strip("\"'"),
            "mode": match.group("mode"),
            "path": match.group("path"),
        })
        return (
            f'{match.group("indent")}auzix_apply_statoverride '
            f'{match.group("user")} {match.group("group")} '
            f'{match.group("mode")} {match.group("path")}\n'
        )

    text, count = DPKG_STATOVERRIDE_ADD_BLOCK.subn(replace_statoverride_add, text)
    if count:
        rules.append("debian-statoverride-add")
    text, extra = DPKG_STATOVERRIDE_ADD_LINE.subn(replace_statoverride_add, text)
    if extra:
        rules.append("debian-statoverride-add")

    def replace_system_account(match: re.Match[str]) -> str:
        account = match.group("account")
        operations.append({
            "type": "ensure-system-account",
            "account": account.strip("\"'"),
        })
        return f'{match.group("indent")}auzix_ensure_system_account {account}\n'

    text, count = SYSTEM_ACCOUNT_SYSUSERS_BLOCK.subn(replace_system_account, text)
    if count:
        rules.append("debian-system-account")
    text, extra = SYSTEM_ACCOUNT_ADDUSER_LINE.subn(replace_system_account, text)
    if extra:
        rules.append("debian-system-account")

    def replace_compare_versions(match: re.Match[str]) -> str:
        operator = match.group("op").strip("'\"")
        operations.append({
            "type": "upgrade-compare",
            "left": match.group("left"),
            "operator": operator,
            "right": match.group("right").strip("'\""),
        })
        return (
            f'auzix_upgrade_cmp {match.group("left")} {operator} '
            f'{match.group("right")}'
        )

    text, count = DPKG_COMPARE_VERSIONS.subn(replace_compare_versions, text)
    if count:
        rules.append("debian-upgrade-compare")

    if "in_sysroot" in text and IN_SYSROOT_FUNCTION.search(text):
        dropped = IN_SYSROOT_FUNCTION.sub("", text)
        if "in_sysroot" not in dropped:
            text = dropped
            rules.append("debian-in-sysroot-unused")

    def replace_service_reload(match: re.Match[str]) -> str:
        name = match.group("name").strip("'\"")
        action = match.group("action")
        operations.append({
            "type": "reload-service" if action != "start" else "start-service",
            "name": name,
            "action": action,
        })
        helper = "auzix_reload_service" if action != "start" else "auzix_reload_service"
        return f'{match.group("indent")}{helper} {match.group("name")} || true\n'

    text, count = INVOKE_RC_LINE.subn(replace_service_reload, text)
    if count:
        rules.append("debian-service-reload")
    text, extra = DEB_SYSTEMD_INVOKE_LINE.subn(replace_service_reload, text)
    if extra:
        rules.append("debian-service-reload")

    def replace_sysctl(match: re.Match[str]) -> str:
        operations.append({
            "type": "apply-sysctl",
            "pattern": match.group("pattern").strip("'\""),
        })
        return (
            f'{match.group("indent")}auzix_apply_sysctl {match.group("pattern")}\n'
        )

    text, count = SYSCTL_SYSTEM_BLOCK.subn(replace_sysctl, text)
    if count:
        rules.append("debian-sysctl-apply")
    return text, rules, operations


DONOR_ACTIONS = {
    "before_install": "install",
    "after_install": "configure",
    "before_remove": "remove",
    "after_remove": "remove",
}

PURGE_IF = re.compile(
    r'^\s*if\s+\[\s*"?\$1"?\s*=\s*"?purge"?\s*\]\s*(?:&&[^;]+)?;?\s*(?:then)?\s*$'
)

CONSTANT_STRING_IF = re.compile(
    r'^\s*if\s+\[\s*"(?P<left>[^"]*)"\s*=\s*"(?P<right>[^"]*)"\s*\]\s*;?\s*then\s*$'
)


def _prune_constant_false_blocks(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    changed = False
    index = 0
    while index < len(lines):
        match = CONSTANT_STRING_IF.match(lines[index].rstrip("\n"))
        if (
            not match
            or "$" in match.group("left")
            or "$" in match.group("right")
            or match.group("left") == match.group("right")
        ):
            output.append(lines[index])
            index += 1
            continue
        depth = 1
        end = index + 1
        while end < len(lines) and depth:
            stripped = lines[end].strip()
            if re.match(r"^if\b.*\bthen$", stripped):
                depth += 1
            if stripped == "fi" or stripped.startswith("fi;"):
                depth -= 1
            end += 1
        if depth:
            output.append(lines[index])
            index += 1
            continue
        output.append(
            f': # constant-false donor branch: {match.group("left")} != {match.group("right")}\n'
        )
        index = end
        changed = True
    result = "".join(output)
    if changed and not re.search(r"\bdb_[A-Za-z0-9_]+\b", result):
        result = re.sub(
            r'(?m)^\s*\.\s+/usr/share/debconf/confmodule\s*$\n?',
            ": # unused donor debconf import\n",
            result,
        )
    return result, changed


def _prune_unreachable_purge_blocks(text: str, lifecycle_name: str) -> tuple[str, bool]:
    """Remove Debian purge-only branches from APK's normal removal stage."""
    if lifecycle_name != "after_remove" or "purge" not in text:
        return text, False
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    changed = False
    index = 0
    while index < len(lines):
        line = lines[index]
        if PURGE_IF.match(line.rstrip("\n")):
            body_start = index + 1
            if body_start < len(lines) and lines[body_start].strip() == "then":
                body_start += 1
            elif not line.rstrip().endswith("then"):
                output.append(line)
                index += 1
                continue
            depth = 1
            end = body_start
            while end < len(lines) and depth:
                stripped = lines[end].strip()
                if re.match(r"^if\b", stripped):
                    depth += 1
                if stripped == "fi" or stripped.startswith("fi;"):
                    depth -= 1
                end += 1
            if depth:
                output.append(line)
                index += 1
                continue
            output.append(": # Debian purge-only effects retained as non-executable intent\n")
            index = end
            changed = True
            continue
        output.append(line)
        index += 1
    result = "".join(output)
    if changed:
        assignment = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)=.*$")
        while True:
            current = result.splitlines(keepends=True)
            removed = False
            rewritten: list[str] = []
            for position, candidate in enumerate(current):
                match = assignment.match(candidate.rstrip("\n"))
                if not match:
                    rewritten.append(candidate)
                    continue
                name = match.group("name")
                elsewhere = "".join(current[:position] + current[position + 1:])
                if re.search(rf"\$(?:{re.escape(name)}\b|\{{{re.escape(name)}\}})", elsewhere):
                    rewritten.append(candidate)
                    continue
                rewritten.append(f'{match.group("indent")}: # unused donor variable {name}\n')
                removed = True
            result = "".join(rewritten)
            if not removed:
                break
    return result, changed


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
        for donor, replacement in load_rewrite_paths():
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
                # libc commonly ships /usr/lib64/ld-linux as a convenience
                # symlink to the canonical multiarch loader.  Publish the
                # canonical object once; the adapter owns compatibility aliases.
                if source.is_symlink():
                    continue
                raise ContractError(f"{name}: duplicate public library basename: {source.name}")
            seen.add(source.name)
            owned = f"/Libraries/Packages/{name}/{version}/{source.name}"
            plan.append({
                "source": "/" + str(source.relative_to(package_root.parent.parent.parent)),
                "owned": owned,
                "public": f"/Libraries/{source.name}",
            })
    return plan


def _alternative_provider_plan(
    stage: Path, package_root: Path, scripts: list[Path]
) -> list[dict[str, str]]:
    selected: dict[str, tuple[int, str]] = {}
    for script in scripts:
        if not script.is_file():
            continue
        body = script.read_text(encoding="utf-8", errors="replace")
        logical_body = body.replace("\\\n", " ")
        for match in UPDATE_ALTERNATIVE_INSTALL.finditer(logical_body):
            source = match.group("source")
            payload = package_root / "RootFS" / source.lstrip("/")
            if not (payload.is_file() or payload.is_symlink()):
                continue
            destination = match.group("destination")
            if destination.endswith(".so") or ".so." in destination:
                public = f"/Libraries/{Path(destination).name}"
            elif destination.startswith(("/usr/", "/lib/", "/bin/", "/sbin/")):
                public = "/System/Compatibility" + destination
            else:
                continue
            candidate = (int(match.group("priority")), source)
            if public not in selected or candidate[0] > selected[public][0]:
                selected[public] = candidate
    prefix = "/" + str(package_root.relative_to(stage))
    return [
        {
            "source": f"{prefix}/RootFS{source}",
            "owned": f"{prefix}/RootFS{source}",
            "public": public,
            "mode": "provider-link",
            "priority": str(priority),
        }
        for public, (priority, source) in sorted(selected.items())
    ]


SED_SUBST = re.compile(r"^s\|(?P<donor>.+?)\|(?P<dest>.+?)\|g\s*$")


@lru_cache(maxsize=1)
def load_rewrite_paths() -> tuple[tuple[str, str], ...]:
    path = REPOSITORY_ROOT / "packaging/rewrite-paths.sed"
    pairs: list[tuple[str, str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = SED_SUBST.match(line)
        if match is None:
            raise ContractError(f"invalid rewrite-paths.sed line: {raw}")
        pairs.append((match.group("donor").replace(r"\>", ""), match.group("dest")))
    return tuple(sorted(pairs, key=lambda item: len(item[0]), reverse=True))


def _apply_rewrite_paths(text: str) -> str:
    donor_root_forms = (r"\$\{DPKG_ROOT:-\}", r'"\$DPKG_ROOT"', r"\$DPKG_ROOT")
    for donor, replacement in load_rewrite_paths():
        for donor_root in donor_root_forms:
            text = re.sub(
                donor_root + re.escape(donor) + r"(?=/|[^A-Za-z0-9_]|$)",
                lambda _match, value=replacement: value,
                text,
            )
        text = re.sub(
            rf"(?<![A-Za-z0-9_${{}}]){re.escape(donor)}(?=/|[^A-Za-z0-9_]|$)",
            lambda _match, value=replacement: value,
            text,
        )
    return text


def _replace_paths(text: str, package_root: Path) -> str:
    lines = text.splitlines(keepends=True)
    shebang = lines[0] if lines and lines[0].startswith("#!") else ""
    result = "".join(lines[1:]) if shebang else text

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
    return shebang + _apply_rewrite_paths(result)


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
    adapter = package_definition.get("intake_adapter") if package_definition else None
    surfaces = receipt.get("maintainer_surfaces", [])
    if not isinstance(surfaces, list) or not all(isinstance(item, str) for item in surfaces):
        raise ContractError("maintainer_surfaces must be a string array")
    # Old receipts can omit annotation even though dpkg control files survived.
    # Discover those files before deciding that a package has no lifecycle.
    prefix_hint = receipt.get("prefix", "")
    if isinstance(prefix_hint, str) and prefix_hint.startswith("/Programs/"):
        control = stage / prefix_hint.lstrip("/") / "Metadata/debian-control-dir"
        discovered = ["/" + str(path.relative_to(stage)) for path in sorted(control.glob("*"))
                      if path.is_file() and path.name in
                      {*LIFECYCLE_STAGES, "triggers", "conffiles", "config", "templates"}]
        surfaces = list(dict.fromkeys([*surfaces, *discovered]))
    retained = [path for path in surfaces if Path(path).name in LIFECYCLE_STAGES]
    other_surfaces = [path for path in surfaces if Path(path).name not in LIFECYCLE_STAGES]
    # A checked-in adapter is authoritative package metadata.  Older donor
    # archives may predate maintainer-surface annotation; they must not bypass
    # the adapter and silently become scriptless APKs.
    if not retained and not other_surfaces and adapter is None:
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
    compatibility_links: list[dict[str, str]] = []
    migrations: list[dict[str, str]] = []
    rules: dict[str, dict[str, Any]] = {}
    evidence_dir = output_dir / "evidence"
    donor_dir = output_dir / "~deb_inst"
    rendered_dir = output_dir / "rendered"
    package_root_path = stage / prefix.lstrip("/")
    library_publications = _alternative_provider_plan(
        stage,
        package_root_path,
        [stage / path.lstrip("/") for path in retained],
    )
    if library_publications:
        operations.extend({
            "type": "publish-provider",
            "source": item["source"],
            "public": item["public"],
            "priority": int(item["priority"]),
        } for item in library_publications)
        rules["native-provider-publication"] = {
            "id": "native-provider-publication",
            "state": "transformed",
            "stages": [],
            "outputs": [item["public"] for item in library_publications],
        }
    inactive_debconf_surfaces = False
    for surface_path in other_surfaces:
        if Path(surface_path).name != "config":
            continue
        source = stage / surface_path.lstrip("/")
        if source.is_file():
            _unused, inactive_debconf_surfaces = _prune_constant_false_blocks(
                source.read_text(encoding="utf-8", errors="replace")
            )
    for surface_path in other_surfaces:
        source = stage / surface_path.lstrip("/")
        name = Path(surface_path).name
        if inactive_debconf_surfaces and name in {"config", "templates"}:
            rules["constant-false-debconf"] = {
                "id": "constant-false-debconf",
                "state": "transformed",
                "source": surface_path,
                "disposition": "not-applicable-target-architecture",
            }
            continue
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
                    direct_publications = _public_library_plan(
                        stage / prefix.lstrip("/"),
                        str(receipt.get("name")),
                        str(receipt.get("version")),
                    )
                    library_publications.extend(direct_publications)
                    if library_publications:
                        operations.extend(
                            {
                                "type": "publish-library",
                                "source": item["source"],
                                "owned": item["owned"],
                                "public": item["public"],
                            }
                            for item in direct_publications
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
        normalized_body, applied_script_rules, protocol_operations = (
            _apply_generated_script_rules(
                normalized_body, str(receipt.get("name")), prefix
            )
        )
        operations.extend(protocol_operations)
        python_cleanup = adapt_python_prerm(original, str(receipt.get("name")), lifecycle_name)
        if python_cleanup is not None:
            normalized_body = python_cleanup
            applied_script_rules.append("reviewed-python-owned-bytecode-cleanup")
        if library_publications and "update-alternatives" in normalized_body:
            normalized_body = UPDATE_ALTERNATIVES_COMMAND.sub(
                lambda match: match.group("indent")
                + ": # AUZiX provider publication is package-owned",
                normalized_body,
            )
            normalized_body = EMPTY_DPKG_VERSION_IF.sub(
                lambda match: match.group("indent")
                + ": # obsolete donor provider migration",
                normalized_body,
            )
            applied_script_rules.append("native-provider-publication")
        normalized_body, constant_false = _prune_constant_false_blocks(normalized_body)
        if constant_false:
            applied_script_rules.append("constant-false-branch")
        normalized_body, pruned_purge = _prune_unreachable_purge_blocks(
            normalized_body, lifecycle_name
        )
        if pruned_purge:
            applied_script_rules.append("apk-no-distinct-purge")
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
        executable_body = "\n".join(
            line for line in normalized_body.splitlines()[1:]
            if not line.lstrip().startswith("#")
            and not re.match(r"^\s*:\s+#", line)
        )
        for kind, pattern in UNSUPPORTED_PATTERNS.items():
            if kind == "lifecycle-arguments" and wrapped_arguments:
                continue
            matches = sorted(set(pattern.findall(executable_body)))
            if matches:
                script_findings.append({
                    "kind": kind,
                    "semantic_class": FINDING_SEMANTICS.get(kind, "unresolved"),
                    "matches": matches,
                })
        remaining_paths = sorted(set(ABSOLUTE_PATH.findall(executable_body)))
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

    adapter_record = None
    donor_findings: list[dict[str, Any]] = []
    trigger_scripts: list[dict[str, Any]] = []
    if adapter is not None:
        if adapter.get("format") != "auzix-lifecycle-adapter-v1":
            raise ContractError("unsupported lifecycle intake adapter format")
        augment = adapter.get("mode", "replace") == "augment"
        if adapter.get("mode", "replace") not in {"augment", "replace"}:
            raise ContractError("unsupported lifecycle adapter mode")
        template_dir = REPOSITORY_ROOT / adapter.get("template_dir", "")
        if not template_dir.is_dir():
            raise ContractError(f"lifecycle adapter template directory is missing: {template_dir}")
        configured = adapter.get("configuration", [])
        if not isinstance(configured, list) or not all(isinstance(path, str) for path in configured):
            raise ContractError("lifecycle adapter configuration must be a string array")
        configuration = list(dict.fromkeys(configuration + configured)) if augment else configured
        package_root = stage / prefix.lstrip("/")
        if adapter.get("publish_libraries"):
            direct_publications = _public_library_plan(
                package_root, str(receipt.get("name")), str(receipt.get("version"))
            )
            existing_public = {item["public"] for item in library_publications}
            library_publications.extend(
                item for item in direct_publications if item["public"] not in existing_public
            )
            rules["adapter-library-publication"] = {
                "id": "adapter-library-publication",
                "state": "transformed",
                "stages": [],
                "outputs": [item["public"] for item in direct_publications],
            }
        compatibility_links = [
            {
                **item,
                "target": item.get("target", "")
                .replace("@PACKAGE_ROOT@", prefix)
                .replace("@VERSION@", str(receipt.get("version"))),
            }
            for item in adapter.get("compatibility_links", [])
        ]
        if not all(
            isinstance(item, dict)
            and isinstance(item.get("path"), str)
            and item["path"].startswith("/System/Compatibility/")
            and isinstance(item.get("target"), str)
            and item["target"].startswith(("/Libraries/", "/Programs/"))
            for item in compatibility_links
        ):
            raise ContractError("lifecycle adapter compatibility_links are invalid")
        operations = (operations if augment else []) + [
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
        donor_findings = list(findings)
        if not augment:
            findings = []
            scripts = []
        rendered_dir.mkdir(parents=True, exist_ok=True)
        for lifecycle_name, template_name in adapter.get("scripts", {}).items():
            if augment and any(script["stage"] == lifecycle_name for script in scripts):
                raise ContractError(f"augment adapter would replace donor stage: {lifecycle_name}")
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
        for trigger in adapter.get("triggers", []):
            if not isinstance(trigger, dict):
                raise ContractError("lifecycle adapter trigger must be an object")
            template_name = trigger.get("template")
            paths = trigger.get("paths")
            if (
                not isinstance(template_name, str)
                or not template_name.endswith(".trigger")
                or not isinstance(paths, list)
                or not paths
                or not all(isinstance(path, str) and path.startswith("/") for path in paths)
            ):
                raise ContractError(
                    "lifecycle adapter trigger must declare a .trigger template and absolute paths"
                )
            template = template_dir / template_name
            if not template.is_file():
                raise ContractError(f"lifecycle adapter trigger template is missing: {template}")
            candidate = rendered_dir / template_name
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
                    f"adapter trigger has invalid shell syntax: {template}: {syntax.stderr.strip()}"
                )
            trigger_scripts.append({"candidate": str(candidate), "paths": paths})
        adapter_record = {
            "format": adapter["format"],
            "template_dir": str(template_dir),
            "disposition": "augmented-by-package-adapter" if augment else "replaced-by-package-adapter",
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
        "triggers": trigger_scripts,
        "donor_objects": donor_objects,
        "effect_candidates": effect_candidates,
        "operations": operations,
        "adapter": adapter_record,
        "configuration": sorted(set(configuration)),
        "library_publications": library_publications,
        "compatibility_links": compatibility_links,
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
        "compatibility_links": compatibility_links,
        "rendered_scripts": scripts,
        "rendered_triggers": trigger_scripts,
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
) -> tuple[dict[str, Any], list[tuple[str, Path | str]]]:
    """Replace donor evidence with the native AUZiX package contract in-place."""
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    prefix = receipt["prefix"]
    package_root = stage / prefix.lstrip("/")
    native_dir = package_root / "Package"
    scripts_dir = native_dir / "Scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    # AUZiX programs are always addressable through a stable current link.
    # Some legacy archives predate that invariant and contain only their
    # versioned prefix. Publish it in the package payload so APK owns the link;
    # activation and Docker assembly must never repair it afterward.
    program_parts = Path(prefix).parts
    if len(program_parts) >= 4 and program_parts[1] == "Programs":
        program_dir = stage / "Programs" / program_parts[2]
        current = program_dir / "current"
        if not (current.exists() or current.is_symlink()):
            current.symlink_to(prefix)
    for publication in intake.get("library_publications", []):
        source = stage / publication["source"].lstrip("/")
        public = stage / publication["public"].lstrip("/")
        if not (source.is_file() or source.is_symlink()):
            raise ContractError(
                f"{receipt.get('name')}: public library disappeared before promotion: {source}"
            )
        public.parent.mkdir(parents=True, exist_ok=True)
        if public.exists() or public.is_symlink():
            raise ContractError(
                f"{receipt.get('name')}: public library destination already exists: {publication}"
            )
        if publication.get("mode") == "provider-link":
            public.symlink_to(os.path.relpath(source, public.parent))
        else:
            owned = stage / publication["owned"].lstrip("/")
            owned.parent.mkdir(parents=True, exist_ok=True)
            if owned.exists() or owned.is_symlink():
                raise ContractError(
                    f"{receipt.get('name')}: owned library destination already exists: {publication}"
                )
            shutil.move(str(source), str(owned))
            # APK's tar payload may truncate absolute link targets at 100
            # bytes. A relative link from /Libraries is shorter and remains
            # relocatable while resolving to the same package-owned object.
            public.symlink_to(os.path.relpath(owned, public.parent))
    for link in intake.get("compatibility_links", []):
        destination = stage / link["path"].lstrip("/")
        target = stage / link["target"].lstrip("/")
        if not (target.exists() or target.is_symlink()):
            raise ContractError(
                f"{receipt.get('name')}: compatibility link target is missing: {link}"
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() or destination.is_symlink():
            raise ContractError(
                f"{receipt.get('name')}: compatibility link destination exists: {link}"
            )
        destination.symlink_to(os.path.relpath(target, destination.parent))
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
    fpm_scripts: list[tuple[str, Path | str]] = []
    for script in intake["scripts"]:
        destination = scripts_dir / Path(script["candidate"]).name
        shutil.copy2(script["candidate"], destination)
        absolute = "/" + str(destination.relative_to(stage))
        lifecycle[script["stage"]] = absolute
        fpm_scripts.append((script["flag"], destination))
    triggers = []
    for trigger in intake.get("triggers", []):
        destination = scripts_dir / Path(trigger["candidate"]).name
        shutil.copy2(trigger["candidate"], destination)
        absolute = "/" + str(destination.relative_to(stage))
        paths = list(trigger["paths"])
        triggers.append({"script": absolute, "paths": paths})
        fpm_scripts.append(("--apk-trigger", f"{destination}={':'.join(paths)}"))

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
            "public": [item["public"] for item in intake.get("library_publications", [])],
            "compatibility_links": intake.get("compatibility_links", []),
        },
        "migrations": intake.get("migrations", []),
        "lifecycle": lifecycle,
        "triggers": triggers,
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

    # Preserve source control evidence with the adapted package. These files
    # are inert metadata, not hooks executed by APK. Do not erase our audit trail.
    (native_dir / "donor-provenance.json").write_text(json.dumps({
        "source": receipt.get("source"),
        "maintainer_surfaces": receipt.get("maintainer_surfaces", []),
        "donor_objects": intake.get("donor_objects", []),
        "rules": intake.get("rules", []),
        "adapter": intake.get("adapter"),
        "operations": intake.get("operations", []),
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
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
    receipt["triggers"] = triggers
    receipt["package_contract"] = prefix + "/Package/package.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return package_json, fpm_scripts

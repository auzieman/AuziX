from __future__ import annotations

import hashlib
import json
import copy
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from .contracts import ContractError, read_json
from .names import apk_name, apk_version
from .package_graph import load_packages
from .process import run
from .lifecycle_intake import FINDING_SEMANTICS, normalize_lifecycle, promote_auzix_package


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_index(repository: Path) -> dict[str, dict[str, Any]]:
    index = read_json(repository / "index.json")
    if index.get("format") != "auzix-repo-v1" or not isinstance(index.get("packages"), list):
        raise ContractError(f"invalid AUZiX repository index: {repository / 'index.json'}")
    records: dict[str, dict[str, Any]] = {}
    for record in index["packages"]:
        name = record.get("name")
        if not isinstance(name, str) or not name:
            raise ContractError("AUZiX repository entry has no package name")
        if name in records:
            raise ContractError(f"duplicate AUZiX repository entry: {name}")
        records[name] = record
    return records


def _archive_apk_name(record: dict[str, Any]) -> str:
    source = record.get("source", {})
    native_name = source.get("package") if isinstance(source, dict) else None
    if isinstance(native_name, str) and native_name:
        return native_name.lower()
    return apk_name(record["name"]).removeprefix("auzix-")


def _archive_layout_domain(record: dict[str, Any]) -> str:
    native_name = _archive_apk_name(record)
    prefix = record.get("prefix", "")
    if (
        record.get("kind") == "library"
        or native_name.startswith("lib")
        or native_name in {"ncurses-base", "ncurses-term"}
        or (isinstance(prefix, str) and prefix.startswith("/Programs/Lib"))
    ):
        return "library"
    return "program"


def _automatic_library_definition(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "dependencies": {"runtime": list(record.get("depends", []))},
        "intake_adapter": {
            "format": "auzix-lifecycle-adapter-v1",
            "template_dir": "packaging/packages/_auto-library/lifecycle",
            "configuration": [],
            "scripts": {},
            "publish_libraries": True,
            "operations": [{
                "type": "publish-package-libraries",
                "destination": "/System/Libraries",
            }],
            "retained_state": [],
        },
    }


def _with_automatic_library_publication(
    record: dict[str, Any], package_definition: dict[str, Any] | None
) -> dict[str, Any]:
    if package_definition is None:
        return _automatic_library_definition(record)
    definition = copy.deepcopy(package_definition)
    adapter = definition.get("intake_adapter")
    if adapter is None:
        adapter = _automatic_library_definition(record)["intake_adapter"]
        definition["intake_adapter"] = adapter
    adapter["publish_libraries"] = True
    operations = adapter.setdefault("operations", [])
    if not any(item.get("type") == "publish-package-libraries" for item in operations):
        operations.append({
            "type": "publish-package-libraries",
            "destination": "/System/Libraries",
        })
    return definition


def _review_summary(packages: list[dict[str, Any]]) -> dict[str, Any]:
    by_rule: dict[str, set[str]] = {}
    by_semantic_class: dict[str, set[str]] = {}
    outliers: list[dict[str, Any]] = []
    for package in packages:
        if package.get("status") != "needs-review":
            continue
        intake = package.get("intake", {})
        residuals = intake.get("residual_findings", intake.get("findings", []))
        residual_rules = []
        for rule in intake.get("rules", []):
            if rule.get("state") == "transformed":
                continue
            rule_id = rule.get("id", "unclassified")
            by_rule.setdefault(rule_id, set()).add(package["name"])
            residual_rules.append(rule_id)
        semantic_classes = []
        for finding in residuals:
            semantic = finding.get(
                "semantic_class",
                FINDING_SEMANTICS.get(finding.get("kind"), "unresolved"),
            )
            by_semantic_class.setdefault(semantic, set()).add(package["name"])
            semantic_classes.append(semantic)
        outliers.append({
            "name": package["name"],
            "apk_name": package["apk_name"],
            "scripts": len(intake.get("scripts", [])),
            "residual_findings": len(residuals),
            "residual_rules": sorted(set(residual_rules)),
            "semantic_classes": sorted(set(semantic_classes)),
        })
    return {
        "packages": len(outliers),
        "by_rule": [
            {"rule": key, "count": len(names), "packages": sorted(names)}
            for key, names in sorted(by_rule.items(), key=lambda item: (-len(item[1]), item[0]))
        ],
        "by_semantic_class": [
            {"semantic_class": key, "count": len(names), "packages": sorted(names)}
            for key, names in sorted(
                by_semantic_class.items(), key=lambda item: (-len(item[1]), item[0])
            )
        ],
        "outliers": sorted(
            outliers, key=lambda item: (-item["residual_findings"], item["name"])
        ),
    }


def archive_profile_plan(repository: Path, profile_path: Path) -> dict[str, Any]:
    profile = read_json(profile_path)
    if profile.get("format") != "auzix-archive-profile-v1":
        raise ContractError(f"invalid archive profile: {profile_path}")
    receipt_policy = profile.get("receipt_policy")
    expected_receipt_policy = {
        "dependencies": "auzix-package-json",
        "lifecycle": "intake-normalize-v1",
        "continue_on_error": True,
    }
    if receipt_policy != expected_receipt_policy:
        raise ContractError(
            f"{profile_path}: receipt_policy must declare the AUZiX intake contract"
        )
    selected = profile.get("packages")
    if not isinstance(selected, list) or not selected or not all(isinstance(x, str) for x in selected):
        raise ContractError(f"{profile_path}: packages must be a non-empty string array")
    dependency_additions = profile.get("dependency_additions", {})
    if not isinstance(dependency_additions, dict) or not all(
        isinstance(name, str)
        and isinstance(dependencies, list)
        and all(isinstance(dependency, str) for dependency in dependencies)
        for name, dependencies in dependency_additions.items()
    ):
        raise ContractError(f"{profile_path}: dependency_additions must map package names to string arrays")
    external_providers = profile.get("external_providers", {})
    if not isinstance(external_providers, dict) or not all(
        isinstance(name, str) and isinstance(provider, str) and provider
        for name, provider in external_providers.items()
    ):
        raise ContractError(f"{profile_path}: external_providers must map package names to APK atoms")
    package_names = profile.get("package_names", {})
    if not isinstance(package_names, dict) or not all(
        isinstance(name, str) and isinstance(apk_atom, str) and apk_atom
        for name, apk_atom in package_names.items()
    ):
        raise ContractError(f"{profile_path}: package_names must map package names to APK atoms")
    records = _load_index(repository)
    package_definitions = {name: package for name, (_, package) in load_packages().items()}
    folded = {name.casefold(): name for name in records}
    apk_names = {
        name: package_names.get(name, _archive_apk_name(record)) for name, record in records.items()
    }
    ordered: list[str] = []
    for requested in selected:
        name = folded.get(requested.casefold(), requested)
        if name not in records:
            raise ContractError(f"repository does not contain selected package: {requested}")
        if name not in ordered:
            ordered.append(name)

    planned = []
    for name in ordered:
        record = records[name]
        archive = repository / "packages" / record["package"]
        if not archive.is_file():
            raise ContractError(f"archive is missing for {name}: {archive}")
        expected = record.get("sha256")
        actual = _sha256(archive)
        if expected != actual:
            raise ContractError(f"archive checksum mismatch for {name}: {archive}")
        result = subprocess.run(
            ["tar", "-tzf", str(archive)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
        )
        if result.returncode:
            raise ContractError(f"archive is unreadable for {name}: {result.stderr.strip()}")
        layout_domain = _archive_layout_domain(record)
        package_definition = package_definitions.get(name)
        if layout_domain == "library":
            package_definition = _with_automatic_library_publication(
                record, package_definition
            )
        # The intake receipt owns the direct Debian dependency graph.  Package
        # definitions and release profiles may add AUZiX-specific providers,
        # but must not erase those upstream edges during APK conversion.
        dependencies = [
            *record.get("depends", []),
            *dependency_additions.get(name, []),
        ]
        if package_definition is not None:
            dependencies = [
                *dependencies,
                *package_definition.get("dependencies", {}).get("runtime", []),
            ]
        dependencies = list(dict.fromkeys(dependencies))
        apk_dependencies = []
        for dependency in dependencies:
            canonical = folded.get(dependency.casefold(), dependency)
            if canonical in external_providers:
                apk_dependencies.append(external_providers[canonical])
            elif canonical in apk_names:
                apk_dependencies.append(apk_names[canonical])
            elif canonical in package_names:
                # Native/bootstrap providers may satisfy an archive package
                # dependency without themselves being part of this donor wave.
                apk_dependencies.append(package_names[canonical])
            else:
                apk_dependencies.append(apk_name(dependency).removeprefix("auzix-"))
        planned.append({
            "name": name,
            "kind": record.get("kind", "program"),
            "layout_domain": layout_domain,
            "version": record["version"],
            "archive": str(archive),
            "sha256": actual,
            "depends": dependencies,
            "apk_name": apk_names[name],
            "apk_depends": apk_dependencies,
            "apk_version": apk_version(record["version"]),
            "description": record.get("description") or f"AUZiX {name}",
            "package_definition": package_definition,
        })
    return {"format": "auzix-archive-fpm-plan-v1", "profile": profile["name"], "packages": planned}


def convert_archive_profile(
    repository: Path, profile_path: Path, output_dir: Path, *, apk_command: str
) -> dict[str, Any]:
    if not shutil.which("fpm"):
        raise ContractError("fpm is required")
    if not Path(apk_command).is_file():
        raise ContractError(f"apk verifier is unavailable: {apk_command}")
    plan = archive_profile_plan(repository.resolve(), profile_path.resolve())
    print(f"PREFLIGHT PASS profile={plan['profile']} packages={len(plan['packages'])}", flush=True)
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)
    architecture_dir = output_dir / "x86_64"
    architecture_dir.mkdir()
    intake_dir = output_dir / "intake"
    intake_dir.mkdir()
    review_dir = output_dir / "review"
    review_dir.mkdir()
    records_dir = output_dir / "records"
    records_dir.mkdir()

    def record(item: dict[str, Any]) -> None:
        safe_name = item["apk_name"].replace("/", "-")
        (records_dir / f"{safe_name}.json").write_text(
            json.dumps(item, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    for position, item in enumerate(plan["packages"], 1):
        # APK repositories are architecture-partitioned and fetch packages by
        # the canonical <name>-<version>.apk filename recorded in APKINDEX.
        output = architecture_dir / f"{item['apk_name']}-{item['apk_version']}.apk"
        argv = [
            "fpm", "-s", "tar", "-t", "apk",
            "--name", item["apk_name"],
            "--version", item["apk_version"],
            "--architecture", "x86_64",
            "--description", item["description"],
            "--provides", item["name"].casefold(),
            # Native AUZiX packages historically depended on canonical
            # AUZiX-prefixed identities. Preserve that transition alias while
            # the public APK name follows the donor package name.
            "--provides", apk_name(item["name"]),
            "--package", str(output),
        ]
        print(
            f"EMIT {position}/{len(plan['packages'])} {item['name']} -> {output.name}", flush=True
        )
        try:
            with tempfile.TemporaryDirectory(prefix="auzix-fpm-") as temporary:
                workspace = Path(temporary)
                stage = workspace / "root"
                stage.mkdir()
                run(["tar", "-xzf", item["archive"], "-C", str(stage)])
                receipts = sorted((stage / "System/PackageDB").glob("*.json"))
                if len(receipts) != 1:
                    raise ContractError(
                        f"archive must contain one AUZiX receipt; found {len(receipts)}"
                    )
                receipt = read_json(receipts[0])
                package_review = review_dir / item["apk_name"]
                intake = normalize_lifecycle(
                    stage, receipt, package_review, item.get("package_definition")
                )
                item["intake"] = intake
                if intake["status"] == "needs-review":
                    item["status"] = "needs-review"
                    print(f"REVIEW {item['name']} findings={len(intake['findings'])}", flush=True)
                    record(item)
                    continue

                package_json, lifecycle = promote_auzix_package(
                    stage, receipts[0], intake, item.get("package_definition")
                )
                item["package_contract"] = package_json
                adapted_archive = intake_dir / f"{item['apk_name']}-{item['apk_version']}.auzix.tar.gz"
                run(["tar", "-czf", str(adapted_archive), "-C", str(stage), "."])
                for dependency in item["apk_depends"]:
                    argv.extend(["--depends", dependency])
                for flag, script in lifecycle:
                    argv.extend([flag, str(script)])
                argv.append(str(adapted_archive))
                result = subprocess.run(argv, capture_output=True, text=True)
                if result.returncode:
                    item["status"] = "build-failed"
                    item["error"] = (result.stderr or result.stdout).strip()
                    print(f"BUILD-FAILED {item['name']}", flush=True)
                    record(item)
                    continue
            verify = subprocess.run(
                [apk_command, "verify", "--allow-untrusted", str(output)],
                capture_output=True,
                text=True,
            )
            if verify.returncode:
                item["status"] = "verify-failed"
                item["error"] = (verify.stderr or verify.stdout).strip()
                print(f"VERIFY-FAILED {item['name']}", flush=True)
            else:
                item["status"] = "static" if item["intake"]["status"] == "static" else "passed"
                item["output"] = str(output)
                item["adapted_archive"] = str(adapted_archive)
                print(f"PACKAGE-PASS {item['name']} status={item['status']}", flush=True)
        except (ContractError, OSError, subprocess.SubprocessError) as exc:
            item["status"] = "intake-failed"
            item["error"] = str(exc)
            print(f"INTAKE-FAILED {item['name']}: {exc}", flush=True)
        record(item)

    counts: dict[str, int] = {}
    for item in plan["packages"]:
        status = item.get("status", "unknown")
        counts[status] = counts.get(status, 0) + 1
    completed = counts.get("passed", 0) + counts.get("static", 0)
    overall = "passed" if completed == len(plan["packages"]) else "completed-with-review"
    proof = output_dir / "conversion-proof.json"
    result = {
        **plan,
        "status": overall,
        "summary": counts,
        "review_summary": _review_summary(plan["packages"]),
        "proof": str(proof),
    }
    proof.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"WAVE-COMPLETE repository={output_dir} summary={counts} proof={proof}", flush=True)
    return result

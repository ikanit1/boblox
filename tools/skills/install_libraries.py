#!/usr/bin/env python3
"""Install/verify three pinned libraries with collision-free Codex skill names.

Uses bundled Codex skill-installer validation and no-overwrite copy helpers.
No upstream script, Blender/Studio operation, or MCP configuration runs.
Requires Python 3.10+, PyYAML, Git, and the installed Codex skill-installer.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import unquote
import yaml

REPO = Path(__file__).resolve().parents[2]
LIBRARIES = [
    {"prefix": "el4", "repo": "EL4CTEO/roblox-skills",
     "sha": "a7538bc9a4355ab08ea141bd9d48670195078188", "root": "skills", "count": 23},
    {"prefix": "brain", "repo": "TabooHarmony/roblox-brain",
     "sha": "ceee4aaa5004502e2a51d78b3c33bba44d84742b", "root": "skills", "count": 29},
    {"prefix": "ccb", "repo": "RobLe3/cc-blender-skill",
     "sha": "a2634b588e80265e796aa53f8ab178d75105c2af", "root": "plugin/skills", "count": 30},
]
LOCK = REPO / "tools/skills/skills-install-lock.json"
CATALOG = REPO / "docs/environment/skills-catalog.json"
KNOWN_MISSING = "[../../IMPLEMENTATION_LOG.md](../../../../../IMPLEMENTATION_LOG.md)"
FIXED_MISSING = ("IMPLEMENTATION_LOG.md (upstream historical link: target absent from the pinned "
                 "repository; this local installation does not claim to include that evidence)")
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
URL_SPLIT = re.compile(r"(https?://[^\s<>)\]]+)")
LINK = re.compile(r"(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)")
LOCAL_REDIRECTS = {
    "intent-routing.md": "# Local reference redirect\n\nThe pinned upstream repository mentions this file but does not contain it.\nUse its existing [intent routing table](../SKILL.md#intent--sub-skill-routing-table)\nand [skill harmonizer](../../ccb-blender-skill-harmonizer/SKILL.md).\nThis adapter adds no new routing policy or acceptance claim.\n",
    "code-execution-rules.md": "# Local reference redirect\n\nThe pinned upstream repository mentions this file but does not contain it.\nUse its existing [code execution rules](../SKILL.md#code-execution-rules--non-negotiable)\nand [MCP backend reference](mcp-backends.md).\nResolve tools and timeout limits from the actual configured backend.\nThis adapter is not an upstream file or evidence of a successful execution.\n",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def metadata(path: Path) -> dict:
    text = path.read_text(encoding="utf-8-sig")
    match = re.match(r"\A---\s*\n(.*?)\n---(?:\s*\n|$)", text, re.S)
    if not match:
        raise ValueError(f"Missing YAML frontmatter: {path}")
    data = yaml.safe_load(match.group(1))
    if not isinstance(data, dict):
        raise ValueError(f"Frontmatter is not a mapping: {path}")
    for field in ("name", "description"):
        if not isinstance(data.get(field), str) or not data[field].strip():
            raise ValueError(f"Missing string {field}: {path}")
    if not NAME.fullmatch(data["name"]) or len(data["name"]) > 64:
        raise ValueError(f"Invalid skill name: {path}")
    if len(data["description"]) > 1024:
        raise ValueError(f"Description exceeds Codex limit: {path}")
    return data


def manifest(path: Path) -> dict[str, str]:
    return {p.relative_to(path).as_posix(): sha(p) for p in sorted(path.rglob("*"))
            if p.is_file() and "__pycache__" not in p.parts}


def get_helper(path: Path):
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("codex_skill_install_helper", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(*args: str) -> str:
    return subprocess.check_output(["git", *map(str, args)], text=True).strip()


def source_checkout(root: Path, library: dict, install: bool) -> Path:
    source = root / library["prefix"]
    if not source.exists():
        if not install:
            raise ValueError(f"Source checkout unavailable: {source}")
        source.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--no-checkout",
                        f'https://github.com/{library["repo"]}.git', str(source)], check=True)
        # Fetch the exact recorded object, never silently substitute the default branch.
        subprocess.run(["git", "-C", str(source), "fetch", "--depth", "1", "origin", library["sha"]], check=True)
        subprocess.run(["git", "-C", str(source), "checkout", "--detach", library["sha"]], check=True)
    if git("-C", source, "rev-parse", "HEAD") != library["sha"]:
        raise ValueError(f"Source is not pinned revision: {source}")
    if git("-C", source, "status", "--porcelain"):
        raise ValueError(f"Source checkout has local changes: {source}")
    return source


def namespace_text(text: str, aliases: dict) -> str:
    # Only skill identifiers and local paths change. Preserve upstream URLs verbatim.
    pattern = re.compile(r"(?<![\w-])(" + "|".join(
        re.escape(k) for k in sorted(aliases, key=len, reverse=True)) + r")(?![\w-])")
    parts = URL_SPLIT.split(text)
    for i in range(0, len(parts), 2):
        parts[i] = pattern.sub(lambda m: aliases[m.group(1)], parts[i])
    return "".join(parts)


def outside_fences(text: str) -> str:
    lines, inside = [], False
    for line in text.splitlines():
        if re.match(r"^\s*(\x60{3}|~~~)", line):
            inside = not inside
            continue
        if not inside:
            lines.append(line)
    return "\n".join(lines)


def validate_folder(folder: Path) -> dict:
    data = metadata(folder / "SKILL.md")
    if data["name"] != folder.name:
        raise ValueError(f"Folder/frontmatter name mismatch: {folder}")
    missing, links, anchors, imports, scripts = [], 0, 0, set(), []
    for path in sorted(folder.rglob("*.md")):
        text = outside_fences(path.read_text(encoding="utf-8-sig"))
        for target in LINK.findall(text):
            target = target.strip().strip("<>").split(' "')[0]
            if target.startswith(("http:", "https:", "mailto:", "#")):
                if target.startswith("#"):
                    anchors += 1
                continue
            raw = unquote(target.split("#", 1)[0])
            if not raw:
                continue
            resolved = (path.parent / raw).resolve()
            links += 1
            if not resolved.exists():
                missing.append({"file": str(path), "target": target})
        # Literal bundled scripts/references are validated; example/output paths are not.
        for raw in re.findall(r"\x60((?:references|scripts)/[^\x60 *<>]+)\x60", text):
            if not (folder / raw).exists() and not (path.parent / raw).exists():
                missing.append({"file": str(path), "target": raw, "kind": "literal_resource"})
    for path in sorted(folder.rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
        scripts.append(path.relative_to(folder).as_posix())
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imports.add(node.module.split(".")[0])
    return {"frontmatter": "PASS", "relativePathLinksChecked": links,
            "anchorLinksPresentNotValidated": anchors, "missingResources": missing,
            "pythonSyntaxFiles": scripts, "pythonImports": sorted(imports),
            "scriptExecution": "NOT_RUN", "naturalLanguageRouting": "NOT_RUN",
            "runtimeWorkflow": "NOT_RUN"}


def run(args) -> None:
    install = args.mode == "install"
    old = json.loads(LOCK.read_text(encoding="utf-8")) if LOCK.exists() else {"skills": {}}
    helper = get_helper(args.helper) if install else None
    rows, libraries, new_lock = [], [], {}
    for library in LIBRARIES:
        source = source_checkout(args.sources_root, library, install)
        skills = sorted((source / library["root"]).rglob("SKILL.md"))
        if len(skills) != library["count"]:
            raise ValueError(f"Unexpected canonical skill count: {library['repo']}")
        metas = {path: metadata(path) for path in skills}
        aliases = {m["name"]: f'{library["prefix"]}-{m["name"]}' for m in metas.values()}
        if len(aliases) != len(skills):
            raise ValueError("Duplicate canonical names")
        conflicts = {}
        for path, data in metas.items():
            original = data["name"]
            name = aliases[original]
            target = args.dest / name
            conflict_paths = [str(p) for p in [args.dest / original,
                Path.home() / ".agents/skills" / original] if p.exists()]
            conflicts[name] = conflict_paths
            if target.exists():
                expected = old["skills"].get(name, {}).get("installedFiles")
                if expected is None or manifest(target) != expected:
                    raise ValueError(f"Refusing to overwrite existing/changed skill: {target}")
            elif not install:
                raise ValueError(f"Installed skill missing: {target}")
            else:
                helper._validate_skill(str(path.parent), str(source))
                helper._validate_skill_name(name)
                helper._copy_skill(str(path.parent), str(target))
                adaptations = []
                for local in target.rglob("*.md"):
                    text = local.read_text(encoding="utf-8-sig")
                    updated = namespace_text(text, aliases)
                    if KNOWN_MISSING in updated:
                        updated = updated.replace(KNOWN_MISSING, FIXED_MISSING)
                        adaptations.append("Label missing upstream historical IMPLEMENTATION_LOG link")
                    if updated != text:
                        local.write_text(updated, encoding="utf-8", newline="\n")
                (target / "LICENSE.upstream").write_bytes((source / "LICENSE").read_bytes())
                if name == "ccb-text-to-blender":
                    for filename, content in LOCAL_REDIRECTS.items():
                        (target / "references" / filename).write_text(content, encoding="utf-8", newline="\n")
                    adaptations.append("Add labeled local redirects for two missing upstream references")
                attribution = {"schemaVersion": 1, "repo": library["repo"],
                    "sourceCommit": library["sha"], "sourcePath": path.parent.relative_to(source).as_posix(),
                    "license": "MIT", "upstreamName": original, "installedName": name,
                    "adaptations": ["Namespace skill identifiers and relative sibling links; preserve source URLs",
                                    *adaptations],
                    "runtimeScriptsExecutedDuringInstall": False}
                (target / "SOURCE.json").write_text(json.dumps(attribution, indent=2) + "\n", encoding="utf-8")
            new_lock[name] = {"repo": library["repo"], "commit": library["sha"],
                "sourcePath": path.parent.relative_to(source).as_posix(),
                "sourceFiles": manifest(path.parent), "installedFiles": manifest(target)}
        # Validate only after all siblings in this library have been installed.
        for path, data in metas.items():
            name = aliases[data["name"]]
            target = args.dest / name
            validation = validate_folder(target)
            evalfile = target / "evals/evals.json"
            cases = json.loads(evalfile.read_text(encoding="utf-8")) if evalfile.exists() else []
            positive = [c["query"] for c in cases if c.get("should_trigger") is True]
            negative = [c["query"] for c in cases if c.get("should_trigger") is False]
            if any(not isinstance(c.get("query"), str) or not isinstance(c.get("should_trigger"), bool)
                   for c in cases):
                raise ValueError(f"Invalid bundled trigger scenarios: {evalfile}")
            dependencies = (["Roblox Studio for engine execution; actual project version authoritative"]
                if library["prefix"] != "ccb" else
                ["Blender >=5.1 with official MCP, or legacy ahujasid route >=4.0",
                 "Configured MCP backend; skill installation does not install/start MCP",
                 "Image inspection for visual acceptance"])
            if "cloud" in name or "publish" in name:
                dependencies.append("Relevant Roblox account/permissions; separate authorization for publication")
            if "tooling" in name:
                dependencies.append("Project-selected Rojo/toolchain; no framework changes during installation")
            rows.append({"name": name, "upstreamName": data["name"], "library": library["repo"],
                "sourceCommit": library["sha"], "license": "MIT",
                "sourceUrl": f'https://github.com/{library["repo"]}/tree/{library["sha"]}/'
                             f'{path.parent.relative_to(source).as_posix()}',
                "installedPath": str(target), "purpose": data["description"],
                "triggers": [data["description"]] + ([data["when_to_use"]] if data.get("when_to_use") else []),
                "toolDependencies": dependencies,
                "upstreamAllowedToolsHints": data.get("allowed-tools"),
                "pythonImports": validation["pythonImports"],
                "scenarios": {"explicitInvocation": "$" + name, "upstreamCount": len(cases),
                    "positiveExamples": positive[:2], "negativeExamples": negative[:2],
                    "status": "DATA_VALIDATED_NOT_EXECUTED" if cases else "EXPLICIT_INVOCATION_ONLY"},
                "conflictsAvoided": conflicts[name],
                "status": "INSTALLED_VALIDATED" if not validation["missingResources"] else "INSTALLED_WITH_RESOURCE_WARNINGS",
                "validation": validation, "discovery": "PENDING_APP_SERVER_SKILLS_LIST"})
        libraries.append({**library, "sourceCheckout": str(source), "license": "MIT",
                          "canonicalCount": len(skills), "readmeUrl":
                          f'https://github.com/{library["repo"]}/blob/{library["sha"]}/README.md'})
    lock = {"schemaVersion": 1, "installer": "Codex skill-installer validation/copy helpers + namespaced adapter",
            "helper": {"path": str(args.helper), "sha256": sha(args.helper)},
            "libraries": LIBRARIES, "skills": new_lock}
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    LOCK.write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = {"schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
              "libraries": libraries, "totalInstalled": len(rows), "skills": rows,
              "installMethod": "Pinned source checkout; official Codex helper validates and copies without overwriting",
              "npxReview": {"package": "skills@1.7.4", "helpExecuted": True, "installUsed": False,
                  "historicalSetupAudit": "2026-10-24; not re-executed by this script",
                  "listExecuted": True, "listCounts": {"el4": 23, "brain": 29, "ccb": 30},
                  "listNodeVersion": "24.22.1",
                  "reason": "No name/prefix option; original names collide with existing and each other. Official add --list --full-depth independently confirmed all counts on user-local Node 24.22.1."},
              "scope": "Global instruction/resource installation only; no third-party bundled script execution, no automatic workflow/routing acceptance",
              "rawSkillMdFiles": 83, "canonicalSkillCount": 82,
              "legacyDuplicateExcluded": {"repo": "RobLe3/cc-blender-skill", "path": "skill/wireframe-to-3d",
                  "reason": "README identifies plugin/ as canonical 30-skill install; legacy copy has same skill name"},
              "upstreamResourceRepairs": [
                  "Two absent text-to-blender references replaced by labeled local redirect files to existing upstream sections; no invented guidance",
                  "Historical asset README's missing IMPLEMENTATION_LOG link labeled unavailable; no substituted evidence"],
              "relativeLinkValidation": "Markdown target paths outside fenced code plus literal bundled references/scripts; anchors and external URL availability not tested"}
    report["defaultSourcesRoot"] = "build/skill-sources (relative to repository)"
    names = {}
    for row in rows:
        names.setdefault(row["upstreamName"], []).append(row["name"])
    report["crossLibraryNameCollisions"] = {name: values for name, values in names.items() if len(values) > 1}
    # Retain earlier real discovery as dated evidence, only for matching current metadata
    # and paths. Validation does not pretend to make a new app-server request.
    discovery_path = CATALOG.parent / "skills-discovery.json"
    if discovery_path.exists():
        discovery = json.loads(discovery_path.read_text(encoding="utf-8"))
        for row in rows:
            current_path = Path(row["installedPath"]) / "SKILL.md"
            current_metadata = metadata(current_path)
            for item in discovery.get("skills", []):
                if (item.get("name") == row["name"] and item.get("enabled") is True
                        and Path(item.get("path", "")).resolve() == current_path.resolve()
                        and item.get("description") == current_metadata["description"]):
                    row["discovery"] = "DISCOVERED_ENABLED"
                    break
        report["discoveryEvidence"] = discovery_path.name
        report["discoveryEvidenceObservedAt"] = discovery.get("observedAt")
    report["discoveryRefreshNote"] = "Prior matching discovery is preserved with its original timestamp; run verify_discovery.py for a fresh Codex observation."
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(report, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    warnings = [row["name"] for row in rows if row["validation"]["missingResources"]]
    print(json.dumps({"installed": len(rows), "resourceWarningSkills": warnings,
                      "pythonSyntaxFiles": sum(len(r["validation"]["pythonSyntaxFiles"]) for r in rows),
                      "catalog": str(CATALOG)}, ensure_ascii=False))
    if warnings:
        for row in rows:
            if row["validation"]["missingResources"]:
                print(json.dumps({"skill": row["name"], "missing": row["validation"]["missingResources"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["install", "validate"], default="validate")
    parser.add_argument("--sources-root", type=Path, default=REPO / "build/skill-sources")
    parser.add_argument("--dest", type=Path, default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "skills")
    parser.add_argument("--helper", type=Path,
                        default=Path.home() / ".codex/skills/.system/skill-installer/scripts/install-skill-from-github.py")
    run(parser.parse_args())


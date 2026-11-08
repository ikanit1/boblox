"""Bind a local build to actual inputs without claiming a dirty tree is a release SHA."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 1


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inputs(root: Path) -> dict[str, str]:
    paths = [root / "default.project.json", root / "Build.ps1",
             root / "rokit.toml", root / "docs/toolchain.json",
             root / ".stylua.toml", root / "selene.toml", root / ".github/workflows/build.yml",
             root / "prototypes.project.json"]
    for folder, pattern in (("src", "*.luau"), ("assets", "*.rbxmx"),
                            ("tests", "*.luau"), ("tools", "*.py"),
                            ("tools", "*.luau"), ("tools", "*.ps1"), ("prototypes", "*.luau")):
        paths.extend((root / folder).rglob(pattern))
    return {p.relative_to(root).as_posix(): digest(p.read_bytes())
            for p in sorted(set(paths)) if p.is_file()}


def fingerprint(files: dict[str, str]) -> str:
    payload = json.dumps(files, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return digest(payload)


def changed(before: dict[str, str], after: dict[str, str]) -> list[str]:
    return sorted(path for path in set(before) | set(after) if before.get(path) != after.get(path))


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True, encoding="utf-8").strip()


def node_name(node: ET.Element) -> str:
    return node.findtext("Properties/string[@name='Name']", default="")


def descendants(node: ET.Element, prefix: tuple[str, ...] = ()):
    for child in node.findall("Item"):
        path = (*prefix, node_name(child))
        yield path, child
        yield from descendants(child, path)


def verify_scripts(root: Path, place: Path, source_directory: str = "src", mapping: dict | None = None) -> int:
    """Compare materialized Source fields, not just the artifact's existence or timestamp."""
    mapping = mapping or {
        "server": ("ServerScriptService", "RuleRoomServer"),
        "shared": ("ReplicatedStorage", "RuleRoomShared"),
        "client": ("StarterPlayer", "StarterPlayerScripts", "RuleRoomClient"),
    }
    tree = ET.parse(place).getroot()
    nodes = dict(descendants(tree))
    expected = set()
    for source in sorted((root / source_directory).rglob("*.luau")):
        relative = source.relative_to(root / source_directory)
        if relative.parts[0] not in mapping:
            raise ValueError(f"Unmapped source: {relative}")
        filename = source.name.removesuffix(".luau")
        cls = "ModuleScript"
        if filename.endswith(".server"):
            filename, cls = filename.removesuffix(".server"), "Script"
        elif filename.endswith(".client"):
            filename, cls = filename.removesuffix(".client"), "LocalScript"
        path = (*mapping[relative.parts[0]], *relative.parts[1:-1], filename)
        expected.add(path)
        node = nodes.get(path)
        if node is None or node.attrib.get("class") != cls:
            raise ValueError(f"Built script missing/wrong class: {'/'.join(path)}")
        actual = node.findtext("Properties/ProtectedString[@name='Source']")
        if actual is None:
            # Rojo 7.7 serializes Script.Source as string; Studio may use ProtectedString.
            actual = node.findtext("Properties/string[@name='Source']")
        desired = source.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
        if actual is None or actual.replace("\r\n", "\n") != desired:
            raise ValueError(f"Built Source is stale: {relative.as_posix()}")
    actual_scripts = {path for path, node in nodes.items()
                      if node.attrib.get("class") in {"Script", "LocalScript", "ModuleScript"}
                      and any(path[:len(prefix)] == prefix for prefix in mapping.values())}
    if actual_scripts != expected:
        raise ValueError("Built script inventory differs from mapped source inventory")
    return len(expected)


def verify_prototype(root: Path) -> dict | None:
    if not (root / "prototypes.project.json").exists():
        return None
    place = root / "build/RuleRoomExperiments.rbxlx"
    count = verify_scripts(root, place, "prototypes", {
        "server": ("ServerScriptService", "PrototypeServer"),
        "shared": ("ReplicatedStorage", "PrototypeShared"),
        "client": ("StarterPlayer", "StarterPlayerScripts", "PrototypeClient"),
    })
    # Experiments must not accidentally start Main or access production profiles/remotes.
    tree = ET.parse(place).getroot()
    for path, _node in descendants(tree):
        if any(name in {"RuleRoomServer", "RuleRoomShared", "RuleRoomRemotes"} for name in path):
            raise ValueError("Prototype place includes production systems")
    return {"path": "build/RuleRoomExperiments.rbxlx", "sha256": digest(place.read_bytes()),
            "bytes": place.stat().st_size, "matchingScripts": count, "kind": "isolated_studio_only_not_released"}


def prepare(root: Path) -> dict:
    """Freeze authored inputs before generation; generated assets may intentionally change."""
    files = {path: value for path, value in inputs(root).items() if not path.startswith("assets/")}
    snapshot = {"schema": SCHEMA, "files": files, "fingerprint": fingerprint(files)}
    folder = root / "build"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "candidate-generation.json").write_text(
        json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return snapshot


def begin(root: Path) -> dict:
    snapshot = {"schema": SCHEMA, "files": inputs(root)}
    snapshot["fingerprint"] = fingerprint(snapshot["files"])
    folder = root / "build"
    folder.mkdir(parents=True, exist_ok=True)
    prepared = json.loads((folder / "candidate-generation.json").read_text(encoding="utf-8"))
    authored = {path: value for path, value in snapshot["files"].items() if not path.startswith("assets/")}
    if prepared.get("schema") != SCHEMA or changed(prepared["files"], authored):
        raise ValueError("Authored inputs changed during generation; rebuild before validating")
    # Remove no files: a failed build must not relabel the previous candidate.
    (folder / "candidate-inputs.json").write_text(
        json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return snapshot


def finish(root: Path) -> dict:
    folder = root / "build"
    snapshot = json.loads((folder / "candidate-inputs.json").read_text(encoding="utf-8"))
    current = inputs(root)
    differences = changed(snapshot["files"], current)
    if differences:
        raise ValueError("Build inputs changed during validation: " + ", ".join(differences))
    place = folder / "RuleRoom.rbxlx"
    count = verify_scripts(root, place)
    dirty = bool(git(root, "status", "--porcelain", "--untracked-files=all"))
    base = git(root, "rev-parse", "HEAD")
    manifest = {
        "schema": SCHEMA,
        "kind": "local_candidate_not_release_acceptance",
        "baseCommit": base,
        "candidateCommit": None if dirty else base,
        "branch": git(root, "branch", "--show-current"),
        "dirty": dirty,
        "inputFingerprint": fingerprint(current),
        "inputs": current,
        "artifact": {"path": "build/RuleRoom.rbxlx", "sha256": digest(place.read_bytes()),
                     "bytes": place.stat().st_size, "matchingScripts": count},
        "verification": {
            "inputSnapshotUnchanged": True,
            "builtScriptSourcesMatch": True,
            "nativeStudio": "not_attested",
            "physicalDevice": "not_attested",
            "cloudSaves": "not_attested",
            "capacity": "not_attested",
            "humanPlaytest": "not_attested",
        },
        "toolchain": json.loads((root / "docs/toolchain.json").read_text(encoding="utf-8-sig")),
    }
    prototype = verify_prototype(root)
    if prototype:
        manifest["prototypeArtifact"] = prototype
    (folder / "candidate-manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def verify(root: Path) -> dict:
    manifest = json.loads((root / "build/candidate-manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != SCHEMA:
        raise ValueError("Unsupported candidate manifest")
    current = inputs(root)
    if current != manifest["inputs"] or fingerprint(current) != manifest["inputFingerprint"]:
        raise ValueError("Inputs no longer match the candidate; rebuild before using this evidence")
    place = root / "build/RuleRoom.rbxlx"
    if digest(place.read_bytes()) != manifest["artifact"]["sha256"]:
        raise ValueError("Artifact no longer matches the candidate")
    verify_scripts(root, place)
    if verify_prototype(root) != manifest.get("prototypeArtifact"):
        raise ValueError("Prototype artifact no longer matches the candidate")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "begin", "finish", "verify"))
    args = parser.parse_args()
    result = {"prepare": prepare, "begin": begin, "finish": finish, "verify": verify}[args.action](ROOT)
    print(f"Candidate {args.action}: {result.get('inputFingerprint', result.get('fingerprint'))}; local evidence only.")


if __name__ == "__main__":
    main()

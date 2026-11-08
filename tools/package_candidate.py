"""Package the verified local main game and handoff documents; never publish."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import candidate_manifest

ROOT = Path(__file__).resolve().parents[1]


def package(root: Path, output: Path) -> dict:
    root, output = root.resolve(), output.resolve()
    build = (root / "build").resolve()
    if output.suffix.lower() != ".zip" or build not in output.parents:
        raise ValueError("Package output must be a .zip inside the project build directory")
    candidate = candidate_manifest.verify(root)
    files = [root / "build/RuleRoom.rbxlx", root / "build/candidate-manifest.json",
             root / "docs/PRODUCT_COMPLETION.md", root / "docs/qa/product-completion.json"]
    files.extend(sorted((root / "docs/release").glob("*.md")))
    files.extend(sorted((root / "docs/release").glob("*.json")))
    for path in files:
        if not path.is_file():
            raise ValueError(f"Missing handoff file: {path.relative_to(root)}")
    payload = {path.relative_to(root).as_posix(): path.read_bytes() for path in files}
    captured_manifest = json.loads(payload["build/candidate-manifest.json"])
    captured_report = json.loads(payload["docs/qa/product-completion.json"])
    artifact_hash = hashlib.sha256(payload["build/RuleRoom.rbxlx"]).hexdigest()
    if (captured_manifest != candidate or artifact_hash != candidate["artifact"]["sha256"]
            or captured_report.get("inputFingerprint") != candidate["inputFingerprint"]
            or captured_report.get("artifact") != candidate["artifact"]):
        raise ValueError("Captured artifact, report and manifest do not identify the same candidate")
    if candidate_manifest.verify(root) != candidate:
        raise ValueError("Candidate changed during packaging")
    receipt = {"kind": "local_candidate_not_public_release", "inputFingerprint": candidate["inputFingerprint"],
               "candidateCommit": candidate["candidateCommit"], "published": False,
               "files": {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}}
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in payload.items():
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
        entry = zipfile.ZipInfo("package-receipt.json", (2026, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(entry, json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("Package CRC validation failed")
        for name, expected in receipt["files"].items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise ValueError(f"Packaged file identity mismatch: {name}")
    return {"path": str(output), "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "files": len(payload) + 1, "published": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/RuleRoom-LocalCandidate.zip")
    args = parser.parse_args()
    print(json.dumps(package(ROOT, args.output.resolve()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

"""Package identity and accidental publication guards, using temporary files only."""
import importlib.util
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

TOOLS = Path(__file__).parents[1]
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("package_candidate", TOOLS / "package_candidate.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ReleasePackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("build/RuleRoom.rbxlx", "build/candidate-manifest.json", "docs/PRODUCT_COMPLETION.md",
                     "docs/qa/product-completion.json", "docs/release/README.md"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture", encoding="utf-8")
        self.manifest = {"inputFingerprint": "a" * 64, "candidateCommit": None,
                         "artifact": {"sha256": hashlib.sha256(b"fixture").hexdigest()}}
        (self.root / "build/candidate-manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        (self.root / "docs/qa/product-completion.json").write_text(json.dumps(self.manifest), encoding="utf-8")
        self.output = self.root / "build/candidate.zip"

    def test_bundle_has_receipt_and_excludes_prototype(self):
        (self.root / "build/RuleRoomExperiments.rbxlx").write_text("not the game", encoding="utf-8")
        with patch.object(MODULE.candidate_manifest, "verify", return_value=self.manifest):
            result = MODULE.package(self.root, self.output)
        self.assertFalse(result["published"])
        with zipfile.ZipFile(self.output) as archive:
            receipt = json.loads(archive.read("package-receipt.json"))
            self.assertIsNone(receipt["candidateCommit"])
            self.assertNotIn("build/RuleRoomExperiments.rbxlx", archive.namelist())
            self.assertIn("build/RuleRoom.rbxlx", receipt["files"])

    def test_stale_build_refuses_to_package(self):
        with patch.object(MODULE.candidate_manifest, "verify", side_effect=ValueError("stale")):
            with self.assertRaises(ValueError):
                MODULE.package(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_missing_report_refuses_to_package(self):
        (self.root / "docs/PRODUCT_COMPLETION.md").unlink()
        with patch.object(MODULE.candidate_manifest, "verify", return_value=self.manifest):
            with self.assertRaises(ValueError):
                MODULE.package(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_output_cannot_overwrite_artifact_or_source(self):
        for name in ("build/RuleRoom.rbxlx", "docs/PRODUCT_COMPLETION.md", "source.zip"):
            target = self.root / name
            before = target.read_bytes() if target.exists() else None
            with self.assertRaises(ValueError):
                MODULE.package(self.root, target)
            self.assertEqual(target.read_bytes() if target.exists() else None, before)

    def test_artifact_change_between_verify_and_read_is_rejected(self):
        def raced_verify(_root):
            (self.root / "build/RuleRoom.rbxlx").write_text("changed after verify", encoding="utf-8")
            return self.manifest
        with patch.object(MODULE.candidate_manifest, "verify", side_effect=raced_verify):
            with self.assertRaises(ValueError):
                MODULE.package(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_copy_has_no_published_ids_or_capacity_claim(self):
        listing = json.loads((TOOLS.parent / "docs/release/listing.json").read_text(encoding="utf-8"))
        self.assertFalse(listing["publication"]["authorized"])
        self.assertIsNone(listing["verifiedReleaseCapacity"])
        self.assertEqual(listing["paidProducts"], [])
        for locale in ("ru", "en"):
            self.assertGreater(len(listing[locale]["description"]), 100)
            self.assertLess(len(listing[locale]["name"]), 50)


if __name__ == "__main__":
    unittest.main()

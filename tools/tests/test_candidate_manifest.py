"""Tamper/stale-build checks in temporary directories, without touching the checkout."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location("candidate_manifest", Path(__file__).parents[1] / "candidate_manifest.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "src/server").mkdir(parents=True)
        (self.root / "assets").mkdir()
        self.source = self.root / "src/server/Main.server.luau"
        self.source.write_text("--!strict\nprint('ready')\n", encoding="utf-8")
        self.asset = self.root / "assets/Arena.rbxmx"
        self.asset.write_text("<roblox />", encoding="utf-8")
        tree = ET.Element("roblox")
        parent = tree
        for cls, name in (("ServerScriptService", "ServerScriptService"),
                          ("Folder", "RuleRoomServer"), ("Script", "Main")):
            parent = ET.SubElement(parent, "Item", {"class": cls})
            props = ET.SubElement(parent, "Properties")
            ET.SubElement(props, "string", {"name": "Name"}).text = name
        ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = self.source.read_text(encoding="utf-8")
        self.place = self.root / "place.rbxlx"
        ET.ElementTree(tree).write(self.place, encoding="utf-8")

    def test_live_source_matches_materialized_script(self):
        self.assertEqual(MODULE.verify_scripts(self.root, self.place), 1)

    def test_rojo_string_source_encoding_is_supported(self):
        tree = ET.parse(self.place)
        source = tree.find(".//ProtectedString[@name='Source']")
        source.tag = "string"
        tree.write(self.place, encoding="utf-8")
        self.assertEqual(MODULE.verify_scripts(self.root, self.place), 1)

    def test_stale_source_is_rejected(self):
        self.source.write_text("print('different')", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Source is stale"):
            MODULE.verify_scripts(self.root, self.place)

    def test_missing_source_is_rejected(self):
        self.source.unlink()
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            MODULE.verify_scripts(self.root, self.place)

    def test_assets_and_untracked_sources_affect_fingerprint(self):
        before = MODULE.inputs(self.root)
        self.asset.write_text("<roblox version='4' />", encoding="utf-8")
        (self.root / "src/server/New.luau").write_text("return {}", encoding="utf-8")
        after = MODULE.inputs(self.root)
        self.assertEqual(MODULE.changed(before, after), ["assets/Arena.rbxmx", "src/server/New.luau"])
        self.assertNotEqual(MODULE.fingerprint(before), MODULE.fingerprint(after))

    def test_fingerprint_does_not_depend_on_dictionary_order(self):
        self.assertEqual(MODULE.fingerprint({"a": "1", "b": "2"}), MODULE.fingerprint({"b": "2", "a": "1"}))

    def test_lf_and_crlf_script_text_are_equivalent_in_rojo(self):
        self.source.write_bytes(b"--!strict\r\nprint('ready')\r\n")
        self.assertEqual(MODULE.verify_scripts(self.root, self.place), 1)

    def test_interrupted_validation_cannot_finalize_new_inputs(self):
        MODULE.prepare(self.root)
        MODULE.begin(self.root)
        self.source.write_text("return false", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "changed during validation"):
            MODULE.finish(self.root)

    def test_authored_change_during_generation_is_rejected(self):
        MODULE.prepare(self.root)
        self.source.write_text("return false", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "changed during generation"):
            MODULE.begin(self.root)

    def test_generation_may_replace_assets_before_checks(self):
        MODULE.prepare(self.root)
        self.asset.write_text("<roblox version='4' />", encoding="utf-8")
        snapshot = MODULE.begin(self.root)
        self.assertEqual(snapshot["files"], MODULE.inputs(self.root))

    def test_check_configuration_and_tool_selection_are_inputs(self):
        (self.root / "tools").mkdir()
        for path in (".stylua.toml", "selene.toml", "tools/Find-Tool.ps1"):
            (self.root / path).write_text("initial", encoding="utf-8")
        before = MODULE.inputs(self.root)
        for path in (".stylua.toml", "selene.toml", "tools/Find-Tool.ps1"):
            self.assertIn(path, before)
            (self.root / path).write_text("changed", encoding="utf-8")
        self.assertEqual(len(MODULE.changed(before, MODULE.inputs(self.root))), 3)

    def build_candidate(self):
        (self.root / "docs").mkdir()
        (self.root / "docs/toolchain.json").write_text("{}", encoding="utf-8")
        MODULE.prepare(self.root)
        MODULE.begin(self.root)
        (self.root / "build/RuleRoom.rbxlx").write_bytes(self.place.read_bytes())
        def fake_git(_root, *args):
            return " M src/server/Main.server.luau" if args[0] == "status" else "fixture-base"
        with patch.object(MODULE, "git", fake_git):
            return MODULE.finish(self.root)

    def test_complete_dirty_candidate_verifies_without_claiming_release_sha(self):
        manifest = self.build_candidate()
        self.assertIsNone(manifest["candidateCommit"])
        self.assertEqual(manifest["verification"]["nativeStudio"], "not_attested")
        self.assertEqual(MODULE.verify(self.root), manifest)

    def test_verify_rejects_modified_artifact(self):
        self.build_candidate()
        (self.root / "build/RuleRoom.rbxlx").write_text("different", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Artifact no longer matches"):
            MODULE.verify(self.root)

    def test_verify_rejects_modified_inputs(self):
        self.build_candidate()
        self.source.write_text("return true", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Inputs no longer match"):
            MODULE.verify(self.root)

    def create_prototype(self):
        (self.root / "prototypes/server").mkdir(parents=True)
        (self.root / "prototypes/server/Experiment.server.luau").write_text("print('isolated')", encoding="utf-8")
        (self.root / "prototypes.project.json").write_text("{}", encoding="utf-8")
        folder = self.root / "build"
        folder.mkdir(exist_ok=True)
        tree = ET.Element("roblox")
        parent = tree
        for cls, name in (("ServerScriptService", "ServerScriptService"),
                          ("Folder", "PrototypeServer"), ("Script", "Experiment")):
            parent = ET.SubElement(parent, "Item", {"class": cls})
            props = ET.SubElement(parent, "Properties")
            ET.SubElement(props, "string", {"name": "Name"}).text = name
        ET.SubElement(props, "string", {"name": "Source"}).text = "print('isolated')"
        place = folder / "RuleRoomExperiments.rbxlx"
        ET.ElementTree(tree).write(place, encoding="utf-8")
        return place

    def test_isolated_prototype_has_its_own_verified_artifact(self):
        place = self.create_prototype()
        manifest = self.build_candidate()
        self.assertEqual(manifest["prototypeArtifact"]["matchingScripts"], 1)
        self.assertEqual(MODULE.verify(self.root), manifest)
        place.write_text("tampered", encoding="utf-8")
        with self.assertRaises(ET.ParseError):
            MODULE.verify(self.root)

    def test_prototype_cannot_import_production_systems(self):
        place = self.create_prototype()
        tree = ET.parse(place)
        imported = ET.SubElement(tree.getroot(), "Item", {"class": "Folder"})
        props = ET.SubElement(imported, "Properties")
        ET.SubElement(props, "string", {"name": "Name"}).text = "RuleRoomServer"
        tree.write(place, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "includes production systems"):
            MODULE.verify_prototype(self.root)


if __name__ == "__main__":
    unittest.main()

"""Local installer checks; no network, Studio, Blender, or global installation writes."""
from pathlib import Path
import tempfile
import unittest
import install_libraries as installer

BASE = installer.REPO.parent.parent / "work/env-skills/tests"
BASE.mkdir(parents=True, exist_ok=True)


class InstallerChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="case-", dir=BASE)
        self.root = Path(self.temp.name)
        self.folder = self.root / "demo"
        self.folder.mkdir()
        self.skill = self.folder / "SKILL.md"
        self.skill.write_text("---\nname: demo\ndescription: A valid demonstration skill.\n---\n", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def test_namespace_preserves_source_urls(self):
        result = installer.namespace_text(
            "name: demo\nSee ../demo/SKILL.md and https://github.com/example/demo/SKILL.md",
            {"demo": "prefix-demo"})
        self.assertIn("name: prefix-demo", result)
        self.assertIn("../prefix-demo/SKILL.md", result)
        self.assertIn("https://github.com/example/demo/SKILL.md", result)

    def test_namespace_does_not_rewrite_other_identifiers(self):
        self.assertEqual(installer.namespace_text("demo-tool demo_tool demo2", {"demo": "prefix-demo"}),
                         "demo-tool demo_tool demo2")

    def test_bad_yaml_rejected(self):
        self.skill.write_text("---\nname: demo\ndescription: [bad\n---\n", encoding="utf-8")
        with self.assertRaises(Exception):
            installer.metadata(self.skill)

    def test_empty_description_rejected(self):
        self.skill.write_text("---\nname: demo\ndescription: ''\n---\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            installer.metadata(self.skill)

    def test_missing_resource_detected(self):
        with self.skill.open("a", encoding="utf-8") as stream:
            stream.write("[Details](references/missing.md)\n")
        self.assertEqual(len(installer.validate_folder(self.folder)["missingResources"]), 1)

    def test_sibling_reference_and_code_example(self):
        sibling = self.root / "sibling"
        sibling.mkdir()
        (sibling / "notes.md").write_text("Details", encoding="utf-8")
        with self.skill.open("a", encoding="utf-8") as stream:
            stream.write("[Details](../sibling/notes.md)\n" + chr(96) * 3 +
                         "\n[example](not-a-resource)\n" + chr(96) * 3 + "\n")
        result = installer.validate_folder(self.folder)
        self.assertEqual(result["missingResources"], [])
        self.assertEqual(result["relativePathLinksChecked"], 1)

    def test_python_syntax_is_checked_without_execution(self):
        script = self.folder / "script.py"
        script.write_text("raise RuntimeError('must not execute')\n", encoding="utf-8")
        self.assertEqual(installer.validate_folder(self.folder)["pythonSyntaxFiles"], ["script.py"])
        script.write_text("def broken(\n", encoding="utf-8")
        with self.assertRaises(SyntaxError):
            installer.validate_folder(self.folder)

    def test_manifest_detects_resource_change(self):
        first = installer.manifest(self.folder)
        with self.skill.open("a", encoding="utf-8") as stream:
            stream.write("Changed\n")
        self.assertNotEqual(first, installer.manifest(self.folder))

    def test_official_helper_preserves_resources_and_refuses_overwrite(self):
        helper = installer.get_helper(
            Path.home() / ".codex/skills/.system/skill-installer/scripts/install-skill-from-github.py")
        resource = self.folder / "asset.bin"
        resource.write_bytes(bytes(range(256)))
        helper._validate_skill(str(self.folder), str(self.root))
        target = self.root / "copy"
        helper._copy_skill(str(self.folder), str(target))
        self.assertEqual(installer.manifest(self.folder), installer.manifest(target))
        with self.assertRaises(helper.InstallError):
            helper._copy_skill(str(self.folder), str(target))
        self.assertEqual((target / "asset.bin").read_bytes(), bytes(range(256)))


if __name__ == "__main__":
    unittest.main()


"""Authored overrides must have a single meaning in every Roblox XML reader."""
import importlib.util
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

TOOLS = Path(__file__).parents[1]
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("build_assets", TOOLS / "build_assets.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GeneratedPropertyTests(unittest.TestCase):
    def test_override_replaces_old_value(self):
        root = ET.Element("roblox")
        part = MODULE.part(root, "Decor", (1, 1, 1), (0, 0, 0))
        MODULE.prop(part, "bool", "CastShadow", False)
        values = part.findall("Properties/bool[@name='CastShadow']")
        self.assertEqual(len(values), 1)
        self.assertEqual(values[0].text, "false")

    def test_all_generated_properties_are_unique(self):
        for factory in (MODULE.arena, MODULE.hud, MODULE.station_hud):
            root = factory()
            for item in root.iter("Item"):
                names = [p.get("name") for p in item.find("Properties")]
                self.assertEqual(len(names), len(set(names)), item.findtext("Properties/string[@name='Name']"))


if __name__ == "__main__":
    unittest.main()

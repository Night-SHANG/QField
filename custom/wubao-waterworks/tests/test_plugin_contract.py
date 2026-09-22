from __future__ import annotations

import unittest
from pathlib import Path


PLUGIN = (
    Path(__file__).resolve().parents[1]
    / "plugins"
    / "wubao-waterworks"
    / "main.qml"
)


class PluginContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = PLUGIN.read_text(encoding="utf-8")

    def test_current_qfield_modules_are_imported(self) -> None:
        self.assertIn("import org.qfield.core", self.text)
        self.assertIn("import org.qfield.gui", self.text)

    def test_current_qfield_utility_names_are_used(self) -> None:
        for utility in ("QfLayerUtils", "QfFeatureUtils", "QfGeometryUtils", "QfTheme"):
            self.assertIn(utility, self.text)

        for obsolete in (
            " LayerUtils.",
            " FeatureUtils.",
            " GeometryUtils.",
            " Theme.",
        ):
            self.assertNotIn(obsolete, self.text)

    def test_field_workflows_reuse_qfield_forms(self) -> None:
        self.assertIn('iface.findItemByObjectName("overlayFeatureFormDrawer")', self.text)
        self.assertIn('iface.findItemByObjectName("featureForm")', self.text)
        self.assertIn('featureForm.model.setFeatures(layer,', self.text)

    def test_nearby_lookup_is_meter_based(self) -> None:
        self.assertIn("EPSG:32649", self.text)
        self.assertIn("nearbyRadiusMeters", self.text)


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import unittest
from pathlib import Path

PLUGIN = (
    Path(__file__).resolve().parents[1] / "plugins" / "waterworks-inspection" / "main.qml"
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
        self.assertIn(
            'iface.findItemByObjectName("overlayFeatureFormDrawer")', self.text
        )
        self.assertIn('iface.findItemByObjectName("featureForm")', self.text)
        self.assertIn("featureForm.model.setFeatures(layer,", self.text)

    def test_nearby_lookup_is_meter_based_and_location_independent(self) -> None:
        self.assertIn("nearbyRadiusMeters", self.text)
        self.assertIn("utmZone", self.text)
        self.assertIn("32600", self.text)
        self.assertIn("32700", self.text)
        self.assertNotIn("EPSG:32649", self.text)

    def test_asset_types_are_loaded_from_project_data(self) -> None:
        self.assertIn("readonly property var assetTypeLayerNames", self.text)
        self.assertIn("function loadAssetTypeOptions()", self.text)
        self.assertIn("model: assetTypeOptions", self.text)
        self.assertNotIn('case "valve_well"', self.text)

    def test_backup_entry_reuses_qfield_project_folder(self) -> None:
        self.assertIn('iface.findItemByObjectName("projectFolderButton")', self.text)
        self.assertIn("function openProjectBackup()", self.text)
        self.assertIn("projectFolderButton.clicked()", self.text)
        self.assertIn('text: "备份 / 导出项目"', self.text)

    def test_navigation_reuses_qfield_navigation(self) -> None:
        self.assertIn('iface.findItemByObjectName("navigation")', self.text)
        self.assertIn("navigation.setDestinationFeature", self.text)

    def test_search_iterators_are_closed(self) -> None:
        self.assertGreaterEqual(self.text.count("iterator.close()"), 4)

    def test_problem_filter_covers_attention_and_repair(self) -> None:
        self.assertIn('value: "problem"', self.text)
        self.assertIn('statusValue === "problem"', self.text)
        self.assertIn("'attention', 'repair'", self.text)

    def test_shared_field_workflows_support_assets_and_pipelines(self) -> None:
        self.assertIn("readonly property var pipelineLayerNames", self.text)
        self.assertIn("function searchObjects(term)", self.text)
        self.assertIn("function setParentReference(feature, objectId, objectKind)", self.text)
        self.assertIn("function createInspection(objectId, objectKind)", self.text)
        self.assertIn("function createRepair(objectId, objectKind)", self.text)
        self.assertIn("function createAttachment(objectId, objectKind)", self.text)
        self.assertIn('feature.setAttribute("pipeline_id", objectId)', self.text)
        self.assertIn('feature.setAttribute("asset_id", objectId)', self.text)

    def test_search_results_support_object_kind_and_distance(self) -> None:
        self.assertIn('"objectKind": objectKind', self.text)
        self.assertIn('"assetDistance":', self.text)
        self.assertIn("required property string objectKind", self.text)
        self.assertIn("required property int assetDistance", self.text)
        self.assertIn('value: "pipeline"', self.text)
        self.assertIn('visible: objectKind === "asset"', self.text)

    def test_field_capture_surfaces_accuracy_warning(self) -> None:
        self.assertIn("accuracyWarningMeters: 15", self.text)
        self.assertIn("精度 ±", self.text)
        self.assertIn("建议到开阔位置等待定位稳定后再采点", self.text)

    def test_inspection_accuracy_checks_validity(self) -> None:
        self.assertIn("info.haccValid", self.text)


if __name__ == "__main__":
    unittest.main()

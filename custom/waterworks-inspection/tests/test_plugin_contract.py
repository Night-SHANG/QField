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
        self.assertIn("function loadNearbyObjects(radiusMeters, objectKind)", self.text)
        self.assertIn("QfExpressionEvaluator", self.text)
        self.assertIn("nearbyDistanceEvaluator.evaluate(distanceValueExpression)", self.text)
        self.assertIn("utmZone", self.text)
        self.assertIn("32600", self.text)
        self.assertIn("32700", self.text)
        self.assertNotIn("EPSG:32649", self.text)

    def test_nearby_pipeline_distance_uses_full_geometry(self) -> None:
        self.assertIn("distanceValueExpression", self.text)
        self.assertIn("transform($geometry", self.text)
        self.assertIn('objectKind === "pipeline" ? pipelineLayer() : assetLayer()', self.text)
        self.assertIn('text: "附近"', self.text)
        self.assertIn('text: "点位"', self.text)
        self.assertIn('text: "管线"', self.text)
        self.assertIn('function loadNearbyKind(objectKind)', self.text)
        self.assertNotIn("function loadNearbyAssets(radiusMeters)", self.text)

    def test_asset_types_are_loaded_from_project_data(self) -> None:
        self.assertIn("readonly property var assetTypeLayerNames", self.text)
        self.assertIn("function loadAssetTypeOptions()", self.text)
        self.assertIn("model: assetTypeOptions", self.text)
        self.assertNotIn('case "valve_well"', self.text)

    def test_backup_entry_reuses_qfield_project_folder(self) -> None:
        self.assertIn('iface.findItemByObjectName("projectFolderButton")', self.text)
        self.assertIn("function openProjectBackup()", self.text)
        self.assertIn("projectFolderButton.clicked()", self.text)
        self.assertIn('text: "备份 / 导出"', self.text)

    def test_single_simplified_field_interface_hides_professional_controls(self) -> None:
        self.assertIn("function simplifyInterface()", self.text)
        for object_name in (
            "mainMenuBar",
            "mainToolbar",
            "zoomToolbar",
            "locatorItem",
            "welcomeActionCloud",
            "welcomeActionNewProject",
            "welcomeActionLocalProjects",
        ):
            self.assertIn(f'iface.findItemByObjectName("{object_name}")', self.text)
        self.assertNotIn("advancedMode", self.text)
        self.assertNotIn('text: "高级功能"', self.text)
        self.assertNotIn('text: "进入高级模式"', self.text)
        self.assertIn('text: "正在准备供水巡检地图"', self.text)
        self.assertIn('text: "打开供水数据"', self.text)

    def test_pipeline_capture_reuses_qfield_digitizing(self) -> None:
        self.assertIn("function startPipelineCapture()", self.text)
        self.assertIn('iface.findItemByObjectName("digitizingToolbar")', self.text)
        self.assertIn("digitizingToolbar.geometryRequestedLayer = layer", self.text)
        self.assertIn("digitizingToolbar.geometryRequestedItem = pipelineGeometryReceiver", self.text)
        self.assertIn("digitizingToolbar.geometryRequested = true", self.text)
        self.assertIn("geometry.asQgsGeometry()", self.text)
        self.assertIn('text: "新建管线"', self.text)

    def test_map_first_navigation_replaces_patrol_dialog(self) -> None:
        self.assertIn('objectName: "waterworksBottomActionBar"', self.text)
        self.assertIn('text: "查找"', self.text)
        self.assertIn('text: "附近"', self.text)
        self.assertIn('text: "新增"', self.text)
        self.assertIn('text: "更多"', self.text)
        self.assertNotIn('id: waterworksButton', self.text)
        self.assertNotIn('id: waterworksDialog', self.text)

    def test_persistent_view_edit_lock_guards_writes(self) -> None:
        self.assertIn("property bool editEnabled: false", self.text)
        self.assertIn("function editAllowed(actionName)", self.text)
        self.assertIn("function setEditEnabled(enabled)", self.text)
        self.assertIn('text: workerAppSettings.editEnabled ? "编辑模式" : "查看模式"', self.text)
        self.assertIn('enabled: workerAppSettings.editEnabled', self.text)
        for action in ("新增点位", "新建管线", "巡检记录", "维修记录", "添加附件"):
            self.assertIn(f'editAllowed("{action}")', self.text)

    def test_nearby_results_are_visible_and_highlighted(self) -> None:
        self.assertIn('objectName: "waterworksBrowserDrawer"', self.text)
        self.assertIn("QfLayerUtils.selectFeaturesByExpression(layer, expression)", self.text)
        self.assertIn('text: assetSearchResults.count > 0', self.text)
        self.assertIn("delegate: queryResultDelegate", self.text)

    def test_first_launch_has_visible_yulin_fallback_map(self) -> None:
        self.assertIn('"basemap": "custom"', self.text)
        self.assertIn('"basemap_custom_provider": "wms"', self.text)
        self.assertIn("fallbackBasemapSource", self.text)
        self.assertIn("yulinDefaultExtent", self.text)
        self.assertIn("tile.openstreetmap.org", self.text)

    def test_asset_capture_keeps_photos_in_simplified_flow(self) -> None:
        self.assertIn("property var pendingAssetPhotoPaths: []", self.text)
        self.assertIn("function startAssetPhotoCapture()", self.text)
        self.assertIn("QfCamera {", self.text)
        self.assertIn('state = "PhotoCapture"', self.text)
        self.assertIn('text: pendingAssetPhotoPaths.length > 0 ? "继续拍照" : "拍照"', self.text)
        self.assertIn("function savePendingAssetPhotos(assetId)", self.text)
        self.assertIn('"attachments/photos/" + assetId', self.text)
        self.assertIn('attachment.setAttribute("media_type", "photo")', self.text)
        self.assertIn('attachment.setAttribute("photo_path", relativePath)', self.text)

    def test_simplified_asset_capture_assigns_stable_id_before_attachments(self) -> None:
        self.assertIn("function newObjectId()", self.text)
        self.assertIn('feature.setAttribute("id", assetId)', self.text)
        self.assertIn("savePendingAssetPhotos(assetId)", self.text)

    def test_runtime_project_layers_are_field_friendly(self) -> None:
        self.assertIn("function configureBusinessLayer(layer, tableName)", self.text)
        self.assertIn("QfLayerUtils.configureField", self.text)
        self.assertIn("QfLayerUtils.setDefaultRenderer(layer, qgisProject)", self.text)
        self.assertIn("QfLayerUtils.setDefaultLabeling(layer, qgisProject)", self.text)
        self.assertIn('"巡检时间"', self.text)
        self.assertIn('"维修内容"', self.text)
        self.assertIn('"附件类型"', self.text)

    def test_search_results_can_focus_map_or_open_details(self) -> None:
        self.assertIn("function focusObjectOnMap(objectKind, objectId, showToast)", self.text)
        self.assertIn('text: "地图"', self.text)
        self.assertIn('text: "详情"', self.text)
        self.assertIn("featureForm.extentController.zoomToAllFeatures()", self.text)

    def test_location_marker_can_be_hidden_without_stopping_positioning(self) -> None:
        self.assertIn("property bool showMyLocationMarker: true", self.text)
        self.assertIn("function setMyLocationMarkerVisible(visible)", self.text)
        self.assertIn('"隐藏我的位置标记"', self.text)
        self.assertIn('"显示我的位置标记"', self.text)

    def test_professional_layer_controls_are_hidden(self) -> None:
        self.assertIn('iface.findItemByObjectName("mapThemeContainer")', self.text)
        self.assertIn('iface.findItemByObjectName("legendContainer")', self.text)
        self.assertIn("dashBoard.allowActiveLayerChange = false", self.text)
        self.assertIn("dashBoard.allowInteractive = false", self.text)

    def test_single_map_tap_opens_and_zooms_to_one_feature(self) -> None:
        self.assertIn('iface.findItemByObjectName("qfieldSettings")', self.text)
        self.assertIn("qfieldSettings.autoOpenFormSingleIdentify = true", self.text)
        self.assertIn("qfieldSettings.autoZoomToIdentifiedFeature = true", self.text)

    def test_map_object_details_focus_on_network_and_attachments(self) -> None:
        self.assertIn('objectName: "waterworksFocusedObjectActionBar"', self.text)
        self.assertIn("function focusedBusinessObjectKind()", self.text)
        self.assertIn("function focusedBusinessObjectId()", self.text)
        self.assertIn('text: "照片/附件"', self.text)
        self.assertIn('text: "编辑"', self.text)
        self.assertIn('text: "删除"', self.text)

    def test_project_load_activates_and_centers_location(self) -> None:
        self.assertIn("function activateAndCenterLocation()", self.text)
        self.assertIn('iface.findItemByObjectName("positioningSettings")', self.text)
        self.assertIn("positioningSettings.positioningActivated = true", self.text)
        self.assertIn("gnssButton.clicked()", self.text)

    def test_worker_mode_reuses_native_gnss_button(self) -> None:
        self.assertIn('iface.findItemByObjectName("gnssButton")', self.text)
        self.assertIn("gnssButton.clicked()", self.text)
        self.assertIn('text: "定位"', self.text)

    def test_navigation_reuses_qfield_navigation(self) -> None:
        self.assertIn('iface.findItemByObjectName("navigation")', self.text)
        self.assertIn("navigation.setDestinationFeature", self.text)

    def test_search_iterators_are_closed(self) -> None:
        self.assertGreaterEqual(self.text.count("iterator.close()"), 4)

    def test_problem_filter_covers_attention_and_repair(self) -> None:
        self.assertIn('"value":"problem"', self.text)
        self.assertIn('statusValue === "problem"', self.text)
        self.assertIn("'attention', 'repair'", self.text)

    def test_shared_field_workflows_support_assets_and_pipelines(self) -> None:
        self.assertIn("readonly property var pipelineLayerNames", self.text)
        self.assertIn("function searchObjects(term)", self.text)
        self.assertIn("function setParentReference(feature, objectId, objectKind)", self.text)
        self.assertIn("function createInspection(objectId, objectKind)", self.text)
        self.assertIn("function createRepair(objectId, objectKind)", self.text)
        self.assertIn("function createAttachment(objectId, objectKind, mediaType)", self.text)
        self.assertIn('feature.setAttribute("pipeline_id", objectId)', self.text)
        self.assertIn('feature.setAttribute("asset_id", objectId)', self.text)

    def test_inspection_specific_search_ui_is_removed(self) -> None:
        self.assertNotIn('text: "仅看从未巡检"', self.text)
        self.assertNotIn('"最近巡检 "', self.text)

    def test_search_results_support_object_kind_and_distance(self) -> None:
        self.assertIn('"objectKind": objectKind', self.text)
        self.assertIn('"assetDistance":', self.text)
        self.assertIn("required property string objectKind", self.text)
        self.assertIn("required property int assetDistance", self.text)
        self.assertIn('plugin.queryObjectKind = "pipeline"', self.text)
        self.assertIn('plugin.loadNearbyKind("pipeline")', self.text)
        self.assertIn('visible: objectKind === "asset"', self.text)

    def test_field_capture_surfaces_accuracy_warning(self) -> None:
        self.assertIn("accuracyWarningMeters: 15", self.text)
        self.assertIn("精度 ±", self.text)
        self.assertIn("建议到开阔位置等待定位稳定后再放点", self.text)

    def test_required_fields_are_explicit_and_enforced(self) -> None:
        self.assertIn('text: "设施类型 *"', self.text)
        self.assertIn('text: "* 为必填；其余信息不知道时可以先不填"', self.text)
        self.assertIn('mainWindow.displayToast("请选择设施类型（* 必填）")', self.text)
        self.assertIn('placeholderText: "位置描述（可选）', self.text)
        self.assertIn('text: "管线位置已经画好。下面参数均为可选，不知道时可以直接保存。"', self.text)

    def test_manual_pipe_relation_is_hidden_from_asset_form(self) -> None:
        self.assertIn('"assets_point": ["fid", "id", "pipeline_id", "last_inspection_at"', self.text)

    def test_inspection_and_repair_buttons_are_not_in_field_ui(self) -> None:
        focused_block = self.text.split('id: focusedObjectActionBar', 1)[1].split('id: attachmentDrawer', 1)[0]
        self.assertNotIn('text: "巡检"', focused_block)
        self.assertNotIn('text: "维修"', focused_block)

    def test_inspection_accuracy_checks_validity(self) -> None:
        self.assertIn("info.haccValid", self.text)

    def test_native_processing_and_delete_are_hidden_in_specialised_ui(self) -> None:
        self.assertIn("featureForm.allowDelete = false", self.text)
        self.assertIn("featureForm.allowProcessing = false", self.text)
        for object_name in (
            "gnssCursorLockButton",
            "gnssCanvasLockButton",
            "addBookmarkAtCurrentLocationButton",
            "gnssTrackingButton",
        ):
            self.assertIn(f'iface.findItemByObjectName("{object_name}")', self.text)
        self.assertIn("gnssTrackingButton.visible = false", self.text)

    def test_pipeline_digitizing_has_persistent_guidance_and_yields_chrome(self) -> None:
        self.assertIn('objectName: "waterworksPipelineDigitizingHint"', self.text)
        self.assertIn("digitizingToolbar.geometryRequested", self.text)
        self.assertIn("至少 2 个", self.text)
        self.assertIn("点 ✓ 完成", self.text)

    def test_overlay_business_forms_bind_their_layer_before_opening(self) -> None:
        self.assertGreaterEqual(
            self.text.count("overlayFeatureFormDrawer.featureModel.currentLayer = layer"),
            3,
        )

    def test_attachment_browser_surfaces_existing_media_and_capture_types(self) -> None:
        self.assertIn('objectName: "waterworksAttachmentDrawer"', self.text)
        self.assertIn("function loadAttachments(objectId, objectKind)", self.text)
        self.assertIn("function attachmentUrl(relativePath)", self.text)
        self.assertIn('text: "照片 / 附件"', self.text)
        for media_type in ("photo", "video", "audio", "document"):
            self.assertIn(f'"{media_type}"', self.text)
        self.assertIn("Image {", self.text)
        self.assertIn("Qt.openUrlExternally(plugin.attachmentUrl(relativePath))", self.text)

    def test_safe_delete_uses_committed_expression_deletion(self) -> None:
        self.assertIn("function requestDeleteBusinessObject(objectId, objectKind)", self.text)
        self.assertIn("function confirmDeleteBusinessObject()", self.text)
        self.assertIn("QfLayerUtils.deleteFeaturesByExpression", self.text)
        self.assertIn("已经有巡检或维修历史", self.text)
        self.assertIn('状态改为“停用”', self.text)
        self.assertIn('title: "确认删除"', self.text)


if __name__ == "__main__":
    unittest.main()

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore

import org.qgis
import org.qfield.core
import org.qfield.gui

Item {
  id: plugin
  objectName: "waterworksInspectionPlugin"

  property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()
  property var positionSource: iface.findItemByObjectName("positionSource")
  property var overlayFeatureFormDrawer: iface.findItemByObjectName("overlayFeatureFormDrawer")
  property var featureForm: iface.findItemByObjectName("featureForm")
  property var navigation: iface.findItemByObjectName("navigation")
  property var projectFolderButton: iface.findItemByObjectName("projectFolderButton")

  readonly property var assetTypeLayerNames: ["设施类型配置", "asset_types"]
  readonly property var assetLayerNames: ["供水设施", "assets_point", "供水点位"]
  readonly property var pipelineLayerNames: ["供水管线", "pipelines"]
  readonly property var inspectionLayerNames: ["巡检记录", "inspections"]
  readonly property var repairLayerNames: ["维修记录", "repairs"]
  readonly property var attachmentLayerNames: ["附件", "attachments"]
  property bool searchBusy: false
  property bool searchPanelVisible: false
  property bool waterworksProjectReady: false
  property var pendingAssetGeometry
  property var pendingPipelineGeometry

  // Reliable no-token fallback map. The rectangle covers the Yulin area in
  // EPSG:3857 so a first launch never opens to an undefined/empty extent.
  readonly property string fallbackBasemapSource: "type=xyz&tilePixelRatio=1&url=https://tile.openstreetmap.org/%7Bz%7D/%7Bx%7D/%7By%7D.png&zmax=19&zmin=0&crs=EPSG3857"
  readonly property string yulinDefaultExtent: "POLYGON((11933449 4411266,12389859 4411266,12389859 4807984,11933449 4807984,11933449 4411266))"

  Settings {
    id: workerAppSettings
    category: "QField"
    property bool loadProjectOnLaunch: true
  }
  property int nearbyRadiusMeters: 500
  property real accuracyWarningMeters: 15

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(waterworksButton);
    workerAppSettings.loadProjectOnLaunch = true;
    refreshProjectState();
    Qt.callLater(function () {
      simplifyInterface();
      if (!iface.hasProjectOnLaunch() && (!qgisProject || !qgisProject.fileName)) {
        createDefaultWaterworksProject();
      }
    });
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {
      workerAppSettings.loadProjectOnLaunch = true;
      Qt.callLater(function () {
        ensureBusinessLayers(path);
        refreshProjectState();
        simplifyInterface();
        activateAndCenterLocation();
      });
    }
  }

  function refreshProjectState() {
    waterworksProjectReady = !!assetLayer() && !!pipelineLayer() && !!inspectionLayer() && !!repairLayer() && !!attachmentLayer();
    loadAssetTypeOptions();
  }

  function createDefaultWaterworksProject() {
    const positioning = iface.positioning();
    const info = positioning && positioning.positionInformation ? positioning.positionInformation : undefined;
    const projectFile = QfProjectUtils.createProject({
      "title": "供水巡检",
      "basemap": "custom",
      "basemap_custom_provider": "wms",
      "basemap_custom_source": fallbackBasemapSource,
      "basemap_custom_extent": yulinDefaultExtent,
      "notes": false,
      "camera_capture": false,
      "tracks": false
    }, info);

    if (!projectFile) {
      mainWindow.displayToast("无法创建供水巡检地图");
      return;
    }

    const sourceDatabase = QfUrlUtils.toLocalFile(Qt.resolvedUrl("waterworks-template.gpkg"));
    const targetDatabase = QfFileUtils.absolutePath(projectFile) + "/waterworks-inspection.gpkg";
    if (!QfFileUtils.copyFile(sourceDatabase, targetDatabase, false) && !QfFileUtils.fileExists(targetDatabase)) {
      mainWindow.displayToast("无法初始化供水数据");
      return;
    }

    iface.loadFile(projectFile, "供水巡检");
  }

  function addBusinessLayer(databasePath, tableName, displayName) {
    if (qgisProject.mapLayersByName(displayName).length > 0 || qgisProject.mapLayersByName(tableName).length > 0) {
      return true;
    }

    const layer = QfLayerUtils.loadVectorLayer(
      databasePath + "|layername=" + tableName,
      displayName,
      "ogr"
    );
    if (!layer || !layer.isValid) {
      return false;
    }
    return QfProjectUtils.addMapLayer(qgisProject, layer);
  }

  function ensureBusinessLayers(projectPath) {
    if (!projectPath) {
      return false;
    }

    const databasePath = QfFileUtils.absolutePath(projectPath) + "/waterworks-inspection.gpkg";
    if (!QfFileUtils.fileExists(databasePath)) {
      return false;
    }

    const definitions = [
      ["asset_types", "设施类型配置"],
      ["assets_point", "供水设施"],
      ["pipelines", "供水管线"],
      ["inspections", "巡检记录"],
      ["repairs", "维修记录"],
      ["attachments", "附件"]
    ];

    let ok = true;
    for (let i = 0; i < definitions.length; i++) {
      ok = addBusinessLayer(databasePath, definitions[i][0], definitions[i][1]) && ok;
    }
    return ok;
  }

  function simplifyInterface() {
    const mainMenuBar = iface.findItemByObjectName("mainMenuBar");
    const mainToolbar = iface.findItemByObjectName("mainToolbar");
    const zoomToolbar = iface.findItemByObjectName("zoomToolbar");
    const locatorItem = iface.findItemByObjectName("locatorItem");
    const dashBoard = iface.findItemByObjectName("dashBoard");
    const welcomeCloud = iface.findItemByObjectName("welcomeActionCloud");
    const welcomeNewProject = iface.findItemByObjectName("welcomeActionNewProject");
    const welcomeLocalProjects = iface.findItemByObjectName("welcomeActionLocalProjects");

    if (mainMenuBar) {
      mainMenuBar.visible = false;
    }
    if (mainToolbar) {
      mainToolbar.visible = false;
    }
    if (zoomToolbar) {
      zoomToolbar.visible = false;
    }
    if (locatorItem) {
      locatorItem.visible = false;
    }
    if (dashBoard && dashBoard.opened) {
      dashBoard.close();
    }
    if (welcomeCloud) {
      welcomeCloud.visible = false;
    }
    if (welcomeNewProject) {
      welcomeNewProject.visible = false;
    }
    if (welcomeLocalProjects) {
      welcomeLocalProjects.label = "打开供水数据";
    }
  }

  function chooseWaterworksProject() {
    waterworksDialog.close();
    simplifyInterface();
    iface.clearProject();
    Qt.callLater(function () {
      const welcomeScreen = iface.findItemByObjectName("welcomeScreen");
      if (welcomeScreen) {
        welcomeScreen.visible = true;
        welcomeScreen.showLocalDataPicker();
      }
    });
  }

  function activateAndCenterLocation() {
    const positioningSettings = iface.findItemByObjectName("positioningSettings");
    const gnssButton = iface.findItemByObjectName("gnssButton");

    if (positioningSettings && !positioningSettings.positioningActivated) {
      positioningSettings.positioningActivated = true;
    }
    if (gnssButton) {
      gnssButton.clicked();
    }
  }

  function centerOnCurrentPosition() {
    const gnssButton = iface.findItemByObjectName("gnssButton");
    if (!gnssButton) {
      mainWindow.displayToast("当前版本无法调用定位按钮");
      return;
    }

    waterworksDialog.close();
    gnssButton.clicked();
  }

  function loadNearbyKind(objectKind) {
    searchPanelVisible = true;
    searchTargetFilter.currentIndex = objectKind === "pipeline" ? 1 : 0;
    const item = nearbyRadiusCombo.model[nearbyRadiusCombo.currentIndex];
    loadNearbyObjects(item.value);
  }

  function startPipelineCapture() {
    const layer = pipelineLayer();
    const digitizingToolbar = iface.findItemByObjectName("digitizingToolbar");
    if (!layer || !digitizingToolbar) {
      mainWindow.displayToast("当前供水数据无法开始画管线");
      return;
    }

    pendingPipelineGeometry = null;
    waterworksDialog.close();
    digitizingToolbar.geometryRequestedLayer = layer;
    digitizingToolbar.geometryRequestedItem = pipelineGeometryReceiver;
    digitizingToolbar.geometryRequested = true;
    mainWindow.displayToast("依次点击管线经过的位置，完成后点右下角 ✓");
  }

  function savePipelineEntry() {
    const layer = pipelineLayer();
    if (!layer || !pendingPipelineGeometry) {
      mainWindow.displayToast("无法保存管线");
      return;
    }

    const feature = QfFeatureUtils.createFeature(layer, pendingPipelineGeometry);
    feature.setAttribute("name", pipelineEntryName.text.trim());
    feature.setAttribute("code", pipelineEntryCode.text.trim());
    feature.setAttribute("diameter_mm", pipelineEntryDiameter.text.length > 0 ? Number(pipelineEntryDiameter.text) : null);
    feature.setAttribute("material", pipelineEntryMaterial.text.trim());
    feature.setAttribute("pipe_type", pipelineEntryType.text.trim());
    feature.setAttribute("pressure_zone", pipelineEntryPressure.text.trim());
    feature.setAttribute("note", pipelineEntryNote.text.trim());

    if (!QfLayerUtils.addFeature(layer, feature)) {
      mainWindow.displayToast("管线保存失败");
      return;
    }

    pipelineEntryDialog.close();
    pendingPipelineGeometry = null;
    mainWindow.changeMode("browse");
    mainWindow.displayToast("管线已保存");
  }

  function assetTypeLayer() {
    for (let i = 0; i < assetTypeLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(assetTypeLayerNames[i]);
      if (layers && layers.length > 0) {
        return layers[0];
      }
    }
    return null;
  }

  function assetLayer() {
    for (let i = 0; i < assetLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(assetLayerNames[i]);
      if (layers && layers.length > 0) {
        return layers[0];
      }
    }
    return null;
  }

  function pipelineLayer() {
    for (let i = 0; i < pipelineLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(pipelineLayerNames[i]);
      if (layers && layers.length > 0) {
        return layers[0];
      }
    }
    return null;
  }

  function inspectionLayer() {
    for (let i = 0; i < inspectionLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(inspectionLayerNames[i]);
      if (layers && layers.length > 0) {
        return layers[0];
      }
    }
    return null;
  }

  function repairLayer() {
    for (let i = 0; i < repairLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(repairLayerNames[i]);
      if (layers && layers.length > 0) {
        return layers[0];
      }
    }
    return null;
  }

  function attachmentLayer() {
    for (let i = 0; i < attachmentLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(attachmentLayerNames[i]);
      if (layers && layers.length > 0) {
        return layers[0];
      }
    }
    return null;
  }

  function positionText() {
    const positioning = iface.positioning();
    if (!positioning || !positioning.active) {
      return "定位未开启";
    }

    const info = positioning.positionInformation;
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      return "正在等待有效定位";
    }

    let text = Number(info.latitude).toFixed(7) + ", " + Number(info.longitude).toFixed(7);
    if (info.haccValid) {
      text += "  ·  精度 ±" + Math.round(Number(info.hacc)) + " m";
    }
    return text;
  }

  function openProjectBackup() {
    if (!projectFolderButton) {
      mainWindow.displayToast("当前版本无法打开项目导出");
      return;
    }

    waterworksDialog.close();
    projectFolderButton.clicked();
  }

  function copyCurrentPosition() {
    const positioning = iface.positioning();
    if (!positioning || !positioning.active) {
      mainWindow.displayToast("请先开启定位");
      return;
    }

    const info = positioning.positionInformation;
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      mainWindow.displayToast("暂未获得有效定位");
      return;
    }

    const text = Number(info.latitude).toFixed(7) + ", " + Number(info.longitude).toFixed(7);
    platformUtilities.copyTextToClipboard(text);
    mainWindow.displayToast("当前位置已复制");
  }

  function escapeExpressionString(value) {
    return String(value || "").replace(/'/g, "''");
  }

  function selectedSearchKind() {
    if (!searchTargetFilter || searchTargetFilter.currentIndex < 0) {
      return "asset";
    }
    return searchTargetFilter.model[searchTargetFilter.currentIndex].value;
  }

  function selectedAssetType() {
    if (!assetTypeFilter || assetTypeFilter.currentIndex < 0) {
      return "";
    }
    const item = assetTypeOptions.get(assetTypeFilter.currentIndex);
    return item ? String(item.value || "") : "";
  }

  function selectedAssetStatus() {
    if (!assetStatusFilter || assetStatusFilter.currentIndex < 0) {
      return "";
    }
    return assetStatusFilter.model[assetStatusFilter.currentIndex].value;
  }

  function applySearchFilters(baseExpression, objectKind) {
    const clauses = [];
    const base = String(baseExpression || "").trim();
    if (base.length > 0) {
      clauses.push("(" + base + ")");
    }

    if (objectKind === "asset") {
      const typeValue = selectedAssetType();
      if (typeValue.length > 0) {
        clauses.push("\"asset_type\" = '" + escapeExpressionString(typeValue) + "'");
      }
    }

    const statusValue = selectedAssetStatus();
    if (statusValue === "problem") {
      clauses.push("\"status\" IN ('attention', 'repair')");
    } else if (statusValue.length > 0) {
      clauses.push("\"status\" = '" + escapeExpressionString(statusValue) + "'");
    }

    if (uninspectedOnly && uninspectedOnly.checked) {
      clauses.push("\"last_inspection_at\" IS NULL");
    }

    return clauses.length > 0 ? clauses.join(" AND ") : "1 = 1";
  }

  function loadAssetTypeOptions() {
    assetTypeOptions.clear();
    assetTypeOptions.append({
      "text": "全部类型",
      "value": "",
      "sortOrder": -1
    });

    const layer = assetTypeLayer();
    if (!layer) {
      return;
    }

    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, "\"active\" = 1");
    const options = [];
    while (iterator.hasNext()) {
      const feature = iterator.next();
      options.push({
        "text": String(feature.attribute("label") || feature.attribute("code") || ""),
        "value": String(feature.attribute("code") || ""),
        "sortOrder": Number(feature.attribute("sort_order") || 100)
      });
    }
    iterator.close();

    options.sort((a, b) => {
      if (a.sortOrder !== b.sortOrder) {
        return a.sortOrder - b.sortOrder;
      }
      return a.text.localeCompare(b.text);
    });
    for (let i = 0; i < options.length; i++) {
      assetTypeOptions.append(options[i]);
    }
  }

  function assetTypeLabel(value) {
    const key = String(value || "");
    for (let i = 0; i < assetTypeOptions.count; i++) {
      const item = assetTypeOptions.get(i);
      if (String(item.value) === key) {
        return String(item.text);
      }
    }
    return key;
  }

  function assetStatusLabel(value) {
    switch (String(value || "")) {
    case "normal":
      return "正常";
    case "attention":
      return "需关注";
    case "repair":
      return "待维修";
    case "disabled":
      return "停用";
    default:
      return String(value || "");
    }
  }

  function appendSearchResult(feature, objectKind, distanceMeters) {
    const idValue = feature.attribute("id");
    const nameValue = feature.attribute("name");
    const codeValue = feature.attribute("code");
    const statusValue = feature.attribute("status");
    const lastInspectionValue = feature.attribute("last_inspection_at");
    let typeValue = "";
    let detailValue = "";
    let fallbackName = "未命名点位";

    if (objectKind === "asset") {
      typeValue = feature.attribute("asset_type");
      const detailParts = [];
      const area = feature.attribute("area_name");
      const hint = feature.attribute("address_hint");
      if (area !== null && area !== undefined && String(area).length > 0) {
        detailParts.push(String(area));
      }
      if (hint !== null && hint !== undefined && String(hint).length > 0) {
        detailParts.push(String(hint));
      }
      detailValue = detailParts.join(" · ");
    } else {
      fallbackName = "未命名管线";
      const parts = [];
      const diameter = Number(feature.attribute("diameter_mm"));
      const pipeType = feature.attribute("pipe_type");
      const material = feature.attribute("material");
      if (isFinite(diameter) && diameter > 0) {
        parts.push("DN" + Math.round(diameter));
      }
      if (pipeType !== null && pipeType !== undefined && String(pipeType).length > 0) {
        parts.push(String(pipeType));
      }
      if (material !== null && material !== undefined && String(material).length > 0) {
        parts.push(String(material));
      }
      typeValue = parts.join(" · ");

      const pressureZone = feature.attribute("pressure_zone");
      if (pressureZone !== null && pressureZone !== undefined && String(pressureZone).length > 0) {
        detailValue = "压力分区 " + String(pressureZone);
      }
    }

    assetSearchResults.append({
      "objectKind": objectKind,
      "assetId": idValue === null || idValue === undefined ? "" : String(idValue),
      "assetName": nameValue === null || nameValue === undefined || String(nameValue).length === 0 ? fallbackName : String(nameValue),
      "assetCode": codeValue === null || codeValue === undefined ? "" : String(codeValue),
      "assetType": typeValue === null || typeValue === undefined ? "" : String(typeValue),
      "assetStatus": statusValue === null || statusValue === undefined ? "" : String(statusValue),
      "assetLastInspection": lastInspectionValue === null || lastInspectionValue === undefined ? "" : String(lastInspectionValue),
      "assetDetail": detailValue,
      "assetDistance": distanceMeters === undefined || distanceMeters === null ? -1 : Math.max(0, Math.round(Number(distanceMeters)))
    });
  }

  function searchObjects(term) {
    assetSearchResults.clear();

    const objectKind = selectedSearchKind();
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    if (!layer) {
      mainWindow.displayToast(objectKind === "pipeline" ? "当前项目缺少“供水管线”图层" : "当前项目缺少“供水设施”图层");
      return;
    }

    const trimmed = String(term || "").trim();

    searchBusy = true;
    let textExpression = "";
    if (trimmed.length > 0) {
      const needle = escapeExpressionString(trimmed.toLowerCase());
      if (objectKind === "pipeline") {
        textExpression = "lower(coalesce(\"name\", '')) LIKE '%" + needle + "%' OR " +
                         "lower(coalesce(\"code\", '')) LIKE '%" + needle + "%' OR " +
                         "lower(coalesce(\"pipe_type\", '')) LIKE '%" + needle + "%' OR " +
                         "lower(coalesce(\"material\", '')) LIKE '%" + needle + "%' OR " +
                         "lower(coalesce(\"pressure_zone\", '')) LIKE '%" + needle + "%'";
      } else {
        textExpression = "lower(coalesce(\"name\", '')) LIKE '%" + needle + "%' OR " +
                         "lower(coalesce(\"code\", '')) LIKE '%" + needle + "%' OR " +
                         "lower(coalesce(\"address_hint\", '')) LIKE '%" + needle + "%'";
      }
    }

    const expression = applySearchFilters(textExpression, objectKind);
    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, expression);
    let count = 0;

    while (iterator.hasNext() && count < 100) {
      appendSearchResult(iterator.next(), objectKind);
      count++;
    }
    const hasMore = iterator.hasNext();
    iterator.close();

    searchBusy = false;

    if (count === 0) {
      mainWindow.displayToast(objectKind === "pipeline" ? "未找到匹配管线" : "未找到匹配点位");
    } else if (hasMore) {
      mainWindow.displayToast("结果超过 100 条，请缩小筛选范围");
    }
  }

  function loadNearbyObjects(radiusMeters) {
    assetSearchResults.clear();

    const objectKind = selectedSearchKind();
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    if (!layer) {
      mainWindow.displayToast(objectKind === "pipeline" ? "当前项目缺少“供水管线”图层" : "当前项目缺少“供水设施”图层");
      return;
    }

    const positioning = iface.positioning();
    if (!positioning || !positioning.active || !positioning.positionInformation) {
      mainWindow.displayToast("请先开启定位");
      return;
    }

    const info = positioning.positionInformation;
    if (!info.longitudeValid || !info.latitudeValid) {
      mainWindow.displayToast("暂未获得有效定位");
      return;
    }

    const radius = Math.max(10, Math.min(5000, Number(radiusMeters)));
    nearbyRadiusMeters = radius;
    searchBusy = true;

    // QGIS expressions calculate the shortest distance to the complete feature
    // geometry. This works for both point assets and line pipelines.
    const lon = Number(info.longitude);
    const lat = Number(info.latitude);
    const utmZone = Math.max(1, Math.min(60, Math.floor((lon + 180) / 6) + 1));
    const utmEpsg = (lat >= 0 ? 32600 : 32700) + utmZone;
    const distanceCrs = "EPSG:" + utmEpsg;
    const distanceValueExpression =
      "distance(" +
      "transform($geometry, 'EPSG:4490', '" + distanceCrs + "'), " +
      "transform(make_point(" + lon + ", " + lat + "), 'EPSG:4326', '" + distanceCrs + "')" +
      ")";
    const expression = applySearchFilters(distanceValueExpression + " <= " + radius, objectKind);

    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, expression);
    const matches = [];
    nearbyDistanceEvaluator.layer = layer;

    while (iterator.hasNext() && matches.length < 100) {
      const feature = iterator.next();
      nearbyDistanceEvaluator.feature = feature;
      const distance = Number(nearbyDistanceEvaluator.evaluate(distanceValueExpression));
      if (isFinite(distance) && distance >= 0) {
        matches.push({
          "feature": feature,
          "distance": distance
        });
      }
    }
    iterator.close();

    matches.sort((a, b) => a.distance - b.distance);
    for (let i = 0; i < matches.length; i++) {
      appendSearchResult(matches[i].feature, objectKind, matches[i].distance);
    }

    searchBusy = false;
    assetSearchField.text = "";

    const objectLabel = objectKind === "pipeline" ? "管线" : "点位";
    if (matches.length === 0) {
      mainWindow.displayToast(radius + " 米内没有" + objectLabel);
    } else {
      mainWindow.displayToast("已按距离载入 " + matches.length + " 个附近" + objectLabel);
    }
  }

  function featureForObjectId(objectKind, objectId) {
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    if (!layer || !objectId) {
      return null;
    }

    const escapedId = escapeExpressionString(objectId);
    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, "\"id\" = '" + escapedId + "'");
    if (!iterator.hasNext()) {
      iterator.close();
      return null;
    }

    const feature = iterator.next();
    iterator.close();
    return feature;
  }

  function navigateToAsset(assetId) {
    const layer = assetLayer();
    const feature = featureForObjectId("asset", assetId);
    if (!layer || !feature || !navigation) {
      mainWindow.displayToast("无法开始点位导航");
      return;
    }

    navigation.setDestinationFeature(feature, layer);
    waterworksDialog.close();
    mainWindow.displayToast("开始导航：" + QfFeatureUtils.displayName(layer, feature));
  }

  function openObject(objectKind, objectId, editMode) {
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    if (!layer || !featureForm || !objectId) {
      mainWindow.displayToast(objectKind === "pipeline" ? "无法打开管线" : "无法打开点位");
      return;
    }

    const escapedId = escapeExpressionString(objectId);
    featureForm.model.setFeatures(layer, "\"id\" = '" + escapedId + "'");
    featureForm.selection.focusedItem = 0;
    featureForm.state = editMode ? "FeatureFormEdit" : "FeatureForm";
    waterworksDialog.close();
  }

  function createAssetAtCurrentPosition() {
    const layer = assetLayer();
    if (!layer) {
      mainWindow.displayToast("当前供水数据缺少点位图层");
      return;
    }

    const positioning = iface.positioning();
    if (!positioning || !positioning.active) {
      mainWindow.displayToast("请先开启定位");
      return;
    }

    const info = positioning.positionInformation;
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      mainWindow.displayToast("暂未获得有效定位");
      return;
    }

    if (info.haccValid && Number(info.hacc) > accuracyWarningMeters) {
      mainWindow.displayToast("当前定位精度约 ±" + Math.round(Number(info.hacc)) + " 米，建议到开阔位置等待定位稳定后再放点");
    }

    pendingAssetGeometry = QfGeometryUtils.createGeometryFromWkt(
      "POINT(" + Number(info.longitude) + " " + Number(info.latitude) + ")"
    );
    assetEntryDialog.open();
  }

  function saveAssetEntry() {
    const layer = assetLayer();
    if (!layer || !pendingAssetGeometry) {
      mainWindow.displayToast("无法保存点位");
      return;
    }

    const feature = QfFeatureUtils.createFeature(layer, pendingAssetGeometry);
    const typeItem = assetTypeOptions.get(assetEntryType.currentIndex);
    feature.setAttribute("asset_type", typeItem && typeItem.value ? String(typeItem.value) : "other");
    feature.setAttribute("name", assetEntryName.text.trim());
    feature.setAttribute("code", assetEntryCode.text.trim());
    feature.setAttribute("area_name", assetEntryArea.text.trim());
    feature.setAttribute("address_hint", assetEntryAddress.text.trim());
    feature.setAttribute("note", assetEntryNote.text.trim());

    if (!QfLayerUtils.addFeature(layer, feature)) {
      mainWindow.displayToast("点位保存失败");
      return;
    }

    assetEntryDialog.close();
    pendingAssetGeometry = null;
    mainWindow.displayToast("点位已保存");
  }

  function setParentReference(feature, objectId, objectKind) {
    if (objectKind === "pipeline") {
      feature.setAttribute("pipeline_id", objectId);
      feature.setAttribute("asset_id", null);
    } else {
      feature.setAttribute("asset_id", objectId);
      feature.setAttribute("pipeline_id", null);
    }
  }

  function createInspection(objectId, objectKind) {
    const layer = inspectionLayer();
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“巡检记录”图层");
      return;
    }
    if (!objectId) {
      mainWindow.displayToast("无法确定巡检对象");
      return;
    }
    if (!overlayFeatureFormDrawer) {
      mainWindow.displayToast("无法打开巡检表单");
      return;
    }

    const feature = QfFeatureUtils.createFeature(layer);
    setParentReference(feature, objectId, objectKind);

    const positioning = iface.positioning();
    if (positioning && positioning.active && positioning.positionInformation) {
      const info = positioning.positionInformation;
      const accuracy = Number(info.hacc);
      if (info.haccValid && isFinite(accuracy) && accuracy >= 0) {
        feature.setAttribute("position_accuracy_m", accuracy);
      }
    }

    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    waterworksDialog.close();
    overlayFeatureFormDrawer.open();
  }

  function createRepair(objectId, objectKind) {
    const layer = repairLayer();
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“维修记录”图层");
      return;
    }
    if (!objectId) {
      mainWindow.displayToast("无法确定维修对象");
      return;
    }
    if (!overlayFeatureFormDrawer) {
      mainWindow.displayToast("无法打开维修表单");
      return;
    }

    const feature = QfFeatureUtils.createFeature(layer);
    setParentReference(feature, objectId, objectKind);

    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    waterworksDialog.close();
    overlayFeatureFormDrawer.open();
  }

  function createAttachment(objectId, objectKind) {
    const layer = attachmentLayer();
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“附件”图层");
      return;
    }
    if (!objectId) {
      mainWindow.displayToast("无法确定附件所属对象");
      return;
    }
    if (!overlayFeatureFormDrawer) {
      mainWindow.displayToast("无法打开附件表单");
      return;
    }

    const feature = QfFeatureUtils.createFeature(layer);
    setParentReference(feature, objectId, objectKind);

    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    waterworksDialog.close();
    overlayFeatureFormDrawer.open();
  }

  Item {
    id: pipelineGeometryReceiver
    visible: false

    function requestedGeometryReceived(geometry) {
      pendingPipelineGeometry = geometry.asQgsGeometry();
      pipelineEntryDialog.open();
    }
  }

  QfExpressionEvaluator {
    id: nearbyDistanceEvaluator
    project: qgisProject
  }

  QfToolButton {
    id: waterworksButton
    objectName: "waterworksInspectionButton"
    text: "巡"
    font.bold: true
    Material.foreground: QfTheme.toolButtonColor
    bgcolor: QfTheme.toolButtonBackgroundColor
    round: true

    onClicked: {
      refreshProjectState()
      simplifyInterface()
      waterworksDialog.open()
    }
  }

  ListModel {
    id: assetTypeOptions
  }

  ListModel {
    id: assetSearchResults
  }

  QfDialog {
    id: assetEntryDialog
    parent: mainWindow.contentItem
    title: "新增点位"
    modal: true
    standardButtons: Dialog.NoButton
    width: Math.min(mainWindow.width - 32, 520)
    height: Math.min(mainWindow.height - 48, 620)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    onOpened: {
      loadAssetTypeOptions();
      assetEntryType.currentIndex = assetTypeOptions.count > 1 ? 1 : 0;
      assetEntryName.clear();
      assetEntryCode.clear();
      assetEntryArea.clear();
      assetEntryAddress.clear();
      assetEntryNote.clear();
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      ComboBox {
        id: assetEntryType
        Layout.fillWidth: true
        model: assetTypeOptions
        textRole: "text"
      }

      TextField {
        id: assetEntryName
        Layout.fillWidth: true
        placeholderText: "点位名称（可选）"
      }

      TextField {
        id: assetEntryCode
        Layout.fillWidth: true
        placeholderText: "设施编号（可选）"
      }

      TextField {
        id: assetEntryArea
        Layout.fillWidth: true
        placeholderText: "片区（可选）"
      }

      TextField {
        id: assetEntryAddress
        Layout.fillWidth: true
        placeholderText: "位置描述，例如：村口向东 20 米"
      }

      TextArea {
        id: assetEntryNote
        Layout.fillWidth: true
        Layout.fillHeight: true
        placeholderText: "备注（可选）"
        wrapMode: TextEdit.Wrap
      }

      RowLayout {
        Layout.fillWidth: true

        Button {
          Layout.fillWidth: true
          text: "取消"
          onClicked: {
            pendingAssetGeometry = null;
            assetEntryDialog.close();
          }
        }

        Button {
          Layout.fillWidth: true
          text: "保存点位"
          onClicked: plugin.saveAssetEntry()
        }
      }
    }
  }

  QfDialog {
    id: pipelineEntryDialog
    parent: mainWindow.contentItem
    title: "填写管线参数"
    modal: true
    standardButtons: Dialog.NoButton
    width: Math.min(mainWindow.width - 32, 520)
    height: Math.min(mainWindow.height - 48, 650)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    onOpened: {
      pipelineEntryName.clear();
      pipelineEntryCode.clear();
      pipelineEntryDiameter.clear();
      pipelineEntryMaterial.clear();
      pipelineEntryType.clear();
      pipelineEntryPressure.clear();
      pipelineEntryNote.clear();
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      TextField {
        id: pipelineEntryName
        Layout.fillWidth: true
        placeholderText: "管线名称（可选）"
      }

      TextField {
        id: pipelineEntryCode
        Layout.fillWidth: true
        placeholderText: "管线编号（可选）"
      }

      TextField {
        id: pipelineEntryDiameter
        Layout.fillWidth: true
        placeholderText: "管径，例如 300"
        inputMethodHints: Qt.ImhFormattedNumbersOnly
      }

      TextField {
        id: pipelineEntryMaterial
        Layout.fillWidth: true
        placeholderText: "材质，例如 PE / 球墨铸铁"
      }

      TextField {
        id: pipelineEntryType
        Layout.fillWidth: true
        placeholderText: "管线类型，例如 主管 / 支管"
      }

      TextField {
        id: pipelineEntryPressure
        Layout.fillWidth: true
        placeholderText: "压力分区（可选）"
      }

      TextArea {
        id: pipelineEntryNote
        Layout.fillWidth: true
        Layout.fillHeight: true
        placeholderText: "备注（可选）"
        wrapMode: TextEdit.Wrap
      }

      RowLayout {
        Layout.fillWidth: true

        Button {
          Layout.fillWidth: true
          text: "取消"
          onClicked: {
            pendingPipelineGeometry = null;
            pipelineEntryDialog.close();
            mainWindow.changeMode("browse");
          }
        }

        Button {
          Layout.fillWidth: true
          text: "保存管线"
          onClicked: plugin.savePipelineEntry()
        }
      }
    }
  }

  QfDialog {
    id: waterworksDialog
    objectName: "waterworksInspectionDialog"
    parent: mainWindow.contentItem
    title: "供水巡检"
    modal: true
    standardButtons: Dialog.Close

    width: Math.min(mainWindow.width - 32, 560)
    height: Math.min(mainWindow.height - 48, 680)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    ColumnLayout {
      anchors.fill: parent
      spacing: 10

      Label {
        Layout.fillWidth: true
        text: "当前位置"
        font.bold: true
        color: QfTheme.mainTextColor
      }

      Label {
        Layout.fillWidth: true
        text: plugin.positionText()
        color: QfTheme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
          Layout.fillWidth: true
          text: "定位到我"
          onClicked: plugin.centerOnCurrentPosition()
        }

        Button {
          Layout.fillWidth: true
          text: "新增点位"
          onClicked: plugin.createAssetAtCurrentPosition()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
          Layout.fillWidth: true
          text: "新建管线"
          onClicked: plugin.startPipelineCapture()
        }

        Button {
          Layout.fillWidth: true
          text: searchPanelVisible ? "收起查找" : "查找"
          onClicked: searchPanelVisible = !searchPanelVisible
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
          Layout.fillWidth: true
          text: "附近点位"
          enabled: !searchBusy
          onClicked: plugin.loadNearbyKind("asset")
        }

        Button {
          Layout.fillWidth: true
          text: "附近管线"
          enabled: !searchBusy
          onClicked: plugin.loadNearbyKind("pipeline")
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: QfTheme.controlBorderColor
      }

      Label {
        Layout.fillWidth: true
        visible: searchPanelVisible
        text: "查找"
        font.bold: true
        color: QfTheme.mainTextColor
      }

      RowLayout {
        Layout.fillWidth: true
        visible: searchPanelVisible

        ComboBox {
          id: searchTargetFilter
          Layout.fillWidth: true
          model: [
            {
              text: "点位",
              value: "asset"
            },
            {
              text: "管线",
              value: "pipeline"
            }
          ]
          textRole: "text"
          currentIndex: 0

          onCurrentIndexChanged: {
            assetSearchResults.clear()
            if (assetTypeFilter) {
              assetTypeFilter.currentIndex = 0
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: searchPanelVisible
        spacing: 6

        ComboBox {
          id: assetTypeFilter
          Layout.fillWidth: true
          model: assetTypeOptions
          textRole: "text"
          currentIndex: 0
          enabled: plugin.selectedSearchKind() === "asset"
        }

        ComboBox {
          id: assetStatusFilter
          Layout.fillWidth: true
          model: [
            {
              text: "全部状态",
              value: ""
            },
            {
              text: "需处理",
              value: "problem"
            },
            {
              text: "正常",
              value: "normal"
            },
            {
              text: "需关注",
              value: "attention"
            },
            {
              text: "待维修",
              value: "repair"
            },
            {
              text: "停用",
              value: "disabled"
            }
          ]
          textRole: "text"
          currentIndex: 0
        }
      }

      CheckBox {
        id: uninspectedOnly
        visible: searchPanelVisible
        Layout.fillWidth: true
        text: "仅看从未巡检"
        onToggled: assetSearchResults.clear()
      }

      RowLayout {
        Layout.fillWidth: true
        visible: searchPanelVisible
        spacing: 6

        ComboBox {
          id: nearbyRadiusCombo
          model: [
            {
              text: "100 m",
              value: 100
            },
            {
              text: "300 m",
              value: 300
            },
            {
              text: "500 m",
              value: 500
            },
            {
              text: "1 km",
              value: 1000
            },
            {
              text: "2 km",
              value: 2000
            }
          ]
          textRole: "text"
          currentIndex: 2
        }

        Label {
          Layout.fillWidth: true
          text: "附近查询范围"
          color: QfTheme.secondaryTextColor
          verticalAlignment: Text.AlignVCenter
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: searchPanelVisible

        TextField {
          id: assetSearchField
          Layout.fillWidth: true
          placeholderText: plugin.selectedSearchKind() === "pipeline" ? "输入管线名称、编号、材质或压力分区" : "输入名称、编号或位置描述"
          selectByMouse: true
          onAccepted: plugin.searchObjects(text)
        }

        Button {
          text: searchBusy ? "查询中" : "查询"
          enabled: !searchBusy
          onClicked: plugin.searchObjects(assetSearchField.text)
        }
      }

      Label {
        Layout.fillWidth: true
        visible: searchPanelVisible && assetSearchResults.count > 0
        text: "找到 " + assetSearchResults.count + " 条结果"
        color: QfTheme.secondaryTextColor
      }

      ListView {
        id: resultsView
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: searchPanelVisible
        clip: true
        spacing: 6
        model: assetSearchResults

        delegate: Rectangle {
          required property string objectKind
          required property string assetId
          required property string assetName
          required property string assetCode
          required property string assetType
          required property string assetStatus
          required property string assetLastInspection
          required property string assetDetail
          required property int assetDistance

          width: resultsView.width
          height: resultColumn.implicitHeight + 20
          radius: 6
          color: QfTheme.groupBoxBackgroundColor
          border.color: QfTheme.controlBorderColor

          ColumnLayout {
            id: resultColumn
            anchors {
              left: parent.left
              right: parent.right
              top: parent.top
              margins: 10
            }
            spacing: 3

            Label {
              Layout.fillWidth: true
              text: assetName
              font.bold: true
              color: QfTheme.mainTextColor
              elide: Text.ElideRight
            }

            Label {
              Layout.fillWidth: true
              text: (assetDistance >= 0 ? assetDistance + " m  " : "") + (assetCode.length > 0 ? "编号 " + assetCode + "  " : "") + (assetType.length > 0 ? (objectKind === "asset" ? plugin.assetTypeLabel(assetType) : assetType) + "  " : "") + (assetStatus.length > 0 ? plugin.assetStatusLabel(assetStatus) : "")
              color: QfTheme.secondaryTextColor
              elide: Text.ElideRight
            }

            Label {
              Layout.fillWidth: true
              text: "最近巡检 " + (assetLastInspection.length > 0 ? assetLastInspection : "从未巡检") + (assetDetail.length > 0 ? "  ·  " + assetDetail : "")
              color: QfTheme.secondaryTextColor
              elide: Text.ElideRight
            }

            RowLayout {
              Layout.fillWidth: true

              Button {
                Layout.fillWidth: true
                text: "查看"
                onClicked: plugin.openObject(objectKind, assetId, false)
              }

              Button {
                Layout.fillWidth: true
                text: "编辑"
                onClicked: plugin.openObject(objectKind, assetId, true)
              }

              Button {
                Layout.fillWidth: true
                text: "导航"
                visible: objectKind === "asset"
                onClicked: plugin.navigateToAsset(assetId)
              }
            }

            RowLayout {
              Layout.fillWidth: true

              Button {
                Layout.fillWidth: true
                text: "巡检"
                onClicked: plugin.createInspection(assetId, objectKind)
              }

              Button {
                Layout.fillWidth: true
                text: "维修"
                onClicked: plugin.createRepair(assetId, objectKind)
              }

              Button {
                Layout.fillWidth: true
                text: "附件"
                onClicked: plugin.createAttachment(assetId, objectKind)
              }
            }
          }
        }
      }

      Button {
        Layout.fillWidth: true
        text: "备份 / 导出"
        onClicked: plugin.openProjectBackup()
      }
    }

    Rectangle {
      anchors.fill: parent
      visible: !plugin.waterworksProjectReady
      z: 10
      color: QfTheme.mainBackgroundColor

      ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 420)
        spacing: 14

        Label {
          Layout.fillWidth: true
          text: "还没有打开供水数据"
          font.bold: true
          font.pixelSize: 20
          horizontalAlignment: Text.AlignHCenter
          color: QfTheme.mainTextColor
        }

        Label {
          Layout.fillWidth: true
          text: "正在准备供水巡检地图。如果自动初始化失败，可以手动打开已有的供水数据。"
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: QfTheme.secondaryTextColor
        }

        Button {
          Layout.fillWidth: true
          text: "打开供水数据"
          onClicked: plugin.chooseWaterworksProject()
        }

      }
    }
  }
}

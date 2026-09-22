import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

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
  property bool advancedMode: false
  property bool waterworksProjectReady: false
  property int nearbyRadiusMeters: 500
  property real accuracyWarningMeters: 15

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(waterworksButton);
    refreshProjectState();
    Qt.callLater(function () {
      applyWorkerMode(false);
      if (waterworksProjectReady) {
        waterworksDialog.open();
      }
    });
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {
      Qt.callLater(function () {
        refreshProjectState();
        applyWorkerMode(false);
        if (waterworksProjectReady) {
          waterworksDialog.open();
        }
      });
    }
  }

  function refreshProjectState() {
    waterworksProjectReady = !!assetLayer() && !!pipelineLayer() && !!inspectionLayer() && !!repairLayer() && !!attachmentLayer();
    loadAssetTypeOptions();
  }

  function applyWorkerMode(enableAdvanced) {
    advancedMode = !!enableAdvanced;

    const mainMenuBar = iface.findItemByObjectName("mainMenuBar");
    const mainToolbar = iface.findItemByObjectName("mainToolbar");
    const zoomToolbar = iface.findItemByObjectName("zoomToolbar");
    const locatorItem = iface.findItemByObjectName("locatorItem");
    const dashBoard = iface.findItemByObjectName("dashBoard");
    const welcomeCloud = iface.findItemByObjectName("welcomeActionCloud");
    const welcomeNewProject = iface.findItemByObjectName("welcomeActionNewProject");
    const welcomeLocalProjects = iface.findItemByObjectName("welcomeActionLocalProjects");

    if (mainMenuBar) {
      mainMenuBar.visible = advancedMode;
    }
    if (mainToolbar) {
      mainToolbar.visible = advancedMode;
    }
    if (zoomToolbar) {
      zoomToolbar.visible = advancedMode;
    }
    if (locatorItem) {
      locatorItem.visible = advancedMode;
    }
    if (!advancedMode && dashBoard && dashBoard.opened) {
      dashBoard.close();
    }

    if (welcomeCloud) {
      welcomeCloud.visible = advancedMode;
    }
    if (welcomeNewProject) {
      welcomeNewProject.visible = advancedMode;
    }
    if (welcomeLocalProjects) {
      welcomeLocalProjects.label = advancedMode ? "本地项目 / 数据" : "打开供水巡检项目";
    }
  }

  function chooseWaterworksProject() {
    waterworksDialog.close();
    applyWorkerMode(false);
    iface.clearProject();
    Qt.callLater(function () {
      const welcomeScreen = iface.findItemByObjectName("welcomeScreen");
      if (welcomeScreen) {
        welcomeScreen.visible = true;
        welcomeScreen.showLocalDataPicker();
      }
    });
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
    searchTargetFilter.currentIndex = objectKind === "pipeline" ? 1 : 0;
    const item = nearbyRadiusCombo.model[nearbyRadiusCombo.currentIndex];
    loadNearbyObjects(item.value);
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
      mainWindow.displayToast("当前项目缺少“供水设施”图层");
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

    if (!positioning.projectedPosition) {
      mainWindow.displayToast("无法取得项目坐标");
      return;
    }

    if (info.haccValid && Number(info.hacc) > accuracyWarningMeters) {
      mainWindow.displayToast("当前定位精度约 ±" + Math.round(Number(info.hacc)) + " 米，建议到开阔位置等待定位稳定后再采点");
    }

    const projected = positioning.projectedPosition;
    const geometry = QfGeometryUtils.createGeometryFromWkt("POINT(" + Number(projected.x) + " " + Number(projected.y) + ")");
    const feature = QfFeatureUtils.createFeature(layer, geometry, positioning.positionInformation);

    if (!overlayFeatureFormDrawer) {
      mainWindow.displayToast("无法打开新增点位表单");
      return;
    }

    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    waterworksDialog.close();
    overlayFeatureFormDrawer.open();
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

  QfExpressionEvaluator {
    id: nearbyDistanceEvaluator
    project: qgisProject
  }

  QfToolButton {
    id: waterworksButton
    objectName: "waterworksInspectionButton"
    text: "水"
    font.bold: true
    Material.foreground: QfTheme.toolButtonColor
    bgcolor: QfTheme.toolButtonBackgroundColor
    round: true

    onClicked: {
      refreshProjectState()
      applyWorkerMode(false)
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
        text: "搜索与筛选"
        font.bold: true
        color: QfTheme.mainTextColor
      }

      RowLayout {
        Layout.fillWidth: true

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
        Layout.fillWidth: true
        text: "仅看从未巡检"
        onToggled: assetSearchResults.clear()
      }

      RowLayout {
        Layout.fillWidth: true
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
        visible: assetSearchResults.count > 0
        text: "找到 " + assetSearchResults.count + " 条结果"
        color: QfTheme.secondaryTextColor
      }

      ListView {
        id: resultsView
        Layout.fillWidth: true
        Layout.fillHeight: true
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

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
          Layout.fillWidth: true
          text: "备份 / 导出"
          onClicked: plugin.openProjectBackup()
        }

        Button {
          Layout.fillWidth: true
          text: "高级功能"
          onClicked: {
            plugin.applyWorkerMode(true)
            waterworksDialog.close()
            mainWindow.displayToast("已进入高级模式；点击“水”按钮可返回维修人员模式")
          }
        }
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
          text: "当前不是供水巡检项目"
          font.bold: true
          font.pixelSize: 20
          horizontalAlignment: Text.AlignHCenter
          color: QfTheme.mainTextColor
        }

        Label {
          Layout.fillWidth: true
          text: "维修人员不需要新建普通 GIS 项目。请打开已经准备好的供水巡检项目，打开后会直接进入地图和巡检功能。"
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: QfTheme.secondaryTextColor
        }

        Button {
          Layout.fillWidth: true
          text: "打开供水巡检项目"
          onClicked: plugin.chooseWaterworksProject()
        }

        Button {
          Layout.fillWidth: true
          text: "进入高级模式"
          onClicked: {
            plugin.applyWorkerMode(true)
            waterworksDialog.close()
          }
        }
      }
    }
  }
}

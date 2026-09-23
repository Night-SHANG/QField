import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore
import "TiandituConfig.js" as TiandituConfig

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
  property var digitizingToolbar: iface.findItemByObjectName("digitizingToolbar")

  readonly property var assetTypeLayerNames: ["设施类型配置", "asset_types"]
  readonly property var assetLayerNames: ["供水设施", "assets_point", "供水点位"]
  readonly property var pipelineLayerNames: ["供水管线", "pipelines"]
  readonly property var inspectionLayerNames: ["巡检记录", "inspections"]
  readonly property var repairLayerNames: ["维修记录", "repairs"]
  readonly property var attachmentLayerNames: ["附件", "attachments"]
  property bool searchBusy: false
  property string queryMode: "search"
  property string queryObjectKind: "asset"
  property bool queryFiltersExpanded: false
  property bool waterworksProjectReady: false
  property var pendingAssetGeometry
  property var pendingPipelineGeometry
  property var pendingAssetPhotoPaths: []
  property string attachmentObjectId: ""
  property string attachmentObjectKind: ""
  property string pendingAttachmentRefreshId: ""
  property string pendingAttachmentRefreshKind: ""
  property string pendingDeleteObjectId: ""
  property string pendingDeleteObjectKind: ""
  property string pendingDeleteObjectName: ""
  property int pendingDeleteAttachmentCount: 0
  property string attachmentCaptureMediaType: ""

  // Reliable no-token fallback map. The rectangle covers the Yulin area in
  // EPSG:3857 so a first launch never opens to an undefined/empty extent.
  readonly property string fallbackBasemapSource: "type=xyz&tilePixelRatio=1&url=https://tile.openstreetmap.org/%7Bz%7D/%7Bx%7D/%7By%7D.png&zmax=19&zmin=0&crs=EPSG3857"
  readonly property string yulinDefaultExtent: "POLYGON((11933449 4411266,12389859 4411266,12389859 4807984,11933449 4807984,11933449 4411266))"
  readonly property var managedBasemapLayerNames: [
    "Basemap",
    "供水底图 OSM",
    "供水底图 天地图矢量",
    "供水底图 天地图矢量注记",
    "供水底图 天地图影像",
    "供水底图 天地图影像注记",
    "供水底图 天地图矢量",
    "供水底图 天地图矢量注记",
    "供水底图 天地图影像",
    "供水底图 天地图影像注记",
    "供水底图 陕西天地图矢量",
    "供水底图 陕西天地图影像",
    "供水底图 陕西天地图影像注记",
    "天地图·陕西 标准地图",
    "天地图·陕西 影像",
    "天地图·陕西 影像注记"
  ]

  Settings {
    id: workerAppSettings
    category: "QField"
    property bool loadProjectOnLaunch: true
    property bool showMyLocationMarker: true
    property bool editEnabled: false
    property string basemapMode: "osm"
    property bool basemapPreferenceInitialized: false
    property string tiandituToken: ""
  }
  property int nearbyRadiusMeters: 500
  property real accuracyWarningMeters: 15

  Component.onCompleted: {
    workerAppSettings.loadProjectOnLaunch = true;
    refreshProjectState();
    Qt.callLater(function () {
      simplifyInterface();
      if (!iface.hasProjectOnLaunch() && (!qgisProject || !qgisProject.fileName)) {
        createDefaultWaterworksProject();
      } else if (qgisProject && qgisProject.fileName) {
        applyBasemap(initialBasemapMode(), false);
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
        applyBasemap(initialBasemapMode(), false);
        activateAndCenterLocation();
      });
    }
  }

  Connections {
    target: overlayFeatureFormDrawer

    function onClosed() {
      if (pendingAttachmentRefreshId) {
        const objectId = pendingAttachmentRefreshId;
        const objectKind = pendingAttachmentRefreshKind;
        pendingAttachmentRefreshId = "";
        pendingAttachmentRefreshKind = "";
        Qt.callLater(function () {
          if (waterworksProjectReady) {
            openAttachmentPanel(objectId, objectKind);
          }
        });
      }
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

  function businessFieldAliases(tableName) {
    const aliases = {
      "asset_types": {"code":"类型代码","label":"类型名称","symbol_shape":"符号形状","symbol_color":"符号颜色","symbol_size":"符号大小","sort_order":"排序","active":"启用"},
      "assets_point": {"code":"设施编号","name":"点位名称","asset_type":"设施类型 *","status":"状态","pipeline_id":"所属管线","area_name":"所属片区","address_hint":"位置描述","install_date":"安装日期","last_inspection_at":"最近巡检","note":"备注","created_at":"创建时间","updated_at":"更新时间"},
      "pipelines": {"code":"管线编号","name":"管线名称","pipe_type":"管线类型","material":"材质","diameter_mm":"管径（mm）","pressure_zone":"压力分区","status":"状态","install_date":"安装日期","last_inspection_at":"最近巡检","note":"备注","created_at":"创建时间","updated_at":"更新时间"},
      "inspections": {"asset_id":"所属设施","pipeline_id":"所属管线","inspected_at":"巡检时间","inspector":"巡检人员","result":"巡检结果","pressure_value":"压力值","issue":"发现问题","action_taken":"现场处理","note":"备注","position_accuracy_m":"定位精度（m）","created_at":"创建时间"},
      "repairs": {"asset_id":"所属设施","pipeline_id":"所属管线","inspection_id":"来源巡检","reported_at":"报修时间","repaired_at":"完成时间","repair_type":"维修类型","description":"维修内容","result":"处理结果","operator":"维修人员","note":"备注"},
      "attachments": {"asset_id":"所属设施","pipeline_id":"所属管线","inspection_id":"所属巡检","repair_id":"所属维修","media_type":"附件类型","photo_path":"照片","video_path":"视频","audio_path":"录音","document_path":"文档","caption":"说明","captured_at":"采集时间","created_at":"创建时间"}
    };
    return aliases[tableName] || {};
  }

  function assetTypeValueMap() {
    const layer = assetTypeLayer();
    const mappings = [];
    if (!layer) {
      return {"map": mappings};
    }

    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, "\"active\" = 1");
    while (iterator.hasNext()) {
      const feature = iterator.next();
      const code = String(feature.attribute("code") || "");
      const label = String(feature.attribute("label") || code);
      if (code.length > 0) {
        const entry = {};
        entry[label] = code;
        mappings.push(entry);
      }
    }
    iterator.close();
    return {"map": mappings};
  }

  function configureBusinessLayer(layer, tableName) {
    if (!layer) {
      return false;
    }

    const displayExpressions = {
      "asset_types": "\"label\"",
      "assets_point": "coalesce(\"name\", '未命名点位') || CASE WHEN coalesce(\"code\", '') <> '' THEN ' [' || \"code\" || ']' ELSE '' END",
      "pipelines": "coalesce(\"name\", '未命名管线') || CASE WHEN coalesce(\"code\", '') <> '' THEN ' [' || \"code\" || ']' ELSE '' END",
      "inspections": "coalesce(\"inspector\", '未填写人员') || ' · ' || coalesce(to_string(\"inspected_at\"), '未填写时间')",
      "repairs": "coalesce(\"repair_type\", '维修') || ' · ' || coalesce(to_string(\"reported_at\"), '未填写时间')",
      "attachments": "coalesce(\"caption\", \"photo_path\", \"video_path\", \"audio_path\", \"document_path\", '附件')"
    };
    QfLayerUtils.setLayerDisplayExpression(layer, displayExpressions[tableName] || "");

    const aliases = businessFieldAliases(tableName);
    for (const fieldName in aliases) {
      QfLayerUtils.configureField(layer, fieldName, aliases[fieldName]);
    }

    const hiddenFields = {
      "asset_types": ["fid"],
      "assets_point": ["fid", "id", "pipeline_id", "last_inspection_at", "created_at", "updated_at"],
      "pipelines": ["fid", "id", "last_inspection_at", "created_at", "updated_at"],
      "inspections": ["fid", "id", "asset_id", "pipeline_id", "created_at"],
      "repairs": ["fid", "id", "asset_id", "pipeline_id", "inspection_id"],
      "attachments": ["fid", "id", "asset_id", "pipeline_id", "inspection_id", "repair_id", "created_at"]
    };
    const hidden = hiddenFields[tableName] || [];
    for (let i = 0; i < hidden.length; i++) {
      QfLayerUtils.configureField(layer, hidden[i], "", "Hidden", {});
    }

    const defaults = {
      "assets_point": {"id":"uuid('WithoutBraces')","created_at":"now()"},
      "pipelines": {"id":"uuid('WithoutBraces')","created_at":"now()"},
      "inspections": {"id":"uuid('WithoutBraces')","inspected_at":"now()","created_at":"now()"},
      "repairs": {"id":"uuid('WithoutBraces')","reported_at":"now()"},
      "attachments": {"id":"uuid('WithoutBraces')","captured_at":"now()","created_at":"now()"}
    };
    const tableDefaults = defaults[tableName] || {};
    for (const fieldName in tableDefaults) {
      QfLayerUtils.configureField(layer, fieldName, "", "", {}, tableDefaults[fieldName]);
    }

    const statusMap = {"map":[{"正常":"normal"},{"需关注":"attention"},{"待维修":"repair"},{"停用":"disabled"}]};
    if (tableName === "assets_point" || tableName === "pipelines") {
      QfLayerUtils.configureField(layer, "status", "", "ValueMap", statusMap);
      if (tableName === "assets_point") {
        QfLayerUtils.configureField(layer, "asset_type", "设施类型 *", "ValueMap", assetTypeValueMap());
      }
    } else if (tableName === "inspections") {
      QfLayerUtils.configureField(layer, "result", "", "ValueMap", {"map":[{"正常":"normal"},{"需关注":"attention"},{"待维修":"repair"}]});
      QfLayerUtils.configureField(layer, "position_accuracy_m", "", "", {}, "", true);
    } else if (tableName === "repairs") {
      QfLayerUtils.configureField(layer, "result", "", "ValueMap", {"map":[{"已解决":"resolved"},{"继续观察":"monitor"},{"未解决":"unresolved"}]});
    } else if (tableName === "attachments") {
      QfLayerUtils.configureField(layer, "media_type", "", "ValueMap", {"map":[{"照片":"photo"},{"视频":"video"},{"录音":"audio"},{"文档":"document"}]});
      const baseResourceConfig = {"StorageMode":0,"RelativeStorage":1,"UseLink":false,"FullUrl":false,"DocumentViewerWidth":0,"DocumentViewerHeight":0};
      QfLayerUtils.configureField(layer, "photo_path", "", "ExternalResource", Object.assign({}, baseResourceConfig, {"DocumentViewer":1}));
      QfLayerUtils.configureField(layer, "video_path", "", "ExternalResource", Object.assign({}, baseResourceConfig, {"DocumentViewer":4}));
      QfLayerUtils.configureField(layer, "audio_path", "", "ExternalResource", Object.assign({}, baseResourceConfig, {"DocumentViewer":3}));
      QfLayerUtils.configureField(layer, "document_path", "", "ExternalResource", Object.assign({}, baseResourceConfig, {"DocumentViewer":0}));
      QfLayerUtils.setLayerCustomProperty(layer, "QFieldSync/attachment_naming", JSON.stringify({
        "photo_path":"'attachments/photos/' || coalesce(\"asset_id\", \"pipeline_id\", \"inspection_id\", \"repair_id\") || '/' || uuid('WithoutBraces') || '.{extension}'",
        "video_path":"'attachments/videos/' || coalesce(\"asset_id\", \"pipeline_id\", \"inspection_id\", \"repair_id\") || '/' || uuid('WithoutBraces') || '.{extension}'",
        "audio_path":"'attachments/audio/' || coalesce(\"asset_id\", \"pipeline_id\", \"inspection_id\", \"repair_id\") || '/' || uuid('WithoutBraces') || '.{extension}'",
        "document_path":"'attachments/documents/' || coalesce(\"asset_id\", \"pipeline_id\", \"inspection_id\", \"repair_id\") || '/' || uuid('WithoutBraces') || '_{filename}'"
      }));
    }

    if (tableName === "assets_point" || tableName === "pipelines") {
      QfLayerUtils.setDefaultRenderer(layer, qgisProject);
    }
    if (tableName === "assets_point") {
      QfLayerUtils.setDefaultLabeling(layer, qgisProject);
    }
    QfLayerUtils.triggerLayerRepaint(layer);
    return true;
  }

  function addBusinessLayer(databasePath, tableName, displayName) {
    let layer = null;
    const namedLayers = qgisProject.mapLayersByName(displayName);
    const tableLayers = qgisProject.mapLayersByName(tableName);
    if (namedLayers && namedLayers.length > 0) {
      layer = namedLayers[0];
    } else if (tableLayers && tableLayers.length > 0) {
      layer = tableLayers[0];
    }

    if (!layer) {
      layer = QfLayerUtils.loadVectorLayer(
        databasePath + "|layername=" + tableName,
        displayName,
        "ogr"
      );
      if (!layer || !layer.isValid || !QfProjectUtils.addMapLayer(qgisProject, layer)) {
        return false;
      }
    }

    return configureBusinessLayer(layer, tableName);
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
    const mapThemeContainer = iface.findItemByObjectName("mapThemeContainer");
    const legendContainer = iface.findItemByObjectName("legendContainer");
    const locationMarker = iface.findItemByObjectName("locationMarker");
    const qfieldSettings = iface.findItemByObjectName("qfieldSettings");
    const welcomeCloud = iface.findItemByObjectName("welcomeActionCloud");
    const welcomeNewProject = iface.findItemByObjectName("welcomeActionNewProject");
    const welcomeLocalProjects = iface.findItemByObjectName("welcomeActionLocalProjects");
    const gnssCursorLockButton = iface.findItemByObjectName("gnssCursorLockButton");
    const gnssCanvasLockButton = iface.findItemByObjectName("gnssCanvasLockButton");
    const addBookmarkAtCurrentLocationButton = iface.findItemByObjectName("addBookmarkAtCurrentLocationButton");
    const gnssTrackingButton = iface.findItemByObjectName("gnssTrackingButton");

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
    if (dashBoard) {
      dashBoard.allowActiveLayerChange = false;
      dashBoard.allowInteractive = false;
      if (dashBoard.opened) {
        dashBoard.close();
      }
    }
    if (mapThemeContainer) {
      mapThemeContainer.visible = false;
    }
    if (legendContainer) {
      legendContainer.visible = false;
    }
    if (locationMarker) {
      locationMarker.userVisible = workerAppSettings.showMyLocationMarker;
    }
    if (qfieldSettings) {
      qfieldSettings.autoOpenFormSingleIdentify = true;
      qfieldSettings.autoZoomToIdentifiedFeature = true;
    }
    if (featureForm) {
      featureForm.allowEdit = workerAppSettings.editEnabled;
      featureForm.allowDelete = false;
      featureForm.allowProcessing = false;
    }
    if (gnssCursorLockButton) {
      gnssCursorLockButton.visible = false;
    }
    if (gnssCanvasLockButton) {
      gnssCanvasLockButton.visible = false;
    }
    if (addBookmarkAtCurrentLocationButton) {
      addBookmarkAtCurrentLocationButton.visible = false;
    }
    if (gnssTrackingButton) {
      gnssTrackingButton.visible = false;
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

  function bundledTiandituToken() {
    return String(TiandituConfig.token() || "").trim();
  }

  function effectiveTiandituToken() {
    const localToken = String(workerAppSettings.tiandituToken || "").trim();
    return localToken.length > 0 ? localToken : bundledTiandituToken();
  }

  function hasBundledTiandituToken() {
    return bundledTiandituToken().length > 0;
  }

  function hasTiandituToken() {
    return effectiveTiandituToken().length > 0;
  }

  function tiandituNationalXyzSource(serviceName) {
    const token = effectiveTiandituToken();
    if (!token) {
      return "";
    }

    const layerName = String(serviceName || "").split("_")[0];
    const tileUrl = "https://t0.tianditu.gov.cn/" + serviceName +
                    "/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0" +
                    "&LAYER=" + layerName +
                    "&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles" +
                    "&TILECOL={x}&TILEROW={y}&TILEMATRIX={z}" +
                    "&tk=" + encodeURIComponent(token);

    return "type=xyz&tilePixelRatio=1&url=" + encodeURIComponent(tileUrl) +
           "&zmin=1&zmax=18&crs=EPSG3857";
  }

  function initialBasemapMode() {
    if (!workerAppSettings.basemapPreferenceInitialized) {
      workerAppSettings.basemapPreferenceInitialized = true;
      workerAppSettings.basemapMode = hasTiandituToken() ? "tdt-vector" : "osm";
    }
    return workerAppSettings.basemapMode || (hasTiandituToken() ? "tdt-vector" : "osm");
  }

  function basemapModeLabel(mode) {
    if (mode === "tdt-vector") {
      return "天地图矢量";
    }
    if (mode === "tdt-imagery") {
      return "天地图影像";
    }
    return "OSM";
  }

  function replaceManagedBasemap(definitions) {
    const result = QfProjectUtils.replaceBasemapLayers(
      qgisProject,
      managedBasemapLayerNames,
      definitions,
      true
    );
    return result || {"success": false, "error": "底图切换失败"};
  }

  function applyBasemap(mode, showToast) {
    if (!qgisProject || !qgisProject.fileName) {
      return false;
    }

    let requestedMode = mode || initialBasemapMode();
    if (requestedMode !== "osm" && !hasTiandituToken()) {
      if (showToast) {
        mainWindow.displayToast("天地图密钥不可用，无法切换");
      }
      return false;
    }

    let definitions = [];
    if (requestedMode === "tdt-vector") {
      definitions = [
        {
          "kind": "raster",
          "name": "供水底图 天地图矢量注记",
          "source": tiandituNationalXyzSource("cva_w"),
          "provider": "wms"
        },
        {
          "kind": "raster",
          "name": "供水底图 天地图矢量",
          "source": tiandituNationalXyzSource("vec_w"),
          "provider": "wms"
        }
      ];
    } else if (requestedMode === "tdt-imagery") {
      definitions = [
        {
          "kind": "raster",
          "name": "供水底图 天地图影像注记",
          "source": tiandituNationalXyzSource("cia_w"),
          "provider": "wms"
        },
        {
          "kind": "raster",
          "name": "供水底图 天地图影像",
          "source": tiandituNationalXyzSource("img_w"),
          "provider": "wms"
        }
      ];
    } else {
      requestedMode = "osm";
      definitions = [{
        "kind": "raster",
        "name": "供水底图 OSM",
        "source": fallbackBasemapSource,
        "provider": "wms"
      }];
    }

    const result = replaceManagedBasemap(definitions);
    const ok = !!result.success;
    if (!ok) {
      if (showToast) {
        mainWindow.displayToast("底图切换失败：" + String(result.error || "图层无效"));
      }
      return false;
    }

    workerAppSettings.basemapMode = requestedMode;
    if (showToast) {
      mainWindow.displayToast("已切换到底图：" + basemapModeLabel(requestedMode));
    }
    return true;
  }

  function saveLocalTiandituToken(value) {
    const token = String(value || "").trim();
    if (!token) {
      mainWindow.displayToast("请输入天地图密钥");
      return false;
    }
    workerAppSettings.tiandituToken = token;
    mainWindow.displayToast("天地图密钥已保存在本机，不会在界面明文显示");
    return true;
  }

  function clearLocalTiandituToken() {
    workerAppSettings.tiandituToken = "";
    workerAppSettings.basemapMode = "osm";
    applyBasemap("osm", false);
    mainWindow.displayToast(hasBundledTiandituToken()
                            ? "已清除本机密钥，将继续使用构建时安全配置"
                            : "已清除本机天地图密钥并切回 OSM");
  }

  function chooseWaterworksProject() {
    closeTransientPanels();
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

  function editAllowed(actionName) {
    if (workerAppSettings.editEnabled) {
      return true;
    }
    mainWindow.displayToast((actionName || "该操作") + "需要先切换到编辑模式");
    return false;
  }

  function setEditEnabled(enabled) {
    workerAppSettings.editEnabled = enabled;
    if (featureForm) {
      featureForm.allowEdit = enabled;
      featureForm.allowDelete = false;
      featureForm.allowProcessing = false;
      if (!enabled && featureForm.state === "FeatureFormEdit") {
        featureForm.state = "FeatureForm";
      }
    }
    mainWindow.displayToast(enabled ? "已进入编辑模式，可以新增和修改数据" : "已进入查看模式，数据不会被修改");
  }

  function closeTransientPanels() {
    if (browserDrawer && browserDrawer.opened) {
      browserDrawer.close();
    }
    if (addDrawer && addDrawer.opened) {
      addDrawer.close();
    }
    if (moreDrawer && moreDrawer.opened) {
      moreDrawer.close();
    }
    if (attachmentDrawer && attachmentDrawer.opened) {
      attachmentDrawer.close();
    }
  }

  function clearQueryHighlight() {
    const points = assetLayer();
    const pipes = pipelineLayer();
    if (points) {
      QfLayerUtils.clearLayerSelection(points);
    }
    if (pipes) {
      QfLayerUtils.clearLayerSelection(pipes);
    }
  }

  function openBrowser(mode) {
    queryMode = mode;
    queryObjectKind = "asset";
    queryFiltersExpanded = false;
    assetSearchResults.clear();
    clearQueryHighlight();
    browserDrawer.open();
    if (mode === "nearby") {
      Qt.callLater(function () {
        loadNearbyKind("asset");
      });
    }
  }

  function openAddPanel() {
    if (!editAllowed("新增")) {
      return;
    }
    addDrawer.open();
  }

  function setMyLocationMarkerVisible(visible) {
    workerAppSettings.showMyLocationMarker = visible;
    const locationMarker = iface.findItemByObjectName("locationMarker");
    if (locationMarker) {
      locationMarker.userVisible = visible;
    }
    mainWindow.displayToast(visible ? "已显示我的位置标记" : "已隐藏我的位置标记，定位仍保持开启");
  }

  function centerOnCurrentPosition() {
    const gnssButton = iface.findItemByObjectName("gnssButton");
    if (!gnssButton) {
      mainWindow.displayToast("当前版本无法调用定位按钮");
      return;
    }

    closeTransientPanels();
    gnssButton.clicked();
  }

  function loadNearbyKind(objectKind) {
    queryObjectKind = objectKind;
    const item = nearbyRadiusFilter.model[nearbyRadiusFilter.currentIndex];
    loadNearbyObjects(item.value, objectKind);
  }

  function startPipelineCapture() {
    if (!editAllowed("新建管线")) {
      return;
    }
    const layer = pipelineLayer();
    const digitizingToolbar = iface.findItemByObjectName("digitizingToolbar");
    if (!layer || !digitizingToolbar) {
      mainWindow.displayToast("当前供水数据无法开始画管线");
      return;
    }

    pendingPipelineGeometry = null;
    closeTransientPanels();
    digitizingToolbar.geometryRequestedLayer = layer;
    digitizingToolbar.geometryRequestedItem = pipelineGeometryReceiver;
    digitizingToolbar.geometryRequested = true;
    mainWindow.displayToast("依次点击管线经过的位置，完成后点右下角 ✓");
  }

  function savePipelineEntry() {
    if (!editAllowed("保存管线")) {
      return;
    }
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

    QfLayerUtils.triggerLayerRepaint(layer);
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

    closeTransientPanels();
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
    return queryObjectKind;
  }

  function selectedAssetType() {
    if (!searchAssetTypeFilter || searchAssetTypeFilter.currentIndex < 0) {
      return "";
    }
    const item = assetTypeOptions.get(searchAssetTypeFilter.currentIndex);
    return item ? String(item.value || "") : "";
  }

  function selectedAssetStatus() {
    if (!searchAssetStatusFilter || searchAssetStatusFilter.currentIndex < 0) {
      return "";
    }
    return searchAssetStatusFilter.model[searchAssetStatusFilter.currentIndex].value;
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
    clearQueryHighlight();
    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, expression);
    let count = 0;

    while (iterator.hasNext() && count < 100) {
      appendSearchResult(iterator.next(), objectKind);
      count++;
    }
    const hasMore = iterator.hasNext();
    iterator.close();

    searchBusy = false;
    if (count > 0) {
      QfLayerUtils.selectFeaturesByExpression(layer, expression);
      QfLayerUtils.triggerLayerRepaint(layer);
      queryResultsView.positionViewAtBeginning();
    }

    if (count === 0) {
      mainWindow.displayToast(objectKind === "pipeline" ? "未找到匹配管线" : "未找到匹配点位");
    } else if (hasMore) {
      mainWindow.displayToast("结果超过 100 条，请缩小筛选范围");
    }
  }

  function loadNearbyObjects(radiusMeters, objectKind) {
    assetSearchResults.clear();
    clearQueryHighlight();

    objectKind = objectKind || selectedSearchKind();
    queryObjectKind = objectKind;
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
    const expression = distanceValueExpression + " <= " + radius;

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
    querySearchField.text = "";
    if (matches.length > 0) {
      QfLayerUtils.selectFeaturesByExpression(layer, expression);
      QfLayerUtils.triggerLayerRepaint(layer);
      queryResultsView.positionViewAtBeginning();
    }

    const objectLabel = objectKind === "pipeline" ? "管线" : "点位";
    if (matches.length === 0) {
      mainWindow.displayToast(radius + " 米内没有" + objectLabel);
    } else {
      mainWindow.displayToast("附近找到 " + matches.length + " 个" + objectLabel + "，地图已高亮，列表在下方");
    }
  }

  function focusedBusinessObjectKind() {
    if (!featureForm || !featureForm.selection || !featureForm.selection.focusedLayer) {
      return "";
    }
    const layerName = String(featureForm.selection.focusedLayer.name || "");
    for (let i = 0; i < assetLayerNames.length; i++) {
      if (layerName === assetLayerNames[i]) {
        return "asset";
      }
    }
    for (let i = 0; i < pipelineLayerNames.length; i++) {
      if (layerName === pipelineLayerNames[i]) {
        return "pipeline";
      }
    }
    return "";
  }

  function focusedBusinessObjectId() {
    if (!featureForm || !featureForm.selection || !featureForm.selection.focusedFeature) {
      return "";
    }
    const value = featureForm.selection.focusedFeature.attribute("id");
    return value === null || value === undefined ? "" : String(value);
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

  function focusObjectOnMap(objectKind, objectId, showToast) {
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    const feature = featureForObjectId(objectKind, objectId);
    if (!layer || !feature || !featureForm) {
      mainWindow.displayToast(objectKind === "pipeline" ? "无法在地图上定位管线" : "无法在地图上定位点位");
      return;
    }

    const escapedId = escapeExpressionString(objectId);
    featureForm.model.setFeatures(layer, "\"id\" = '" + escapedId + "'");
    featureForm.selection.focusedItem = 0;
    if (featureForm.extentController) {
      featureForm.extentController.zoomToAllFeatures();
    }
    featureForm.state = "Hidden";
    closeTransientPanels();
    if (showToast !== false) {
      mainWindow.displayToast(objectKind === "pipeline" ? "已定位到管线，点击地图对象可查看详情" : "已定位到点位，点击地图标记可查看详情");
    }
  }

  function navigateToAsset(assetId) {
    const layer = assetLayer();
    const feature = featureForObjectId("asset", assetId);
    if (!layer || !feature || !navigation) {
      mainWindow.displayToast("无法开始点位导航");
      return;
    }

    navigation.setDestinationFeature(feature, layer);
    closeTransientPanels();
    mainWindow.displayToast("开始导航：" + QfFeatureUtils.displayName(layer, feature));
  }

  function openObject(objectKind, objectId, editMode) {
    if (editMode && !editAllowed("编辑")) {
      editMode = false;
    }
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    if (!layer || !featureForm || !objectId) {
      mainWindow.displayToast(objectKind === "pipeline" ? "无法打开管线" : "无法打开点位");
      return;
    }

    const escapedId = escapeExpressionString(objectId);
    featureForm.model.setFeatures(layer, "\"id\" = '" + escapedId + "'");
    featureForm.selection.focusedItem = 0;
    featureForm.state = editMode ? "FeatureFormEdit" : "FeatureForm";
    closeTransientPanels();
  }

  function newObjectId() {
    const value = nearbyDistanceEvaluator.evaluate("uuid('WithoutBraces')");
    return value === null || value === undefined ? "" : String(value).replace(/[{}]/g, "");
  }

  function clearPendingAssetPhotos(deleteFiles) {
    if (deleteFiles) {
      for (let i = 0; i < pendingAssetPhotoPaths.length; i++) {
        const path = String(pendingAssetPhotoPaths[i] || "");
        if (path.length > 0 && QfFileUtils.fileExists(path)) {
          platformUtilities.rmFile(path);
        }
      }
    }
    pendingAssetPhotoPaths = [];
  }

  function startAssetPhotoCapture() {
    if (!pendingAssetGeometry || assetPhotoCameraLoader.active) {
      return;
    }

    Qt.inputMethod.hide();
    platformUtilities.createDir(qgisProject.homePath, "DCIM");
    assetPhotoCameraLoader.active = true;
  }

  function savePendingAssetPhotos(assetId) {
    const sourcePaths = pendingAssetPhotoPaths.slice(0);
    if (sourcePaths.length === 0) {
      return 0;
    }

    const layer = attachmentLayer();
    if (!layer || !assetId) {
      return -1;
    }

    let savedCount = 0;
    for (let i = 0; i < sourcePaths.length; i++) {
      const sourcePath = String(sourcePaths[i] || "");
      if (!sourcePath || !QfFileUtils.fileExists(sourcePath)) {
        continue;
      }

      const attachmentId = newObjectId();
      if (!attachmentId) {
        continue;
      }

      const suffix = QfFileUtils.fileSuffix(sourcePath) || "jpg";
      const relativePath = "attachments/photos/" + assetId + "/" + attachmentId + "." + String(suffix).toLowerCase();
      const targetPath = qgisProject.homePath + "/" + relativePath;
      if (!QfFileUtils.copyFile(sourcePath, targetPath, false)) {
        continue;
      }

      const attachment = QfFeatureUtils.createFeature(layer);
      attachment.setAttribute("id", attachmentId);
      attachment.setAttribute("asset_id", assetId);
      attachment.setAttribute("pipeline_id", null);
      attachment.setAttribute("inspection_id", null);
      attachment.setAttribute("repair_id", null);
      attachment.setAttribute("media_type", "photo");
      attachment.setAttribute("photo_path", relativePath);
      attachment.setAttribute("video_path", null);
      attachment.setAttribute("audio_path", null);
      attachment.setAttribute("document_path", null);

      if (QfLayerUtils.addFeature(layer, attachment)) {
        savedCount++;
        platformUtilities.rmFile(sourcePath);
      } else {
        platformUtilities.rmFile(targetPath);
      }
    }

    return savedCount;
  }

  function createAssetAtCurrentPosition() {
    if (!editAllowed("新增点位")) {
      return;
    }
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

    clearPendingAssetPhotos(true);
    pendingAssetGeometry = QfGeometryUtils.createGeometryFromWkt(
      "POINT(" + Number(info.longitude) + " " + Number(info.latitude) + ")"
    );
    assetEntryDialog.open();
  }

  function saveAssetEntry() {
    if (!editAllowed("保存点位")) {
      return;
    }
    const layer = assetLayer();
    if (!layer || !pendingAssetGeometry) {
      mainWindow.displayToast("无法保存点位");
      return;
    }

    const assetId = newObjectId();
    if (!assetId) {
      mainWindow.displayToast("无法生成点位编号");
      return;
    }

    const typeItem = assetTypeOptions.get(assetEntryType.currentIndex);
    if (!typeItem || !typeItem.value) {
      mainWindow.displayToast("请选择设施类型（* 必填）");
      return;
    }

    const feature = QfFeatureUtils.createFeature(layer, pendingAssetGeometry);
    feature.setAttribute("id", assetId);
    feature.setAttribute("asset_type", String(typeItem.value));
    feature.setAttribute("name", assetEntryName.text.trim());
    feature.setAttribute("code", assetEntryCode.text.trim());
    feature.setAttribute("area_name", assetEntryArea.text.trim());
    feature.setAttribute("address_hint", assetEntryAddress.text.trim());
    feature.setAttribute("note", assetEntryNote.text.trim());

    if (!QfLayerUtils.addFeature(layer, feature)) {
      mainWindow.displayToast("点位保存失败");
      return;
    }

    const photoCount = pendingAssetPhotoPaths.length;
    const savedPhotoCount = savePendingAssetPhotos(assetId);
    QfLayerUtils.triggerLayerRepaint(layer);
    clearPendingAssetPhotos(false);
    pendingAssetGeometry = null;
    assetEntryDialog.close();

    if (savedPhotoCount < 0) {
      mainWindow.displayToast("点位已保存，但附件图层不可用，照片未写入记录");
    } else if (savedPhotoCount !== photoCount) {
      mainWindow.displayToast("点位已保存，" + savedPhotoCount + "/" + photoCount + " 张照片已保存");
    } else if (photoCount > 0) {
      mainWindow.displayToast("点位和 " + photoCount + " 张照片已保存");
    } else {
      mainWindow.displayToast("点位已保存");
    }

    Qt.callLater(function () {
      focusObjectOnMap("asset", assetId, false);
      mainWindow.displayToast("点位已保存并标记在地图上，点击标记可查看详情");
    });
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

  function parentExpression(objectId, objectKind) {
    const fieldName = objectKind === "pipeline" ? "pipeline_id" : "asset_id";
    return "\"" + fieldName + "\" = '" + escapeExpressionString(objectId) + "'";
  }

  function countMatches(layer, expression) {
    if (!layer) {
      return 0;
    }
    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, expression);
    let count = 0;
    while (iterator.hasNext()) {
      iterator.next();
      count++;
    }
    iterator.close();
    return count;
  }

  function attachmentRelativePath(feature) {
    const mediaType = String(feature.attribute("media_type") || "");
    const fieldName = mediaType === "video" ? "video_path" :
                      mediaType === "audio" ? "audio_path" :
                      mediaType === "document" ? "document_path" : "photo_path";
    const value = feature.attribute(fieldName);
    return value === null || value === undefined ? "" : String(value);
  }

  function attachmentAbsolutePath(relativePath) {
    const value = String(relativePath || "");
    if (!value) {
      return "";
    }
    if (value.indexOf("file://") === 0) {
      return QfUrlUtils.toLocalFile(value);
    }
    if (value.indexOf("/") === 0 || /^[A-Za-z]:[\\/]/.test(value)) {
      return value;
    }
    return qgisProject.homePath + "/" + value;
  }

  function attachmentUrl(relativePath) {
    const path = attachmentAbsolutePath(relativePath);
    return path ? QfUrlUtils.fromString(path) : "";
  }

  function attachmentTypeLabel(mediaType) {
    switch (String(mediaType || "")) {
    case "video":
      return "视频";
    case "audio":
      return "录音";
    case "document":
      return "文档";
    default:
      return "照片";
    }
  }

  function loadAttachments(objectId, objectKind) {
    attachmentItems.clear();
    const layer = attachmentLayer();
    if (!layer || !objectId) {
      return;
    }
    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, parentExpression(objectId, objectKind));
    while (iterator.hasNext()) {
      const feature = iterator.next();
      const mediaType = String(feature.attribute("media_type") || "photo");
      const relativePath = attachmentRelativePath(feature);
      const caption = feature.attribute("caption");
      const capturedAt = feature.attribute("captured_at");
      attachmentItems.append({
        "attachmentId": String(feature.attribute("id") || ""),
        "mediaType": mediaType,
        "relativePath": relativePath,
        "caption": caption === null || caption === undefined ? "" : String(caption),
        "capturedAt": capturedAt === null || capturedAt === undefined ? "" : String(capturedAt)
      });
    }
    iterator.close();
  }

  function openAttachmentPanel(objectId, objectKind) {
    if (!objectId) {
      mainWindow.displayToast("无法确定附件所属对象");
      return;
    }
    closeTransientPanels();
    attachmentObjectId = objectId;
    attachmentObjectKind = objectKind;
    loadAttachments(objectId, objectKind);
    attachmentDrawer.open();
  }

  function configureAttachmentCaptureMode(mediaType) {
    const layer = attachmentLayer();
    if (!layer) {
      return;
    }
    const configs = {
      "photo": ["photo_path", 1],
      "video": ["video_path", 4],
      "audio": ["audio_path", 3],
      "document": ["document_path", 0]
    };
    const selected = configs[mediaType] || configs["photo"];
    const baseConfig = {"StorageMode":0,"RelativeStorage":1,"UseLink":false,"FullUrl":false,"DocumentViewerWidth":0,"DocumentViewerHeight":0};
    const fields = [
      ["photo_path", 1],
      ["video_path", 4],
      ["audio_path", 3],
      ["document_path", 0]
    ];
    QfLayerUtils.configureField(layer, "media_type", "", "Hidden", {});
    for (let i = 0; i < fields.length; i++) {
      const field = fields[i][0];
      if (field === selected[0]) {
        const config = {
          "StorageMode": baseConfig.StorageMode,
          "RelativeStorage": baseConfig.RelativeStorage,
          "UseLink": baseConfig.UseLink,
          "FullUrl": baseConfig.FullUrl,
          "DocumentViewerWidth": baseConfig.DocumentViewerWidth,
          "DocumentViewerHeight": baseConfig.DocumentViewerHeight,
          "DocumentViewer": fields[i][1]
        };
        QfLayerUtils.configureField(layer, field, "", "ExternalResource", config);
      } else {
        QfLayerUtils.configureField(layer, field, "", "Hidden", {});
      }
    }
  }

  function requestDeleteBusinessObject(objectId, objectKind) {
    if (!editAllowed("删除")) {
      return;
    }
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    const feature = featureForObjectId(objectKind, objectId);
    if (!layer || !feature) {
      mainWindow.displayToast("无法找到要删除的对象");
      return;
    }

    const parentExpr = parentExpression(objectId, objectKind);
    const hasInspection = countMatches(inspectionLayer(), parentExpr) > 0;
    const hasRepair = countMatches(repairLayer(), parentExpr) > 0;
    const hasLinkedAssets = objectKind === "pipeline" &&
      countMatches(assetLayer(), "\"pipeline_id\" = '" + escapeExpressionString(objectId) + "'") > 0;

    if (hasInspection || hasRepair || hasLinkedAssets) {
      const reason = hasLinkedAssets ? "该管线仍有关联点位" : "该对象已经有巡检或维修历史";
      mainWindow.displayToast(reason + "，不能直接删除；如已停用，请在编辑中把状态改为“停用”");
      return;
    }

    pendingDeleteObjectId = objectId;
    pendingDeleteObjectKind = objectKind;
    pendingDeleteAttachmentCount = countMatches(attachmentLayer(), parentExpr);
    const nameValue = feature.attribute("name");
    const codeValue = feature.attribute("code");
    pendingDeleteObjectName = String(nameValue || codeValue || (objectKind === "pipeline" ? "该管线" : "该点位"));
    deleteObjectDialog.open();
  }

  function confirmDeleteBusinessObject() {
    const objectId = pendingDeleteObjectId;
    const objectKind = pendingDeleteObjectKind;
    const layer = objectKind === "pipeline" ? pipelineLayer() : assetLayer();
    const attachments = attachmentLayer();
    if (!objectId || !layer) {
      deleteObjectDialog.close();
      return;
    }

    const parentExpr = parentExpression(objectId, objectKind);
    const files = [];
    if (attachments) {
      const iterator = QfLayerUtils.createFeatureIteratorFromExpression(attachments, parentExpr);
      while (iterator.hasNext()) {
        const path = attachmentRelativePath(iterator.next());
        if (path) {
          files.push(attachmentAbsolutePath(path));
        }
      }
      iterator.close();

      if (QfLayerUtils.deleteFeaturesByExpression(qgisProject, attachments, parentExpr) < 0) {
        mainWindow.displayToast("删除附件记录失败，对象未删除");
        deleteObjectDialog.close();
        return;
      }
    }

    const deleted = QfLayerUtils.deleteFeaturesByExpression(
      qgisProject,
      layer,
      "\"id\" = '" + escapeExpressionString(objectId) + "'"
    );
    if (deleted !== 1) {
      mainWindow.displayToast("删除失败，数据仍保留");
      deleteObjectDialog.close();
      return;
    }

    for (let i = 0; i < files.length; i++) {
      if (files[i] && QfFileUtils.fileExists(files[i])) {
        platformUtilities.rmFile(files[i]);
      }
    }

    QfLayerUtils.triggerLayerRepaint(layer);
    if (attachments) {
      QfLayerUtils.triggerLayerRepaint(attachments);
    }
    if (featureForm) {
      featureForm.state = "Hidden";
    }
    deleteObjectDialog.close();
    mainWindow.displayToast(objectKind === "pipeline" ? "管线已删除" : "点位已删除");
    pendingDeleteObjectId = "";
    pendingDeleteObjectKind = "";
    pendingDeleteObjectName = "";
    pendingDeleteAttachmentCount = 0;
  }

  function createInspection(objectId, objectKind) {
    if (!editAllowed("巡检记录")) {
      return;
    }
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

    overlayFeatureFormDrawer.featureModel.currentLayer = layer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    closeTransientPanels();
    overlayFeatureFormDrawer.open();
  }

  function createRepair(objectId, objectKind) {
    if (!editAllowed("维修记录")) {
      return;
    }
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

    overlayFeatureFormDrawer.featureModel.currentLayer = layer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    closeTransientPanels();
    overlayFeatureFormDrawer.open();
  }

  function capturedAttachmentField(mediaType) {
    switch (mediaType) {
    case "video":
      return "video_path";
    case "audio":
      return "audio_path";
    case "document":
      return "document_path";
    default:
      return "photo_path";
    }
  }

  function capturedAttachmentFolder(mediaType) {
    switch (mediaType) {
    case "video":
      return "attachments/videos/";
    case "audio":
      return "attachments/audio/";
    case "document":
      return "attachments/documents/";
    default:
      return "attachments/photos/";
    }
  }

  function capturedAttachmentDefaultSuffix(mediaType) {
    switch (mediaType) {
    case "video":
      return "mp4";
    case "audio":
      return "m4a";
    default:
      return "jpg";
    }
  }

  function saveCapturedAttachment(sourcePath, mediaType) {
    const layer = attachmentLayer();
    const objectId = attachmentObjectId;
    const objectKind = attachmentObjectKind;
    if (!layer || !objectId || !sourcePath) {
      mainWindow.displayToast("附件保存失败：缺少目标对象或文件");
      return false;
    }

    const localSource = String(sourcePath).indexOf("file://") === 0
      ? QfUrlUtils.toLocalFile(String(sourcePath))
      : String(sourcePath);
    if (!QfFileUtils.fileExists(localSource)) {
      mainWindow.displayToast("附件保存失败：采集文件不存在");
      return false;
    }

    const attachmentId = newObjectId();
    if (!attachmentId) {
      mainWindow.displayToast("附件保存失败：无法生成编号");
      return false;
    }

    const suffix = String(QfFileUtils.fileSuffix(localSource) || capturedAttachmentDefaultSuffix(mediaType)).toLowerCase();
    const relativePath = capturedAttachmentFolder(mediaType) + objectId + "/" + attachmentId + "." + suffix;
    const targetPath = qgisProject.homePath + "/" + relativePath;
    if (!QfFileUtils.copyFile(localSource, targetPath, false)) {
      mainWindow.displayToast("附件保存失败：无法写入项目目录");
      return false;
    }

    const feature = QfFeatureUtils.createFeature(layer);
    feature.setAttribute("id", attachmentId);
    setParentReference(feature, objectId, objectKind);
    feature.setAttribute("inspection_id", null);
    feature.setAttribute("repair_id", null);
    feature.setAttribute("media_type", mediaType);
    feature.setAttribute("photo_path", null);
    feature.setAttribute("video_path", null);
    feature.setAttribute("audio_path", null);
    feature.setAttribute("document_path", null);
    feature.setAttribute(capturedAttachmentField(mediaType), relativePath);

    if (!QfLayerUtils.addFeature(layer, feature)) {
      platformUtilities.rmFile(targetPath);
      mainWindow.displayToast("附件保存失败：无法写入附件记录");
      return false;
    }

    platformUtilities.rmFile(localSource);
    QfLayerUtils.triggerLayerRepaint(layer);
    loadAttachments(objectId, objectKind);
    mainWindow.displayToast(attachmentTypeLabel(mediaType) + "已添加");
    return true;
  }

  function startAttachmentCapture(mediaType) {
    if (!editAllowed("添加附件")) {
      return;
    }
    if (!attachmentObjectId) {
      mainWindow.displayToast("无法确定附件所属对象");
      return;
    }

    attachmentCaptureMediaType = mediaType;
    if (mediaType === "audio") {
      attachmentAudioRecorderLoader.active = true;
    } else if (mediaType === "photo" || mediaType === "video") {
      attachmentCameraLoader.active = true;
    } else {
      createAttachment(attachmentObjectId, attachmentObjectKind, "document");
    }
  }

  function createAttachment(objectId, objectKind, mediaType) {
    if (!editAllowed("添加附件")) {
      return;
    }
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

    const type = mediaType || "document";
    configureAttachmentCaptureMode(type);
    const feature = QfFeatureUtils.createFeature(layer);
    setParentReference(feature, objectId, objectKind);
    feature.setAttribute("media_type", type);

    pendingAttachmentRefreshId = objectId;
    pendingAttachmentRefreshKind = objectKind;
    overlayFeatureFormDrawer.featureModel.currentLayer = null;
    overlayFeatureFormDrawer.featureModel.currentLayer = layer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    closeTransientPanels();
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

  Loader {
    id: assetPhotoCameraLoader
    active: false
    sourceComponent: assetPhotoCameraComponent
  }

  Component {
    id: assetPhotoCameraComponent

    QfCamera {
      visible: false
      allowCaptureModeToggle: false
      autoAcceptPhoto: true
      currentLayer: assetLayer()

      Component.onCompleted: {
        state = "PhotoCapture";
        open();
      }

      onFinished: path => {
        if (path && path !== "") {
          const paths = pendingAssetPhotoPaths.slice(0);
          paths.push(path);
          pendingAssetPhotoPaths = paths;
        }
        close();
      }

      onCanceled: close()
      onClosed: assetPhotoCameraLoader.active = false
    }
  }

  Loader {
    id: attachmentCameraLoader
    active: false
    sourceComponent: attachmentCameraComponent
  }

  Component {
    id: attachmentCameraComponent

    QfCamera {
      visible: false
      allowCaptureModeToggle: false
      autoAcceptPhoto: attachmentCaptureMediaType === "photo"
      currentLayer: attachmentLayer()

      Component.onCompleted: {
        state = attachmentCaptureMediaType === "video" ? "VideoCapture" : "PhotoCapture";
        open();
      }

      onFinished: path => {
        if (path && path !== "") {
          plugin.saveCapturedAttachment(path, attachmentCaptureMediaType);
        }
        close();
      }

      onCanceled: close()
      onClosed: {
        attachmentCameraLoader.active = false;
        attachmentCaptureMediaType = "";
      }
    }
  }

  Loader {
    id: attachmentAudioRecorderLoader
    active: false
    sourceComponent: attachmentAudioRecorderComponent
  }

  Component {
    id: attachmentAudioRecorderComponent

    QfAudioClipRecorder {
      visible: false

      Component.onCompleted: open()

      onFinished: path => {
        if (path && path !== "") {
          plugin.saveCapturedAttachment(path, "audio");
        }
        close();
      }

      onCanceled: close()
      onClosed: {
        attachmentAudioRecorderLoader.active = false;
        attachmentCaptureMediaType = "";
      }
    }
  }

  QfExpressionEvaluator {
    id: nearbyDistanceEvaluator
    project: qgisProject
  }

  ListModel {
    id: assetTypeOptions
  }

  ListModel {
    id: assetSearchResults
  }

  ListModel {
    id: attachmentItems
  }

  QfDialog {
    id: deleteObjectDialog
    parent: mainWindow.contentItem
    title: "确认删除"
    modal: true
    standardButtons: Dialog.NoButton
    width: Math.min(mainWindow.width - 40, 460)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    ColumnLayout {
      width: parent.width
      spacing: 12

      Label {
        Layout.fillWidth: true
        text: "确定删除“" + pendingDeleteObjectName + "”吗？"
        font.bold: true
        wrapMode: Text.WordWrap
        color: QfTheme.mainTextColor
      }

      Label {
        Layout.fillWidth: true
        text: pendingDeleteAttachmentCount > 0
              ? "将同时删除 " + pendingDeleteAttachmentCount + " 个照片/附件及对应文件。此操作无法恢复。"
              : "此操作无法恢复。"
        wrapMode: Text.WordWrap
        color: QfTheme.secondaryTextColor
      }

      RowLayout {
        Layout.fillWidth: true

        Button {
          Layout.fillWidth: true
          text: "取消"
          onClicked: deleteObjectDialog.close()
        }

        Button {
          Layout.fillWidth: true
          text: "删除"
          onClicked: plugin.confirmDeleteBusinessObject()
        }
      }
    }
  }

  QfDialog {
    id: assetEntryDialog
    parent: mainWindow.contentItem
    title: "新增点位"
    modal: true
    standardButtons: Dialog.NoButton
    width: Math.min(mainWindow.width - 32, 520)
    height: Math.min(mainWindow.height - 48, 680)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    onOpened: {
      loadAssetTypeOptions();
      assetEntryType.currentIndex = 0;
      assetEntryName.clear();
      assetEntryCode.clear();
      assetEntryArea.clear();
      assetEntryAddress.clear();
      assetEntryNote.clear();
    }

    onClosed: {
      if (pendingAssetGeometry || pendingAssetPhotoPaths.length > 0) {
        clearPendingAssetPhotos(true);
        pendingAssetGeometry = null;
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: "设施类型 *"
        font.bold: true
        color: QfTheme.mainTextColor
      }

      ComboBox {
        id: assetEntryType
        Layout.fillWidth: true
        model: assetTypeOptions
        textRole: "text"
      }

      Label {
        Layout.fillWidth: true
        text: "* 为必填；其余信息不知道时可以先不填"
        color: QfTheme.secondaryTextColor
        font.pixelSize: 12
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
        placeholderText: "位置描述（可选），例如：村口向东 20 米"
      }

      RowLayout {
        Layout.fillWidth: true

        Button {
          Layout.fillWidth: true
          text: pendingAssetPhotoPaths.length > 0 ? "继续拍照" : "拍照"
          onClicked: plugin.startAssetPhotoCapture()
        }

        Label {
          text: pendingAssetPhotoPaths.length > 0 ? "已拍 " + pendingAssetPhotoPaths.length + " 张" : "可选"
          color: QfTheme.secondaryTextColor
        }

        Button {
          visible: pendingAssetPhotoPaths.length > 0
          text: "清空"
          onClicked: plugin.clearPendingAssetPhotos(true)
        }
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
          onClicked: assetEntryDialog.close()
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

      Label {
        Layout.fillWidth: true
        text: "管线位置已经画好。下面参数均为可选，不知道时可以直接保存。"
        wrapMode: Text.WordWrap
        color: QfTheme.secondaryTextColor
      }

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
        placeholderText: "管径（可选），例如 300"
        inputMethodHints: Qt.ImhFormattedNumbersOnly
      }

      TextField {
        id: pipelineEntryMaterial
        Layout.fillWidth: true
        placeholderText: "材质（可选），例如 PE / 球墨铸铁"
      }

      TextField {
        id: pipelineEntryType
        Layout.fillWidth: true
        placeholderText: "管线类型（可选），例如 主管 / 支管"
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


  Component {
    id: queryResultDelegate

    Rectangle {
      required property string objectKind
      required property string assetId
      required property string assetName
      required property string assetCode
      required property string assetType
      required property string assetStatus
      required property string assetLastInspection
      required property string assetDetail
      required property int assetDistance

      width: queryResultsView.width
      height: resultColumn.implicitHeight + 20
      radius: 10
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
        spacing: 4

        RowLayout {
          Layout.fillWidth: true

          Label {
            Layout.fillWidth: true
            text: assetName
            font.bold: true
            color: QfTheme.mainTextColor
            elide: Text.ElideRight
          }

          Label {
            text: assetStatus.length > 0 ? plugin.assetStatusLabel(assetStatus) : ""
            color: QfTheme.secondaryTextColor
          }
        }

        Label {
          Layout.fillWidth: true
          text: (assetDistance >= 0 ? assetDistance + " m  ·  " : "") +
                (assetCode.length > 0 ? "编号 " + assetCode + "  ·  " : "") +
                (assetType.length > 0 ? (objectKind === "asset" ? plugin.assetTypeLabel(assetType) : assetType) : "")
          color: QfTheme.secondaryTextColor
          elide: Text.ElideRight
        }

        Label {
          Layout.fillWidth: true
          visible: assetDetail.length > 0 || assetLastInspection.length > 0
          text: (assetDetail.length > 0 ? assetDetail : "") +
                ""
          color: QfTheme.secondaryTextColor
          elide: Text.ElideRight
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Button {
            Layout.fillWidth: true
            text: "地图"
            onClicked: plugin.focusObjectOnMap(objectKind, assetId, true)
          }

          Button {
            Layout.fillWidth: true
            text: "详情"
            onClicked: plugin.openObject(objectKind, assetId, false)
          }

          Button {
            Layout.fillWidth: true
            text: "附件"
            onClicked: plugin.openAttachmentPanel(assetId, objectKind)
          }

          Button {
            Layout.fillWidth: true
            visible: objectKind === "asset"
            text: "导航"
            onClicked: plugin.navigateToAsset(assetId)
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: workerAppSettings.editEnabled
          spacing: 6

          Button {
            Layout.fillWidth: true
            text: "编辑"
            onClicked: plugin.openObject(objectKind, assetId, true)
          }

          Button {
            Layout.fillWidth: true
            text: "删除"
            onClicked: plugin.requestDeleteBusinessObject(assetId, objectKind)
          }
        }
      }
    }
  }

  Button {
    id: editModeButton
    objectName: "waterworksEditModeButton"
    parent: mainWindow.contentItem
    z: 90
    visible: plugin.waterworksProjectReady &&
             (!digitizingToolbar || !digitizingToolbar.geometryRequested) &&
             !attachmentDrawer.opened &&
             (!featureForm || featureForm.state === "Hidden") &&
             (!overlayFeatureFormDrawer || !overlayFeatureFormDrawer.opened) &&
             !assetEntryDialog.visible && !pipelineEntryDialog.visible
    anchors {
      top: parent.top
      right: parent.right
      topMargin: mainWindow.sceneTopMargin + 10
      rightMargin: mainWindow.sceneRightMargin + 10
    }
    text: workerAppSettings.editEnabled ? "编辑模式" : "查看模式"
    font.bold: true
    onClicked: plugin.setEditEnabled(!workerAppSettings.editEnabled)
  }

  Button {
    id: locationMapButton
    objectName: "waterworksLocationButton"
    parent: mainWindow.contentItem
    z: 90
    visible: plugin.waterworksProjectReady && !browserDrawer.opened && !addDrawer.opened && !moreDrawer.opened && !attachmentDrawer.opened &&
             (!digitizingToolbar || !digitizingToolbar.geometryRequested) &&
             (!featureForm || featureForm.state === "Hidden") &&
             (!overlayFeatureFormDrawer || !overlayFeatureFormDrawer.opened) &&
             !assetEntryDialog.visible && !pipelineEntryDialog.visible
    anchors {
      right: parent.right
      bottom: bottomActionBar.top
      rightMargin: mainWindow.sceneRightMargin + 12
      bottomMargin: 10
    }
    text: "定位"
    onClicked: plugin.centerOnCurrentPosition()
  }

  Rectangle {
    id: pipelineDigitizingHint
    objectName: "waterworksPipelineDigitizingHint"
    parent: mainWindow.contentItem
    z: 92
    visible: digitizingToolbar && digitizingToolbar.geometryRequested &&
             digitizingToolbar.geometryRequestedLayer === plugin.pipelineLayer()
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      leftMargin: mainWindow.sceneLeftMargin + 12
      rightMargin: mainWindow.sceneRightMargin + 12
      topMargin: mainWindow.sceneTopMargin + 10
    }
    height: pipelineHintLabel.implicitHeight + 20
    radius: 8
    color: QfTheme.mainBackgroundColor
    border.color: QfTheme.controlBorderColor

    Label {
      id: pipelineHintLabel
      anchors {
        fill: parent
        margins: 10
      }
      text: "新建管线：依次点击地图添加节点（至少 2 个） → 点 ✓ 完成 → 再填写管径、材质等参数"
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      color: QfTheme.mainTextColor
    }
  }

  Rectangle {
    id: bottomActionBar
    objectName: "waterworksBottomActionBar"
    parent: mainWindow.contentItem
    z: 80
    visible: plugin.waterworksProjectReady &&
             !browserDrawer.opened && !addDrawer.opened && !moreDrawer.opened && !attachmentDrawer.opened &&
             (!digitizingToolbar || !digitizingToolbar.geometryRequested) &&
             (!featureForm || featureForm.state === "Hidden") &&
             (!overlayFeatureFormDrawer || !overlayFeatureFormDrawer.opened) &&
             !assetEntryDialog.visible && !pipelineEntryDialog.visible
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
    }
    height: 60 + mainWindow.sceneBottomMargin
    color: QfTheme.mainBackgroundColor
    border.color: QfTheme.controlBorderColor

    RowLayout {
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        leftMargin: mainWindow.sceneLeftMargin + 8
        rightMargin: mainWindow.sceneRightMargin + 8
        topMargin: 6
      }
      spacing: 6

      Button {
        Layout.fillWidth: true
        text: "查找"
        onClicked: plugin.openBrowser("search")
      }

      Button {
        Layout.fillWidth: true
        text: "附近"
        onClicked: plugin.openBrowser("nearby")
      }

      Button {
        Layout.fillWidth: true
        text: "新增"
        enabled: workerAppSettings.editEnabled
        onClicked: plugin.openAddPanel()
      }

      Button {
        Layout.fillWidth: true
        text: "更多"
        onClicked: moreDrawer.open()
      }
    }
  }

  Rectangle {
    id: focusedObjectActionBar
    objectName: "waterworksFocusedObjectActionBar"
    parent: mainWindow.contentItem
    z: 95
    visible: featureForm && featureForm.state === "FeatureForm" &&
             plugin.focusedBusinessObjectKind().length > 0 &&
             plugin.focusedBusinessObjectId().length > 0
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      bottomMargin: featureForm ? featureForm.height + 6 : 6
      leftMargin: mainWindow.sceneLeftMargin + 8
      rightMargin: mainWindow.sceneRightMargin + 8
    }
    height: workerAppSettings.editEnabled ? 96 : 48
    radius: 8
    color: QfTheme.mainBackgroundColor
    border.color: QfTheme.controlBorderColor

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 4
      spacing: 4

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 4

        Button {
          Layout.fillWidth: true
          text: "照片/附件"
          onClicked: plugin.openAttachmentPanel(plugin.focusedBusinessObjectId(), plugin.focusedBusinessObjectKind())
        }

        Button {
          Layout.fillWidth: true
          visible: plugin.focusedBusinessObjectKind() === "asset"
          text: "导航"
          onClicked: plugin.navigateToAsset(plugin.focusedBusinessObjectId())
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: workerAppSettings.editEnabled
        spacing: 4

        Button {
          Layout.fillWidth: true
          text: "编辑"
          onClicked: plugin.openObject(plugin.focusedBusinessObjectKind(), plugin.focusedBusinessObjectId(), true)
        }

        Button {
          Layout.fillWidth: true
          text: "删除"
          onClicked: plugin.requestDeleteBusinessObject(plugin.focusedBusinessObjectId(), plugin.focusedBusinessObjectKind())
        }
      }
    }
  }

  Drawer {
    id: attachmentDrawer
    objectName: "waterworksAttachmentDrawer"
    parent: mainWindow.contentItem
    z: 110
    edge: Qt.BottomEdge
    modal: false
    interactive: true
    width: mainWindow.width
    height: Math.min(mainWindow.height * 0.68, 680)

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
      border.color: QfTheme.controlBorderColor
    }

    ColumnLayout {
      anchors {
        fill: parent
        leftMargin: mainWindow.sceneLeftMargin + 12
        rightMargin: mainWindow.sceneRightMargin + 12
        topMargin: 10
        bottomMargin: mainWindow.sceneBottomMargin + 10
      }
      spacing: 8

      RowLayout {
        Layout.fillWidth: true

        Label {
          Layout.fillWidth: true
          text: "照片 / 附件"
          font.bold: true
          font.pixelSize: 18
          color: QfTheme.mainTextColor
        }

        Button {
          text: "关闭"
          onClicked: attachmentDrawer.close()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: workerAppSettings.editEnabled
        spacing: 5

        Button {
          Layout.fillWidth: true
          text: "拍照"
          onClicked: plugin.startAttachmentCapture("photo")
        }

        Button {
          Layout.fillWidth: true
          text: "视频"
          onClicked: plugin.startAttachmentCapture("video")
        }

        Button {
          Layout.fillWidth: true
          text: "录音"
          onClicked: plugin.startAttachmentCapture("audio")
        }

        Button {
          Layout.fillWidth: true
          text: "文档"
          onClicked: plugin.createAttachment(attachmentObjectId, attachmentObjectKind, "document")
        }
      }

      Label {
        Layout.fillWidth: true
        visible: attachmentItems.count === 0
        text: workerAppSettings.editEnabled ? "还没有附件，可用上面的按钮添加。" : "还没有照片或附件。"
        color: QfTheme.secondaryTextColor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      ListView {
        id: attachmentListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 8
        model: attachmentItems

        delegate: Rectangle {
          required property string attachmentId
          required property string mediaType
          required property string relativePath
          required property string caption
          required property string capturedAt

          width: attachmentListView.width
          height: mediaType === "photo" ? 150 : attachmentInfoColumn.implicitHeight + 24
          radius: 8
          color: QfTheme.groupBoxBackgroundColor
          border.color: QfTheme.controlBorderColor

          RowLayout {
            anchors {
              fill: parent
              margins: 8
            }
            spacing: 10

            Image {
              visible: mediaType === "photo"
              Layout.preferredWidth: visible ? 120 : 0
              Layout.fillHeight: visible
              source: visible ? plugin.attachmentUrl(relativePath) : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
            }

            ColumnLayout {
              id: attachmentInfoColumn
              Layout.fillWidth: true
              spacing: 4

              Label {
                Layout.fillWidth: true
                text: plugin.attachmentTypeLabel(mediaType) + (caption.length > 0 ? " · " + caption : "")
                font.bold: true
                color: QfTheme.mainTextColor
                elide: Text.ElideRight
              }

              Label {
                Layout.fillWidth: true
                text: capturedAt.length > 0 ? capturedAt : relativePath
                color: QfTheme.secondaryTextColor
                elide: Text.ElideRight
              }

              Button {
                Layout.fillWidth: true
                text: mediaType === "photo" ? "查看原图" : "打开" + plugin.attachmentTypeLabel(mediaType)
                enabled: relativePath.length > 0
                onClicked: Qt.openUrlExternally(plugin.attachmentUrl(relativePath))
              }
            }
          }
        }
      }
    }
  }

  Drawer {
    id: browserDrawer
    objectName: "waterworksBrowserDrawer"
    parent: mainWindow.contentItem
    z: 100
    edge: Qt.BottomEdge
    modal: false
    interactive: true
    width: mainWindow.width
    height: Math.min(mainWindow.height * 0.62, 620)

    onClosed: plugin.clearQueryHighlight()

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
      border.color: QfTheme.controlBorderColor
    }

    ColumnLayout {
      anchors {
        fill: parent
        leftMargin: mainWindow.sceneLeftMargin + 12
        rightMargin: mainWindow.sceneRightMargin + 12
        topMargin: 10
        bottomMargin: mainWindow.sceneBottomMargin + 10
      }
      spacing: 8

      RowLayout {
        Layout.fillWidth: true

        Label {
          Layout.fillWidth: true
          text: plugin.queryMode === "nearby" ? "附近" : "查找"
          font.bold: true
          font.pixelSize: 18
          color: QfTheme.mainTextColor
        }

        Button {
          text: "关闭"
          onClicked: browserDrawer.close()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
          Layout.fillWidth: true
          text: "点位"
          font.bold: plugin.queryObjectKind === "asset"
          onClicked: {
            plugin.queryObjectKind = "asset";
            assetSearchResults.clear();
            plugin.clearQueryHighlight();
            if (plugin.queryMode === "nearby") {
              plugin.loadNearbyKind("asset");
            }
          }
        }

        Button {
          Layout.fillWidth: true
          text: "管线"
          font.bold: plugin.queryObjectKind === "pipeline"
          onClicked: {
            plugin.queryObjectKind = "pipeline";
            assetSearchResults.clear();
            plugin.clearQueryHighlight();
            if (plugin.queryMode === "nearby") {
              plugin.loadNearbyKind("pipeline");
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: plugin.queryMode === "nearby"
        spacing: 8

        ComboBox {
          id: nearbyRadiusFilter
          Layout.fillWidth: true
          model: [
            {"text":"100 米","value":100},
            {"text":"300 米","value":300},
            {"text":"500 米","value":500},
            {"text":"1 公里","value":1000},
            {"text":"2 公里","value":2000}
          ]
          textRole: "text"
          currentIndex: 2
          onCurrentIndexChanged: {
            if (browserDrawer.opened && plugin.queryMode === "nearby") {
              plugin.loadNearbyKind(plugin.queryObjectKind);
            }
          }
        }

        Button {
          text: searchBusy ? "查询中" : "刷新"
          enabled: !searchBusy
          onClicked: plugin.loadNearbyKind(plugin.queryObjectKind)
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: plugin.queryMode === "search"
        spacing: 6

        TextField {
          id: querySearchField
          Layout.fillWidth: true
          placeholderText: plugin.queryObjectKind === "pipeline" ? "管线名称、编号、材质…" : "点位名称、编号、位置…"
          selectByMouse: true
          onAccepted: plugin.searchObjects(text)
        }

        Button {
          text: searchBusy ? "查询中" : "查询"
          enabled: !searchBusy
          onClicked: plugin.searchObjects(querySearchField.text)
        }
      }

      Button {
        Layout.fillWidth: true
        visible: plugin.queryMode === "search"
        text: plugin.queryFiltersExpanded ? "收起筛选" : "筛选"
        onClicked: plugin.queryFiltersExpanded = !plugin.queryFiltersExpanded
      }

      RowLayout {
        Layout.fillWidth: true
        visible: plugin.queryMode === "search" && plugin.queryFiltersExpanded
        spacing: 6

        ComboBox {
          id: searchAssetTypeFilter
          Layout.fillWidth: true
          model: assetTypeOptions
          textRole: "text"
          currentIndex: 0
          enabled: plugin.queryObjectKind === "asset"
          onCurrentIndexChanged: assetSearchResults.clear()
        }

        ComboBox {
          id: searchAssetStatusFilter
          Layout.fillWidth: true
          model: [
            {"text":"全部状态","value":""},
            {"text":"需处理","value":"problem"},
            {"text":"正常","value":"normal"},
            {"text":"需关注","value":"attention"},
            {"text":"待维修","value":"repair"},
            {"text":"停用","value":"disabled"}
          ]
          textRole: "text"
          currentIndex: 0
          onCurrentIndexChanged: assetSearchResults.clear()
        }
      }

      Label {
        Layout.fillWidth: true
        text: assetSearchResults.count > 0
              ? "找到 " + assetSearchResults.count + " 条 · 地图已高亮"
              : (searchBusy ? "正在查询…" : "结果会显示在这里")
        color: QfTheme.secondaryTextColor
      }

      ListView {
        id: queryResultsView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 8
        model: assetSearchResults
        delegate: queryResultDelegate
      }
    }
  }

  Drawer {
    id: addDrawer
    objectName: "waterworksAddDrawer"
    parent: mainWindow.contentItem
    z: 105
    edge: Qt.BottomEdge
    modal: false
    interactive: true
    width: mainWindow.width
    height: Math.min(230 + mainWindow.sceneBottomMargin, mainWindow.height * 0.4)

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
      border.color: QfTheme.controlBorderColor
    }

    ColumnLayout {
      anchors {
        fill: parent
        leftMargin: mainWindow.sceneLeftMargin + 16
        rightMargin: mainWindow.sceneRightMargin + 16
        topMargin: 12
        bottomMargin: mainWindow.sceneBottomMargin + 12
      }
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: "新增"
        font.bold: true
        font.pixelSize: 18
        color: QfTheme.mainTextColor
      }

      Label {
        Layout.fillWidth: true
        text: "新增操作只在编辑模式开放"
        color: QfTheme.secondaryTextColor
      }

      Button {
        Layout.fillWidth: true
        text: "新增点位"
        onClicked: {
          addDrawer.close();
          plugin.createAssetAtCurrentPosition();
        }
      }

      Button {
        Layout.fillWidth: true
        text: "新建管线"
        onClicked: {
          addDrawer.close();
          plugin.startPipelineCapture();
        }
      }
    }
  }

  Drawer {
    id: moreDrawer
    objectName: "waterworksMoreDrawer"
    parent: mainWindow.contentItem
    z: 105
    edge: Qt.BottomEdge
    modal: false
    interactive: true
    width: mainWindow.width
    height: Math.min(520 + mainWindow.sceneBottomMargin, mainWindow.height * 0.75)

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
      border.color: QfTheme.controlBorderColor
    }

    ColumnLayout {
      anchors {
        fill: parent
        leftMargin: mainWindow.sceneLeftMargin + 16
        rightMargin: mainWindow.sceneRightMargin + 16
        topMargin: 12
        bottomMargin: mainWindow.sceneBottomMargin + 12
      }
      spacing: 8

      RowLayout {
        Layout.fillWidth: true

        Label {
          Layout.fillWidth: true
          text: "更多"
          font.bold: true
          font.pixelSize: 18
          color: QfTheme.mainTextColor
        }

        Button {
          text: "关闭"
          onClicked: moreDrawer.close()
        }
      }

      Label {
        Layout.fillWidth: true
        text: plugin.positionText()
        color: QfTheme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      Label {
        Layout.fillWidth: true
        text: "底图"
        font.bold: true
        color: QfTheme.mainTextColor
      }

      ComboBox {
        id: basemapSelector
        Layout.fillWidth: true
        model: [
          {"text":"OSM（备用）","value":"osm"},
          {"text":"天地图矢量","value":"tdt-vector"},
          {"text":"天地图影像","value":"tdt-imagery"}
        ]
        textRole: "text"
        currentIndex: workerAppSettings.basemapMode === "tdt-vector"
                      ? 1
                      : (workerAppSettings.basemapMode === "tdt-imagery" ? 2 : 0)
        onActivated: index => {
          const requested = model[index].value;
          if (!plugin.applyBasemap(requested, true)) {
            currentIndex = workerAppSettings.basemapMode === "tdt-vector"
                           ? 1
                           : (workerAppSettings.basemapMode === "tdt-imagery" ? 2 : 0);
          }
        }
      }

      Label {
        Layout.fillWidth: true
        text: "当前底图：" + plugin.basemapModeLabel(workerAppSettings.basemapMode)
        color: QfTheme.mainTextColor
      }

      Label {
        Layout.fillWidth: true
        text: plugin.hasTiandituToken()
              ? (plugin.hasBundledTiandituToken()
                 ? "天地图密钥：已由构建安全配置提供"
                 : "天地图密钥：本机已配置（不显示明文）")
              : "天地图密钥：尚未配置"
        color: QfTheme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        visible: !plugin.hasBundledTiandituToken()
        spacing: 6

        TextField {
          id: tiandituTokenField
          Layout.fillWidth: true
          echoMode: TextInput.Password
          placeholderText: workerAppSettings.tiandituToken.length > 0
                           ? "本机已配置，可重新粘贴覆盖"
                           : "粘贴天地图 tk"
          selectByMouse: true
        }

        Button {
          text: "保存"
          onClicked: {
            if (plugin.saveLocalTiandituToken(tiandituTokenField.text)) {
              tiandituTokenField.clear();
            }
          }
        }

        Button {
          visible: workerAppSettings.tiandituToken.length > 0
          text: "清除"
          onClicked: {
            tiandituTokenField.clear();
            plugin.clearLocalTiandituToken();
          }
        }
      }

      Button {
        Layout.fillWidth: true
        text: workerAppSettings.showMyLocationMarker ? "隐藏我的位置标记" : "显示我的位置标记"
        onClicked: plugin.setMyLocationMarkerVisible(!workerAppSettings.showMyLocationMarker)
      }

      Button {
        Layout.fillWidth: true
        text: "复制当前位置"
        onClicked: plugin.copyCurrentPosition()
      }

      Button {
        Layout.fillWidth: true
        text: "备份 / 导出"
        onClicked: plugin.openProjectBackup()
      }

      Button {
        Layout.fillWidth: true
        text: "打开其他供水数据"
        onClicked: plugin.chooseWaterworksProject()
      }
    }
  }

  Rectangle {
    id: projectNotReadyOverlay
    objectName: "waterworksProjectNotReadyOverlay"
    parent: mainWindow.contentItem
    anchors.fill: parent
    z: 120
    visible: !plugin.waterworksProjectReady
    color: QfTheme.mainBackgroundColor

    ColumnLayout {
      anchors.centerIn: parent
      width: Math.min(parent.width - 40, 420)
      spacing: 14

      Label {
        Layout.fillWidth: true
        text: "正在准备供水巡检地图"
        font.bold: true
        font.pixelSize: 20
        horizontalAlignment: Text.AlignHCenter
        color: QfTheme.mainTextColor
      }

      Label {
        Layout.fillWidth: true
        text: "首次启动会自动创建地图和供水数据；如果没有自动完成，可以手动打开已有数据。"
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

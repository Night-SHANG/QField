import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

import org.qgis
import org.qfield.core
import org.qfield.gui

Item {
  id: plugin
  objectName: "wubaoWaterworksPlugin"

  property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()
  property var positionSource: iface.findItemByObjectName("positionSource")
  property var overlayFeatureFormDrawer: iface.findItemByObjectName("overlayFeatureFormDrawer")
  property var featureForm: iface.findItemByObjectName("featureForm")
  property var navigation: iface.findItemByObjectName("navigation")

  readonly property var assetLayerNames: ["供水设施", "assets_point", "供水点位"]
  readonly property var inspectionLayerNames: ["巡检记录", "inspections"]
  property bool searchBusy: false
  property int nearbyRadiusMeters: 500

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(waterworksButton)
  }

  function assetLayer() {
    for (let i = 0; i < assetLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(assetLayerNames[i])
      if (layers && layers.length > 0) {
        return layers[0]
      }
    }
    return null
  }

  function inspectionLayer() {
    for (let i = 0; i < inspectionLayerNames.length; i++) {
      const layers = qgisProject.mapLayersByName(inspectionLayerNames[i])
      if (layers && layers.length > 0) {
        return layers[0]
      }
    }
    return null
  }

  function positionText() {
    const positioning = iface.positioning()
    if (!positioning || !positioning.active) {
      return "定位未开启"
    }

    const info = positioning.positionInformation
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      return "正在等待有效定位"
    }

    return Number(info.latitude).toFixed(7) + ", " + Number(info.longitude).toFixed(7)
  }

  function copyCurrentPosition() {
    const positioning = iface.positioning()
    if (!positioning || !positioning.active) {
      mainWindow.displayToast("请先开启定位")
      return
    }

    const info = positioning.positionInformation
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      mainWindow.displayToast("暂未获得有效定位")
      return
    }

    const text = Number(info.latitude).toFixed(7) + ", " + Number(info.longitude).toFixed(7)
    platformUtilities.copyTextToClipboard(text)
    mainWindow.displayToast("当前位置已复制")
  }

  function escapeExpressionString(value) {
    return String(value || "").replace(/'/g, "''")
  }

  function appendAssetResult(feature, distanceMeters) {
    const idValue = feature.attribute("id")
    const nameValue = feature.attribute("name")
    const codeValue = feature.attribute("code")
    const typeValue = feature.attribute("asset_type")
    const statusValue = feature.attribute("status")

    assetSearchResults.append({
      "assetId": idValue === null || idValue === undefined ? "" : String(idValue),
      "assetName": nameValue === null || nameValue === undefined || String(nameValue).length === 0 ? "未命名点位" : String(nameValue),
      "assetCode": codeValue === null || codeValue === undefined ? "" : String(codeValue),
      "assetType": typeValue === null || typeValue === undefined ? "" : String(typeValue),
      "assetStatus": statusValue === null || statusValue === undefined ? "" : String(statusValue)
    })
  }

  function searchAssets(term) {
    assetSearchResults.clear()

    const layer = assetLayer()
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“供水设施”图层")
      return
    }

    const trimmed = String(term || "").trim()
    if (trimmed.length === 0) {
      return
    }

    searchBusy = true
    const needle = escapeExpressionString(trimmed.toLowerCase())
    const expression =
      "lower(coalesce(\"name\", '')) LIKE '%" + needle + "%' OR " +
      "lower(coalesce(\"code\", '')) LIKE '%" + needle + "%' OR " +
      "lower(coalesce(\"address_hint\", '')) LIKE '%" + needle + "%'"

    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, expression)
    let count = 0

    while (iterator.hasNext() && count < 100) {
      appendAssetResult(iterator.next())
      count++
    }

    searchBusy = false

    if (count === 0) {
      mainWindow.displayToast("未找到匹配点位")
    } else if (count === 100 && iterator.hasNext()) {
      mainWindow.displayToast("结果超过 100 条，请输入更精确的名称或编号")
    }
  }

  function loadNearbyAssets(radiusMeters) {
    assetSearchResults.clear()

    const layer = assetLayer()
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“供水设施”图层")
      return
    }

    const positioning = iface.positioning()
    if (!positioning || !positioning.active || !positioning.positionInformation) {
      mainWindow.displayToast("请先开启定位")
      return
    }

    const info = positioning.positionInformation
    if (!info.longitudeValid || !info.latitudeValid) {
      mainWindow.displayToast("暂未获得有效定位")
      return
    }

    const radius = Math.max(10, Math.min(5000, Number(radiusMeters)))
    nearbyRadiusMeters = radius
    searchBusy = true

    // Wubao is in UTM zone 49N. Transforming both geometries to EPSG:32649
    // gives a meter-based distance filter while the master data remains
    // CGCS2000/EPSG:4490.
    const lon = Number(info.longitude)
    const lat = Number(info.latitude)
    const expression =
      "distance(" +
      "transform($geometry, 'EPSG:4490', 'EPSG:32649'), " +
      "transform(make_point(" + lon + ", " + lat + "), 'EPSG:4326', 'EPSG:32649')" +
      ") <= " + radius

    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(layer, expression)
    const utm49 = QfCoordinateReferenceSystemUtils.fromDescription("EPSG:32649")
    const currentUtm = QfGeometryUtils.reprojectPoint(
      QfGeometryUtils.point(lon, lat),
      QfCoordinateReferenceSystemUtils.wgs84Crs(),
      utm49
    )
    const matches = []

    while (iterator.hasNext() && matches.length < 100) {
      const feature = iterator.next()
      const center = QfGeometryUtils.centroid(feature.geometry)
      const centerUtm = QfGeometryUtils.reprojectPoint(center, layer.crs, utm49)
      const dx = Number(centerUtm.x) - Number(currentUtm.x)
      const dy = Number(centerUtm.y) - Number(currentUtm.y)
      matches.push({
        "feature": feature,
        "distance": Math.sqrt(dx * dx + dy * dy)
      })
    }
    iterator.close()

    matches.sort((a, b) => a.distance - b.distance)
    for (let i = 0; i < matches.length; i++) {
      appendAssetResult(matches[i].feature, matches[i].distance)
    }

    searchBusy = false
    assetSearchField.text = ""

    if (matches.length === 0) {
      mainWindow.displayToast(radius + " 米内没有点位")
    } else {
      mainWindow.displayToast("已按距离载入 " + matches.length + " 个附近点位")
    }
  }

  function featureForAssetId(assetId) {
    const layer = assetLayer()
    if (!layer || !assetId) {
      return null
    }

    const escapedId = escapeExpressionString(assetId)
    const iterator = QfLayerUtils.createFeatureIteratorFromExpression(
      layer,
      "\"id\" = '" + escapedId + "'"
    )
    if (!iterator.hasNext()) {
      iterator.close()
      return null
    }

    const feature = iterator.next()
    iterator.close()
    return feature
  }

  function navigateToAsset(assetId) {
    const layer = assetLayer()
    const feature = featureForAssetId(assetId)
    if (!layer || !feature || !navigation) {
      mainWindow.displayToast("无法开始点位导航")
      return
    }

    navigation.setDestinationFeature(feature, layer)
    waterworksDialog.close()
    mainWindow.displayToast(
      "开始导航：" + QfFeatureUtils.displayName(layer, feature)
    )
  }

  function openAsset(assetId, editMode) {
    const layer = assetLayer()
    if (!layer || !featureForm || !assetId) {
      mainWindow.displayToast("无法打开点位")
      return
    }

    const escapedId = escapeExpressionString(assetId)
    featureForm.model.setFeatures(layer, "\"id\" = '" + escapedId + "'")
    featureForm.selection.focusedItem = 0
    featureForm.state = editMode ? "FeatureFormEdit" : "FeatureForm"
    waterworksDialog.close()
  }

  function createAssetAtCurrentPosition() {
    const layer = assetLayer()
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“供水设施”图层")
      return
    }

    const positioning = iface.positioning()
    if (!positioning || !positioning.active) {
      mainWindow.displayToast("请先开启定位")
      return
    }

    const info = positioning.positionInformation
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      mainWindow.displayToast("暂未获得有效定位")
      return
    }

    if (!positioning.projectedPosition) {
      mainWindow.displayToast("无法取得项目坐标")
      return
    }

    const projected = positioning.projectedPosition
    const geometry = QfGeometryUtils.createGeometryFromWkt(
      "POINT(" + Number(projected.x) + " " + Number(projected.y) + ")"
    )
    const feature = QfFeatureUtils.createFeature(
      layer,
      geometry,
      positioning.positionInformation
    )

    if (!overlayFeatureFormDrawer) {
      mainWindow.displayToast("无法打开新增点位表单")
      return
    }

    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.state = "Add"
    waterworksDialog.close()
    overlayFeatureFormDrawer.open()
  }

  function createInspection(assetId) {
    const layer = inspectionLayer()
    if (!layer) {
      mainWindow.displayToast("当前项目缺少“巡检记录”图层")
      return
    }
    if (!assetId) {
      mainWindow.displayToast("无法确定巡检设施")
      return
    }
    if (!overlayFeatureFormDrawer) {
      mainWindow.displayToast("无法打开巡检表单")
      return
    }

    const feature = QfFeatureUtils.createFeature(layer)
    feature.setAttribute("asset_id", assetId)

    const positioning = iface.positioning()
    if (positioning && positioning.active && positioning.positionInformation) {
      const accuracy = Number(positioning.positionInformation.hacc)
      if (isFinite(accuracy) && accuracy >= 0) {
        feature.setAttribute("position_accuracy_m", accuracy)
      }
    }

    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.state = "Add"
    waterworksDialog.close()
    overlayFeatureFormDrawer.open()
  }

  QfToolButton {
    id: waterworksButton
    objectName: "wubaoWaterworksButton"
    text: "水"
    font.bold: true
    Material.foreground: QfTheme.toolButtonColor
    bgcolor: QfTheme.toolButtonBackgroundColor
    round: true

    onClicked: waterworksDialog.open()
  }

  ListModel {
    id: assetSearchResults
  }

  QfDialog {
    id: waterworksDialog
    objectName: "wubaoWaterworksDialog"
    parent: mainWindow.contentItem
    title: "吴堡供水巡检"
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
        text: "现场定位"
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

        Button {
          Layout.fillWidth: true
          text: "复制坐标"
          onClicked: plugin.copyCurrentPosition()
        }

        Button {
          Layout.fillWidth: true
          text: "当前位置新增点位"
          onClicked: plugin.createAssetAtCurrentPosition()
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: QfTheme.controlBorderColor
      }

      Label {
        Layout.fillWidth: true
        text: "查找点位"
        font.bold: true
        color: QfTheme.mainTextColor
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        ComboBox {
          id: nearbyRadiusCombo
          model: [
            { text: "100 m", value: 100 },
            { text: "300 m", value: 300 },
            { text: "500 m", value: 500 },
            { text: "1 km", value: 1000 },
            { text: "2 km", value: 2000 }
          ]
          textRole: "text"
          currentIndex: 2
        }

        Button {
          text: "附近点位"
          enabled: !searchBusy
          onClicked: {
            const item = nearbyRadiusCombo.model[nearbyRadiusCombo.currentIndex]
            plugin.loadNearbyAssets(item.value)
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true

        TextField {
          id: assetSearchField
          Layout.fillWidth: true
          placeholderText: "输入名称、编号或位置描述"
          selectByMouse: true
          onAccepted: plugin.searchAssets(text)
        }

        Button {
          text: searchBusy ? "查询中" : "查询"
          enabled: !searchBusy && assetSearchField.text.trim().length > 0
          onClicked: plugin.searchAssets(assetSearchField.text)
        }
      }

      Label {
        Layout.fillWidth: true
        visible: assetSearchResults.count > 0
        text: "找到 " + assetSearchResults.count + " 个点位"
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
          required property string assetId
          required property string assetName
          required property string assetCode
          required property string assetType
          required property string assetStatus
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
              text: (assetDistance >= 0 ? assetDistance + " m  " : "") +
                    (assetCode.length > 0 ? "编号 " + assetCode + "  " : "") +
                    (assetType.length > 0 ? assetType + "  " : "") +
                    (assetStatus.length > 0 ? assetStatus : "")
              color: QfTheme.secondaryTextColor
              elide: Text.ElideRight
            }

            RowLayout {
              Layout.fillWidth: true

              Button {
                text: "查看"
                onClicked: plugin.openAsset(assetId, false)
              }

              Button {
                text: "编辑"
                onClicked: plugin.openAsset(assetId, true)
              }

              Button {
                text: "导航"
                onClicked: plugin.navigateToAsset(assetId)
              }

              Button {
                text: "巡检"
                onClicked: plugin.createInspection(assetId)
              }

              Item {
                Layout.fillWidth: true
              }
            }
          }
        }
      }
    }
  }
}

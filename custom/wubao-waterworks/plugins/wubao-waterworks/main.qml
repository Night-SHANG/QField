import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield 1.0
import Theme 1.0

Item {
    id: plugin
    objectName: "wubaoWaterworksPlugin"

    property var mainWindow: iface.mainWindow()
    property var positioning: iface.positioning()

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(waterworksButton)
    }

    function positionText() {
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

    QfToolButton {
        id: waterworksButton
        objectName: "wubaoWaterworksButton"
        iconSource: Theme.getThemeVectorIcon("ic_info_white_24dp")
        iconColor: Theme.toolButtonColor
        bgcolor: Theme.toolButtonBackgroundColor
        round: true

        onClicked: waterworksDialog.open()
    }

    Dialog {
        id: waterworksDialog
        title: "吴堡供水巡检"
        modal: true
        standardButtons: Dialog.Close
        width: Math.min(520, mainWindow ? mainWindow.width * 0.9 : 420)

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: "现场工具"
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                text: "当前定位：" + plugin.positionText()
                wrapMode: Text.WordWrap
            }

            Button {
                Layout.fillWidth: true
                text: "复制当前坐标"
                onClicked: plugin.copyCurrentPosition()
            }

            Label {
                Layout.fillWidth: true
                text: "后续将在这里加入：附近点位、设备搜索、快速新增、巡检记录、照片/视频附件和地图源切换。"
                wrapMode: Text.WordWrap
            }
        }
    }
}

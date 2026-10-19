import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings
import HHU.Controls

// 关于 (需求说明 V1.0 §3.4): version, build date, 检查更新 (§3.8), location of the editable tables.
// The open source notices are shown by the installer and kept in <install dir>\licenses (not in the UI).
SettingsPage {
    objectName: "settingsPage_HHUAbout"

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Unmanned Vehicle Ground Station")

        Image {
            Layout.alignment:       Qt.AlignHCenter
            source:                 "qrc:/hhu/hhu_logo.svg"
            sourceSize.height:      ScreenTools.defaultFontPixelHeight * 5
            fillMode:               Image.PreserveAspectFit
        }

        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Version")
            labelText:          hhuService.appVersion
        }

        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Based on QGroundControl")
            labelText:          QGroundControl.qgcVersion
        }

        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Build date")
            labelText:          hhuConfig.buildDate
        }

        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Message tables")
            labelText:          hhuConfig.source.startsWith(":") ? qsTr("Built in") : hhuConfig.source
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Software update")

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth
            QGCLabel {
                Layout.fillWidth:   true
                text:               hhuService.updateMessage !== "" ? hhuService.updateMessage : qsTr("Current version %1").arg(hhuService.appVersion)
                color:              hhuService.updateState === "error" ? "#B42318" : (hhuService.updateState === "available" ? "#004B97" : "#5B6B7F")
                wrapMode:           Text.WordWrap
            }
            QGCButton {
                text:       qsTr("Check for updates")
                enabled:    !hhuService.busy
                onClicked:  hhuService.checkForUpdate(false)
            }
        }

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            visible:                hhuService.updateState === "available" && !!hhuService.update.notes
            text:                   hhuService.update.notes || ""
            wrapMode:               Text.WordWrap
        }

        ProgressBar {
            Layout.fillWidth:   true
            visible:            hhuService.updateState === "downloading"
            value:              hhuService.progress
        }

        QGCButton {
            visible:    hhuService.updateState === "available"
            text:       qsTr("Download and install")
            primary:    true
            onClicked:  hhuService.downloadAndInstall()
        }
    }

    // 高级 (指令超时、告警阈值、航点上限、上传日志、流量统计) for after-sales
    HHUButton {
        Layout.alignment:   Qt.AlignLeft
        text:               qsTr("After-sales settings ›")
        kind:               "plain"
        size:               16
        onClicked:          mainWindow.showSettingsTool("Advanced")
    }
}

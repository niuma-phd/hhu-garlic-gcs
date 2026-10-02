import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings

// 关于 (需求说明 V1.0 §3.4): version, build date, 检查更新 (§3.8), open source notices,
// location of the editable tables.
SettingsPage {
    objectName: "settingsPage_HHUAbout"

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Hohai University Garlic Seeder Ground Station")

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

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Open source notices")

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 70
            wrapMode:               Text.WordWrap
            textFormat:             Text.RichText
            onLinkActivated:        (link) => Qt.openUrlExternally(link)
            text: qsTr("This software is based on QGroundControl (<a href=\"https://github.com/mavlink/qgroundcontrol\">github.com/mavlink/qgroundcontrol</a>), "
                       + "licensed under the Apache License 2.0 and the GNU General Public License v3. "
                       + "It uses the Qt framework (<a href=\"https://www.qt.io\">qt.io</a>) under the GNU LGPL v3, "
                       + "MAVLink (MIT License) and map data from TianDiTu (<a href=\"https://www.tianditu.gov.cn\">tianditu.gov.cn</a>). "
                       + "The source code of the open source parts is available on request.")
        }

        // Required by the HarmonyOS Sans Fonts License (fonts/HarmonyOS_Sans_LICENSE.txt)
        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 70
            wrapMode:               Text.WordWrap
            text: qsTr("Fonts: this software uses HarmonyOS Sans Fonts (© Huawei Device Co., Ltd., HarmonyOS Sans Fonts License Agreement) and Barlow (SIL Open Font License 1.1).")
        }
    }
}

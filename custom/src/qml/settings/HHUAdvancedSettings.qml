import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings

// 高级 (需求说明 V1.0 §3.4): 指令超时时间、连接中断判定时间, plus the low battery alarm
// threshold, the waypoint limit of the upload check and 上传日志给售后 (§3.8).
SettingsPage {
    objectName: "settingsPage_HHUAdvanced"

    readonly property var _secondsChoices:  [ 3, 5, 8, 10, 15, 20 ]
    readonly property var _batteryChoices:  [ 10, 15, 20, 25, 30, 40 ]

    function _secondsModel() {
        return _secondsChoices.map(s => qsTr("%1 s").arg(s))
    }

    /// Index of value in choices; a value set in the settings file that is not listed shows as the nearest
    function _indexOf(choices, value) {
        let best = 0
        for (let i = 0; i < choices.length; i++) {
            if (Math.abs(choices[i] - value) < Math.abs(choices[best] - value)) best = i
        }
        return best
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Vehicle link")

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Command timeout")
            model:              _secondsModel()
            currentIndex:       _indexOf(_secondsChoices, hhuSettings.commandTimeoutSec)
            onActivated:        (index) => hhuSettings.commandTimeoutSec = _secondsChoices[index]
        }
        QGCLabel {
            Layout.fillWidth:   true
            text:               qsTr("\"Command not executed\" is shown when the vehicle has not carried out a work command within this time.")
            font.pointSize:     ScreenTools.smallFontPointSize
            wrapMode:           Text.WordWrap
        }

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Link lost after")
            model:              _secondsModel()
            currentIndex:       _indexOf(_secondsChoices, hhuSettings.linkLostSec)
            onActivated:        (index) => hhuSettings.linkLostSec = _secondsChoices[index]
        }
        QGCLabel {
            Layout.fillWidth:   true
            text:               qsTr("The link counts as lost when no data has come from the vehicle for this time.")
            font.pointSize:     ScreenTools.smallFontPointSize
            wrapMode:           Text.WordWrap
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Alarms and checks")

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Low battery alarm below")
            model:              _batteryChoices.map(p => p + "%")
            currentIndex:       _indexOf(_batteryChoices, hhuSettings.lowBatteryPct)
            onActivated:        (index) => hhuSettings.lowBatteryPct = _batteryChoices[index]
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel {
                Layout.fillWidth:   true
                text:               qsTr("Waypoint limit")
            }
            QGCTextField {
                id:                     maxWaypointsField
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 12
                text:                   hhuSettings.maxWaypoints
                inputMethodHints:       Qt.ImhDigitsOnly
                validator:              IntValidator { bottom: 10; top: 10000 }
                onEditingFinished: {
                    if (acceptableInput) {
                        hhuSettings.maxWaypoints = parseInt(text)
                    }
                    text = hhuSettings.maxWaypoints
                }
            }
        }
        QGCLabel {
            Layout.fillWidth:   true
            text:               qsTr("Routes with more waypoints are flagged before upload (10 to 10000).")
            font.pointSize:     ScreenTools.smallFontPointSize
            wrapMode:           Text.WordWrap
        }
    }

    // ---- 上传日志给售后 (需求说明 V1.0 §3.8) ----------------------------------------------------

    readonly property var _rangeNames: [ qsTr("Last work run"), qsTr("Today"), qsTr("Last 3 days"), qsTr("Last 7 days") ]

    /// [from, to] of the chosen range (Date objects)
    function _range(index) {
        const now = new Date()
        switch (index) {
        case 0: {
            const last = hhuWork.lastRun
            if (last.start && last.end) {
                // A few minutes around the run: logs are written just before / after
                return [ new Date(new Date(last.start).getTime() - 10 * 60000), new Date(new Date(last.end).getTime() + 10 * 60000) ]
            }
            return [ new Date(now.getTime() - 24 * 3600000), now ]
        }
        case 1: {
            const start = new Date(now)
            start.setHours(0, 0, 0, 0)
            return [ start, now ]
        }
        case 2:  return [ new Date(now.getTime() - 3 * 24 * 3600000), now ]
        default: return [ new Date(now.getTime() - 7 * 24 * 3600000), now ]
        }
    }

    FileDialog {
        id:             logExportDialog
        title:          qsTr("Save logs")
        fileMode:       FileDialog.SaveFile
        nameFilters:    [ "ZIP (*.zip)" ]
        defaultSuffix:  "zip"
        onAccepted: {
            const ok = hhuService.exportLogs(selectedFile.toString())
            QGroundControl.showMessageDialog(logExportDialog, qsTr("Save logs"),
                                             ok ? qsTr("Saved.") : qsTr("The file could not be written."), Dialog.Ok)
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Send logs to after-sales service")

        LabelledComboBox {
            id:                 rangeCombo
            Layout.fillWidth:   true
            label:              qsTr("Time range")
            model:              _rangeNames
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth
            QGCButton {
                text:       qsTr("Pack logs")
                enabled:    !hhuService.busy && hhuService.logState !== "uploading"
                onClicked: {
                    const r = _range(rangeCombo.currentIndex)
                    hhuService.packLogs(r[0], r[1])
                }
            }
            QGCButton {
                text:       hhuService.logState === "error" || hhuService.logMessage !== "" && hhuService.logState === "ready" ? qsTr("Upload again") : qsTr("Upload")
                primary:    true
                enabled:    !hhuService.busy && (hhuService.logState === "ready" || hhuService.logState === "error") && hhuService.logFileCount >= 0
                onClicked: {
                    if (hhuService.logZipSize > 20 * 1024 * 1024) {
                        QGroundControl.showMessageDialog(rangeCombo, qsTr("Send logs"),
                                                         qsTr("The logs are large (%1). Uploading over WiFi is recommended. Upload now?").arg(hhuLink.formatBytes(hhuService.logZipSize)),
                                                         Dialog.Ok | Dialog.Cancel, function() { hhuService.uploadLogs() })
                    } else {
                        hhuService.uploadLogs()
                    }
                }
            }
            QGCButton {
                text:       qsTr("Save to this computer")
                enabled:    hhuService.logState !== "idle" && hhuService.logState !== "packing"
                onClicked:  logExportDialog.open()
            }
            QGCButton {
                text:       qsTr("Stop")
                visible:    hhuService.logState === "uploading"
                onClicked:  hhuService.cancel()
            }
        }

        QGCLabel {
            Layout.fillWidth:   true
            visible:            hhuService.logState !== "idle"
            text:               qsTr("%1 files, %2 packed").arg(hhuService.logFileCount).arg(hhuLink.formatBytes(hhuService.logZipSize))
                                + (hhuService.logZipSize > 20 * 1024 * 1024 ? "  " + qsTr("(large: upload over WiFi recommended)") : "")
        }

        ProgressBar {
            Layout.fillWidth:   true
            visible:            hhuService.logState === "uploading"
            value:              hhuService.progress
        }

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            visible:                hhuService.logMessage !== ""
            text:                   hhuService.logMessage
            color:                  hhuService.logState === "error" ? "#B42318" : (hhuService.logState === "done" ? "#1F8A3B" : "#5B6B7F")
            font.bold:              hhuService.logState === "done"
            wrapMode:               Text.WordWrap
        }

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            text:                   qsTr("Uploading continues in the background and resumes where it stopped. Give the ticket number to after-sales. Logs are kept for 7 days.")
            font.pointSize:         ScreenTools.smallFontPointSize
            wrapMode:               Text.WordWrap
        }
    }
}

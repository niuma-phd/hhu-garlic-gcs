import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings
import HHU.Controls

// 飞控日志 (our own engineers only, hhu_config.json engineeringTuning): the autopilot's .BIN logs over
// MAVFTP, through hhuLogs. Downloads to <save path>/飞控日志/<车号>/; deleting on the vehicle takes only
// downloaded logs and never the newest one. No explanatory text beyond the speed hint.
SettingsPage {
    id:         logsPage
    objectName: "settingsPage_HHULogs"

    readonly property real _nameW:  150 * HHUStyle.s
    readonly property real _sizeW:  110 * HHUStyle.s
    readonly property real _stateW: 110 * HHUStyle.s

    property var _selected: ({})    ///< name → true
    readonly property var _selectedNames: Object.keys(_selected).filter(n => _selected[n])

    Component.onCompleted:  hhuLogs.active = true
    Component.onDestruction: hhuLogs.active = false

    function _size(bytes) {
        return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1024)) + " KB"
    }
    function _toggle(name) {
        let s = Object.assign({}, _selected)
        s[name] = !s[name]
        _selected = s
    }

    Connections {
        target: hhuLogs
        function onFilesChanged() { logsPage._selected = ({}) }
    }

    // Buttons and state
    Flow {
        Layout.fillWidth:   true
        spacing:            10 * HHUStyle.s

        HHUButton {
            text:       qsTr("Refresh")
            kind:       "outline"
            size:       16
            enabled:    hhuLogs.connected && !hhuLogs.busy
            onClicked:  hhuLogs.refresh()
        }
        HHUButton {
            text:       qsTr("Download all new (%1, %2)").arg(hhuLogs.pendingCount).arg(logsPage._size(hhuLogs.pendingBytes))
            size:       16
            enabled:    hhuLogs.canTransfer && hhuLogs.pendingCount > 0
            onClicked:  hhuLogs.download([])
        }
        HHUButton {
            text:       qsTr("Download selected (%1)").arg(logsPage._selectedNames.length)
            kind:       "plain"
            size:       16
            enabled:    hhuLogs.canTransfer && logsPage._selectedNames.length > 0
            onClicked:  hhuLogs.download(logsPage._selectedNames)
        }
        HHUButton {
            text:       qsTr("Cancel")
            kind:       "plain"
            size:       16
            visible:    hhuLogs.busy && hhuLogs.progress >= 0
            onClicked:  hhuLogs.cancel()
        }
        HHUButton {
            text:       qsTr("Delete downloaded on vehicle…")
            kind:       "plain"
            size:       16
            enabled:    hhuLogs.canTransfer
            onClicked: {
                const names = logsPage._selectedNames
                mainWindow.hhuConfirm(logsPage, qsTr("Delete logs on the vehicle"),
                                      (names.length > 0 ? qsTr("Delete the %1 selected logs on %2 that are downloaded?").arg(names.length)
                                                        : qsTr("Delete all logs on %2 that are downloaded?")).arg(hhuTuning.vehicleName)
                                      + "\n" + qsTr("Logs not downloaded and the newest log stay on the vehicle."),
                                      qsTr("Delete"), function() { hhuLogs.removeDownloaded(names) })
            }
        }
        HHUButton {
            text:       qsTr("Open folder")
            kind:       "plain"
            size:       16
            onClicked:  hhuLogs.openFolder()
        }
        HHUText {
            height:     HHUStyle.touch
            visible:    text !== ""
            text:       !hhuLogs.connected ? qsTr("Not connected") : (hhuLogs.busy ? hhuLogs.busyText : hhuLogs.blockReason)
            color:      hhuLogs.busy ? HHUStyle.text2 : HHUStyle.red
            bold:       true
        }
    }

    // progress of the running download
    ColumnLayout {
        Layout.fillWidth:   true
        visible:            hhuLogs.busy && hhuLogs.progress >= 0
        spacing:            4 * HHUStyle.s
        Rectangle {
            Layout.fillWidth:       true
            Layout.preferredHeight: 10 * HHUStyle.s
            radius:                 height / 2
            color:                  HHUStyle.divider
            Rectangle {
                width:  parent.width * Math.max(0, hhuLogs.progress)
                height: parent.height
                radius: parent.radius
                color:  HHUStyle.blue
            }
        }
        HHUText {
            text:   Math.round(Math.max(0, hhuLogs.progress) * 100) + "%" + (hhuLogs.speedText !== "" ? "  ·  " + hhuLogs.speedText : "")
            number: true
            color:  HHUStyle.text2
        }
    }

    HHUText {
        Layout.fillWidth:   true
        visible:            hhuLogs.message !== ""
        text:               hhuLogs.message
        color:              hhuLogs.messageError ? HHUStyle.red : HHUStyle.green
        bold:               true
        wrapMode:           Text.WrapAnywhere
    }

    HHUText {
        Layout.fillWidth:   true
        text:               qsTr("Saved in %1. Over 4G the logs count against the data plan; many or large logs are faster from the SD card.")
                                .arg(hhuLogs.folder())
        size:               14
        color:              HHUStyle.text3
        wrapMode:           Text.WrapAnywhere
    }

    HHUText {
        visible:    hhuLogs.connected && !hhuLogs.busy && hhuLogs.files.length === 0 && hhuLogs.message === ""
        text:       qsTr("No logs on the vehicle")
        color:      HHUStyle.text3
    }

    // Logs, newest first
    ColumnLayout {
        Layout.fillWidth:   true
        spacing:            4 * HHUStyle.s

        Repeater {
            model: hhuLogs.files

            Rectangle {
                id:                 logRow
                Layout.fillWidth:   true
                implicitHeight:     logLayout.implicitHeight + 8 * HHUStyle.s
                radius:             HHUStyle.radiusCtl
                color:              logsPage._selected[modelData.name] ? HHUStyle.blueLight : (index % 2 ? "transparent" : HHUStyle.grey)

                required property int   index
                required property var   modelData

                MouseArea {
                    anchors.fill:   parent
                    onClicked:      logsPage._toggle(logRow.modelData.name)
                }

                RowLayout {
                    id:                     logLayout
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left:           parent.left
                    anchors.right:          parent.right
                    anchors.leftMargin:     8 * HHUStyle.s
                    anchors.rightMargin:    8 * HHUStyle.s
                    spacing:                12 * HHUStyle.s

                    HHUIcon {
                        name:   "check"
                        color:  logsPage._selected[logRow.modelData.name] ? HHUStyle.blue : HHUStyle.border
                        size:   20
                    }
                    HHUText {
                        Layout.preferredWidth:  _nameW
                        text:                   logRow.modelData.name
                        number:                 true
                    }
                    HHUText {
                        Layout.preferredWidth:  _sizeW
                        text:                   logsPage._size(logRow.modelData.size)
                        number:                 true
                        color:                  HHUStyle.text2
                    }
                    HHUText {
                        Layout.preferredWidth:  _stateW
                        text:                   logRow.modelData.downloaded ? qsTr("Downloaded") : ""
                        color:                  HHUStyle.green
                        bold:                   true
                    }
                    HHUText {
                        Layout.fillWidth:       true
                        text:                   logRow.modelData.newest ? qsTr("Newest") : ""
                        color:                  HHUStyle.text3
                    }
                }
            }
        }
    }

    Item { Layout.preferredHeight: 24 * HHUStyle.s }
}

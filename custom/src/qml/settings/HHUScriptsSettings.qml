import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings
import HHU.Controls

// Lua 脚本 (our own engineers only, hhu_config.json engineeringTuning): the autopilot's scripts
// directory over MAVFTP, through hhuScripts. Replacing a script backs the old one up and only takes
// effect after 重启脚本. No explanatory text.
SettingsPage {
    id:         scriptsPage
    objectName: "settingsPage_HHUScripts"

    readonly property real _nameW:  100 * HHUStyle.s
    readonly property real _sizeW:  90 * HHUStyle.s

    property string _replaceName    ///< vehicle file the file dialog replaces ("" = upload under the local name)

    Component.onCompleted:  hhuScripts.active = true
    Component.onDestruction: hhuScripts.active = false

    function _upload(fileUrl) {
        const name = _replaceName !== "" ? _replaceName : hhuScripts.fileName(fileUrl)
        const nameError = hhuScripts.checkName(name)
        if (nameError !== "") {
            mainWindow.hhuConfirm(scriptsPage, qsTr("Upload script"), nameError, qsTr("OK"), function() {})
            return
        }
        if (hhuScripts.exists(name)) {
            mainWindow.hhuConfirm(scriptsPage, qsTr("Replace script"),
                                  qsTr("Replace %1 on %2 with %3?").arg(name).arg(hhuTuning.vehicleName).arg(hhuScripts.localPath(fileUrl)),
                                  qsTr("Replace"), function() { hhuScripts.upload(fileUrl, name) })
        } else {
            hhuScripts.upload(fileUrl, name)
        }
    }

    // Buttons and state
    Flow {
        Layout.fillWidth:   true
        spacing:            10 * HHUStyle.s

        HHUButton {
            text:       qsTr("Refresh")
            kind:       "outline"
            size:       16
            enabled:    hhuScripts.connected && !hhuScripts.busy
            onClicked:  hhuScripts.refresh()
        }
        HHUButton {
            text:       qsTr("Upload script…")
            size:       16
            enabled:    hhuScripts.canModify && hhuScripts.directory !== ""
            onClicked: {
                scriptsPage._replaceName = ""
                fileDialog.open()
            }
        }
        HHUButton {
            text:       qsTr("Restart scripts")
            kind:       "plain"
            size:       16
            enabled:    hhuScripts.canModify
            onClicked:  mainWindow.hhuConfirm(scriptsPage, qsTr("Restart scripts"),
                                              qsTr("Restart the scripts of %1 now?").arg(hhuTuning.vehicleName),
                                              qsTr("Restart"), function() { hhuScripts.restartScripts() })
        }
        HHUButton {
            text:       qsTr("Open backup folder")
            kind:       "plain"
            size:       16
            onClicked:  hhuScripts.openBackupFolder()
        }
        HHUText {
            height:     HHUStyle.touch
            visible:    text !== ""
            text:       !hhuScripts.connected ? qsTr("Not connected") : (hhuScripts.busy ? hhuScripts.busyText : hhuScripts.blockReason)
            color:      hhuScripts.busy ? HHUStyle.text2 : HHUStyle.red
            bold:       true
        }
    }

    HHUText {
        Layout.fillWidth:   true
        visible:            hhuScripts.message !== ""
        text:               hhuScripts.message
        color:              hhuScripts.messageError ? HHUStyle.red : HHUStyle.green
        bold:               true
        wrapMode:           Text.WrapAnywhere
    }

    // A script was changed: it runs after the scripts restart
    Rectangle {
        Layout.fillWidth:   true
        visible:            hhuScripts.restartNeeded
        implicitHeight:     restartRow.implicitHeight + 16 * HHUStyle.s
        radius:             HHUStyle.radiusCtl
        color:              HHUStyle.yellowLight

        RowLayout {
            id:                     restartRow
            anchors.fill:           parent
            anchors.leftMargin:     14 * HHUStyle.s
            anchors.rightMargin:    8 * HHUStyle.s
            spacing:                12 * HHUStyle.s

            HHUText {
                Layout.fillWidth:   true
                text:               qsTr("Scripts changed, restart the scripts to run them")
                bold:               true
            }
            HHUButton {
                text:       qsTr("Restart scripts")
                kind:       "yellow"
                size:       16
                enabled:    hhuScripts.canModify
                onClicked:  mainWindow.hhuConfirm(scriptsPage, qsTr("Restart scripts"),
                                                  qsTr("Restart the scripts of %1 now?").arg(hhuTuning.vehicleName),
                                                  qsTr("Restart"), function() { hhuScripts.restartScripts() })
            }
        }
    }

    HHUText {
        visible:    hhuScripts.directory !== ""
        text:       hhuScripts.directory
        number:     true
        color:      HHUStyle.text3
    }

    // Files of the scripts directory
    ColumnLayout {
        Layout.fillWidth:   true
        spacing:            4 * HHUStyle.s

        Repeater {
            model: hhuScripts.files

            Rectangle {
                id:                 fileRow
                Layout.fillWidth:   true
                implicitHeight:     fileLayout.implicitHeight + 8 * HHUStyle.s
                radius:             HHUStyle.radiusCtl
                color:              index % 2 ? "transparent" : HHUStyle.grey

                required property int   index
                required property var   modelData
                readonly property string _name: modelData.name

                RowLayout {
                    id:                     fileLayout
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left:           parent.left
                    anchors.right:          parent.right
                    anchors.leftMargin:     8 * HHUStyle.s
                    anchors.rightMargin:    8 * HHUStyle.s
                    spacing:                12 * HHUStyle.s

                    HHUText {
                        Layout.fillWidth:       true
                        Layout.minimumWidth:    _nameW
                        text:                   fileRow._name
                        number:                 true
                        elide:                  Text.ElideRight
                    }
                    HHUText {
                        Layout.preferredWidth:  _sizeW
                        text:                   qsTr("%1 B").arg(fileRow.modelData.size)
                        number:                 true
                        color:                  HHUStyle.text2
                    }
                    HHUButton {
                        visible:    fileRow._name.toLowerCase().endsWith(".lua")
                        text:       qsTr("Replace…")
                        kind:       "plain"
                        size:       16
                        h:          40 * HHUStyle.s
                        enabled:    hhuScripts.canModify
                        onClicked: {
                            scriptsPage._replaceName = fileRow._name
                            fileDialog.open()
                        }
                    }
                    HHUButton {
                        text:       qsTr("Back up")
                        kind:       "plain"
                        size:       16
                        h:          40 * HHUStyle.s
                        enabled:    hhuScripts.connected && !hhuScripts.busy
                        onClicked:  hhuScripts.backup(fileRow._name)
                    }
                    HHUButton {
                        text:       qsTr("Delete")
                        kind:       "plain"
                        size:       16
                        h:          40 * HHUStyle.s
                        enabled:    hhuScripts.canModify
                        onClicked:  mainWindow.hhuConfirm(scriptsPage, qsTr("Delete script"),
                                                          qsTr("Delete %1 on %2? It is saved to the backup folder first.").arg(fileRow._name).arg(hhuTuning.vehicleName),
                                                          qsTr("Delete"), function() { hhuScripts.remove(fileRow._name) })
                    }
                }
            }
        }
    }

    Item { Layout.preferredHeight: 24 * HHUStyle.s }

    FileDialog {
        id:             fileDialog
        title:          scriptsPage._replaceName !== "" ? qsTr("Replace %1").arg(scriptsPage._replaceName) : qsTr("Upload script")
        fileMode:       FileDialog.OpenFile
        nameFilters:    [ qsTr("Lua scripts (*.lua)"), qsTr("All files (*)") ]
        onAccepted:     scriptsPage._upload(selectedFile.toString())
    }
}

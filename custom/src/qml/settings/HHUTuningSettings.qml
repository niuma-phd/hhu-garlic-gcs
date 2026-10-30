import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings
import HHU.Controls

// 工程调参 (our own engineers only, hhu_config.json engineeringTuning): the parameters of
// config/hhu_tuning_params.json, read / written by hhuTuning. Editing only marks a row pending (yellow);
// 写入 snapshots the vehicle's values first and writes the rows one by one. No explanatory text.
SettingsPage {
    id:         tuningPage
    objectName: "settingsPage_HHUTuning"

    readonly property real _nameW:      190 * HHUStyle.s
    readonly property real _currentW:   100 * HHUStyle.s
    readonly property real _inputW:     120 * HHUStyle.s
    readonly property real _statusW:    220 * HHUStyle.s

    Component.onCompleted:  hhuTuning.active = true
    Component.onDestruction: hhuTuning.active = false

    // Buttons and state
    Flow {
        Layout.fillWidth:   true
        spacing:            10 * HHUStyle.s

        HHUButton {
            text:       hhuTuning.reading ? qsTr("Reading…") : qsTr("Read")
            kind:       "outline"
            size:       16
            enabled:    hhuTuning.connected && !hhuTuning.reading && !hhuTuning.writing
            onClicked:  hhuTuning.read()
        }
        HHUButton {
            text:       hhuTuning.writing ? qsTr("Writing…") : qsTr("Write (%1)").arg(hhuTuning.pendingCount)
            size:       16
            enabled:    hhuTuning.canWrite && hhuTuning.pendingCount > 0 && hhuTuning.invalidCount === 0
            onClicked:  hhuTuning.write()
        }
        HHUButton {
            text:       qsTr("Discard changes")
            kind:       "plain"
            size:       16
            enabled:    !hhuTuning.writing && (hhuTuning.pendingCount > 0 || hhuTuning.invalidCount > 0)
            onClicked:  hhuTuning.discard()
        }
        HHUButton {
            text:       qsTr("Restore snapshot")
            kind:       "plain"
            size:       16
            enabled:    !hhuTuning.writing
            onClicked: {
                snapshotDialog.snapshots = hhuTuning.snapshots()
                snapshotDialog.open()
            }
        }
        HHUButton {
            text:       qsTr("Import .param")
            kind:       "plain"
            size:       16
            enabled:    !hhuTuning.writing
            onClicked:  importDialog.open()
        }
        HHUText {
            height:     HHUStyle.touch
            visible:    text !== ""
            text:       !hhuTuning.connected ? qsTr("Not connected") : hhuTuning.blockReason
            color:      HHUStyle.red
            bold:       true
        }
    }

    HHUText {
        Layout.fillWidth:   true
        visible:            hhuTuning.summary !== ""
        text:               hhuTuning.summary
        color:              hhuTuning.summaryError ? HHUStyle.red : HHUStyle.green
        bold:               true
        wrapMode:           Text.WordWrap
    }

    // A parameter that only takes effect after an autopilot reboot was written
    Rectangle {
        Layout.fillWidth:   true
        visible:            hhuTuning.rebootNeeded
        implicitHeight:     rebootRow.implicitHeight + 16 * HHUStyle.s
        radius:             HHUStyle.radiusCtl
        color:              HHUStyle.yellowLight

        RowLayout {
            id:                     rebootRow
            anchors.fill:           parent
            anchors.leftMargin:     14 * HHUStyle.s
            anchors.rightMargin:    8 * HHUStyle.s
            spacing:                12 * HHUStyle.s

            HHUText {
                Layout.fillWidth:   true
                text:               qsTr("Some parameters take effect after the autopilot reboots")
                bold:               true
            }
            HHUButton {
                text:       qsTr("Reboot autopilot")
                kind:       "yellow"
                size:       16
                enabled:    hhuTuning.connected && !hhuTuning.armed && !hhuTuning.writing
                onClicked:  mainWindow.hhuConfirm(tuningPage, qsTr("Reboot autopilot"),
                                                  qsTr("Reboot the autopilot of %1 now?").arg(hhuTuning.vehicleName),
                                                  qsTr("Reboot"), function() { hhuTuning.rebootAutopilot() })
            }
        }
    }

    // Column titles
    RowLayout {
        Layout.fillWidth:   true
        spacing:            12 * HHUStyle.s

        HHUText { Layout.preferredWidth: _nameW;    text: qsTr("Parameter");  color: HHUStyle.text3 }
        HHUText { Layout.preferredWidth: _currentW; text: qsTr("Current");    color: HHUStyle.text3 }
        HHUText { Layout.preferredWidth: _inputW + 2 * HHUStyle.touch + 12 * HHUStyle.s; text: qsTr("New value"); color: HHUStyle.text3 }
        HHUText { Layout.fillWidth: true; Layout.minimumWidth: _statusW; text: qsTr("Status"); color: HHUStyle.text3 }
    }

    // Rows without the page's paragraph spacing
    ColumnLayout {
        Layout.fillWidth:   true
        spacing:            4 * HHUStyle.s

        Repeater {
            model: hhuTuning

            ColumnLayout {
                id:                 paramRow
                Layout.fillWidth:   true
                spacing:            6 * HHUStyle.s

                required property int    index
                required property string name
                required property string group
                required property bool   groupStart
                required property real   min
                required property real   max
                required property int    decimals
                required property bool   reboot
                required property bool   missing
                required property string currentText
                required property string input
                required property bool   pending
                required property bool   invalid
                required property string status
                required property string statusText

                HHUText {
                    Layout.topMargin:   paramRow.index === 0 ? 0 : 14 * HHUStyle.s
                    visible:            paramRow.groupStart
                    text:               paramRow.group
                    size:               19
                    bold:               true
                    color:              HHUStyle.blue
                }

                Rectangle {
                    Layout.fillWidth:   true
                    implicitHeight:     rowLayout.implicitHeight + 8 * HHUStyle.s
                    radius:             HHUStyle.radiusCtl
                    color:              paramRow.invalid ? HHUStyle.redLight : (paramRow.pending ? HHUStyle.yellowLight : "transparent")
                    opacity:            paramRow.missing ? 0.45 : 1

                    RowLayout {
                        id:                     rowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:           parent.left
                        anchors.right:          parent.right
                        anchors.leftMargin:     8 * HHUStyle.s
                        spacing:                12 * HHUStyle.s

                        HHUText {
                            Layout.preferredWidth:  _nameW - 8 * HHUStyle.s
                            text:                   paramRow.name + (paramRow.reboot ? " ⟳" : "")
                            number:                 true
                            elide:                  Text.ElideRight
                        }
                        HHUText {
                            Layout.preferredWidth:  _currentW
                            text:                   paramRow.currentText !== "" ? paramRow.currentText : "—"
                            number:                 true
                        }
                        HHUButton {
                            Layout.preferredWidth:  HHUStyle.touch
                            text:                   "−"
                            kind:                   "plain"
                            size:                   18
                            h:                      40 * HHUStyle.s
                            enabled:                !paramRow.missing && !hhuTuning.writing && (paramRow.currentText !== "" || paramRow.input !== "")
                            onClicked:              hhuTuning.stepInput(paramRow.index, -1)
                        }
                        HHUTextField {
                            id:                     valueField
                            Layout.preferredWidth:  _inputW
                            implicitHeight:         40 * HHUStyle.s
                            text:                   paramRow.input
                            enabled:                !paramRow.missing && !hhuTuning.writing
                            font.family:            HHUStyle.numberFamily
                            horizontalAlignment:    TextInput.AlignRight
                            inputMethodHints:       Qt.ImhFormattedNumbersOnly
                            onTextEdited:           hhuTuning.setInput(paramRow.index, text)
                            background: Rectangle {
                                radius:         8 * HHUStyle.s
                                color:          valueField.enabled ? "white" : HHUStyle.grey
                                border.color:   paramRow.invalid ? HHUStyle.red : (valueField.activeFocus ? HHUStyle.blue : (paramRow.pending ? HHUStyle.yellow : HHUStyle.border))
                                border.width:   2
                            }
                        }
                        HHUButton {
                            Layout.preferredWidth:  HHUStyle.touch
                            text:                   "+"
                            kind:                   "plain"
                            size:                   18
                            h:                      40 * HHUStyle.s
                            enabled:                !paramRow.missing && !hhuTuning.writing && (paramRow.currentText !== "" || paramRow.input !== "")
                            onClicked:              hhuTuning.stepInput(paramRow.index, 1)
                        }
                        HHUText {
                            Layout.fillWidth:       true
                            Layout.minimumWidth:    _statusW
                            text: {
                                if (paramRow.missing)               return qsTr("No such parameter")
                                if (paramRow.invalid)               return qsTr("%1 – %2").arg(paramRow.min.toFixed(paramRow.decimals)).arg(paramRow.max.toFixed(paramRow.decimals))
                                if (paramRow.statusText !== "")     return paramRow.statusText
                                if (paramRow.status === "reading")  return "…"
                                return paramRow.pending ? qsTr("To write") : ""
                            }
                            color: {
                                if (paramRow.missing)                   return HHUStyle.text3
                                if (paramRow.invalid)                   return HHUStyle.red
                                switch (paramRow.status) {
                                case "ok":          return HHUStyle.green
                                case "fail":
                                case "unconfirmed":
                                case "unread":      return HHUStyle.red
                                default:            return HHUStyle.text2
                                }
                            }
                            bold:       paramRow.status === "ok" || paramRow.status === "fail" || paramRow.status === "unconfirmed" || paramRow.invalid
                            elide:      Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Item { Layout.preferredHeight: 24 * HHUStyle.s }

    // Snapshots of this vehicle, newest first: the values only go into the inputs
    HHUDialog {
        id:             snapshotDialog
        title:          qsTr("Restore snapshot")
        subtitle:       hhuTuning.vehicleName
        dialogWidth:    480

        property var snapshots: []

        HHUText {
            visible:    snapshotDialog.snapshots.length === 0
            text:       qsTr("No snapshots")
            color:      HHUStyle.text3
        }

        ListView {
            Layout.fillWidth:       true
            Layout.preferredHeight: Math.min(contentHeight, 420 * HHUStyle.s)
            visible:                snapshotDialog.snapshots.length > 0
            clip:                   true
            spacing:                6 * HHUStyle.s
            model:                  snapshotDialog.snapshots

            delegate: HHUButton {
                required property var modelData
                width:      ListView.view.width
                text:       modelData.label
                kind:       "plain"
                size:       16
                onClicked: {
                    hhuTuning.loadParamFile(modelData.path)
                    snapshotDialog.close()
                }
            }
        }

        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton {
                text:       qsTr("Cancel")
                kind:       "plain"
                onClicked:  snapshotDialog.close()
            }
        ]
    }

    FileDialog {
        id:             importDialog
        title:          qsTr("Import .param")
        fileMode:       FileDialog.OpenFile
        nameFilters:    [ qsTr("Parameter files (*.param *.params *.txt)"), qsTr("All files (*)") ]
        onAccepted:     hhuTuning.loadParamFile(selectedFile.toString())
    }
}

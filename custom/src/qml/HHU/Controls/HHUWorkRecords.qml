import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 作业记录 (需求说明 V1.0 §3.7): filter by date, vehicle, field; totals of area and time;
/// export for Excel (CSV, UTF-8). Opened from the 校徽 menu.
Popup {
    id:             root
    parent:         mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
    anchors.centerIn: parent
    modal:          true
    focus:          true
    closePolicy:    Popup.CloseOnEscape
    padding:        ScreenTools.defaultFontPixelWidth * 2
    width:          parent ? parent.width * 0.94 : 1000
    height:         parent ? parent.height * 0.9 : 700

    property var _rows: []

    function refresh() {
        const vehicle = vehicleCombo.currentIndex > 0 ? vehicleCombo.currentText : ""
        const field = fieldCombo.currentIndex > 0 ? fieldCombo.currentText : ""
        _rows = hhuWork.query(fromField.text.trim(), toField.text.trim(), vehicle, field)
    }

    readonly property real _totalArea:  _rows.reduce((sum, r) => sum + (r.area || 0), 0)
    readonly property real _totalSec:   _rows.reduce((sum, r) => sum + (r.durationSec || 0), 0)
    readonly property real _totalRoute: _rows.reduce((sum, r) => sum + (r.routeLength || 0), 0)

    function _duration(sec) {
        const min = Math.round(sec / 60)
        return min >= 60 ? qsTr("%1 h %2 min").arg(Math.floor(min / 60)).arg(min % 60) : qsTr("%1 min").arg(min)
    }
    function _time(iso) {
        const d = new Date(iso)
        return isNaN(d.getTime()) ? "" : d.toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    onOpened: refresh()

    Connections {
        target: hhuWork
        function onRecordsChanged() { if (root.opened) root.refresh() }
    }

    FileDialog {
        id:             exportDialog
        title:          qsTr("Export work records")
        fileMode:       FileDialog.SaveFile
        nameFilters:    [ qsTr("Excel CSV (*.csv)") ]
        defaultSuffix:  "csv"
        onAccepted: {
            const ok = hhuWork.exportCsv(selectedFile.toString(), root._rows)
            QGroundControl.showMessageDialog(root, qsTr("Export work records"),
                                             ok ? qsTr("Exported %1 records.").arg(root._rows.length) : qsTr("The file could not be written."),
                                             Dialog.Ok)
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    background: Rectangle {
        color:          qgcPal.window
        radius:         ScreenTools.defaultFontPixelHeight * 0.5
        border.color:   "#004B97"
        border.width:   2
    }

    contentItem: ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight * 0.6

        RowLayout {
            Layout.fillWidth: true
            QGCLabel {
                text:               qsTr("Work records")
                font.pointSize:     ScreenTools.largeFontPointSize * hhuSettings.fontScale
                font.bold:          true
                color:              "#004B97"
            }
            Item { Layout.fillWidth: true }
            QGCButton {
                text:       qsTr("Export to Excel")
                enabled:    root._rows.length > 0
                onClicked:  exportDialog.open()
            }
            QGCButton {
                text:       qsTr("Close")
                onClicked:  root.close()
            }
        }

        // Filters
        Flow {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel { text: qsTr("From"); height: fromField.height; verticalAlignment: Text.AlignVCenter }
            QGCTextField {
                id:                 fromField
                width:              ScreenTools.defaultFontPixelWidth * 13
                placeholderText:    "2026-01-01"
                inputMask:          ""
                onEditingFinished:  root.refresh()
            }
            QGCLabel { text: qsTr("to"); height: fromField.height; verticalAlignment: Text.AlignVCenter }
            QGCTextField {
                id:                 toField
                width:              ScreenTools.defaultFontPixelWidth * 13
                placeholderText:    "2026-12-31"
                onEditingFinished:  root.refresh()
            }
            QGCLabel { text: qsTr("Vehicle"); height: fromField.height; verticalAlignment: Text.AlignVCenter }
            QGCComboBox {
                id:             vehicleCombo
                width:          ScreenTools.defaultFontPixelWidth * 22
                model:          [ qsTr("All") ].concat(hhuWork.vehicles)
                onActivated:    root.refresh()
            }
            QGCLabel { text: qsTr("Field"); height: fromField.height; verticalAlignment: Text.AlignVCenter }
            QGCComboBox {
                id:             fieldCombo
                width:          ScreenTools.defaultFontPixelWidth * 22
                model:          [ qsTr("All") ].concat(hhuWork.fieldNames)
                onActivated:    root.refresh()
            }
            QGCButton {
                text: qsTr("Today")
                onClicked: {
                    const today = new Date().toLocaleDateString(Qt.locale(), "yyyy-MM-dd")
                    fromField.text = today
                    toField.text = today
                    root.refresh()
                }
            }
            QGCButton {
                text: qsTr("Clear filter")
                onClicked: {
                    fromField.text = ""
                    toField.text = ""
                    vehicleCombo.currentIndex = 0
                    fieldCombo.currentIndex = 0
                    root.refresh()
                }
            }
        }

        // Totals
        Rectangle {
            Layout.fillWidth:   true
            implicitHeight:     totals.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.6
            radius:             ScreenTools.defaultFontPixelHeight * 0.3
            color:              "#E6EEF7"
            RowLayout {
                id:                 totals
                anchors.centerIn:   parent
                spacing:            ScreenTools.defaultFontPixelWidth * 4
                QGCLabel { text: qsTr("Records: %1").arg(root._rows.length); font.bold: true }
                QGCLabel { text: qsTr("Total area: %1").arg(hhuSettings.areaUnit >= 0 ? hhuSettings.formatArea(root._totalArea) : ""); font.bold: true }
                QGCLabel { text: qsTr("Total time: %1").arg(root._duration(root._totalSec)); font.bold: true }
                QGCLabel { text: qsTr("Route done: %1 m").arg(root._totalRoute.toFixed(0)); font.bold: true }
            }
        }

        // Table
        readonly property var _columns: [
            { title: qsTr("Date"),          width: 10 },
            { title: qsTr("Vehicle"),       width: 14 },
            { title: qsTr("Field"),         width: 14 },
            { title: qsTr("Start"),         width: 6 },
            { title: qsTr("End"),           width: 6 },
            { title: qsTr("Duration"),      width: 10 },
            { title: qsTr("Driven (m)"),    width: 8 },
            { title: qsTr("Area"),          width: 10 },
            { title: qsTr("Waypoints"),     width: 8 },
            { title: qsTr("Interruptions"), width: 8 },
            { title: qsTr("Finished"),      width: 6 }
        ]

        Row {
            Repeater {
                model: parent.parent._columns
                QGCLabel {
                    width:          ScreenTools.defaultFontPixelWidth * modelData.width * 1.6
                    text:           modelData.title
                    font.bold:      true
                    color:          "#5B6B7F"
                    elide:          Text.ElideRight
                }
            }
        }

        ListView {
            id:                 table
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            clip:               true
            model:              root._rows

            delegate: Rectangle {
                width:      table.width
                height:     cells.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.4
                color:      index % 2 ? "transparent" : "#F2F5F9"

                readonly property var _values: [
                    modelData.date,
                    modelData.vehicle,
                    modelData.field || qsTr("(no field)"),
                    root._time(modelData.start),
                    root._time(modelData.end),
                    root._duration(modelData.durationSec || 0),
                    (modelData.odometer || 0).toFixed(0),
                    hhuSettings.areaUnit >= 0 ? hhuSettings.formatArea(modelData.area || 0) : "",
                    modelData.fromSeq + "–" + modelData.toSeq,
                    modelData.interruptions,
                    modelData.completed ? qsTr("Yes") : qsTr("No")
                ]

                Row {
                    id:                     cells
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: parent.parent._values
                        QGCLabel {
                            width:  ScreenTools.defaultFontPixelWidth * table.parent._columns[index].width * 1.6
                            text:   modelData
                            elide:  Text.ElideRight
                        }
                    }
                }
            }
        }

        QGCLabel {
            Layout.fillWidth:       true
            visible:                root._rows.length === 0
            horizontalAlignment:    Text.AlignHCenter
            text:                   qsTr("No work records. A record is written for every work run, from Start work until the route is finished or the vehicle is stopped.")
            wrapMode:               Text.WordWrap
        }
    }
}

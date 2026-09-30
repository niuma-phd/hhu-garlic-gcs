import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 开始作业 with 断点续作 (需求说明 V1.0 §3.2): start from the first waypoint, from where work on this
/// field last stopped, or from a chosen waypoint; slide to confirm.
/// openStart(waypointCount, firstSeq, lastSeq, resumeSeq, fieldName, callback(seq))
Popup {
    id:             root
    parent:         mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
    anchors.centerIn: parent
    modal:          true
    focus:          true
    closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding:        ScreenTools.defaultFontPixelWidth * 2

    property int    firstSeq:   1
    property int    lastSeq:    1
    property int    resumeSeq:  0
    property int    waypoints:  0
    property string fieldName
    property int    choice:     0   ///< 0 first, 1 resume, 2 chosen
    property var    _callback:  null

    readonly property bool _resumeValid: resumeSeq > firstSeq && resumeSeq <= lastSeq

    function openStart(waypointCount, first, last, resume, field, callback) {
        waypoints = waypointCount
        firstSeq = first
        lastSeq = last
        resumeSeq = resume
        fieldName = field
        choice = _resumeValid ? 1 : 0
        seqSpin.value = _resumeValid ? resume : first
        _callback = callback
        open()
    }

    function _selectedSeq() {
        switch (choice) {
        case 1:  return resumeSeq
        case 2:  return seqSpin.value
        default: return firstSeq
        }
    }

    onOpened: slider.forceActiveFocus()

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    background: Rectangle {
        color:          qgcPal.window
        radius:         ScreenTools.defaultFontPixelHeight * 0.5
        border.color:   "#004B97"
        border.width:   2
    }

    contentItem: ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight * 0.8

        QGCLabel {
            text:               qsTr("Start work")
            font.pointSize:     ScreenTools.largeFontPointSize * hhuSettings.fontScale
            font.bold:          true
            color:              "#004B97"
        }

        QGCLabel {
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 44 * hhuSettings.fontScale
            wrapMode:               Text.WordWrap
            font.pointSize:         ScreenTools.defaultFontPointSize * hhuSettings.fontScale
            text: (root.fieldName !== "" ? qsTr("Field: %1. ").arg(root.fieldName) : "")
                  + qsTr("The vehicle will arm and drive the uploaded route (%1 waypoints). Make sure nobody is near the vehicle.").arg(root.waypoints)
        }

        QGCLabel {
            text:           qsTr("Start from")
            font.bold:      true
            font.pointSize: ScreenTools.defaultFontPointSize * hhuSettings.fontScale
        }

        QGCRadioButton {
            text:       qsTr("The first waypoint")
            checked:    root.choice === 0
            onClicked:  root.choice = 0
        }

        QGCRadioButton {
            text:       root._resumeValid ? qsTr("Where work last stopped (waypoint %1)").arg(root.resumeSeq)
                                          : qsTr("Where work last stopped (no record for this field)")
            enabled:    root._resumeValid
            checked:    root.choice === 1
            onClicked:  root.choice = 1
        }

        RowLayout {
            spacing: ScreenTools.defaultFontPixelWidth

            QGCRadioButton {
                text:       qsTr("Waypoint")
                checked:    root.choice === 2
                onClicked:  root.choice = 2
            }
            SpinBox {
                id:         seqSpin
                from:       root.firstSeq
                to:         Math.max(root.firstSeq, root.lastSeq)
                editable:   true
                enabled:    root.choice === 2
                font.pointSize: ScreenTools.defaultFontPointSize * hhuSettings.fontScale
            }
        }

        SliderSwitch {
            id:                     slider
            Layout.fillWidth:       true
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
            confirmText:            qsTr("Slide to start")
            fontPointSize:          ScreenTools.mediumFontPointSize * hhuSettings.fontScale
            onAccept: {
                const cb = root._callback
                const seq = root._selectedSeq()
                root.close()
                if (cb) {
                    cb(seq)
                }
            }
        }

        QGCButton {
            Layout.alignment:   Qt.AlignRight
            text:               qsTr("Cancel")
            onClicked:          root.close()
        }
    }
}

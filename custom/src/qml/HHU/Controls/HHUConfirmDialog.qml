import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Modal slide-to-confirm dialog for work actions (§5.2).
/// open(title, message, confirmText, callback, choices) — when choices (array of strings) is given,
/// the selected index is passed to callback.
Popup {
    id:             root
    parent:         mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
    anchors.centerIn: parent
    modal:          true
    focus:          true
    closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding:        ScreenTools.defaultFontPixelWidth * 2

    property string title
    property string message
    property string confirmText
    property var    choices:        []
    property int    choiceIndex:    0
    property var    _callback:      null

    function openAction(title, message, confirmText, callback, choices) {
        root.title          = title
        root.message        = message
        root.confirmText    = confirmText
        root.choices        = choices || []
        root.choiceIndex    = 0
        root._callback      = callback
        root.open()
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
        spacing: ScreenTools.defaultFontPixelHeight

        QGCLabel {
            text:               root.title
            font.pointSize:     ScreenTools.largeFontPointSize * hhuSettings.fontScale
            font.bold:          true
            color:              "#004B97"
        }

        QGCLabel {
            text:                   root.message
            wrapMode:               Text.WordWrap
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 40 * hhuSettings.fontScale
            font.pointSize:         ScreenTools.defaultFontPointSize * hhuSettings.fontScale
            visible:                text !== ""
        }

        ColumnLayout {
            visible: root.choices.length > 0
            Repeater {
                model: root.choices
                QGCRadioButton {
                    text:       modelData
                    checked:    index === root.choiceIndex
                    onClicked:  root.choiceIndex = index
                }
            }
        }

        SliderSwitch {
            id:                     slider
            Layout.fillWidth:       true
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
            confirmText:            root.confirmText
            fontPointSize:          ScreenTools.mediumFontPointSize * hhuSettings.fontScale
            onAccept: {
                const cb = root._callback
                const idx = root.choiceIndex
                root.close()
                if (cb) {
                    cb(idx)
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

import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Large touch button for outdoor use.
Rectangle {
    id: root

    property string text
    property string iconSource
    property color  accent:     "#004B97"

    signal clicked

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 22 * hhuSettings.fontScale
    implicitHeight: ScreenTools.defaultFontPixelHeight * 3.4 * hhuSettings.fontScale
    radius:         ScreenTools.defaultFontPixelHeight * 0.4
    color:          !enabled ? "#D9DEE5" : (mouseArea.pressed ? Qt.darker(accent, 1.25) : accent)
    opacity:        enabled ? 1.0 : 0.85

    RowLayout {
        anchors.fill:           parent
        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 1.5
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth
        spacing:                ScreenTools.defaultFontPixelWidth

        QGCColoredImage {
            source:                 root.iconSource
            color:                  root.enabled ? "white" : "#8A94A3"
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 1.6 * hhuSettings.fontScale
            Layout.preferredWidth:  Layout.preferredHeight
            sourceSize.height:      Layout.preferredHeight
        }
        QGCLabel {
            Layout.fillWidth:   true
            text:               root.text
            color:              root.enabled ? "white" : "#8A94A3"
            font.bold:          true
            font.pointSize:     ScreenTools.largeFontPointSize * hhuSettings.fontScale
            elide:              Text.ElideRight
        }
    }

    MouseArea {
        id:             mouseArea
        anchors.fill:   parent
        enabled:        root.enabled
        cursorShape:    Qt.PointingHandCursor
        onClicked:      root.clicked()
    }
}

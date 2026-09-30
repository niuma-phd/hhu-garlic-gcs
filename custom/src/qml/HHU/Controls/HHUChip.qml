import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Status item on the blue HHU toolbar: colored dot + title + detail line.
Item {
    id: root

    property string title
    property string detail
    property color  dotColor:   "transparent"
    property bool   showDot:    true

    signal clicked

    implicitWidth:  row.implicitWidth + ScreenTools.defaultFontPixelWidth * 2
    implicitHeight: parent ? parent.height : ScreenTools.toolbarHeight

    Rectangle {
        anchors.fill:       parent
        anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.25
        radius:             ScreenTools.defaultFontPixelHeight * 0.3
        color:              mouseArea.containsMouse ? "#1AFFFFFF" : "transparent"
    }

    RowLayout {
        id:                 row
        anchors.centerIn:   parent
        spacing:            ScreenTools.defaultFontPixelWidth * 0.8

        Rectangle {
            visible:                root.showDot
            Layout.alignment:       Qt.AlignVCenter
            width:                  ScreenTools.defaultFontPixelHeight * 0.7
            height:                 width
            radius:                 width / 2
            color:                  root.dotColor
            border.color:           "white"
            border.width:           1
        }

        ColumnLayout {
            spacing: 0

            QGCLabel {
                text:               root.title
                color:              "white"
                font.bold:          true
                font.pointSize:     ScreenTools.mediumFontPointSize * hhuSettings.fontScale
            }
            QGCLabel {
                text:               root.detail
                visible:            text !== ""
                color:              hhuSettings.highContrast ? "white" : "#CFE0F5"
                font.pointSize:     ScreenTools.smallFontPointSize * hhuSettings.fontScale
            }
        }
    }

    MouseArea {
        id:             mouseArea
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    Qt.PointingHandCursor
        onClicked:      root.clicked()
    }
}

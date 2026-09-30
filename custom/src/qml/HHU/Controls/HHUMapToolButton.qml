import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Small map button with icon + label. primary: filled blue (used for the 作业/航线 switch).
Rectangle {
    id: root

    property string text
    property string iconSource
    property bool   primary: false

    readonly property color _fg: primary ? "white" : "#004B97"

    signal clicked

    implicitWidth:  row.implicitWidth + ScreenTools.defaultFontPixelWidth * 2
    implicitHeight: ScreenTools.defaultFontPixelHeight * 2.2
    radius:         ScreenTools.defaultFontPixelHeight * 0.4
    color:          primary ? (mouseArea.pressed ? "#003A75" : "#004B97") : (mouseArea.pressed ? "#E6EEF7" : "#F2FFFFFF")
    border.color:   "#004B97"
    border.width:   1
    opacity:        enabled ? 1.0 : 0.5

    RowLayout {
        id:                 row
        anchors.centerIn:   parent
        spacing:            ScreenTools.defaultFontPixelWidth * 0.6

        QGCColoredImage {
            source:                 root.iconSource
            color:                  root._fg
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 1.1
            Layout.preferredWidth:  Layout.preferredHeight
            sourceSize.height:      Layout.preferredHeight
        }
        QGCLabel {
            text:   root.text
            color:  root._fg
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

import QtQuick
import QtQuick.Layouts

/// Status item of the top bar (设计稿 2a): color dot + short word.
/// Separated from the item before it by a thin line; tap opens the details.
Item {
    id: root

    property string text
    property color  dotColor

    signal clicked

    Layout.fillHeight:      true
    implicitWidth:          row.implicitWidth + HHUStyle.statusPad * 2

    Rectangle { width: 1; height: parent.height; color: HHUStyle.divider }

    Rectangle {
        anchors.fill:       parent
        anchors.margins:    6 * HHUStyle.s
        anchors.leftMargin: 6 * HHUStyle.s + 1
        radius:             8 * HHUStyle.s
        color:              mouse.containsMouse ? HHUStyle.grey2 : "transparent"
    }

    RowLayout {
        id:                 row
        anchors.centerIn:   parent
        spacing:            8 * HHUStyle.s

        Rectangle {
            Layout.preferredWidth:  12 * HHUStyle.s
            Layout.preferredHeight: Layout.preferredWidth
            radius:                 width / 2
            color:                  root.dotColor
        }

        HHUText {
            text:       root.text
            size:       16
            bold:       true
        }
    }

    MouseArea {
        id:             mouse
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    Qt.PointingHandCursor
        onClicked:      root.clicked()
    }
}

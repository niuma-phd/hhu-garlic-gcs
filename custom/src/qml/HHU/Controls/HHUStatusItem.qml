import QtQuick
import QtQuick.Layouts

/// Status item of the top bar (设计稿 2a): color dot + short word, or battery icon + percent.
/// Separated from the item before it by a thin line; tap opens the details.
Item {
    id: root

    property string text
    property color  dotColor
    property bool   battery:    false
    property real   batteryPct: NaN
    property bool   batteryLow: false

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
            visible:                !root.battery
            Layout.preferredWidth:  12 * HHUStyle.s
            Layout.preferredHeight: Layout.preferredWidth
            radius:                 width / 2
            color:                  root.dotColor
        }

        // battery outline with fill and tip
        Item {
            visible:                root.battery
            Layout.preferredWidth:  34 * HHUStyle.s
            Layout.preferredHeight: 16 * HHUStyle.s
            Rectangle {
                id:             body
                width:          30 * HHUStyle.s
                height:         parent.height
                radius:         3
                color:          "transparent"
                border.color:   HHUStyle.text
                border.width:   2
                Rectangle {
                    x:      3
                    y:      3
                    height: parent.height - 6
                    width:  isNaN(root.batteryPct) ? 0 : (parent.width - 6) * Math.max(0, Math.min(1, root.batteryPct / 100))
                    radius: 1
                    color:  root.batteryLow ? HHUStyle.red : HHUStyle.green
                }
            }
            Rectangle {
                anchors.left:           body.right
                anchors.leftMargin:     1
                anchors.verticalCenter: body.verticalCenter
                width:  3
                height: 6 * HHUStyle.s
                color:  HHUStyle.text
            }
        }

        HHUText {
            visible:    !root.battery
            text:       root.text
            size:       16
            bold:       true
        }
        HHUText {
            visible:    root.battery
            text:       isNaN(root.batteryPct) ? "—" : root.batteryPct.toFixed(0) + "%"
            size:       20
            number:     true
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

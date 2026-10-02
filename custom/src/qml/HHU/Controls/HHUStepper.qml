import QtQuick
import QtQuick.Layouts

/// − value + control (设计稿 2h), e.g. 1.2 m/s or a waypoint number.
Rectangle {
    id: root

    property real   value:      0
    property real   from:       0
    property real   to:         100
    property real   step:       1
    property int    decimals:   0
    property string unit

    signal edited(real value)

    implicitWidth:  row.implicitWidth
    implicitHeight: 52 * HHUStyle.s
    radius:         10 * HHUStyle.s
    border.color:   HHUStyle.border
    border.width:   2
    color:          "white"

    function _set(v) {
        v = Math.max(from, Math.min(to, Math.round(v / step) * step))
        if (v !== value) {
            edited(v)
        }
    }

    RowLayout {
        id:             row
        anchors.fill:   parent
        spacing:        0

        component StepButton: Item {
            id: stepButton
            property string glyph
            property bool   available
            signal pressed
            Layout.preferredWidth:  48 * HHUStyle.s
            Layout.fillHeight:      true
            opacity:                available ? 1 : 0.35
            HHUText { anchors.centerIn: parent; text: stepButton.glyph; size: 22; bold: true }
            MouseArea {
                anchors.fill:   parent
                enabled:        stepButton.available
                cursorShape:    Qt.PointingHandCursor
                onClicked:      stepButton.pressed()
                onPressAndHold: repeat.start()
                onReleased:     repeat.stop()
                Timer { id: repeat; interval: 120; repeat: true; onTriggered: stepButton.pressed() }
            }
        }

        StepButton { glyph: "−"; available: root.value > root.from; onPressed: root._set(root.value - root.step) }
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: HHUStyle.border }
        HHUText {
            Layout.minimumWidth:    80 * HHUStyle.s
            Layout.leftMargin:      12 * HHUStyle.s
            Layout.rightMargin:     12 * HHUStyle.s
            horizontalAlignment:    Text.AlignHCenter
            text:                   root.value.toFixed(root.decimals) + (root.unit !== "" ? " " + root.unit : "")
            number:                 true
            size:                   18
        }
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: HHUStyle.border }
        StepButton { glyph: "+"; available: root.value < root.to; onPressed: root._set(root.value + root.step) }
    }
}

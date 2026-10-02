import QtQuick

/// Slide to confirm (设计稿 2e): 84×56 knob in a 64 px track. Releasing before the right end springs back.
Item {
    id: root

    property string text
    property color  color:  HHUStyle.blue

    signal accepted

    function reset() { knob.x = _pad }

    implicitHeight: 64 * HHUStyle.s
    implicitWidth:  360 * HHUStyle.s

    readonly property real _pad:    4 * HHUStyle.s
    readonly property real _maxX:   width - knob.width - _pad

    Rectangle {
        anchors.fill:   parent
        radius:         height / 2
        color:          root.color
    }

    // filled part behind the knob
    Rectangle {
        x:          0
        height:     parent.height
        width:      knob.x + knob.width + root._pad
        radius:     height / 2
        color:      Qt.darker(root.color, 1.15)
        visible:    knob.x > root._pad
    }

    HHUText {
        anchors.verticalCenter: parent.verticalCenter
        x:                      knob.width + root._pad + (parent.width - knob.width - root._pad - width) / 2
        text:                   root.text + " ›››"
        size:                   18
        bold:                   true
        color:                  "white"
        opacity:                1 - Math.min(1, (knob.x - root._pad) / Math.max(1, root._maxX) * 1.5)
    }

    Rectangle {
        id:             knob
        x:              root._pad
        y:              root._pad
        width:          84 * HHUStyle.s
        height:         parent.height - root._pad * 2
        radius:         height / 2
        color:          "white"

        Behavior on x { enabled: !drag.drag.active; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        HHUIcon {
            anchors.centerIn:   parent
            name:               "arrow"
            size:               30
            color:              root.color
        }

        MouseArea {
            id:                 drag
            anchors.fill:       parent
            cursorShape:        Qt.PointingHandCursor
            drag.target:        knob
            drag.axis:          Drag.XAxis
            drag.minimumX:      root._pad
            drag.maximumX:      root._maxX
            onReleased: {
                if (knob.x >= root._maxX - 2) {
                    knob.x = root._maxX
                    root.accepted()
                } else {
                    knob.x = root._pad
                }
            }
        }
    }
}

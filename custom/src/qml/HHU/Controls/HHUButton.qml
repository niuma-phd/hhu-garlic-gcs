import QtQuick
import QtQuick.Layouts

/// Button of the HHU design. `kind`: "blue" | "green" | "yellow" | "red" | "outline" | "plain".
/// Disabled buttons turn grey. `size`: font size (design px), height follows `h`.
Item {
    id: root

    property string text
    property string icon
    property string kind:       "blue"
    property real   size:       17
    property real   h:          HHUStyle.touch
    property real   minWidth:   0
    property bool   shadow:     false
    property bool   whiteRim:   false   ///< 2 px white border (buttons on the map)

    signal clicked

    implicitHeight: h
    implicitWidth:  Math.max(minWidth * HHUStyle.s, row.implicitWidth + 40 * HHUStyle.s)
    opacity:        1

    readonly property var _c: {
        if (!enabled) return { bg: HHUStyle.disabledBg, fg: HHUStyle.disabledText, bd: whiteRim ? "white" : HHUStyle.disabledBg }
        switch (kind) {
        case "green":   return { bg: HHUStyle.green,  fg: "white",              bd: whiteRim ? "white" : HHUStyle.green }
        case "yellow":  return { bg: HHUStyle.yellow, fg: HHUStyle.yellowText,  bd: whiteRim ? "white" : HHUStyle.yellow }
        case "red":     return { bg: HHUStyle.red,    fg: "white",              bd: whiteRim ? "white" : HHUStyle.red }
        case "outline": return { bg: "white",         fg: HHUStyle.blue,        bd: HHUStyle.blue }
        case "plain":   return { bg: "white",         fg: HHUStyle.text,        bd: HHUStyle.border }
        default:        return { bg: HHUStyle.blue,   fg: "white",              bd: whiteRim ? "white" : HHUStyle.blue }
        }
    }

    HHUCard {
        anchors.fill:   parent
        visible:        root.shadow
        radius:         bg.radius
    }

    Rectangle {
        id:             bg
        anchors.fill:   parent
        radius:         12 * HHUStyle.s
        color:          mouse.pressed ? Qt.darker(root._c.bg, 1.12) : root._c.bg
        border.color:   root._c.bd
        border.width:   2
    }

    RowLayout {
        id:                 row
        anchors.centerIn:   parent
        spacing:            10 * HHUStyle.s

        HHUIcon {
            visible:    root.icon !== ""
            name:       root.icon
            size:       root.size + 4
            color:      root._c.fg
        }
        HHUText {
            text:       root.text
            size:       root.size
            bold:       true
            color:      root._c.fg
        }
    }

    MouseArea {
        id:             mouse
        anchors.fill:   parent
        cursorShape:    Qt.PointingHandCursor
        onClicked:      root.clicked()
    }
}

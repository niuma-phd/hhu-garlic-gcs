import QtQuick
import QtQuick.Controls

/// Text input of the HHU design (设计稿 2h): 48 px, 2 px border, blue when focused.
TextField {
    id: root

    implicitHeight:     48 * HHUStyle.s
    leftPadding:        12 * HHUStyle.s
    rightPadding:       12 * HHUStyle.s
    font.family:        HHUStyle.fontFamily
    font.pixelSize:     HHUStyle.px(16)
    color:              HHUStyle.text
    placeholderTextColor: HHUStyle.neutral
    selectByMouse:      true

    background: Rectangle {
        radius:         10 * HHUStyle.s
        color:          "white"
        border.color:   root.activeFocus ? HHUStyle.blue : HHUStyle.border
        border.width:   2
    }
}

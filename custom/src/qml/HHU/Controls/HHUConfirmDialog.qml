import QtQuick
import QtQuick.Layouts

/// Slide-to-confirm dialog for work actions (设计稿 4j): round icon + title, what will happen,
/// 取消 and the slide in the footer.
/// openAction(title, message, slideText, callback, icon, color)
HHUDialog {
    id: root

    property string message
    property string slideText
    property color  slideColor: HHUStyle.blue
    property var    _callback:  null

    function openAction(title, message, slideText, callback, icon, color) {
        root.title      = title
        root.message    = message
        root.slideText  = slideText
        root.icon       = icon || ""
        root.iconColor  = color || HHUStyle.blue
        root.slideColor = color || HHUStyle.blue
        root._callback  = callback
        slide.reset()
        root.open()
    }

    HHUText {
        Layout.fillWidth:   true
        text:               root.message
        size:               18
        lineHeight:         1.3
        wrapMode:           Text.WordWrap
    }

    footerItems: [
        HHUButton {
            text:       qsTr("Cancel")
            kind:       "plain"
            size:       18
            h:          64 * HHUStyle.s
            minWidth:   120
            onClicked:  root.close()
        },
        HHUSlide {
            id:                 slide
            Layout.fillWidth:   true
            text:               root.slideText
            color:              root.slideColor
            onAccepted: {
                const cb = root._callback
                root.close()
                if (cb) {
                    cb()
                }
            }
        }
    ]
}

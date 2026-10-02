import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/// Modal dialog of the HHU design (设计稿 2d): white, radius 18, big title, grey footer with the buttons.
/// Content goes into the body; the footer row is `footer` (children placed left to right).
Popup {
    id: root

    property string title
    property string subtitle
    property string icon            ///< optional round icon before the title
    property color  iconColor:  HHUStyle.red
    property real   dialogWidth: 520
    default property alias body:    bodyColumn.data
    property alias footerItems:     footerRow.data

    parent:             mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
    anchors.centerIn:   parent
    modal:              true
    focus:              true
    closePolicy:        Popup.CloseOnEscape
    padding:            0
    width:              Math.min(dialogWidth * HHUStyle.s, parent ? parent.width - 32 : dialogWidth)

    Overlay.modal: Rectangle { color: HHUStyle.dim }

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 } }
    exit:  Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 } }

    background: Rectangle {
        radius: HHUStyle.radiusDlg
        color:  "white"
    }

    contentItem: ColumnLayout {
        spacing: 0

        ColumnLayout {
            Layout.fillWidth:   true
            Layout.margins:     28 * HHUStyle.s
            Layout.topMargin:   24 * HHUStyle.s
            Layout.bottomMargin: 20 * HHUStyle.s
            spacing:            14 * HHUStyle.s

            RowLayout {
                spacing: 12 * HHUStyle.s

                Rectangle {
                    visible:                root.icon !== ""
                    Layout.preferredWidth:  48 * HHUStyle.s
                    Layout.preferredHeight: Layout.preferredWidth
                    radius:                 width / 2
                    color:                  Qt.lighter(root.iconColor, 1.9)
                    HHUIcon {
                        anchors.centerIn:   parent
                        name:               root.icon
                        size:               26
                        color:              root.iconColor
                    }
                }
                ColumnLayout {
                    spacing: 4 * HHUStyle.s
                    HHUText { text: root.title; size: 28; bold: true }
                    HHUText { text: root.subtitle; size: 16; color: HHUStyle.text3; visible: text !== "" }
                }
            }

            ColumnLayout {
                id:                 bodyColumn
                Layout.fillWidth:   true
                spacing:            10 * HHUStyle.s
            }
        }

        Rectangle {
            Layout.fillWidth:       true
            Layout.preferredHeight: footerRow.implicitHeight + 40 * HHUStyle.s
            color:                  HHUStyle.grey
            radius:                 HHUStyle.radiusDlg
            visible:                footerRow.children.length > 0

            // square top corners of the footer
            Rectangle { width: parent.width; height: parent.radius; color: parent.color }
            Rectangle { width: parent.width; height: 1; color: HHUStyle.divider }

            RowLayout {
                id:                 footerRow
                anchors.left:       parent.left
                anchors.right:      parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 28 * HHUStyle.s
                anchors.rightMargin: 28 * HHUStyle.s
                spacing:            12 * HHUStyle.s
            }
        }
    }
}

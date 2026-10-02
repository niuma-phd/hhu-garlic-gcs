import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl

/// Vehicle messages (设计稿 2g): newest first, colored bar by level, time; 清空 clears them.
/// Opening it marks the messages as read.
Popup {
    id: root

    parent:         mainWindow.contentItem
    padding:        0
    width:          Math.min(420 * HHUStyle.s, parent ? parent.width - 16 : 420)
    height:         Math.min(list.contentHeight + header.height + (_items.length === 0 ? 60 * HHUStyle.s : 2), (parent ? parent.height : 600) * 0.7)
    closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property var _vehicle: QGroundControl.multiVehicleManager.activeVehicle

    function openAt(item) {
        const p = item.mapToItem(parent, item.width, item.height)
        x = Math.max(8, Math.min(p.x - width, parent.width - width - 8))
        y = p.y + 4
        open()
    }

    onOpened: if (_vehicle) _vehicle.resetAllMessages()

    function _unescape(t) {
        return t.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&")
    }

    /// [{ level: "E" | "I" | "N", time, text }] from the upstream formatted message log (newest first)
    readonly property var _items: {
        if (!_vehicle || !visible) return []
        const out = []
        const re = /<font style="<#([EIN])>">\[(\d\d:\d\d:\d\d)[^\]]*\][^:]*:\s*([\s\S]*?)<\/font>/g
        const text = _vehicle.formattedMessages
        let m
        while ((m = re.exec(text)) !== null && out.length < 200) {
            out.push({ level: m[1], time: m[2], text: _unescape(m[3]) })
        }
        return out
    }

    background: HHUCard {}

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            id:                     header
            Layout.fillWidth:       true
            Layout.preferredHeight: 60 * HHUStyle.s
            color:                  HHUStyle.grey
            radius:                 HHUStyle.radiusCard
            Rectangle { y: parent.height - parent.radius; width: parent.width; height: parent.radius; color: parent.color }

            RowLayout {
                anchors.fill:           parent
                anchors.leftMargin:     16 * HHUStyle.s
                anchors.rightMargin:    12 * HHUStyle.s
                HHUText { Layout.fillWidth: true; text: qsTr("Messages"); size: 17; bold: true }
                HHUButton {
                    text:       qsTr("Clear")
                    kind:       "plain"
                    size:       15
                    h:          44 * HHUStyle.s
                    enabled:    root._items.length > 0
                    onClicked:  if (root._vehicle) root._vehicle.clearMessages()
                }
            }
        }

        HHUText {
            visible:            root._items.length === 0
            Layout.margins:     20 * HHUStyle.s
            text:               qsTr("No messages")
            size:               16
            color:              HHUStyle.text3
        }

        ListView {
            id:                 list
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            clip:               true
            model:              root._items
            boundsBehavior:     Flickable.StopAtBounds

            delegate: Item {
                width:  ListView.view.width
                height: col.implicitHeight + 20 * HHUStyle.s

                Rectangle { width: parent.width; height: 1; color: HHUStyle.divider }
                Rectangle {
                    x:      14 * HHUStyle.s
                    y:      10 * HHUStyle.s
                    width:  4
                    height: parent.height - 20 * HHUStyle.s
                    radius: 2
                    color:  modelData.level === "E" ? HHUStyle.red : (modelData.level === "I" ? HHUStyle.yellow : HHUStyle.disabledBg)
                }
                ColumnLayout {
                    id:         col
                    x:          28 * HHUStyle.s
                    y:          10 * HHUStyle.s
                    width:      parent.width - x - 16 * HHUStyle.s
                    spacing:    2
                    HHUText {
                        Layout.fillWidth:   true
                        text:               modelData.text
                        size:               16
                        bold:               modelData.level !== "N"
                        wrapMode:           Text.WordWrap
                    }
                    HHUText {
                        text:   modelData.time
                        size:   14
                        color:  HHUStyle.text3
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings
import HHU.Controls

/// HHU override of QGroundControl/Controls/AppSettings.qml (设计稿 6a–6d): grey page, white navigation
/// on the left (通用 / 连接 / 地图 / 差分定位 / 关于), the page on the right. 高级 (after-sales) is
/// opened from the 关于 page. showSettingsPage() takes the upstream page keys.
Rectangle {
    id:     settingsView
    color:  HHUStyle.grey
    z:      QGroundControl.zOrderTopMost

    readonly property var _pages: [
        { key: "General",    name: qsTr("General"),     url: "qrc:/qml/QGroundControl/AppSettings/GeneralSettings.qml" },
        { key: "Comm Links", name: qsTr("Connection"),  url: "qrc:/qml/QGroundControl/AppSettings/CommLinksSettings.qml" },
        { key: "Maps",       name: qsTr("Map"),         url: "qrc:/qml/QGroundControl/AppSettings/MapsSettings.qml" },
        { key: "NTRIP/RTK",  name: qsTr("RTK"),         url: "qrc:/qml/QGroundControl/AppSettings/NTRIPSettings.qml" },
        { key: "About",      name: qsTr("About"),       url: "qrc:/qml/QGroundControl/AppSettings/HHUAboutSettings.qml" }
    ]
    readonly property string _advancedUrl: "qrc:/qml/QGroundControl/AppSettings/HHUAdvancedSettings.qml"

    property int  _selected: 0
    property bool _advanced: false

    function showSettingsPage(settingsPage) {
        if (settingsPage === "Advanced") {
            _selected = _pages.length - 1
            _advanced = true
            page.source = _advancedUrl
            return
        }
        for (let i = 0; i < _pages.length; i++) {
            if (_pages[i].key === settingsPage) {
                _show(i)
                return
            }
        }
    }

    function _show(index) {
        _selected = index
        _advanced = false
        page.source = _pages[index].url
    }

    Component.onCompleted: _show(0)

    // This need to block click event leakage to underlying map.
    DeadMouseArea {
        anchors.fill: parent
    }

    Rectangle {
        id:             nav
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        width:          220 * HHUStyle.s
        color:          "white"

        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: HHUStyle.settingsBorder }

        Column {
            anchors.fill:       parent
            anchors.margins:    12 * HHUStyle.s
            spacing:            4 * HHUStyle.s

            Repeater {
                model: settingsView._pages

                Rectangle {
                    readonly property bool _sel: index === settingsView._selected
                    width:  parent.width
                    height: 56 * HHUStyle.s
                    radius: 10 * HHUStyle.s
                    color:  _sel ? HHUStyle.blueLight : (navMouse.containsMouse ? HHUStyle.grey : "transparent")

                    Rectangle {
                        visible:    parent._sel
                        width:      4 * HHUStyle.s
                        height:     parent.height - 16 * HHUStyle.s
                        anchors.verticalCenter: parent.verticalCenter
                        radius:     2
                        color:      HHUStyle.blue
                    }
                    HHUText {
                        anchors.verticalCenter: parent.verticalCenter
                        x:          16 * HHUStyle.s
                        text:       modelData.name
                        size:       17
                        bold:       parent._sel
                        color:      parent._sel ? HHUStyle.blue : HHUStyle.text
                    }
                    MouseArea {
                        id:             navMouse
                        anchors.fill:   parent
                        hoverEnabled:   true
                        cursorShape:    Qt.PointingHandCursor
                        onClicked:      settingsView._show(index)
                    }
                }
            }
        }
    }

    HHUText {
        id:                     pageTitle
        anchors.top:            parent.top
        anchors.left:           nav.right
        anchors.topMargin:      20 * HHUStyle.s
        anchors.leftMargin:     24 * HHUStyle.s
        text:                   settingsView._pages[settingsView._selected].name + (settingsView._advanced ? " › " + qsTr("After-sales settings") : "")
        size:                   24
        bold:                   true
    }

    Loader {
        id:                     page
        anchors.top:            pageTitle.bottom
        anchors.bottom:         parent.bottom
        anchors.left:           nav.right
        anchors.right:          parent.right
        anchors.topMargin:      16 * HHUStyle.s
        anchors.leftMargin:     24 * HHUStyle.s
        anchors.rightMargin:    24 * HHUStyle.s
    }
}

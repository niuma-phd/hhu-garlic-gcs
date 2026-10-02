import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Toolbar

/// Top bar of the 作业 / 规划 / 设置 pages (设计稿 5.1): 作业 / 规划 switch, connection, position and
/// battery as color dot + short word (tap for details), vehicle state tag, messages, settings.
/// `page`: "work" | "plan" | "settings" (no tab highlighted, no status items).
/// Children are placed in the free space in the middle (e.g. the slide-to-confirm of the 作业 page).
Rectangle {
    id: root

    property string page: "work"
    default property alias centerContent: centerSlot.data

    width:  parent.width
    height: HHUStyle.barH
    color:  "white"

    /// Written by the upstream MainStatusIndicator / GuidedActionConfirm (they expect the upstream toolbar)
    property color _mainStatusBGColor: "transparent"
    property bool  _communicationLost: _vehicle ? _vehicle.vehicleLinkManager.communicationLost : false

    function dropMainStatusIndicator() {
        messages.openAt(bellButton)
    }

    // 1280×720 at 150 % and smaller: compact sizes (设计稿 §7)
    Binding {
        target:     HHUStyle
        property:   "compact"
        value:      mainWindow.height < 620 || mainWindow.width < 1000
    }

    HHUStatus { id: status }

    readonly property var  _vehicle:    status.vehicle
    readonly property bool _statusShown: page !== "settings"
    /// 4G link quality the operator notices: slow answers or many lost packets
    readonly property bool _weakLink:   status.connected && ((hhuLink.latencyMs > 1500) || (_vehicle && _vehicle.mavlinkLossPercent > 20))

    readonly property var _conn: {
        if (!_vehicle) {
            return hhu4G.active && hhu4G.state !== "online" ? { t: qsTr("Connecting"), c: HHUStyle.yellow }
                                                          : { t: qsTr("Not connected"), c: HHUStyle.neutral }
        }
        if (status.linkLost)    return { t: qsTr("Link lost"),      c: HHUStyle.red }
        if (status.readOnly)    return { t: qsTr("View only"),      c: HHUStyle.blue }
        if (_weakLink)          return { t: qsTr("Weak signal"),    c: HHUStyle.yellow }
        return { t: qsTr("Connected"), c: HHUStyle.green }
    }
    readonly property var _pos: {
        if (!_vehicle)          return { t: "—",                    c: HHUStyle.disabledBg }
        if (status.rtkFixed)    return { t: qsTr("Position good"),  c: HHUStyle.green }
        if (status.fixType >= 3) return { t: qsTr("Position poor"), c: HHUStyle.yellow }
        return { t: qsTr("No position"), c: HHUStyle.red }
    }
    readonly property bool _vcuFault:   !!_vehicle && status.vcuValid && hhuVcu.fault !== 0
    /// State tag at the right (设计稿 2a)
    readonly property var _work: {
        if (!_vehicle)          return { t: "—",                        bg: HHUStyle.grey2,       fg: HHUStyle.text3, bd: HHUStyle.border }
        if (_vcuFault)          return { t: qsTr("Fault"),              bg: HHUStyle.red,         fg: "white",        bd: HHUStyle.red }
        if (status.routeDone)   return { t: qsTr("Done"),         bg: HHUStyle.greenLight,  fg: HHUStyle.green,     bd: HHUStyle.green }
        if (status.inAuto && status.armed)  return { t: qsTr("Working"), bg: HHUStyle.green,      fg: "white",        bd: HHUStyle.green }
        if (status.inPause && status.armed) return { t: qsTr("Paused"),  bg: HHUStyle.yellow,     fg: HHUStyle.yellowText, bd: HHUStyle.yellow }
        if (status.inReturn && status.armed) return { t: qsTr("Returning"), bg: HHUStyle.blue,    fg: "white",        bd: HHUStyle.blue }
        if (status.inGuided && status.armed) return { t: qsTr("To target"), bg: HHUStyle.blue,    fg: "white",        bd: HHUStyle.blue }
        if (status.armed)       return { t: qsTr("Manual"),             bg: "white",              fg: HHUStyle.text,  bd: HHUStyle.text }
        if (hhuVcu.seen && (!status.vcuValid || !hhuVcu.ok)) return { t: qsTr("Chassis not ready"), bg: HHUStyle.yellowLight, fg: HHUStyle.text, bd: HHUStyle.yellow }
        return { t: qsTr("Standby"), bg: HHUStyle.grey2, fg: HHUStyle.text, bd: HHUStyle.border }
    }

    // bottom shadow line
    Rectangle {
        anchors.top:    parent.bottom
        width:          parent.width
        height:         2
        color:          "#24142030"
    }

    RowLayout {
        anchors.fill:           parent
        anchors.leftMargin:     12 * HHUStyle.s
        anchors.rightMargin:    8 * HHUStyle.s
        spacing:                0

        // ---- 作业 / 规划 ------------------------------------------------------------------
        Rectangle {
            Layout.alignment:       Qt.AlignVCenter
            implicitWidth:          tabRow.implicitWidth + 6
            implicitHeight:         HHUStyle.tabH + 6
            radius:                 10 * HHUStyle.s
            color:                  HHUStyle.grey2

            Row {
                id:                 tabRow
                anchors.centerIn:   parent
                spacing:            3

                Repeater {
                    model: [ { page: "work", t: qsTr("Work") }, { page: "plan", t: qsTr("Plan") } ]
                    Rectangle {
                        readonly property bool _sel: modelData.page === root.page
                        width:  tabLabel.implicitWidth + HHUStyle.tabPad * 2
                        height: HHUStyle.tabH
                        radius: 8 * HHUStyle.s
                        color:  _sel ? HHUStyle.blue : (tabMouse.containsMouse ? "white" : "transparent")

                        HHUText {
                            id:                 tabLabel
                            anchors.centerIn:   parent
                            text:               modelData.t
                            size:               17
                            bold:               true
                            color:              parent._sel ? "white" : HHUStyle.text
                        }
                        MouseArea {
                            id:             tabMouse
                            anchors.fill:   parent
                            hoverEnabled:   true
                            cursorShape:    Qt.PointingHandCursor
                            onClicked: {
                                if (parent._sel || !mainWindow.allowViewSwitch()) {
                                    return
                                }
                                if (modelData.page === "plan") {
                                    mainWindow.showPlanView()
                                } else {
                                    mainWindow.showFlyView()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- 连接 / 定位 / 电量 ----------------------------------------------------------
        HHUStatusItem {
            id:         connItem
            visible:    root._statusShown
            dotColor:   root._conn.c
            text:       root._conn.t
            onClicked:  detail.openConnection(connItem)
        }
        HHUStatusItem {
            id:         posItem
            visible:    root._statusShown
            dotColor:   root._pos.c
            text:       root._pos.t
            onClicked:  detail.openPosition(posItem)
        }
        HHUStatusItem {
            id:         battItem
            visible:    root._statusShown
            battery:    true
            batteryPct: !!root._vehicle ? status.batteryPct : NaN
            batteryLow: status.batteryPct <= hhuSettings.lowBatteryPct
            onClicked:  detail.openBattery(battItem)
        }

        Item {
            id:                 centerSlot
            Layout.fillWidth:   true
            Layout.fillHeight:  true
        }

        // ---- 车辆状态 ---------------------------------------------------------------------
        Rectangle {
            visible:                root._statusShown
            Layout.alignment:       Qt.AlignVCenter
            Layout.rightMargin:     8 * HHUStyle.s
            implicitWidth:          workLabel.implicitWidth + 28 * HHUStyle.s
            implicitHeight:         36 * HHUStyle.s
            radius:                 8 * HHUStyle.s
            color:                  root._work.bg
            border.color:           root._work.bd
            border.width:           1
            HHUText {
                id:                 workLabel
                anchors.centerIn:   parent
                text:               root._work.t
                size:               16
                bold:               true
                color:              root._work.fg
            }
        }

        // ---- 消息 -------------------------------------------------------------------------
        Item {
            id:                     bellButton
            visible:                root._statusShown
            Layout.preferredWidth:  48 * HHUStyle.s
            Layout.preferredHeight: 48 * HHUStyle.s
            Rectangle {
                anchors.fill:   parent
                radius:         10 * HHUStyle.s
                color:          bellMouse.containsMouse ? HHUStyle.grey2 : "transparent"
            }
            HHUIcon {
                anchors.centerIn:   parent
                name:               "bell"
                size:               26
            }
            Rectangle {
                visible:        !!root._vehicle && root._vehicle.messageCount > 0
                x:              parent.width - width - 3
                y:              4
                width:          Math.max(height, badge.implicitWidth + 10)
                height:         20 * HHUStyle.s
                radius:         height / 2
                color:          HHUStyle.red
                border.color:   "white"
                border.width:   2
                HHUText {
                    id:                 badge
                    anchors.centerIn:   parent
                    text:               root._vehicle ? root._vehicle.messageCount : ""
                    size:               13
                    number:             true
                    color:              "white"
                }
            }
            MouseArea {
                id:             bellMouse
                anchors.fill:   parent
                hoverEnabled:   true
                cursorShape:    Qt.PointingHandCursor
                onClicked:      messages.openAt(bellButton)
            }
        }

        // ---- 设置 -------------------------------------------------------------------------
        Item {
            visible:                root.page !== "settings"
            Layout.preferredWidth:  48 * HHUStyle.s
            Layout.preferredHeight: 48 * HHUStyle.s
            Rectangle {
                anchors.fill:   parent
                radius:         10 * HHUStyle.s
                color:          gearMouse.containsMouse ? HHUStyle.grey2 : "transparent"
            }
            HHUIcon {
                anchors.centerIn:   parent
                name:               "settings"
                size:               26
            }
            MouseArea {
                id:             gearMouse
                anchors.fill:   parent
                hoverEnabled:   true
                cursorShape:    Qt.PointingHandCursor
                onClicked:      mainWindow.showSettingsTool()
            }
        }
    }

    HHUStatusDetail { id: detail }
    HHUMessageList { id: messages }
}

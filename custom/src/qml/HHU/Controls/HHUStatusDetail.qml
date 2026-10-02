import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl

/// Details behind a top bar status item: a small card under the item with a few label / value rows
/// and a button to the matching settings page.
Popup {
    id: root

    parent:         mainWindow.contentItem
    padding:        16 * HHUStyle.s
    closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string title
    property string action
    property string settingsPage
    property string _kind

    HHUStatus { id: status }

    function _openUnder(item) {
        const p = item.mapToItem(parent, 0, item.height)
        x = Math.max(8, Math.min(p.x, parent.width - width - 8))
        y = p.y + 4
        open()
    }

    function openConnection(item) { _kind = "conn"; title = qsTr("Connection"); action = qsTr("Connection settings"); settingsPage = "Comm Links"; _openUnder(item) }
    function openPosition(item)   { _kind = "pos";  title = qsTr("Position");   action = qsTr("RTK settings");        settingsPage = "NTRIP/RTK";  _openUnder(item) }
    function openBattery(item)    { _kind = "batt"; title = qsTr("Battery");    action = "";                          settingsPage = "";           _openUnder(item) }

    readonly property var _connRows: {
        const v = status.vehicle
        if (!v) {
            return [ { k: qsTr("State"), v: hhu4G.active ? hhu4G.statusText : qsTr("Not connected") } ]
        }
        let list = [ { k: qsTr("Connection"),  v: status.linkTypeText || "—" },
                     { k: qsTr("Delay"),       v: hhuLink.latencyMs >= 0 ? qsTr("%1 ms").arg(hhuLink.latencyMs) : "—" },
                     { k: qsTr("Packet loss"), v: v.mavlinkLossPercent.toFixed(0) + "%" } ]
        if (status.linkLost) {
            list.unshift({ k: qsTr("State"), v: qsTr("No data for %1 s").arg(hhuLink.silentSec) })
        }
        if (status.readOnly) {
            list.push({ k: qsTr("Control"), v: qsTr("Another ground station controls the vehicle") })
        }
        return list
    }
    readonly property var _posRows: {
        if (!status.vehicle) return []
        const fix = status.rtkFixed ? qsTr("RTK fixed") : (status.rtkFloat ? qsTr("RTK float") : (status.fixType >= 3 ? qsTr("Single point") : qsTr("No fix")))
        return [ { k: qsTr("Fix"),        v: fix },
                 { k: qsTr("Satellites"), v: String(status.satCount) },
                 { k: qsTr("HDOP"),       v: isNaN(status.hdop) ? "—" : status.hdop.toFixed(1) } ]
    }
    readonly property var _battRows: {
        if (!status.vehicle) return []
        return [ { k: qsTr("Battery"),     v: isNaN(status.batteryPct) ? "—" : status.batteryPct.toFixed(0) + "%" },
                 { k: qsTr("Voltage"),     v: isNaN(status.batteryVolts) ? "—" : qsTr("%1 V").arg(status.batteryVolts.toFixed(1)) },
                 { k: qsTr("Alarm below"), v: hhuSettings.lowBatteryPct + "%" } ]
    }
    readonly property var _rows: _kind === "conn" ? _connRows : (_kind === "pos" ? _posRows : _battRows)

    background: HHUCard {}

    contentItem: ColumnLayout {
        spacing: 10 * HHUStyle.s

        HHUText { text: root.title; size: 18; bold: true }

        GridLayout {
            columns:        2
            columnSpacing:  24 * HHUStyle.s
            rowSpacing:     6 * HHUStyle.s
            Repeater {
                model: root._rows.length * 2
                HHUText {
                    readonly property var _r: root._rows[Math.floor(index / 2)]
                    text:                   _r ? (index % 2 === 0 ? _r.k : _r.v) : ""
                    size:                   16
                    bold:                   index % 2 === 1
                    color:                  index % 2 === 0 ? HHUStyle.text3 : HHUStyle.text
                    Layout.maximumWidth:    260 * HHUStyle.s
                    wrapMode:               Text.WordWrap
                }
            }
        }

        HHUButton {
            visible:            root.action !== ""
            Layout.fillWidth:   true
            text:               root.action
            kind:               "outline"
            size:               16
            onClicked: {
                root.close()
                mainWindow.showSettingsTool(root.settingsPage)
            }
        }
    }
}

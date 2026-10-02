import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Summary card at the bottom right of the 规划 page (设计稿 5a–5e): field area while choosing / drawing
/// the field; waypoints, length and time once the route is planned (showRoute).
HHUCard {
    id: root

    property var  missionController
    property var  geoFenceController
    property bool showRoute: false

    implicitWidth:  row.implicitWidth + 28 * HHUStyle.s
    implicitHeight: row.implicitHeight + 20 * HHUStyle.s
    width:          implicitWidth
    height:         implicitHeight
    radius:         12 * HHUStyle.s

    readonly property int   _count:     missionController ? Math.max(0, missionController.visualItems.count - 1) : 0
    readonly property real  _distance:  missionController ? missionController.missionTotalDistance : 0
    readonly property real  _time:      missionController ? missionController.missionTime : 0
    readonly property real  _fenceArea: {
        let area = 0
        if (geoFenceController) {
            for (let i = 0; i < geoFenceController.polygons.count; i++) {
                const polygon = geoFenceController.polygons.get(i)
                if (polygon.inclusion) {
                    area += polygon.area
                }
            }
        }
        return area
    }

    HHUStatus { id: status }

    function _fmtDist(m) {
        return m >= 1000 ? qsTr("%1 km").arg((m / 1000).toFixed(2)) : qsTr("%1 m").arg(m.toFixed(0))
    }
    function _fmtTime(s) {
        if (!(s > 0)) return "--"
        const min = Math.round(s / 60)
        return min >= 60 ? qsTr("%1 h %2 min").arg(Math.floor(min / 60)).arg(min % 60) : qsTr("%1 min").arg(Math.max(1, min))
    }

    component Value: Column {
        property string label
        property string value
        property string unit
        HHUText { text: parent.label; size: 14; color: HHUStyle.text3 }
        Row {
            spacing: 3
            HHUText { text: parent.parent.value; number: true; size: 22 }
            HHUText { text: parent.parent.unit; size: 14; anchors.bottom: parent.bottom; bottomPadding: 3 }
        }
    }

    Row {
        id:         row
        anchors.centerIn: parent
        spacing:    20 * HHUStyle.s

        Value {
            visible:    !root.showRoute
            label:      qsTr("Area")
            value:      root._fenceArea > 0 ? hhuSettings.formatArea(root._fenceArea).split(" ")[0] : "--"
            unit:       root._fenceArea > 0 ? (hhuSettings.formatArea(root._fenceArea).split(" ")[1] || "") : ""
        }
        Value { visible: root.showRoute; label: qsTr("Waypoints"); value: String(root._count); unit: qsTr("pcs") }
        Value {
            visible:    root.showRoute
            label:      qsTr("Length")
            value:      root._distance >= 1000 ? (root._distance / 1000).toFixed(2) : root._distance.toFixed(0)
            unit:       root._distance >= 1000 ? "km" : "m"
        }
        Value {
            visible:    root.showRoute
            label:      qsTr("Time")
            value:      root._time > 0 ? String(Math.max(1, Math.round(root._time / 60))) : "--"
            unit:       qsTr("min")
        }
    }
}

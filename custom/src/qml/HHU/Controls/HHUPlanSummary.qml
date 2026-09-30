import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Route summary card on the 航线 page (需求说明 V1.0 §3.3): waypoint count, total length,
/// estimated time, and the field area enclosed by the geofence (亩 / 公顷 per 通用设置).
Rectangle {
    id: root

    property var missionController
    property var geoFenceController

    implicitWidth:  grid.implicitWidth + _pad * 2
    implicitHeight: grid.implicitHeight + _pad * 2
    radius:         ScreenTools.defaultFontPixelHeight * 0.5
    color:          status.panelColor
    border.color:   "#004B97"
    border.width:   status.panelBorder

    property real _pad: ScreenTools.defaultFontPixelWidth * 1.2

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

    GridLayout {
        id:                 grid
        anchors.centerIn:   parent
        columns:            root._fenceArea > 0 ? 4 : 3
        rowSpacing:         ScreenTools.defaultFontPixelHeight * 0.2
        columnSpacing:      ScreenTools.defaultFontPixelWidth * 3
        flow:               GridLayout.TopToBottom
        rows:               2

        QGCLabel { text: qsTr("Waypoints");      color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: root._count;            font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }

        QGCLabel { text: qsTr("Total length");   color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: root._fmtDist(root._distance); font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }

        QGCLabel { text: qsTr("Estimated time"); color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: root._fmtTime(root._time); font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }

        QGCLabel { text: qsTr("Field area");     color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale; visible: root._fenceArea > 0 }
        QGCLabel { text: hhuSettings.areaUnit >= 0 ? hhuSettings.formatArea(root._fenceArea) : ""; font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale; visible: root._fenceArea > 0 }
    }
}

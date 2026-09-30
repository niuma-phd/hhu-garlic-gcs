import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Bottom status card (需求说明 §5.3): waypoint progress, distance/time left, speed, heading.
Rectangle {
    id: root

    property var missionController

    implicitWidth:  grid.implicitWidth + _pad * 2
    implicitHeight: grid.implicitHeight + _pad * 2
    radius:         ScreenTools.defaultFontPixelHeight * 0.5
    color:          status.panelColor
    border.color:   "#004B97"
    border.width:   status.panelBorder

    property real _pad: ScreenTools.defaultFontPixelWidth * 1.2

    HHUStatus { id: status }

    readonly property var   _vehicle:       status.vehicle
    readonly property int   _total:         missionController ? Math.max(0, missionController.visualItems.count - 1) : 0
    readonly property int   _current:       _vehicle ? _vehicle.missionItemIndex.rawValue : 0
    readonly property real  _speed:         _vehicle ? _vehicle.groundSpeed.rawValue : 0

    /// Route geometry of the vehicle's mission: waypoints by sequence number, total length
    readonly property var   _route: {
        let points = []
        let length = 0
        if (missionController) {
            const items = missionController.visualItems
            for (let i = 1; i < items.count; i++) {
                const item = items.get(i)
                if (item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                    if (points.length > 0) {
                        length += points[points.length - 1].coordinate.distanceTo(item.coordinate)
                    }
                    points.push({ seq: item.sequenceNumber, coordinate: item.coordinate, cumulative: length })
                }
            }
        }
        return { points: points, length: length }
    }

    /// Remaining = vehicle → current target + the legs after it (整条航线 when not started)
    readonly property real  _remainDist: {
        const points = _route.points
        if (points.length === 0) return 0
        let target = points.findIndex(p => p.seq >= _current)
        if (target < 0) return 0    // past the last waypoint
        if (_current < 1) target = 0
        const legs = _route.length - points[target].cumulative
        const toTarget = _vehicle && _vehicle.coordinate.isValid && (status.inAuto || _paused) ? _vehicle.coordinate.distanceTo(points[target].coordinate) : 0
        return legs + toTarget
    }
    readonly property bool  _paused:        status.inPause && status.armed
    readonly property real  _progress:      _route.length > 0 ? Math.min(1, Math.max(0, 1 - (_remainDist / _route.length))) : 0
    readonly property real  _remainTime:    _speed > 0.1 ? _remainDist / _speed : NaN

    function _fmtDist(m) {
        return m >= 1000 ? qsTr("%1 km").arg((m / 1000).toFixed(2)) : qsTr("%1 m").arg(m.toFixed(0))
    }
    function _fmtTime(s) {
        if (isNaN(s)) return "--"
        const min = Math.floor(s / 60)
        return min >= 60 ? qsTr("%1 h %2 min").arg(Math.floor(min / 60)).arg(min % 60) : qsTr("%1 min").arg(Math.max(1, min))
    }

    GridLayout {
        id:                 grid
        anchors.centerIn:   parent
        columns:            5
        rowSpacing:         ScreenTools.defaultFontPixelHeight * 0.2
        columnSpacing:      ScreenTools.defaultFontPixelWidth * 3

        QGCLabel { text: qsTr("Waypoint");       color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: qsTr("Distance left");  color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: qsTr("Time left");      color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: qsTr("Speed");          color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: qsTr("Heading");        color: status.labelColor; font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale }

        QGCLabel { text: root._total > 0 ? "%1 / %2".arg(Math.min(root._current, root._total)).arg(root._total) : "--"; font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: root._total > 0 ? root._fmtDist(root._remainDist) : "--";  font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: status.inAuto ? root._fmtTime(root._remainTime) : "--";     font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: root._vehicle ? qsTr("%1 m/s").arg(root._speed.toFixed(1)) : "--"; font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }
        QGCLabel { text: root._vehicle ? "%1°".arg(root._vehicle.heading.rawValue.toFixed(0)) : "--"; font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale }

        Rectangle {
            Layout.columnSpan:      5
            Layout.fillWidth:       true
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.35
            radius:                 height / 2
            color:                  "#D9E3EF"
            visible:                root._total > 0
            Rectangle {
                width:  parent.width * root._progress
                height: parent.height
                radius: parent.radius
                color:  "#1F8A3B"
            }
        }
    }
}

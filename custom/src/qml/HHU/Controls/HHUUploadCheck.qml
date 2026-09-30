import QtQuick
import QtQuick.Dialogs
import QtPositioning

import QGroundControl
import QGroundControl.Controls

/// Route checks of the 航线 page (需求说明 V1.0 §3.3).
/// Warnings (user may upload anyway): turn too sharp for TURN_RADIUS, more waypoints than
/// hhuSettings.maxWaypoints, first waypoint more than 5 km from the vehicle.
/// Errors (upload refused): no geofence, waypoints outside the geofence, read-only 4G connection.
/// With live: true, tightTurns is kept up to date for the red map markers.
Item {
    id: root

    property var  planMasterController
    property bool live: false

    readonly property real maxVehicleDistance: 5000    // m

    /// [{ seq, coordinate }] of waypoints where the vehicle cannot make the turn (live mode)
    property var tightTurns: []

    readonly property var _missionController:   planMasterController ? planMasterController.missionController : null
    readonly property var _fenceController:     planMasterController ? planMasterController.geoFenceController : null
    readonly property var _vehicle:             QGroundControl.multiVehicleManager.activeVehicle

    HHUFence { id: fence; geoFenceController: root._fenceController }

    /// TURN_RADIUS of the vehicle; kept up to date by the plugin, last value kept for offline planning
    function _turnRadius() {
        return hhuSettings.lastTurnRadius
    }

    function _waypoints() {
        let points = []     // { seq, coordinate }
        if (!_missionController) {
            return points
        }
        const items = _missionController.visualItems
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                points.push({ seq: item.sequenceNumber, coordinate: item.coordinate })
            }
        }
        return points
    }

    /// A corner turning by angle t needs a tangent length r*tan(t/2), which must fit in
    /// half of the shorter adjacent segment
    function _findTightTurns(points, turnRadius) {
        let tight = []
        if (isNaN(turnRadius) || turnRadius <= 0) {
            return tight
        }
        for (let j = 1; j + 1 < points.length; j++) {
            const a = points[j - 1].coordinate, p = points[j].coordinate, b = points[j + 1].coordinate
            const l1 = a.distanceTo(p), l2 = p.distanceTo(b)
            if (l1 < 0.01 || l2 < 0.01) {
                continue
            }
            let turn = Math.abs(p.azimuthTo(b) - a.azimuthTo(p)) % 360
            if (turn > 180) {
                turn = 360 - turn
            }
            if (turn < 5) {
                continue
            }
            const maxRadius = turn >= 179 ? 0 : (Math.min(l1, l2) / 2) / Math.tan(turn * Math.PI / 360)
            if (maxRadius < turnRadius) {
                tight.push(points[j])
            }
        }
        return tight
    }

    function _seqList(points) {
        return points.slice(0, 15).map(p => p.seq).join(", ") + (points.length > 15 ? " …" : "")
    }

    /// { errors: [...], warnings: [...] } (strings)
    function check() {
        const points = _waypoints()
        let errors = []
        let warnings = []

        if (hhu4G.active && hhu4G.readOnly) {
            errors.push(qsTr("Read-only connection: another ground station controls this vehicle. The route can be edited and saved but not uploaded."))
        }

        if (!fence.hasInclusion()) {
            errors.push(qsTr("The route has no geofence. Draw the field boundary as a geofence first."))
        } else {
            const outside = points.filter(p => !fence.contains(p.coordinate))
            if (outside.length > 0) {
                errors.push(qsTr("Waypoints outside the geofence: %1").arg(_seqList(outside)))
            }
        }

        const turnRadius = _turnRadius()
        const tight = _findTightTurns(points, turnRadius)
        if (tight.length > 0) {
            warnings.push(qsTr("Turns too sharp for the vehicle (turn radius %1 m) at waypoints: %2 (marked red on the map)").arg(turnRadius.toFixed(1)).arg(_seqList(tight)))
        }

        if (points.length > hhuSettings.maxWaypoints) {
            warnings.push(qsTr("The route has %1 waypoints, more than the limit of %2.").arg(points.length).arg(hhuSettings.maxWaypoints))
        }

        if (_vehicle && _vehicle.coordinate.isValid && points.length > 0) {
            const d = _vehicle.coordinate.distanceTo(points[0].coordinate)
            if (d > maxVehicleDistance) {
                warnings.push(qsTr("The first waypoint is %1 km from the vehicle.").arg((d / 1000).toFixed(1)))
            }
        }
        return { errors: errors, warnings: warnings }
    }

    /// Runs the checks, then calls uploadFn directly, after the user confirms the warnings, or not at all
    function run(uploadFn) {
        const result = check()
        if (result.errors.length > 0) {
            QGroundControl.showMessageDialog(root, qsTr("Route cannot be uploaded"),
                                             result.errors.concat(result.warnings).map(s => "• " + s).join("\n"),
                                             Dialog.Ok)
            return
        }
        if (result.warnings.length === 0) {
            uploadFn()
            return
        }
        QGroundControl.showMessageDialog(root, qsTr("Check the route"),
                                         result.warnings.map(s => "• " + s).join("\n") + "\n\n" + qsTr("Upload anyway?"),
                                         Dialog.Ok | Dialog.Cancel, uploadFn)
    }

    // ---- Live tight turn markers ---------------------------------------------------------

    function _updateTightTurns() {
        tightTurns = live ? _findTightTurns(_waypoints(), _turnRadius()) : []
    }

    Timer {
        id:             recalcTimer
        interval:       300
        onTriggered:    root._updateTightTurns()
    }

    Connections {
        target:     root.live ? root._missionController : null
        function onMissionTotalDistanceChanged() { recalcTimer.restart() }
        function onVisualItemsReset() { recalcTimer.restart() }
    }

    Connections {
        target:     root.live && root._missionController ? root._missionController.visualItems : null
        function onCountChanged() { recalcTimer.restart() }
    }

    Connections {
        target:     root.live ? hhuSettings : null
        function onChanged() { recalcTimer.restart() }
    }

    Component.onCompleted: if (live) recalcTimer.restart()
}

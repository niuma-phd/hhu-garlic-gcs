import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Progress card at the bottom left of the 作业 page (设计稿 4b–4h): field name, big percent, time left,
/// progress bar, one small line with waypoint / distance / speed. While driving to a target point
/// (开到指定点) it shows that trip instead.
HHUCard {
    id: root

    property var missionController

    width:          HHUStyle.cardW
    implicitHeight: column.implicitHeight + HHUStyle.cardPad * 2

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
        return m >= 1000 ? (m / 1000).toFixed(2) + " km" : m.toFixed(0) + " m"
    }

    /// Field on the vehicle (as uploaded from the 规划 page; re-read when the route on the vehicle changes)
    readonly property string _fieldName: {
        const id = _vehicle && _total >= 0 ? hhuWork.vehicleField(_vehicle) : ""
        return id !== "" ? (hhuFields.field(id).name || "") : ""
    }

    readonly property bool _started:    _current >= 1 && (status.inAuto || _paused || status.inReturn)
    readonly property bool _goto:       status.inGuided && status.armed && !!HHUState.gotoTarget
    readonly property real _gotoLeft:   _goto && _vehicle.coordinate.isValid ? _vehicle.coordinate.distanceTo(HHUState.gotoTarget) : 0
    /// Planned time of the whole route: QGC's estimate, else length / cruise speed
    readonly property real _routeTime: {
        if (missionController && missionController.missionTime > 0) return missionController.missionTime
        const v = QGroundControl.settingsManager.appSettings.offlineEditingCruiseSpeed.rawValue
        return v > 0 ? _route.length / v : NaN
    }
    readonly property real _fraction: status.routeDone ? 1 : _goto ? (HHUState.gotoStartDist > 0 ? Math.max(0, 1 - _gotoLeft / HHUState.gotoStartDist) : 0)
                                            : (_started ? _progress : 0)
    /// seconds left: from the current speed while moving, else estimated
    readonly property real _secondsLeft: {
        if (_goto) return _speed > 0.1 ? _gotoLeft / _speed : NaN
        if (_started && _speed > 0.1) return _remainDist / _speed
        if (_started) return _route.length > 0 ? _routeTime * _remainDist / _route.length : NaN
        return _routeTime
    }
    readonly property bool _vcuFault:   status.vcuValid && hhuVcu.fault !== 0
    readonly property color _barColor:  (_paused || _vcuFault) ? HHUStyle.yellow : HHUStyle.green

    ColumnLayout {
        id:                 column
        anchors.fill:       parent
        anchors.margins:    HHUStyle.cardPad
        spacing:            0

        HHUText {
            Layout.fillWidth:   true
            text:               root._goto ? qsTr("To target point") : (root._fieldName !== "" ? root._fieldName : qsTr("Route on the vehicle"))
            size:               16
            bold:               true
            color:              HHUStyle.text2
            elide:              Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth:   true
            Layout.topMargin:   4 * HHUStyle.s
            spacing:            10 * HHUStyle.s

            Row {
                HHUText { text: (root._fraction * 100).toFixed(0); number: true; font.pixelSize: HHUStyle.pctFont; height: font.pixelSize }
                HHUText { text: "%"; number: true; size: 20; anchors.bottom: parent.bottom }
            }
            Item { Layout.fillWidth: true }
            HHUText {
                visible:    status.routeDone
                text:       qsTr("Done")
                size:       24
                bold:       true
                color:      HHUStyle.green
            }
            Row {
                visible: !status.routeDone
                spacing: 4 * HHUStyle.s
                Layout.alignment: Qt.AlignBottom
                HHUText {
                    anchors.baseline: leftValue.baseline
                    text:   root._goto || root._started ? qsTr("left") : qsTr("about")
                    size:   16
                    color:  HHUStyle.text2
                }
                HHUText {
                    id:     leftValue
                    text:   root._goto ? root._gotoLeft.toFixed(0) : (isNaN(root._secondsLeft) ? "--" : String(Math.max(1, Math.round(root._secondsLeft / 60))))
                    number: true
                    size:   24
                }
                HHUText {
                    anchors.baseline: leftValue.baseline
                    text:   root._goto ? qsTr("m") : qsTr("min")
                    size:   16
                    color:  HHUStyle.text2
                }
            }
        }

        Rectangle {
            Layout.fillWidth:       true
            Layout.topMargin:       10 * HHUStyle.s
            Layout.preferredHeight: 12 * HHUStyle.s
            radius:                 height / 2
            color:                  HHUStyle.divider
            Rectangle {
                width:  parent.width * root._fraction
                height: parent.height
                radius: parent.radius
                color:  root._barColor
            }
        }

        HHUText {
            Layout.fillWidth:   true
            Layout.topMargin:   8 * HHUStyle.s
            size:               14
            color:              HHUStyle.text3
            elide:              Text.ElideRight
            text: {
                const speed = root._speed > 0.05 ? " · " + root._speed.toFixed(1) + " m/s" : ""
                if (status.routeDone) return qsTr("All %1 waypoints driven").arg(root._route.points.length)
                if (root._goto) return root._speed.toFixed(1) + " m/s"
                if (!root._started) return qsTr("%1 waypoints").arg(root._route.points.length) + " · " + root._fmtDist(root._route.length)
                return qsTr("Waypoint %1/%2").arg(Math.min(root._current, root._total)).arg(root._total) + " · " + root._fmtDist(root._remainDist) + speed
            }
        }
    }
}

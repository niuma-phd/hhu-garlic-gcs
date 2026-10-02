import QtQuick
import QtQuick.Dialogs
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls

/// 开到指定点 (需求说明 V1.0 §3.2, 设计稿 2e / 4h): long press or right click on the 作业 map → a small card
/// at the point "开到这里？ 离车 XX m" with 取消 / 开过去; the vehicle switches to GUIDED, drives to the
/// point (flag) and stops there. The point must be inside the geofence; not available while the link
/// is lost or view only. 暂停 stops it at any time (work panel).
Item {
    id: root

    property var mapControl
    property var planMasterController

    HHUStatus { id: status }
    HHUFence { id: fence; geoFenceController: root.planMasterController ? root.planMasterController.geoFenceController : null }

    property var _target: QtPositioning.coordinate()
    property bool _armPending: false

    /// Called by the map on a long press / right click
    function request(coordinate) {
        const vehicle = status.vehicle
        let reason = ""
        if (!vehicle) {
            reason = qsTr("Not connected")
        } else if (status.linkLost) {
            reason = qsTr("Link lost")
        } else if (status.readOnly) {
            reason = qsTr("Read-only connection")
        } else if (!fence.hasInclusion()) {
            reason = qsTr("There is no geofence on the vehicle. Upload the field boundary first.")
        } else if (!fence.contains(coordinate)) {
            reason = qsTr("The point is outside the geofence.")
        }
        if (reason !== "") {
            QGroundControl.showMessageDialog(root, qsTr("Drive here"), reason, Dialog.Ok)
            return
        }
        _target = coordinate
        _distance = vehicle.coordinate.isValid ? vehicle.coordinate.distanceTo(coordinate) : NaN
        askCard.visible = true
    }

    property real _distance: NaN

    function _cancel() {
        askCard.visible = false
    }

    function _go() {
        const vehicle = status.vehicle
        if (!vehicle) {
            return
        }
        askCard.visible = false
        marker.visible = true
        HHUState.gotoTarget = _target
        HHUState.gotoStartDist = isNaN(_distance) ? 0 : _distance
        vehicle.prearmError = ""
        if (!vehicle.armed) {
            // A disarmed rover does not move: arm in GUIDED first, then send the point
            vehicle.flightMode = vehicle.gotoFlightMode
            vehicle.armed = true
            _armPending = true
            armTimeout.restart()
        } else {
            vehicle.guidedModeGotoLocation(_target)
        }
        confirmTimer.restart()
    }

    Connections {
        target: status.vehicle
        function onArmedChanged(armed) {
            if (armed && root._armPending) {
                root._armPending = false
                armTimeout.stop()
                status.vehicle.guidedModeGotoLocation(root._target)
            }
        }
    }

    Timer {
        id:         armTimeout
        interval:   Math.max(hhuSettings.commandTimeoutSec, 3) * 1000
        onTriggered: root._armPending = false
    }

    // 指令未执行 when the vehicle is not in GUIDED in time
    Timer {
        id:         confirmTimer
        interval:   Math.max(hhuSettings.commandTimeoutSec, 5) * 1000 + 1000
        onTriggered: {
            if (status.vehicle && !(status.inGuided && status.armed)) {
                marker.visible = false
                HHUState.gotoTarget = null
                let text = qsTr("The vehicle did not carry out \"%1\". Check the vehicle state and try again.").arg(qsTr("Drive here"))
                if (status.vehicle.prearmError !== "") {
                    text += "\n\n" + status.vehicle.prearmError
                }
                QGroundControl.showMessageDialog(root, qsTr("Command not executed"), text, Dialog.Ok)
            }
        }
    }

    // Target point: flag (设计稿 3), shown while the vehicle drives there
    MapQuickItem {
        id:             marker
        visible:        false
        coordinate:     root._target
        anchorPoint.x:  10 * HHUStyle.s
        anchorPoint.y:  sourceItem.height
        z:              QGroundControl.zOrderMapItems + 3

        sourceItem: Item {
            width:  44 * HHUStyle.s
            height: 48 * HHUStyle.s
            // pole
            Rectangle { x: 9 * HHUStyle.s; y: 4 * HHUStyle.s; width: 3 * HHUStyle.s; height: parent.height - 8 * HHUStyle.s; color: HHUStyle.text }
            // flag
            Canvas {
                x:      12 * HHUStyle.s
                y:      4 * HHUStyle.s
                width:  28 * HHUStyle.s
                height: 20 * HHUStyle.s
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.fillStyle = HHUStyle.blue
                    c.strokeStyle = "white"
                    c.lineWidth = 2
                    c.beginPath()
                    c.moveTo(0, 0); c.lineTo(width - 1, 0); c.lineTo(width * 0.7, height / 2); c.lineTo(width - 1, height - 1); c.lineTo(0, height - 1)
                    c.closePath()
                    c.fill(); c.stroke()
                }
            }
            // foot
            Rectangle {
                x:              4 * HHUStyle.s
                y:              parent.height - 10 * HHUStyle.s
                width:          13 * HHUStyle.s
                height:         width
                radius:         width / 2
                color:          HHUStyle.blue
                border.color:   "white"
                border.width:   2
            }
        }
    }

    // Line vehicle → target while driving there
    MapPolyline {
        id:         gotoLine
        visible:    marker.visible && !!status.vehicle && status.vehicle.coordinate.isValid
        line.width: 2
        line.color: "white"
        path:       visible ? [ status.vehicle.coordinate, root._target ] : []
        z:          QGroundControl.zOrderMapItems + 2
    }

    // 开到这里？ card at the point
    MapQuickItem {
        id:             askCard
        visible:        false
        coordinate:     root._target
        anchorPoint.x:  sourceItem.width / 2
        anchorPoint.y:  sourceItem.height + 8 * HHUStyle.s
        z:              QGroundControl.zOrderMapItems + 4

        sourceItem: HHUCard {
            width:  260 * HHUStyle.s
            height: askColumn.implicitHeight + 32 * HHUStyle.s

            Column {
                id:         askColumn
                x:          16 * HHUStyle.s
                y:          16 * HHUStyle.s
                width:      parent.width - 32 * HHUStyle.s
                spacing:    4 * HHUStyle.s

                HHUText { text: qsTr("Drive here?"); size: 18; bold: true }
                HHUText {
                    text:   isNaN(root._distance) ? "" : qsTr("%1 m from the vehicle").arg(root._distance.toFixed(0))
                    size:   15
                    color:  HHUStyle.text3
                }
                Item { width: 1; height: 8 * HHUStyle.s }
                Row {
                    spacing: 10 * HHUStyle.s
                    HHUButton {
                        width:      (askColumn.width - 10 * HHUStyle.s) / 2
                        text:       qsTr("Cancel")
                        kind:       "plain"
                        size:       16
                        onClicked:  root._cancel()
                    }
                    HHUButton {
                        width:      (askColumn.width - 10 * HHUStyle.s) / 2
                        text:       qsTr("Drive")
                        kind:       "blue"
                        size:       16
                        onClicked:  root._go()
                    }
                }
            }
        }
    }

    Connections {
        target: status
        function onInGuidedChanged() {
            if (!status.inGuided && !confirmTimer.running) {
                marker.visible = false
                HHUState.gotoTarget = null
            }
        }
    }

    Component.onCompleted: {
        if (mapControl) {
            mapControl.addMapItem(marker)
            mapControl.addMapItem(gotoLine)
            mapControl.addMapItem(askCard)
        }
    }
}

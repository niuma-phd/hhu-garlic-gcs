import QtQuick
import QtQuick.Dialogs
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls

/// 开到指定点 (需求说明 V1.0 §3.2): long press on the 作业 map → "开到这里", slide to confirm, the vehicle
/// switches to GUIDED, drives to the point and stops there. The point must be inside the geofence;
/// not available while the link is lost or read only. 暂停 stops it at any time (work panel).
Item {
    id: root

    property var mapControl
    property var planMasterController

    HHUStatus { id: status }
    HHUFence { id: fence; geoFenceController: root.planMasterController ? root.planMasterController.geoFenceController : null }
    HHUConfirmDialog { id: confirmDialog }

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
        marker.visible = true
        const distance = vehicle.coordinate.isValid ? vehicle.coordinate.distanceTo(coordinate) : NaN
        confirmDialog.openAction(qsTr("Drive here"),
                                 (isNaN(distance) ? "" : qsTr("Distance %1 m. ").arg(distance.toFixed(0)))
                                 + qsTr("The vehicle will drive straight to this point and stop there. Tap Pause to stop it earlier."),
                                 qsTr("Slide to drive"),
                                 function() { root._go() })
    }

    function _go() {
        const vehicle = status.vehicle
        if (!vehicle) {
            return
        }
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
                let text = qsTr("The vehicle did not carry out \"%1\". Check the vehicle state and try again.").arg(qsTr("Drive here"))
                if (status.vehicle.prearmError !== "") {
                    text += "\n\n" + status.vehicle.prearmError
                }
                QGroundControl.showMessageDialog(root, qsTr("Command not executed"), text, Dialog.Ok)
            }
        }
    }

    // Target marker: shown while confirming and while the vehicle drives there
    MapQuickItem {
        id:             marker
        visible:        false
        coordinate:     root._target
        anchorPoint.x:  sourceItem.width / 2
        anchorPoint.y:  sourceItem.height
        z:              QGroundControl.zOrderMapItems + 3

        sourceItem: Column {
            spacing: 0
            Rectangle {
                width:      targetLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 2
                height:     targetLabel.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.4
                radius:     height / 4
                color:      "#004B97"
                QGCLabel {
                    id:                 targetLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Target")
                    color:              "white"
                    font.bold:          true
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width:      ScreenTools.defaultFontPixelHeight * 0.3
                height:     ScreenTools.defaultFontPixelHeight
                color:      "#004B97"
            }
        }
    }

    Connections {
        target: confirmDialog
        function onClosed() {
            // Cancelled: hide the marker unless the vehicle is heading there (checked after the
            // confirm callback has run)
            Qt.callLater(function() {
                if (!confirmTimer.running && !status.inGuided) {
                    marker.visible = false
                }
            })
        }
    }

    Connections {
        target: status
        function onInGuidedChanged() {
            if (!status.inGuided && !confirmTimer.running) {
                marker.visible = false
            }
        }
    }

    Component.onCompleted: {
        if (mapControl) {
            mapControl.addMapItem(marker)
        }
    }
}

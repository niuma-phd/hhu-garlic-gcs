import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Work buttons (需求说明 V1.0 §3.2). Only the buttons that apply to the current state are shown:
/// 未连接 → 连接车辆; 待机 → 开始作业; 作业中 → 暂停 / 返回; 已暂停 → 继续 / 返回;
/// 返回中 / 前往目标点 → 暂停; 停车上锁 whenever the vehicle is armed;
/// nothing while the link is lost or the 4G connection is read only.
/// A command the vehicle has not carried out after hhuSettings.commandTimeoutSec is reported as 指令未执行.
/// 开始作业 offers 断点续作 and starts the work record (hhuWork).
Rectangle {
    id: root

    property var planMasterController

    implicitWidth:  column.implicitWidth + _pad * 2
    implicitHeight: column.implicitHeight + _pad * 2
    radius:         ScreenTools.defaultFontPixelHeight * 0.5
    color:          status.panelColor
    border.color:   "#004B97"
    border.width:   status.panelBorder

    property real _pad: ScreenTools.defaultFontPixelWidth

    readonly property var   _vehicle:           status.vehicle
    readonly property var   _missionController: planMasterController ? planMasterController.missionController : null
    readonly property var   _fenceController:   planMasterController ? planMasterController.geoFenceController : null
    readonly property int   _missionItems:      _missionController ? _missionController.visualItems.count - 1 : 0
    readonly property bool  _missionAvailable:  _missionItems > 0
    readonly property bool  _fenceAvailable:    !!_fenceController && (_fenceController.polygons.count > 0 || _fenceController.circles.count > 0)
    readonly property bool  _paused:            status.inPause && status.armed
    readonly property bool  _idle:              !!_vehicle && !status.inAuto && !_paused && !status.inReturn && !status.inGuided

    /// First reason (in this order) why 开始作业 is not possible, "" when it is
    readonly property string _startBlockedReason: {
        if (!_vehicle)              return qsTr("Not connected")
        if (status.linkLost)        return qsTr("Link lost")
        if (status.readOnly)        return qsTr("Read-only connection")
        if (!_missionAvailable)     return qsTr("No route on vehicle")
        if (!_fenceAvailable)       return qsTr("No geofence on vehicle")
        if (!status.rtkFixed)       return qsTr("Waiting for RTK fixed")
        return ""
    }

    HHUStatus { id: status }

    // ---- Command confirmation ------------------------------------------------------------

    property string _pendingName
    property var    _pendingCheck:   null
    property var    _pendingSuccess: null
    property real   _pendingDeadline: 0

    /// Remember what the vehicle should do; onSuccess runs once it happened, 指令未执行 is shown
    /// when it has not happened in time
    function _expect(name, check, minSeconds, onSuccess) {
        _pendingName = name
        _pendingCheck = check
        _pendingSuccess = onSuccess || null
        _pendingDeadline = Date.now() + Math.max(hhuSettings.commandTimeoutSec, minSeconds || 0) * 1000
        commandTimer.restart()
    }

    Timer {
        id:         commandTimer
        interval:   500
        repeat:     true
        onTriggered: {
            const check = root._pendingCheck
            if (!check || !root._vehicle) {
                stop()
                return
            }
            if (check()) {
                stop()
                root._pendingCheck = null
                if (root._pendingSuccess) {
                    root._pendingSuccess()
                }
                return
            }
            if (Date.now() < root._pendingDeadline) {
                return
            }
            stop()
            root._pendingCheck = null
            let text = qsTr("The vehicle did not carry out \"%1\". Check the vehicle state and try again.").arg(root._pendingName)
            if (root._vehicle.prearmError !== "") {
                text += "\n\n" + root._vehicle.prearmError
            }
            QGroundControl.showMessageDialog(root, qsTr("Command not executed"), text, Dialog.Ok)
        }
    }

    // ---- Route on the vehicle ------------------------------------------------------------

    /// { first, last, count, cumulative[seq] = route length (m) from the first waypoint }
    function _routeInfo() {
        let info = { first: 0, last: 0, count: 0, cumulative: [] }
        const items = _missionController.visualItems
        let prev = null
        let length = 0
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            const seq = item.sequenceNumber
            if (item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                if (prev) {
                    length += prev.distanceTo(item.coordinate)
                }
                prev = item.coordinate
                if (info.first === 0) info.first = seq
                info.last = seq
                info.count++
            }
            while (info.cumulative.length <= seq) {
                info.cumulative.push(length)
            }
            info.cumulative[seq] = length
        }
        return info
    }

    // ---- Actions -------------------------------------------------------------------------

    function _openStart() {
        const route = _routeInfo()
        const fieldId = hhuWork.vehicleField(_vehicle)
        const field = hhuFields.field(fieldId)
        startDialog.openStart(route.count, route.first, route.last,
                              hhuWork.resumeWaypoint(_vehicle, fieldId), field.name || "",
                              function(seq) { root._startWork(seq, route, fieldId, field) })
    }

    function _startWork(seq, route, fieldId, field) {
        _vehicle.prearmError = ""
        _vehicle.setCurrentMissionSequence(seq)
        _vehicle.startMission()
        _expect(qsTr("Start work"), function() { return status.armed && status.inAuto }, 0, function() {
            hhuWork.start(root._vehicle, {
                fieldId:    fieldId,
                fieldName:  field.name || "",
                swath:      field.swath || 0,
                startSeq:   seq,
                lastSeq:    route.last,
                cumulative: route.cumulative
            })
            if (fieldId !== "") {
                hhuFields.markWorked(fieldId)
            }
        })
    }

    function _pause() {
        _vehicle.flightMode = _vehicle.pauseFlightMode
        _expect(qsTr("Pause"), function() { return status.inPause })
    }

    function _continue() {
        _vehicle.flightMode = _vehicle.missionFlightMode
        _expect(qsTr("Continue"), function() { return status.inAuto })
    }

    function _returnHome() {
        if (_vehicle.flightModes.indexOf(_vehicle.smartRTLFlightMode) >= 0) {
            _vehicle.guidedModeRTL(true)
            rtlFallbackTimer.restart()
        } else {
            _vehicle.guidedModeRTL(false)
        }
        // allow for the Smart RTL → RTL fallback
        _expect(qsTr("Return"), function() { return status.inReturn }, 6)
    }

    function _stopAndDisarm() {
        _vehicle.flightMode = _vehicle.pauseFlightMode
        disarmTimer.restart()
        _expect(qsTr("Stop and disarm"), function() { return !status.armed })
    }

    // Smart RTL can be rejected (no return path recorded) - fall back to plain RTL within 3 s
    Timer {
        id:         rtlFallbackTimer
        interval:   2500
        onTriggered: {
            if (root._vehicle && !status.inReturn) {
                root._vehicle.guidedModeRTL(false)
            }
        }
    }

    Timer {
        id:         disarmTimer
        interval:   600
        onTriggered: {
            if (root._vehicle) {
                root._vehicle.armed = false
            }
        }
    }

    HHUConfirmDialog { id: confirmDialog }
    HHUStartDialog { id: startDialog }

    ColumnLayout {
        id:                 column
        anchors.centerIn:   parent
        spacing:            ScreenTools.defaultFontPixelHeight * 0.5

        HHUWorkButton {
            Layout.fillWidth:   true
            visible:            !root._vehicle
            text:               qsTr("Connect vehicle")
            iconSource:         "/InstrumentValueIcons/link.svg"
            accent:             "#004B97"
            onClicked:          mainWindow.showSettingsTool("Comm Links")
        }

        // Link lost / read only: no control buttons, only the reason
        QGCLabel {
            Layout.fillWidth:       true
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 22 * hhuSettings.fontScale
            visible:                !!root._vehicle && (status.linkLost || status.readOnly)
            text:                   status.linkLost ? qsTr("Link lost\nControls are unavailable")
                                                    : qsTr("Read-only connection\nAnother ground station controls this vehicle")
            color:                  status.linkLost ? "#B42318" : "#B7791F"
            font.bold:              true
            wrapMode:               Text.WordWrap
            horizontalAlignment:    Text.AlignHCenter
            font.pointSize:         ScreenTools.mediumFontPointSize * hhuSettings.fontScale
        }

        HHUWorkButton {
            Layout.fillWidth:   true
            visible:            root._idle && status.canControl
            text:               qsTr("Start work")
            iconSource:         "/InstrumentValueIcons/play.svg"
            accent:             "#1F8A3B"
            enabled:            _startBlockedReason === ""
            onClicked:          root._openStart()
        }

        QGCLabel {
            Layout.fillWidth:       true
            visible:                root._idle && status.canControl && _startBlockedReason !== ""
            text:                   _startBlockedReason
            color:                  "#B42318"
            horizontalAlignment:    Text.AlignHCenter
            font.pointSize:         ScreenTools.smallFontPointSize * hhuSettings.fontScale
        }

        HHUWorkButton {
            Layout.fillWidth:   true
            visible:            status.canControl && (status.inAuto || status.inReturn || status.inGuided)
            text:               qsTr("Pause")
            iconSource:         "/InstrumentValueIcons/pause.svg"
            accent:             "#B7791F"
            onClicked:          root._pause()
        }

        HHUWorkButton {
            Layout.fillWidth:   true
            visible:            status.canControl && root._paused
            text:               qsTr("Continue")
            iconSource:         "/InstrumentValueIcons/play-outline.svg"
            accent:             "#1F8A3B"
            enabled:            _missionAvailable
            onClicked:          root._continue()
        }

        HHUWorkButton {
            Layout.fillWidth:   true
            visible:            status.canControl && (status.inAuto || root._paused)
            text:               qsTr("Return")
            iconSource:         "/InstrumentValueIcons/home.svg"
            accent:             "#004B97"
            onClicked: confirmDialog.openAction(
                           qsTr("Return"),
                           qsTr("The vehicle will stop working and drive back along its path to the start point."),
                           qsTr("Slide to return"),
                           function() { root._returnHome() })
        }

        HHUWorkButton {
            Layout.fillWidth:   true
            visible:            status.canControl && status.armed
            text:               qsTr("Stop and disarm")
            iconSource:         "/InstrumentValueIcons/lock-closed.svg"
            accent:             "#B42318"
            onClicked: confirmDialog.openAction(
                           qsTr("Stop and disarm"),
                           qsTr("The vehicle will stop and disarm. Work can be restarted with Start work."),
                           qsTr("Slide to stop"),
                           function() { root._stopAndDisarm() })
        }
    }
}

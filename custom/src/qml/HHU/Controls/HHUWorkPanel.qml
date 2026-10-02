import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Work buttons at the bottom right of the 作业 page (设计稿 2b, 4a–4j). Only the buttons that apply to
/// the current state are shown, main action first, 停车上锁 set apart by a line:
/// 未连接 → 连接车辆; 待机 → 开始作业 (grey with the reasons and 去处理 buttons when it cannot start);
/// 作业中 → 暂停 / 返回起点 | 停车上锁; 已暂停 → 继续 / 返回起点 | 停车上锁 (继续 grey on a chassis fault);
/// 返回中 / 去目标点 → 暂停 | 停车上锁; nothing while the link is lost or the connection is view only.
/// A command the vehicle has not carried out in time is reported as 指令未执行 with 重新发送.
/// 开始作业 offers 断点续作 and starts following the run for it (hhuWork).
Item {
    id: root

    property var  planMasterController
    property real maxWidth: 10000

    implicitWidth:  Math.min(column.implicitWidth, maxWidth)
    implicitHeight: column.implicitHeight
    width:          implicitWidth
    height:         implicitHeight

    readonly property var   _vehicle:           status.vehicle
    readonly property var   _missionController: planMasterController ? planMasterController.missionController : null
    readonly property var   _fenceController:   planMasterController ? planMasterController.geoFenceController : null
    readonly property int   _missionItems:      _missionController ? _missionController.visualItems.count - 1 : 0
    readonly property bool  _missionAvailable:  _missionItems > 0
    readonly property bool  _fenceAvailable:    !!_fenceController && (_fenceController.polygons.count > 0 || _fenceController.circles.count > 0)
    readonly property bool  _paused:            status.inPause && status.armed
    readonly property bool  _idle:              !!_vehicle && !status.inAuto && !_paused && !status.inReturn && !status.inGuided

    /// Why 开始作业 is not possible ([] when it is): { t, btn, page } - btn opens the place to fix it
    readonly property var _startBlocked: {
        let list = []
        if (!_missionAvailable)     list.push({ t: qsTr("No route on the vehicle"), btn: qsTr("Go to plan"), page: "plan" })
        if (!_fenceAvailable)       list.push({ t: qsTr("No field boundary on the vehicle"), btn: qsTr("Go to plan"), page: "plan" })
        if (!status.rtkFixed)       list.push({ t: qsTr("Wait for a good position, about 1-3 minutes"), btn: "", page: "" })
        if (_vcuFault)              list.push({ t: qsTr("Chassis fault: %1").arg(status.faultText), btn: "", page: "" })
        return list
    }
    readonly property bool  _vcuFault:  status.vcuValid && hhuVcu.fault !== 0

    HHUStatus { id: status }

    // ---- Command confirmation ------------------------------------------------------------

    property string _pendingName
    property var    _pendingCheck:   null
    property var    _pendingSuccess: null
    property real   _pendingDeadline: 0
    property var    _pendingResend:  null

    /// Remember what the vehicle should do; onSuccess runs once it happened, 指令未执行 is shown
    /// when it has not happened in time
    function _expect(name, check, minSeconds, onSuccess, resend) {
        _pendingResend = resend || null
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
            failDialog.openFor(root._pendingName, root._vehicle.prearmError, root._pendingResend)
        }
    }

    // ---- Route on the vehicle ------------------------------------------------------------

    /// { first, last, count } of the waypoints (sequence numbers)
    function _routeInfo() {
        let info = { first: 0, last: 0, count: 0 }
        const items = _missionController.visualItems
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                if (info.first === 0) info.first = item.sequenceNumber
                info.last = item.sequenceNumber
                info.count++
            }
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
            HHUState.gotoTarget = null
            hhuWork.start(root._vehicle, {
                fieldId:    fieldId,
                startSeq:   seq,
                lastSeq:    route.last
            })
            if (fieldId !== "") {
                hhuFields.markWorked(fieldId)
            }
        }, function() { root._startWork(seq, route, fieldId, field) })
    }

    function _pause() {
        _vehicle.flightMode = _vehicle.pauseFlightMode
        _expect(qsTr("Pause"), function() { return status.inPause }, 0, null, _pause)
    }

    function _continue() {
        _vehicle.flightMode = _vehicle.missionFlightMode
        _expect(qsTr("Continue"), function() { return status.inAuto }, 0, null, _continue)
    }

    function _returnHome() {
        if (_vehicle.flightModes.indexOf(_vehicle.smartRTLFlightMode) >= 0) {
            _vehicle.guidedModeRTL(true)
            rtlFallbackTimer.restart()
        } else {
            _vehicle.guidedModeRTL(false)
        }
        // allow for the Smart RTL → RTL fallback
        _expect(qsTr("Return"), function() { return status.inReturn }, 6, null, _returnHome)
    }

    function _stopAndDisarm() {
        _vehicle.flightMode = _vehicle.pauseFlightMode
        disarmTimer.restart()
        _expect(qsTr("Stop and disarm"), function() { return !status.armed }, 0, function() { HHUState.gotoTarget = null }, _stopAndDisarm)
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

    HHUDialog {
        id:     failDialog
        title:  qsTr("Command not executed")

        property var _resend: null

        function openFor(name, reason, resend) {
            failText.text = qsTr("The vehicle did not respond to \"%1\".").arg(name) + (reason !== "" ? " " + reason : "")
            _resend = resend
            open()
        }

        HHUText {
            id:                 failText
            Layout.fillWidth:   true
            size:               17
            color:              HHUStyle.text2
            wrapMode:           Text.WordWrap
        }

        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Close"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: failDialog.close() },
            HHUButton {
                text:       qsTr("Send again")
                kind:       "blue"
                size:       18
                h:          56 * HHUStyle.s
                visible:    !!failDialog._resend && status.canControl
                onClicked: {
                    const resend = failDialog._resend
                    failDialog.close()
                    if (resend) resend()
                }
            }
        ]
    }

    ColumnLayout {
        id:             column
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        spacing:        10 * HHUStyle.s

        // 暂时不能开始: reasons with the place to fix them
        HHUCard {
            visible:                root._idle && status.canControl && root._startBlocked.length > 0
            Layout.alignment:       Qt.AlignRight
            Layout.preferredWidth:  Math.min(root.maxWidth, Math.max(340 * HHUStyle.s, noteColumn.implicitWidth + 28 * HHUStyle.s))
            Layout.preferredHeight: noteColumn.implicitHeight + 24 * HHUStyle.s
            color:                  HHUStyle.yellowLight
            radius:                 12 * HHUStyle.s
            border.color:           HHUStyle.yellow
            border.width:           2

            ColumnLayout {
                id:                 noteColumn
                anchors.fill:       parent
                anchors.margins:    12 * HHUStyle.s
                anchors.leftMargin: 14 * HHUStyle.s
                spacing:            8 * HHUStyle.s

                HHUText { text: qsTr("Cannot start yet"); size: 17; bold: true }
                Repeater {
                    model: root._startBlocked
                    RowLayout {
                        Layout.fillWidth:       true
                        Layout.minimumHeight:   44 * HHUStyle.s
                        spacing:                12 * HHUStyle.s
                        HHUText { Layout.fillWidth: true; text: modelData.t; size: 16; wrapMode: Text.WordWrap }
                        HHUButton {
                            visible:    modelData.btn !== ""
                            text:       modelData.btn
                            size:       16
                            h:          44 * HHUStyle.s
                            onClicked: {
                                if (modelData.page === "plan" && mainWindow.allowViewSwitch()) {
                                    mainWindow.showPlanView()
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment:   Qt.AlignRight
            spacing:            12 * HHUStyle.s

            HHUButton {
                visible:    !root._vehicle
                text:       qsTr("Connect vehicle")
                icon:       "link"
                kind:       "blue"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                minWidth:   220
                shadow:     true
                whiteRim:   true
                onClicked:  mainWindow.showSettingsTool("Comm Links")
            }

            HHUButton {
                visible:    root._idle && status.canControl
                enabled:    root._startBlocked.length === 0
                text:       qsTr("Start work")
                icon:       "play"
                kind:       "green"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                minWidth:   220
                shadow:     true
                whiteRim:   true
                onClicked:  root._openStart()
            }

            HHUButton {
                visible:    status.canControl && (status.inAuto || status.inReturn || status.inGuided) && status.armed && !status.routeDone
                text:       qsTr("Pause")
                icon:       "pause"
                kind:       "yellow"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                minWidth:   160
                shadow:     true
                whiteRim:   true
                onClicked:  root._pause()
            }

            HHUButton {
                visible:    status.canControl && root._paused
                enabled:    root._missionAvailable && !root._vcuFault
                text:       qsTr("Continue")
                icon:       "play"
                kind:       "green"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                minWidth:   160
                shadow:     true
                whiteRim:   true
                onClicked:  root._continue()
            }

            HHUButton {
                visible:    status.canControl && (status.inAuto || root._paused) && status.armed
                text:       qsTr("Return to start")
                icon:       "return"
                kind:       "outline"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                minWidth:   170
                shadow:     true
                onClicked: confirmDialog.openAction(
                               qsTr("Return to start?"),
                               qsTr("The vehicle stops working and drives back along its path to the start point."),
                               qsTr("Slide to return"),
                               function() { root._returnHome() },
                               "return", HHUStyle.blue)
            }

            Rectangle {
                visible:                stopButton.visible && (status.inAuto || root._paused || status.inReturn || status.inGuided)
                Layout.preferredWidth:  2
                Layout.preferredHeight: 48 * HHUStyle.s
                Layout.leftMargin:      10 * HHUStyle.s
                Layout.rightMargin:     10 * HHUStyle.s
                radius:                 1
                color:                  "#B3FFFFFF"
            }

            HHUButton {
                id:         stopButton
                visible:    status.canControl && status.armed
                text:       qsTr("Stop and lock")
                icon:       "lock"
                kind:       "red"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                shadow:     true
                whiteRim:   true
                onClicked: confirmDialog.openAction(
                               qsTr("Stop and lock?"),
                               qsTr("The vehicle stops at once and this work run ends.\nNext time you can continue where it stopped."),
                               qsTr("Slide to lock"),
                               function() { root._stopAndDisarm() },
                               "lock", HHUStyle.red)
            }
        }
    }
}

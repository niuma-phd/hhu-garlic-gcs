import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Work buttons at the bottom right of the 作业 page (设计稿 2b, 4a–4j). Only the buttons that apply to
/// the current state are shown, main action first, 停车上锁 set apart by a line:
/// 未连接 → 连接车辆; 待机 → 开始作业 (grey with the reasons and 去处理 buttons when it cannot start);
/// 作业中 → 暂停 / 返回起点 | 停车上锁; 已暂停 → 继续作业 / 返回起点 | 停车上锁 (继续 grey on a chassis fault);
/// 返回中 / 去目标点 → 暂停 | 停车上锁; nothing while the link is lost or the connection is view only.
/// 开始 / 继续 is one entry (_startOrContinue): disarmed goes through startDialog + startMission,
/// paused simply switches back to AUTO. The remote control can take over at any time; GCS 暂停 does not conflict.
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
    readonly property int   _missionItems:      _missionController ? _missionController.visualItems.count - 1 : 0
    readonly property bool  _missionAvailable:  _missionItems > 0
    readonly property bool  _paused:            status.inPause && status.armed
    readonly property bool  _idle:              !!_vehicle && !status.inAuto && !_paused && !status.inReturn && !status.inGuided

    /// Why 开始作业 is not possible ([] when it is): { t, btn, page } - btn opens the place to fix it.
    /// Most important first (issue #6): 底盘通信中断 > 未授权 / 故障 > 无航线 > 定位. With the chassis
    /// link down nothing about 授权 is known, so 切无人 is not suggested then.
    readonly property var _startBlocked: {
        let list = []
        if (status.chassisLinkLost) {
            list.push({ t: qsTr("Chassis communication lost, check the CAN cable and the VCU"), btn: "", page: "" })
        } else if (status.vcuValid) {
            if (_vcuFault)                  list.push({ t: qsTr("Chassis fault: %1").arg(status.faultText), btn: "", page: "" })
            if (!status.vcuAuthorized)      list.push({ t: qsTr("Switch to unmanned mode with the remote control"), btn: "", page: "" })
            else if (!hhuVcu.ok && !_vcuFault) list.push({ t: qsTr("Chassis not ready, see the message list"), btn: "", page: "" })
        }
        if (!_missionAvailable)     list.push({ t: qsTr("No route on the vehicle"), btn: qsTr("Go to plan"), page: "plan" })
        if (!status.rtkFixed)       list.push({ t: qsTr("Wait for a good position, about 1-3 minutes"), btn: "", page: "" })
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

    /// { seqs, last, count } of the waypoints: seqs[n - 1] is the mission sequence of waypoint n
    function _routeInfo() {
        const seqs = HHUState.waypointSeqs(_missionController)
        return { seqs: seqs, last: seqs.length > 0 ? seqs[seqs.length - 1] : 0, count: seqs.length }
    }

    // ---- Actions -------------------------------------------------------------------------

    function _openStart() {
        const route = _routeInfo()
        // The dialog shows waypoint numbers; the vehicle gets the mission sequence of that waypoint
        const resumeSeq = hhuWork.resumeWaypoint(_vehicle)
        startDialog.openStart(route.count,
                              resumeSeq > 0 ? HHUState.waypointNumber(_missionController, resumeSeq) : 0,
                              function(number) { root._startWork(route.seqs[number - 1], route) })
    }

    function _startWork(seq, route) {
        _vehicle.prearmError = ""
        _vehicle.setCurrentMissionSequence(seq)
        _vehicle.startMission()
        _expect(qsTr("Start work"), function() { return status.armed && status.inAuto }, 0, function() {
            HHUState.gotoTarget = null
            hhuWork.start(root._vehicle, {
                fieldId:    "",
                startSeq:   seq,
                lastSeq:    route.last
            })
        }, function() { root._startWork(seq, route) })
    }

    function _pause() {
        _vehicle.flightMode = _vehicle.pauseFlightMode
        _expect(qsTr("Pause"), function() { return status.inPause }, 0, null, _pause)
    }

    function _continue() {
        _vehicle.flightMode = _vehicle.missionFlightMode
        _expect(qsTr("Continue"), function() { return status.inAuto }, 0, null, _continue)
    }

    /// 开始 / 继续 is one entry: disarmed goes through the start dialog and startMission,
    /// paused (still armed) simply switches back to AUTO. Both share the _expect confirmation.
    function _startOrContinue() {
        if (root._paused) {
            _continue()
        } else {
            _openStart()
        }
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
                        HHUText { Layout.fillWidth: true; text: modelData.t; size: HHUStyle.bodySize; wrapMode: Text.WordWrap }
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

            // 开始 / 继续作业: one entry, the text follows the state
            HHUButton {
                visible:    status.canControl && (root._idle || root._paused)
                enabled:    root._paused ? (root._missionAvailable && !root._vcuFault) : root._startBlocked.length === 0
                text:       root._paused ? qsTr("Continue work") : qsTr("Start work")
                icon:       "play"
                kind:       "green"
                h:          HHUStyle.btnH
                size:       HHUStyle.btnFont / HHUStyle.s
                minWidth:   220
                shadow:     true
                whiteRim:   true
                onClicked:  root._startOrContinue()
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

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import HHU.AB

/// 作业 page while an AB line is driven (hhuABRun): status card (第几条 / 共几条, 阶段, 作业杆, 横向偏差)
/// and the dialogs of the run: slide to start, 对准不合格, 放杆 / 作业 / 收杆 faults, 本条标为完成？,
/// the 完成面板 (下一条 / 重走本条 / 选其他条 / 结束) and the line list of 选其他条.
HHUCard {
    id: root

    width:      HHUStyle.cardW
    height:     cardColumn.implicitHeight + HHUStyle.cardPad * 2
    radius:     HHUStyle.radiusCard
    visible:    hhuABRun.active && hhuABRun.phase !== HHUABRun.Done

    HHUStatus { id: status }

    readonly property int    _phase:   hhuABRun.phase
    readonly property int    _line:    hhuABRun.line
    readonly property bool   _paused:  (_phase === HHUABRun.Aligning || _phase === HHUABRun.Working)
                                       && !hhuABRun.starting && status.armed && !status.inAuto

    function phaseText(phase) {
        switch (phase) {
        case HHUABRun.Aligning:     return qsTr("Aligning")
        case HHUABRun.AlignFailed:  return qsTr("Alignment out of limits")
        case HHUABRun.Lowering:     return qsTr("Lowering")
        case HHUABRun.LowerFault:   return qsTr("Lowering failed")
        case HHUABRun.Working:      return qsTr("Working")
        case HHUABRun.WorkFault:    return qsTr("Lift fault")
        case HHUABRun.Raising:      return qsTr("Raising")
        case HHUABRun.Ending:       return qsTr("Raising")
        case HHUABRun.RaiseFault:   return qsTr("Raising failed")
        case HHUABRun.EndAsk:       return qsTr("Line ended")
        case HHUABRun.Done:         return qsTr("Line done")
        default:                    return ""
        }
    }

    function faultText(fault) {
        switch (fault) {
        case HHUABRun.LiftTimeout:  return qsTr("Lift did not reach its position in %1 s").arg(hhuConfig.abLiftTimeout)
        case HHUABRun.LiftFault:    return qsTr("Lift fault (WorkFb 4)")
        case HHUABRun.LiftMoving:   return qsTr("Lift moving while working, the vehicle stopped")
        case HHUABRun.NoWorkFb:     return qsTr("The vehicle does not report the lift state")
        case HHUABRun.NoEcho:       return qsTr("The vehicle script does not support the lift link (garlic.15 or later needed)")
        case HHUABRun.UploadFailed: return qsTr("Route upload failed")
        case HHUABRun.ModeFailed:   return qsTr("The vehicle did not switch to auto")
        default:                    return ""
        }
    }

    function _xtrackText(v) {
        return isNaN(v) ? "—" : (v >= 0 ? qsTr("L") : qsTr("R")) + " " + Math.abs(v).toFixed(2) + " m"
    }

    // ---- Start (slide to confirm) ----------------------------------------------------------------

    function _confirmStart(line, title) {
        const blockers = status.driveBlockers()
        if (!status.canControl) {
            return
        }
        if (blockers.length > 0) {
            messageDialog.show(qsTr("Cannot start"), blockers.join("\n"))
            return
        }
        confirmDialog.openAction(title || qsTr("Start line %1?").arg(line + 1),
                                 qsTr("Line %1 / %2").arg(line + 1).arg(hhuAB.count),
                                 qsTr("Slide to start"),
                                 function() { root._start(line) },
                                 "play", HHUStyle.green)
    }

    function _start(line) {
        const r = hhuABRun.start(line)
        if (r === HHUABRun.WorkEnOff) {
            messageDialog.show(qsTr("Cannot start"), qsTr("Work link is off on the vehicle (VCU_WORK_EN=0)"))
        } else if (r !== HHUABRun.StartOk) {
            messageDialog.show(qsTr("Cannot start"), r === HHUABRun.NoVehicle ? qsTr("Vehicle not connected") : qsTr("Line cannot be started now"))
        }
    }

    Connections {
        target: HHUState
        function onAbStartRequested(line) { root._confirmStart(line) }
    }

    // ---- Phase dialogs ------------------------------------------------------------------------------

    property int _lastPhase: HHUABRun.Idle
    Connections {
        target: hhuABRun
        function onChanged() {
            if (hhuABRun.phase === root._lastPhase) {
                return
            }
            root._lastPhase = hhuABRun.phase
            alignDialog.close()
            faultDialog.close()
            endAskDialog.close()
            doneDialog.close()
            switch (hhuABRun.phase) {
            case HHUABRun.AlignFailed:  alignDialog.open(); break
            case HHUABRun.LowerFault:
            case HHUABRun.WorkFault:
            case HHUABRun.RaiseFault:   faultDialog.open(); break
            case HHUABRun.EndAsk:       endAskDialog.open(); break
            case HHUABRun.Done:         doneDialog.open(); break
            case HHUABRun.Idle:
                if (hhuABRun.fault !== HHUABRun.NoFault) {
                    messageDialog.show(qsTr("Line stopped"), root.faultText(hhuABRun.fault))
                }
                break
            }
        }
    }

    HHUConfirmDialog { id: confirmDialog }

    HHUDialog {
        id: messageDialog
        function show(t, m) {
            title = t
            messageText.text = m
            open()
        }
        HHUText { id: messageText; Layout.fillWidth: true; size: 17; color: HHUStyle.text2; wrapMode: Text.WordWrap }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Close"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: messageDialog.close() }
        ]
    }

    // 对准不合格: the two errors, 仍然开始 (second confirmation) / 结束本条
    HHUDialog {
        id:             alignDialog
        title:          qsTr("Alignment out of limits")
        icon:           "warning"
        iconColor:      HHUStyle.yellow
        closePolicy:    Popup.NoAutoClose

        GridLayout {
            columns:        2
            columnSpacing:  16 * HHUStyle.s
            rowSpacing:     6 * HHUStyle.s
            HHUText { text: qsTr("Cross-track"); size: 17; color: HHUStyle.text3 }
            HHUText { text: root._xtrackText(hhuABRun.alignXtrack); number: true; size: 22
                      color: !(Math.abs(hhuABRun.alignXtrack) <= hhuConfig.abAlignXtrack) ? HHUStyle.red : HHUStyle.text }
            HHUText { text: qsTr("Heading"); size: 17; color: HHUStyle.text3 }
            HHUText { text: isNaN(hhuABRun.alignHeadingErr) ? "—" : hhuABRun.alignHeadingErr.toFixed(1) + "°"; number: true; size: 22
                      color: !(Math.abs(hhuABRun.alignHeadingErr) <= hhuConfig.abAlignHeading) ? HHUStyle.red : HHUStyle.text }
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("End line"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: { alignDialog.close(); hhuABRun.endLine() } },
            HHUButton {
                text: qsTr("Start anyway"); kind: "yellow"; size: 18; h: 56 * HHUStyle.s; minWidth: 140
                onClicked: {
                    alignDialog.close()
                    confirmDialog.openAction(qsTr("Start anyway?"),
                                             qsTr("Cross-track %1, heading %2").arg(root._xtrackText(hhuABRun.alignXtrack))
                                                 .arg(isNaN(hhuABRun.alignHeadingErr) ? "—" : hhuABRun.alignHeadingErr.toFixed(1) + "°"),
                                             qsTr("Slide to start"),
                                             function() { hhuABRun.startAnyway() },
                                             "play", HHUStyle.yellow)
                }
            }
        ]
        // 取消 in the second confirmation brings this dialog back
        Connections {
            target: confirmDialog
            function onClosed() {
                if (hhuABRun.phase === HHUABRun.AlignFailed && !alignDialog.opened) {
                    alignDialog.open()
                }
            }
        }
    }

    // 放杆 / 作业 / 收杆 faults
    HHUDialog {
        id:             faultDialog
        title:          root.phaseText(hhuABRun.phase)
        icon:           "warning"
        iconColor:      HHUStyle.red
        closePolicy:    Popup.NoAutoClose

        HHUText {
            Layout.fillWidth:   true
            text:               root.faultText(hhuABRun.fault)
            size:               18
            wrapMode:           Text.WordWrap
        }
        RowLayout {
            spacing: 8 * HHUStyle.s
            HHUText { text: qsTr("Lift"); size: 16; color: HHUStyle.text3 }
            HHUText { text: status.workFbShown ? status.workFbText(status.workFb) : "—"; size: 16; bold: true
                      color: status.workFb === 4 ? HHUStyle.red : HHUStyle.text }
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton {
                text:       hhuABRun.phase === HHUABRun.RaiseFault ? qsTr("End") : qsTr("End line")
                kind:       "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120
                onClicked: {
                    faultDialog.close()
                    if (hhuABRun.phase === HHUABRun.RaiseFault) {
                        hhuABRun.finish()
                    } else {
                        hhuABRun.endLine()
                    }
                }
            },
            HHUButton {
                text:       hhuABRun.phase === HHUABRun.RaiseFault ? qsTr("Retry raising") : qsTr("Retry lowering")
                kind:       "blue"; size: 18; h: 56 * HHUStyle.s; minWidth: 140
                enabled:    status.canControl
                onClicked: {
                    faultDialog.close()
                    if (hhuABRun.phase === HHUABRun.RaiseFault) {
                        hhuABRun.retryRaise()
                    } else {
                        hhuABRun.retryLower()
                    }
                }
            }
        ]
    }

    // 结束本条 → 本条标为完成？
    HHUDialog {
        id:             endAskDialog
        title:          qsTr("Mark line %1 as done?").arg(hhuABRun.line + 1)
        closePolicy:    Popup.NoAutoClose
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("No"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: { endAskDialog.close(); hhuABRun.confirmEnd(false) } },
            HHUButton { text: qsTr("Yes"); kind: "green"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: { endAskDialog.close(); hhuABRun.confirmEnd(true) } }
        ]
    }

    // 完成面板
    HHUDialog {
        id:             doneDialog
        title:          qsTr("Line %1 done (done %2/%3)").arg(hhuABRun.line + 1).arg(hhuAB.doneCount).arg(hhuAB.count)
        icon:           "check"
        iconColor:      HHUStyle.green
        dialogWidth:    600
        closePolicy:    Popup.NoAutoClose

        readonly property int _next: hhuAB.nextPending(hhuABRun.line)

        GridLayout {
            Layout.fillWidth:   true
            columns:            2
            columnSpacing:      10 * HHUStyle.s
            rowSpacing:         10 * HHUStyle.s
            HHUButton {
                Layout.fillWidth:   true
                Layout.columnSpan:  2
                text:       doneDialog._next >= 0 ? qsTr("Next line (%1)").arg(doneDialog._next + 1) : qsTr("Next line")
                icon:       "play"
                kind:       "green"; size: 18; h: 60 * HHUStyle.s
                enabled:    doneDialog._next >= 0 && status.canControl
                onClicked: {
                    const next = doneDialog._next
                    doneDialog.close()
                    root._confirmStart(next)
                }
            }
            HHUButton {
                Layout.fillWidth: true
                text: qsTr("Drive this line again"); kind: "outline"; size: 17; h: 56 * HHUStyle.s
                enabled: status.canControl
                onClicked: {
                    const line = hhuABRun.line
                    doneDialog.close()
                    root._confirmStart(line, qsTr("Drive line %1 again?").arg(line + 1))
                }
            }
            HHUButton {
                Layout.fillWidth: true
                text: qsTr("Choose another line"); kind: "outline"; size: 17; h: 56 * HHUStyle.s
                enabled: status.canControl
                onClicked: { doneDialog.close(); pickDialog.open() }
            }
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("End"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: { doneDialog.close(); hhuABRun.finish() } }
        ]
        // 取消 in the slide confirmation brings the panel back
        Connections {
            target: confirmDialog
            function onClosed() {
                if (hhuABRun.phase === HHUABRun.Done && !doneDialog.opened && !pickDialog.opened) {
                    doneDialog.open()
                }
            }
        }
    }

    // 选其他条: the lines with their state, tap one → slide to start
    HHUDialog {
        id:             pickDialog
        title:          qsTr("Choose a line")
        dialogWidth:    560
        closePolicy:    Popup.NoAutoClose

        ListView {
            Layout.fillWidth:       true
            Layout.preferredHeight: Math.min(contentHeight, 440 * HHUStyle.s)
            clip:                   true
            spacing:                4 * HHUStyle.s
            model:                  hhuAB.lines
            ScrollBar.vertical: ScrollBar { width: 8 * HHUStyle.s }
            delegate: Rectangle {
                width:          ListView.view.width - 12 * HHUStyle.s
                height:         48 * HHUStyle.s
                radius:         10 * HHUStyle.s
                color:          pickMouse.pressed ? HHUStyle.grey2 : HHUStyle.grey
                border.color:   index === hhuABRun.line ? HHUStyle.blue : "transparent"
                border.width:   2
                RowLayout {
                    anchors.fill:       parent
                    anchors.leftMargin: 12 * HHUStyle.s
                    anchors.rightMargin: 12 * HHUStyle.s
                    HHUText { Layout.preferredWidth: 48 * HHUStyle.s; text: modelData.n; number: true; size: 18; font.strikeout: modelData.status === 2 }
                    HHUText {
                        Layout.fillWidth: true
                        text:   modelData.status === 1 ? qsTr("Done") : (modelData.status === 2 ? qsTr("Skipped") : qsTr("Not driven"))
                        size:   15
                        color:  modelData.status === 1 ? HHUStyle.green : HHUStyle.text3
                    }
                }
                MouseArea {
                    id:             pickMouse
                    anchors.fill:   parent
                    cursorShape:    Qt.PointingHandCursor
                    onClicked: {
                        pickDialog.close()
                        root._confirmStart(index)
                    }
                }
            }
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton {
                text: qsTr("Back"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120
                onClicked: {
                    pickDialog.close()
                    if (hhuABRun.phase === HHUABRun.Done) doneDialog.open()
                }
            }
        ]
    }

    // ---- Status card ----------------------------------------------------------------------------------

    ColumnLayout {
        id:                 cardColumn
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.margins:    HHUStyle.cardPad
        spacing:            6 * HHUStyle.s

        RowLayout {
            Layout.fillWidth: true
            HHUText { Layout.fillWidth: true; text: qsTr("AB line"); size: 15; color: HHUStyle.text3; elide: Text.ElideRight }
            HHUText { text: (root._line + 1) + " / " + hhuAB.count; number: true; size: 22 }
        }
        HHUText {
            text:   root._paused ? qsTr("Paused") : root.phaseText(root._phase)
            size:   20
            bold:   true
            color:  (root._phase === HHUABRun.LowerFault || root._phase === HHUABRun.WorkFault || root._phase === HHUABRun.RaiseFault)
                    ? HHUStyle.red : (root._paused ? HHUStyle.yellowText : HHUStyle.blue)
        }
        RowLayout {
            Layout.fillWidth:   true
            visible:            hhuABRun.workLink
            HHUText { Layout.fillWidth: true; text: qsTr("Lift"); size: 15; color: HHUStyle.text3 }
            HHUText {
                text:   status.workFbShown ? status.workFbText(status.workFb) : "—"
                size:   16
                bold:   true
                color:  status.workFb === 4 ? HHUStyle.red : HHUStyle.text
            }
        }
        RowLayout {
            Layout.fillWidth: true
            HHUText { Layout.fillWidth: true; text: qsTr("Cross-track"); size: 15; color: HHUStyle.text3 }
            HHUText { text: root._xtrackText(hhuABRun.xtrack); number: true; size: 22 }
        }
        // 结束本条: raises the lift, then asks 本条标为完成？
        HHUButton {
            Layout.fillWidth:   true
            Layout.topMargin:   4 * HHUStyle.s
            visible:            status.canControl && [ HHUABRun.Aligning, HHUABRun.AlignFailed, HHUABRun.Lowering, HHUABRun.LowerFault,
                                                       HHUABRun.Working, HHUABRun.WorkFault ].indexOf(root._phase) >= 0
            text:               qsTr("End line")
            icon:               "close"
            kind:               "outline"
            size:               16
            h:                  48 * HHUStyle.s
            onClicked: confirmDialog.openAction(qsTr("End line %1?").arg(root._line + 1), "", qsTr("Slide to end"),
                                                function() { hhuABRun.endLine() }, "close", HHUStyle.blue)
        }
    }
}

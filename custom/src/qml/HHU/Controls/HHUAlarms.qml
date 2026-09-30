import QtQuick
import QtQuick.Layouts
import QtLocation
import QtPositioning
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

/// Alarms of the 作业 page (需求说明 V1.0 §3.6).
/// - Banner + repeating sound while an alarm is active and not yet confirmed (知道了):
///   link lost, chassis link lost, RTK fixed lost while working, low battery, chassis fault.
/// - Link lost: map label at the vehicle's last position with the time since the last data.
/// - Link back: notice with outage length and vehicle state; the route is reloaded from the vehicle.
Item {
    id: root

    property var planMasterController
    property var mapControl

    implicitWidth:  messages.implicitWidth
    implicitHeight: messages.implicitHeight

    HHUStatus { id: status }

    /// Working (AUTO) when the link was lost - the vehicle keeps driving the route without us
    property bool _workingAtLoss: false
    /// Alarm ids the user confirmed; an id is dropped again once its alarm clears
    property var  _acked: ({})

    readonly property var activeAlarms: {
        let list = []
        if (status.linkLost) {
            list.push({ id: "link", text: _workingAtLoss
                        ? qsTr("Link to the vehicle lost. The vehicle is still driving the route automatically. To stop it now, use the emergency stop button on the vehicle or the remote control.")
                        : qsTr("Link to the vehicle lost (no data for %1 s).").arg(hhuLink.silentSec) })
        }
        if (status.connected && hhuVcu.seen && !hhuVcu.valid) {
            list.push({ id: "chassisLink", text: qsTr("Chassis communication lost.") })
        }
        if (status.connected && status.inAuto && !status.rtkFixed) {
            list.push({ id: "rtk", text: qsTr("RTK fixed solution lost while working (now: %1).").arg(status.fixText) })
        }
        if (status.connected && !isNaN(status.batteryPct) && status.batteryPct < hhuSettings.lowBatteryPct) {
            list.push({ id: "battery", text: qsTr("Battery low: %1% (alarm below %2%).").arg(status.batteryPct.toFixed(0)).arg(hhuSettings.lowBatteryPct) })
        }
        if (status.faultText !== "") {
            list.push({ id: "fault", text: qsTr("Chassis fault: %1").arg(status.faultText) })
        }
        return list
    }

    readonly property var shownAlarms: activeAlarms.filter(a => !_acked[a.id])

    onActiveAlarmsChanged: {
        // Forget confirmations of alarms that have cleared, so they sound again next time
        const active = activeAlarms.map(a => a.id)
        let acked = {}
        let changed = false
        for (const id in _acked) {
            if (active.indexOf(id) >= 0) {
                acked[id] = true
            } else {
                changed = true
            }
        }
        if (changed) {
            _acked = acked
        }
    }

    function _ackAll() {
        let acked = Object.assign({}, _acked)
        for (const a of shownAlarms) {
            acked[a.id] = true
        }
        _acked = acked
    }

    Connections {
        target: QGroundControl.multiVehicleManager
        function onActiveVehicleChanged(vehicle) {
            hhuVcu.reset()
            root._acked = {}
            notice.visible = false
        }
    }

    Connections {
        target: status
        function onLinkLostChanged() {
            if (status.linkLost) {
                root._workingAtLoss = status.inAuto
                notice.visible = false
                hhuWork.linkInterrupted()   // 作业记录: 中断次数
            } else if (status.vehicle) {
                // Let fresh telemetry arrive before reporting the vehicle state
                recoveredTimer.restart()
            }
        }
    }

    Timer {
        id:         recoveredTimer
        interval:   1500
        onTriggered: {
            if (!status.connected) {
                return
            }
            notice.text = qsTr("Link restored after %1 s. Vehicle state: %2.").arg(hhuLink.lastOutageSec).arg(status.modeText)
            notice.visible = true
            noticeTimer.restart()
            if (root.planMasterController && !root.planMasterController.syncInProgress) {
                root.planMasterController.loadFromVehicle()
            }
        }
    }

    Timer {
        id:         noticeTimer
        interval:   10000
        onTriggered: notice.visible = false
    }

    // ---- Sound ---------------------------------------------------------------------------

    SoundEffect {
        id:         alarmSound
        source:     "qrc:/hhu/sounds/alarm.wav"
        volume:     QGroundControl.settingsManager.appSettings.audioVolume.rawValue / 100
        muted:      QGroundControl.settingsManager.appSettings.audioMuted.rawValue
    }

    Timer {
        interval:           4000
        repeat:             true
        triggeredOnStart:   true
        running:            root.shownAlarms.length > 0
        onTriggered:        alarmSound.play()
    }

    Column {
        id:         messages
        spacing:    ScreenTools.defaultFontPixelHeight * 0.5

        // ---- Banner --------------------------------------------------------------------------

        Rectangle {
            id:             banner
            visible:        root.shownAlarms.length > 0
            width:          Math.min(ScreenTools.defaultFontPixelWidth * 70 * hhuSettings.fontScale, root.parent ? root.parent.width * 0.6 : 600)
            height:         bannerRow.implicitHeight + ScreenTools.defaultFontPixelHeight
            radius:         ScreenTools.defaultFontPixelHeight * 0.4
            color:          "#B42318"
            border.color:   "white"
            border.width:   hhuSettings.highContrast ? 3 : 1

            RowLayout {
                id:                 bannerRow
                anchors.fill:       parent
                anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.5
                spacing:            ScreenTools.defaultFontPixelWidth

                QGCColoredImage {
                    source:                 "/InstrumentValueIcons/exclamation-outline.svg"
                    color:                  "white"
                    Layout.alignment:       Qt.AlignTop
                    Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 1.6 * hhuSettings.fontScale
                    Layout.preferredWidth:  Layout.preferredHeight
                    sourceSize.height:      Layout.preferredHeight
                }

                ColumnLayout {
                    Layout.fillWidth:   true
                    spacing:            ScreenTools.defaultFontPixelHeight * 0.3

                    Repeater {
                        model: root.shownAlarms
                        QGCLabel {
                            Layout.fillWidth:   true
                            text:               modelData.text
                            color:              "white"
                            font.bold:          true
                            font.pointSize:     ScreenTools.mediumFontPointSize * hhuSettings.fontScale
                            wrapMode:           Text.WordWrap
                        }
                    }
                }

                QGCButton {
                    Layout.alignment:   Qt.AlignVCenter
                    text:               qsTr("OK")
                    onClicked:          root._ackAll()
                }
            }
        }

        // ---- Link restored notice ------------------------------------------------------------

        Rectangle {
            id:             notice
            visible:        false
            width:          Math.min(noticeLabel.implicitWidth, ScreenTools.defaultFontPixelWidth * 70 * hhuSettings.fontScale) + ScreenTools.defaultFontPixelHeight
            height:         noticeLabel.implicitHeight + ScreenTools.defaultFontPixelHeight
            radius:         ScreenTools.defaultFontPixelHeight * 0.4
            color:          "#1F8A3B"

            property alias text: noticeLabel.text

            QGCLabel {
                id:                 noticeLabel
                anchors.centerIn:   parent
                width:              Math.min(implicitWidth, ScreenTools.defaultFontPixelWidth * 70 * hhuSettings.fontScale)
                color:              "white"
                font.bold:          true
                font.pointSize:     ScreenTools.mediumFontPointSize * hhuSettings.fontScale
                wrapMode:           Text.WordWrap
            }

            MouseArea {
                anchors.fill:   parent
                onClicked:      notice.visible = false
            }
        }

    } // Column

    // ---- Last known position while the link is lost -------------------------------------

    MapQuickItem {
        id:             lastPositionItem
        visible:        status.linkLost && !!status.vehicle && status.vehicle.coordinate.isValid
        coordinate:     status.vehicle ? status.vehicle.coordinate : QtPositioning.coordinate()
        anchorPoint.x:  sourceItem.width / 2
        anchorPoint.y:  -ScreenTools.defaultFontPixelHeight * 1.5   // below the vehicle icon
        z:              QGroundControl.zOrderMapItems + 1

        sourceItem: Rectangle {
            width:      lastPositionLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 2
            height:     lastPositionLabel.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.4
            radius:     height / 4
            color:      "#E6B42318"

            QGCLabel {
                id:                 lastPositionLabel
                anchors.centerIn:   parent
                text:               qsTr("Last position (%1 s ago)").arg(hhuLink.silentSec)
                color:              "white"
                font.bold:          true
                font.pointSize:     ScreenTools.defaultFontPointSize * hhuSettings.fontScale
            }
        }
    }

    Component.onCompleted: {
        if (mapControl) {
            mapControl.addMapItem(lastPositionItem)
        }
    }
}

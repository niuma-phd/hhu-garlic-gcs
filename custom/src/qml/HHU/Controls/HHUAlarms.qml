import QtQuick
import QtQuick.Layouts
import QtLocation
import QtPositioning
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

/// Alarm banners of the 作业 page (设计稿 5.3, 需求说明 V1.0 §3.6), top center, one line title + at
/// most one line of text, at most two at a time (the most severe first; all are in the message list too).
///   提示 (info):     light blue, blue border, one beep          - link restored, view only
///   注意 (warning):  yellow, dark text, beep every 30 s         - battery low, position lost while working,
///                                                                 chassis data lost
///   危险 (danger):   red, white text, beeps until tapped (mute) - link lost, chassis fault
/// Link lost: label at the vehicle's last position. Link back: the route is reloaded from the vehicle.
Item {
    id: root

    property var  planMasterController
    property var  mapControl
    property real maxWidth: 640

    implicitWidth:  column.implicitWidth
    implicitHeight: column.implicitHeight

    HHUStatus { id: status }

    /// Working (AUTO) when the link was lost - the vehicle keeps driving the route without us
    property bool _workingAtLoss:   false
    /// Danger alarm ids the user muted; an id is dropped again once its alarm clears
    property var  _muted:           ({})
    property bool _restoredShown:   false
    property real _lostSince:       0
    property int  _lostSeconds:     0

    function _fmtDuration(sec) {
        const m = Math.floor(sec / 60)
        return m > 0 ? qsTr("%1 min %2 s").arg(m).arg(sec % 60) : qsTr("%1 s").arg(sec)
    }

    readonly property var activeAlarms: {
        let list = []
        if (status.linkLost) {
            list.push({ id: "link", level: 2,
                        title: qsTr("Link lost %1").arg(_fmtDuration(_lostSeconds)),
                        text: _workingAtLoss ? qsTr("The vehicle is still working. To stop it, press the emergency stop on the vehicle.")
                                             : qsTr("Waiting for the vehicle to come back.") })
        }
        if (status.faultText !== "") {
            const desc = hhuConfig.faultText(hhuVcu.fault)
            list.push({ id: "fault", level: 2,
                        title: desc !== "" ? qsTr("Chassis fault: %1").arg(desc) : qsTr("Chassis fault %1").arg(status.faultText),
                        text: qsTr("Clear the fault on the vehicle, then tap \"Continue\".") })
        }
        if (status.connected && hhuVcu.seen && !hhuVcu.valid) {
            list.push({ id: "chassisLink", level: 1, title: qsTr("No data from the chassis"), text: qsTr("Check the chassis cable and power.") })
        }
        if (status.connected && status.inAuto && !status.rtkFixed) {
            list.push({ id: "rtk", level: 1, title: qsTr("Position poor while working"), text: qsTr("The vehicle may leave the route. Watch it or pause.") })
        }
        if (status.connected && !isNaN(status.batteryPct) && status.batteryPct < hhuSettings.lowBatteryPct) {
            list.push({ id: "battery", level: 1, title: qsTr("Battery low %1%, please come back to charge").arg(status.batteryPct.toFixed(0)), text: "" })
        }
        if (status.readOnly) {
            list.push({ id: "readOnly", level: 0, title: qsTr("View only"), text: qsTr("Another ground station controls this vehicle.") })
        }
        if (status.routeDone) {
            list.push({ id: "done", level: 0, title: qsTr("Work done"), text: qsTr("The whole route is driven. Return to start or stop and lock the vehicle.") })
        }
        if (_restoredShown && status.connected) {
            list.push({ id: "restored", level: 0, title: qsTr("Link restored"), text: qsTr("Lost for %1. Vehicle: %2.").arg(_fmtDuration(hhuLink.lastOutageSec)).arg(status.modeText) })
        }
        return list
    }

    readonly property var shownAlarms: activeAlarms.slice().sort((a, b) => b.level - a.level).slice(0, 2)

    onActiveAlarmsChanged: {
        // Forget mutes of alarms that have cleared, so they sound again next time
        const active = activeAlarms.map(a => a.id)
        let muted = {}
        let changed = false
        for (const id in _muted) {
            if (active.indexOf(id) >= 0) {
                muted[id] = true
            } else {
                changed = true
            }
        }
        if (changed) {
            _muted = muted
        }
        // a new alarm: info beeps once, warning starts its 30 s cycle
        for (const a of activeAlarms) {
            if (_known.indexOf(a.id) < 0) {
                alarmSound.play()
                warningTimer.restart()
            }
        }
        _known = active
    }
    property var _known: []

    function _mute(id) {
        let muted = Object.assign({}, _muted)
        muted[id] = true
        _muted = muted
    }

    readonly property bool _dangerSounding: activeAlarms.some(a => a.level === 2 && !_muted[a.id])
    readonly property bool _warningActive:  activeAlarms.some(a => a.level === 1)

    Connections {
        target: QGroundControl.multiVehicleManager
        function onActiveVehicleChanged(vehicle) {
            hhuVcu.reset()
            root._muted = {}
            root._restoredShown = false
        }
    }

    Connections {
        target: status
        function onLinkLostChanged() {
            if (status.linkLost) {
                root._workingAtLoss = status.inAuto
                root._restoredShown = false
                root._lostSince = Date.now() - hhuLink.silentSec * 1000
                root._lostSeconds = hhuLink.silentSec
            } else if (status.vehicle) {
                // Let fresh telemetry arrive before reporting the vehicle state
                recoveredTimer.restart()
            }
        }
    }

    Timer {
        interval:   1000
        repeat:     true
        running:    status.linkLost
        onTriggered: root._lostSeconds = Math.round((Date.now() - root._lostSince) / 1000)
    }

    Timer {
        id:         recoveredTimer
        interval:   1500
        onTriggered: {
            if (!status.connected) {
                return
            }
            root._restoredShown = true
            restoredTimer.restart()
            if (root.planMasterController && !root.planMasterController.syncInProgress) {
                root.planMasterController.loadFromVehicle()
            }
        }
    }

    Timer {
        id:         restoredTimer
        interval:   10000
        onTriggered: root._restoredShown = false
    }

    // ---- Sound ---------------------------------------------------------------------------

    SoundEffect {
        id:         alarmSound
        source:     "qrc:/hhu/sounds/alarm.wav"
        volume:     QGroundControl.settingsManager.appSettings.audioVolume.rawValue / 100
        muted:      QGroundControl.settingsManager.appSettings.audioMuted.rawValue
    }

    // 危险: continuous
    Timer {
        interval:   4000
        repeat:     true
        running:    root._dangerSounding
        onTriggered: alarmSound.play()
    }

    // 注意: every 30 s
    Timer {
        id:         warningTimer
        interval:   30000
        repeat:     true
        running:    root._warningActive && !root._dangerSounding
        onTriggered: alarmSound.play()
    }

    // ---- Banners -------------------------------------------------------------------------

    Column {
        id:         column
        spacing:    8 * HHUStyle.s

        Repeater {
            model: root.shownAlarms

            HHUCard {
                id:     banner
                width:  Math.min(HHUStyle.bannerW, root.maxWidth)
                height: bannerRow.implicitHeight + 24 * HHUStyle.s
                radius: 12 * HHUStyle.s
                color:          modelData.level === 2 ? HHUStyle.red : (modelData.level === 1 ? HHUStyle.yellow : HHUStyle.blueLight)
                border.color:   modelData.level === 0 ? HHUStyle.blue : "transparent"
                border.width:   modelData.level === 0 ? 2 : 0

                readonly property color _fg: modelData.level === 2 ? "white" : (modelData.level === 1 ? HHUStyle.yellowText : HHUStyle.text)
                readonly property bool  _muted: !!root._muted[modelData.id]

                RowLayout {
                    id:                 bannerRow
                    anchors.left:       parent.left
                    anchors.right:      parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16 * HHUStyle.s
                    anchors.rightMargin: 12 * HHUStyle.s
                    spacing:            14 * HHUStyle.s

                    Rectangle {
                        Layout.preferredWidth:  40 * HHUStyle.s
                        Layout.preferredHeight: Layout.preferredWidth
                        radius:                 width / 2
                        color:                  modelData.level === 0 ? HHUStyle.blue : "white"
                        HHUIcon {
                            anchors.centerIn:   parent
                            name:               modelData.level === 0 ? "info" : "warning"
                            size:               22
                            color:              modelData.level === 2 ? HHUStyle.red : (modelData.level === 1 ? "#8A5A00" : "white")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth:   true
                        spacing:            2
                        HHUText {
                            Layout.fillWidth:   true
                            text:               modelData.title
                            size:               19
                            bold:               true
                            color:              banner._fg
                            elide:              Text.ElideRight
                        }
                        HHUText {
                            Layout.fillWidth:   true
                            visible:            modelData.text !== ""
                            text:               modelData.text
                            size:               16
                            color:              banner._fg
                            wrapMode:           Text.WordWrap
                            maximumLineCount:   2
                            elide:              Text.ElideRight
                        }
                    }

                    // 危险: tap to mute
                    HHUIcon {
                        visible:    modelData.level === 2
                        name:       "mute"
                        size:       24
                        color:      "white"
                        opacity:    banner._muted ? 0.45 : 1
                    }
                }

                MouseArea {
                    anchors.fill:   parent
                    enabled:        modelData.level === 2
                    cursorShape:    Qt.PointingHandCursor
                    onClicked:      root._mute(modelData.id)
                }
            }
        }
    }

    // ---- Last known position while the link is lost -------------------------------------

    MapQuickItem {
        id:             lastPositionItem
        visible:        status.linkLost && !!status.vehicle && status.vehicle.coordinate.isValid
        coordinate:     status.vehicle ? status.vehicle.coordinate : QtPositioning.coordinate()
        anchorPoint.x:  sourceItem.width / 2
        anchorPoint.y:  -36 * HHUStyle.s   // below the vehicle icon and its ring
        z:              QGroundControl.zOrderMapItems + 1

        sourceItem: Rectangle {
            width:      lastPositionColumn.implicitWidth + 20 * HHUStyle.s
            height:     lastPositionColumn.implicitHeight + 10 * HHUStyle.s
            radius:     6 * HHUStyle.s
            color:      HHUStyle.red

            Column {
                id:                 lastPositionColumn
                anchors.centerIn:   parent
                HHUText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:   qsTr("Last position")
                    size:   14
                    bold:   true
                    color:  "white"
                }
                HHUText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:   new Date(root._lostSince).toLocaleTimeString(Qt.locale(), "HH:mm:ss") + " · " + qsTr("%1 ago").arg(root._fmtDuration(root._lostSeconds))
                    size:   14
                    color:  "white"
                }
            }
        }
    }

    Component.onCompleted: {
        if (mapControl) {
            mapControl.addMapItem(lastPositionItem)
        }
    }
}

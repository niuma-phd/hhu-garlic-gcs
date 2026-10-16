import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import QtPositioning

import QGroundControl
import QGroundControl.Controls

/// 规划 page: white panel on the left with two steps
///   ① 排航线 (waypoints, one speed for the route)  ② 检查上传
/// The map keeps QGC's editing (drag points); a map click adds a waypoint in step ①.
/// Routes are opened/saved as .plan files from the toolbar; the rover no longer uses a
/// geofence (issue #4), so there is no boundary step and no field management.
HHUCard {
    id: root

    property var planView               ///< PlanView root (_editingLayer, _addWaypointOnClick)
    property var planMasterController   ///< PlanView's PlanMasterController (has the file dialogs)
    property var editorMap

    property int step: 0

    width:  HHUStyle.planPanelW
    radius: HHUStyle.radiusCard

    readonly property var _mission:   planMasterController.missionController
    readonly property int _waypoints: Math.max(0, _mission.visualItems.count - 1)

    HHUStatus { id: status }

    HHUUploadCheck {
        id:                     checker
        visible:                false
        planMasterController:   root.planMasterController
    }

    // ---- Steps -------------------------------------------------------------------------------

    readonly property var _stepNames: [ qsTr("Route"), qsTr("Upload") ]

    function goTo(newStep) {
        step = newStep
    }

    onStepChanged: _applyStep()
    Component.onCompleted: _applyStep()

    function _applyStep() {
        planView._addWaypointOnClick = step === 0
        planView._editingLayer = planView._layerMission
        if (step === 1) {
            _check = checker.check()
        }
    }

    // ---- Route -----------------------------------------------------------------------------------

    function _addWaypoint(coordinate) {
        if (!_mission.homePositionSet) {
            // home = where the vehicle is (route time / distance estimates start there)
            _mission.setHomePosition(status.vehicle && status.vehicle.coordinate.isValid ? status.vehicle.coordinate : coordinate)
        }
        _mission.insertSimpleMissionItem(coordinate, _mission.visualItems.count, true)
    }

    /// 清空 asks first and keeps the speed (removeAll recreates the route settings without it, issue #6)
    function _clearRoute() {
        mainWindow.hhuConfirm(root, qsTr("Clear the route"),
                                         qsTr("Clear %1 waypoints?").arg(_waypoints),
                                         qsTr("Clear"),
                                         function() {
                                             const speed = root._speed
                                             root.planMasterController.removeAll()
                                             root._setSpeed(speed)
                                         })
    }

    function _undoRoute() {
        if (_waypoints > 0) {
            _mission.removeVisualItem(_mission.visualItems.count - 1)
        }
    }

    /// Waypoint at the vehicle's position; without RTK fixed the user is warned first
    function _addWaypointAtVehicle(what) {
        const coordinate = QtPositioning.coordinate(status.vehicle.coordinate.latitude, status.vehicle.coordinate.longitude)
        if (status.rtkFixed) {
            _addWaypoint(coordinate)
            return
        }
        QGroundControl.showMessageDialog(root, what,
                                         qsTr("Position accuracy is not sufficient (%1). Add the point anyway?").arg(status.fixText),
                                         Dialog.Ok | Dialog.Cancel, function() { _addWaypoint(coordinate) })
    }

    readonly property var _speedSection: _mission.visualItems.count > 0 ? _mission.visualItems.get(0).speedSection : null

    /// Highest route speed: the vehicle's WP_SPEED / VCU_V_MAX (the lower one), 1.5 m/s when they cannot be read
    readonly property real _maxSpeed: hhuSettings.vehicleMaxSpeed > 0 ? Math.floor(hhuSettings.vehicleMaxSpeed * 10 + 1e-6) / 10 : 1.5
    /// Route speed; a route without its own speed shows the last speed set here (never above _maxSpeed)
    readonly property real _speed: _speedSection && _speedSection.specifyFlightSpeed
                                   ? _speedSection.flightSpeed.rawValue
                                   : Math.min(QGroundControl.settingsManager.appSettings.offlineEditingCruiseSpeed.rawValue, _maxSpeed)

    function _setSpeed(v) {
        if (!_speedSection) return
        _speedSection.specifyFlightSpeed = true
        _speedSection.flightSpeed.rawValue = v
        QGroundControl.settingsManager.appSettings.offlineEditingCruiseSpeed.rawValue = v   // time estimate
    }

    // ---- Check / upload ----------------------------------------------------------------------

    property var  _check:     ({ errors: [], warnings: [], items: [] })
    property bool _uploaded:  false

    Connections {
        target: root.planMasterController
        function onDirtyForUploadChanged() {
            if (root.planMasterController.dirtyForUpload) {
                root._uploaded = false
            }
        }
        function onSyncInProgressChanged() {
            if (!root.planMasterController.syncInProgress && root._uploading) {
                root._uploading = false
                root._uploaded = !root.planMasterController.dirtyForUpload
                if (root._uploaded) {
                    // A new route on the vehicle invalidates the resume point (断点续作)
                    hhuWork.clearResume(QGroundControl.multiVehicleManager.activeVehicle)
                }
            }
        }
    }
    property bool _uploading: false

    // an upload the vehicle refused never starts syncing
    Timer {
        id:         uploadStartTimer
        interval:   2000
        onTriggered: if (!root.planMasterController.syncInProgress) root._uploading = false
    }

    function _upload() {
        _uploading = true
        uploadStartTimer.restart()
        planMasterController.sendToVehicle()
    }

    // ---- Layout ----------------------------------------------------------------------------------

    ColumnLayout {
        anchors.fill:       parent
        anchors.margins:    16 * HHUStyle.s
        spacing:            12 * HHUStyle.s

        // step bar: current blue, done green, later grey
        RowLayout {
            Layout.fillWidth:   true
            spacing:            4 * HHUStyle.s
            Repeater {
                model: root._stepNames
                ColumnLayout {
                    Layout.fillWidth:   true
                    Layout.preferredWidth: 1
                    spacing:            4 * HHUStyle.s
                    Rectangle {
                        Layout.fillWidth:       true
                        Layout.preferredHeight: 4 * HHUStyle.s
                        radius:                 2
                        color:                  index === root.step ? HHUStyle.blue : (index < root.step ? HHUStyle.green : HHUStyle.divider)
                    }
                    HHUText {
                        Layout.alignment:   Qt.AlignHCenter
                        text:               modelData
                        size:               14
                        bold:               index === root.step
                        color:              index === root.step ? HHUStyle.text : HHUStyle.text3
                    }
                    MouseArea {
                        Layout.fillWidth:       true
                        Layout.preferredHeight: 1
                        Layout.topMargin:       -30 * HHUStyle.s
                        Layout.minimumHeight:   30 * HHUStyle.s
                        cursorShape:            Qt.PointingHandCursor
                        enabled:                index !== root.step
                        onClicked:              root.goTo(index)
                    }
                }
            }
        }

        // Step content scrolls on short screens; 下一步 / 上传 below always stay visible
        Flickable {
            id:                 stepFlick
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            clip:               true
            contentWidth:       width
            contentHeight:      stepStack.height
            boundsBehavior:     Flickable.StopAtBounds
            interactive:        contentHeight > height

            StackLayout {
                id:             stepStack
                width:          stepFlick.width
                height:         Math.max(implicitHeight, stepFlick.height)
                currentIndex:       root.step

                // ① 排航线 ---------------------------------------------------------------------
                ColumnLayout {
                    spacing: 10 * HHUStyle.s

                    Row {
                        spacing: 6 * HHUStyle.s
                        HHUText { text: String(root._waypoints); number: true; size: 30; anchors.bottom: parent.bottom }
                        HHUText { text: qsTr("waypoints"); size: 15; color: HHUStyle.text3; anchors.bottom: parent.bottom; bottomPadding: 4 }
                    }
                    HHUButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Add a waypoint at the vehicle")
                        icon:               "pin"
                        kind:               "outline"
                        size:               16
                        h:                  56 * HHUStyle.s
                        enabled:            !!status.vehicle && status.vehicle.coordinate.isValid
                        onClicked:          root._addWaypointAtVehicle(text)
                    }
                    RowLayout {
                        Layout.fillWidth:   true
                        spacing:            8 * HHUStyle.s
                        HHUButton { Layout.fillWidth: true; text: qsTr("Undo"); kind: "plain"; size: 16; enabled: root._waypoints > 0; onClicked: root._undoRoute() }
                        HHUButton { Layout.fillWidth: true; text: qsTr("Clear"); kind: "plain"; size: 16; enabled: root._waypoints > 0; onClicked: root._clearRoute() }
                    }
                    RowLayout {
                        Layout.fillWidth:   true
                        Layout.topMargin:   8 * HHUStyle.s
                        HHUText { Layout.fillWidth: true; text: qsTr("Speed"); size: 16; bold: true }
                        HHUStepper {
                            value:      root._speed
                            from:       0.1
                            to:         root._maxSpeed
                            editable:   true
                            step:       0.1
                            decimals:   1
                            unit:       "m/s"
                            onEdited:   (v) => root._setSpeed(v)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ② 检查上传 -------------------------------------------------------------------
                ColumnLayout {
                    spacing: 10 * HHUStyle.s

                    Rectangle {
                        Layout.fillWidth:       true
                        Layout.preferredHeight: 52 * HHUStyle.s
                        radius:                 10 * HHUStyle.s
                        readonly property bool _ok: root._check.errors.length === 0
                        color:          _ok ? HHUStyle.greenLight : HHUStyle.redLight
                        border.color:   _ok ? HHUStyle.green : HHUStyle.red
                        border.width:   2
                        RowLayout {
                            anchors.fill:       parent
                            anchors.leftMargin: 14 * HHUStyle.s
                            spacing:            10 * HHUStyle.s
                            HHUIcon { name: parent.parent._ok ? "check" : "close"; color: parent.parent._ok ? HHUStyle.green : HHUStyle.red }
                            HHUText {
                                Layout.fillWidth: true
                                text:   parent.parent._ok ? (root._uploaded ? qsTr("Uploaded to the vehicle") : qsTr("Check passed"))
                                                          : qsTr("%1 items to fix").arg(root._check.errors.length)
                                size:   17
                                bold:   true
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth:   true
                        Layout.fillHeight:  true
                        clip:               true
                        spacing:            8 * HHUStyle.s
                        model:              root._check.items
                        delegate: Rectangle {
                            width:          ListView.view.width
                            height:         itemColumn.implicitHeight + 20 * HHUStyle.s
                            radius:         10 * HHUStyle.s
                            color:          modelData.error ? HHUStyle.redLight : HHUStyle.yellowLight
                            ColumnLayout {
                                id:         itemColumn
                                x:          12 * HHUStyle.s
                                y:          10 * HHUStyle.s
                                width:      parent.width - 24 * HHUStyle.s
                                spacing:    6 * HHUStyle.s
                                HHUText { Layout.fillWidth: true; text: modelData.t; size: 15; wrapMode: Text.WordWrap }
                                HHUButton {
                                    visible:            modelData.step >= 0
                                    Layout.alignment:   Qt.AlignRight
                                    text:               modelData.look ? qsTr("Show") : qsTr("Fix")
                                    size:               15
                                    h:                  40 * HHUStyle.s
                                    onClicked: {
                                        if (modelData.look && checker.tightTurns.length > 0) {
                                            root.editorMap.center = checker.tightTurns[0].coordinate
                                        }
                                        root.goTo(modelData.step)
                                    }
                                }
                            }
                        }
                    }

                    HHUText {
                        visible:            root._check.items.length === 0
                        Layout.fillWidth:   true
                        text:               qsTr("Tight turns, waypoint count and connection are all fine.")
                        size:               15
                        color:              HHUStyle.text3
                        wrapMode:           Text.WordWrap
                    }
                }
            }
        }

        // bottom buttons
        RowLayout {
            Layout.fillWidth:   true
            spacing:            8 * HHUStyle.s

            HHUButton {
                visible:                root.step > 0
                Layout.preferredWidth:  104 * HHUStyle.s
                text:                   qsTr("Back")
                kind:                   "plain"
                size:                   16
                h:                      56 * HHUStyle.s
                onClicked:              root.goTo(root.step - 1)
            }
            HHUButton {
                visible:            root.step < 1
                Layout.fillWidth:   true
                text:               qsTr("Next")
                kind:               "blue"
                size:               17
                h:                  56 * HHUStyle.s
                onClicked:          root.goTo(root.step + 1)
            }
            HHUButton {
                visible:            root.step === 1 && !root._uploaded
                Layout.fillWidth:   true
                text:               root._uploading ? qsTr("Uploading…") : qsTr("Upload to vehicle")
                kind:               "green"
                size:               17
                h:                  56 * HHUStyle.s
                enabled:            root._check.errors.length === 0 && !root._uploading && !!status.vehicle && status.canControl
                onClicked:          root._upload()
            }
            HHUButton {
                visible:            root.step === 1 && root._uploaded
                Layout.fillWidth:   true
                text:               qsTr("Go to work")
                kind:               "green"
                size:               17
                h:                  56 * HHUStyle.s
                onClicked:          mainWindow.showFlyView()
            }
        }
    }

    // How to edit on the map, centered above the map while drawing (设计稿 5c)
    Rectangle {
        parent:         root.parent
        visible:        root.step === 0
        y:              12 * HHUStyle.s
        x:              root.x + root.width + (parent.width - root.x - root.width - width) / 2
        width:          hintText.implicitWidth + 32 * HHUStyle.s
        height:         40 * HHUStyle.s
        radius:         height / 2
        color:          "#E614202E"
        z:              QGroundControl.zOrderWidgets
        HHUText {
            id:                 hintText
            anchors.centerIn:   parent
            text:               qsTr("Tap the map to add a waypoint · drag to change")
            size:               15
            bold:               true
            color:              "white"
        }
    }
}

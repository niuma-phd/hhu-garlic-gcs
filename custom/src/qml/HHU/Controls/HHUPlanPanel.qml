import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap

/// 规划 page: white panel on the left with two steps
///   ① 排航线 (waypoints, one speed for the route)  ② 检查上传
/// The map keeps QGC's dragging; in step ① a map click adds a waypoint at the end, the + on a
/// segment inserts one there, right click / long press on a waypoint asks to delete it.
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

    onStepChanged: {
        stepFlick.contentY = 0     // each step starts at its top (检查通过 / 已上传 is at the top)
        _closeDeleteCard()
        _applyStep()
    }
    onVisibleChanged: if (!visible) _closeDeleteCard()
    Component.onCompleted: {
        editorMap.addMapItemView(splitView)
        editorMap.addMapItem(deleteCard)
        _applyStep()
    }

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
        _mission.insertSimpleMissionItem(coordinate, _mission.visualItems.count, false)
        _clearSelection()
    }

    /// Map click in step ① (PlanView): closes an open delete card, else adds a waypoint at the end
    function mapClicked(coordinate) {
        if (deleteCard.visible) {
            _closeDeleteCard()
            return
        }
        _addWaypoint(coordinate)
    }

    /// A tapped waypoint is selected only to show it and to drag it; adding, inserting, deleting
    /// and Esc select nothing (the planned home is QGC's "nothing selected")
    function _clearSelection() {
        _mission.setCurrentPlanViewSeqNum(0, true)
    }

    function escapePressed() {
        _closeDeleteCard()
        _clearSelection()
    }

    /// Delete key: the same card for the selected waypoint
    function deletePressed() {
        const item = _mission.currentPlanViewItem
        if (step === 0 && item) {
            HHUState.requestWaypointMenu(item)
        }
    }

    // ---- Insert / delete on the map ------------------------------------------------------------

    /// + in the middle of every segment between two waypoints: { coordinate, index } with index
    /// the visual item index the new waypoint gets
    readonly property var _splits: {
        const items = _mission.visualItems
        let out = []
        let prev = null
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (!item.specifiesCoordinate || item.isStandaloneCoordinate) {
                continue
            }
            if (prev) {
                const c1 = prev.coordinate
                const c2 = item.coordinate
                out.push({ coordinate: c1.atDistanceAndAzimuth(c1.distanceTo(c2) / 2, c1.azimuthTo(c2)), index: i })
            }
            prev = item
        }
        return out
    }

    function _insertAt(index, coordinate) {
        _mission.insertSimpleMissionItem(coordinate, index, false)
        _clearSelection()
    }

    property var _deleteItem: null     ///< waypoint the delete card is open for

    Connections {
        target: HHUState
        function onWaypointMenuRequested(missionItem) {
            if (root.visible && root.step === 0) {
                root._deleteItem = missionItem
                deleteCard.visible = true
            }
        }
    }

    function _closeDeleteCard() {
        deleteCard.visible = false
        _deleteItem = null
    }

    function _deleteWaypoint() {
        const items = _mission.visualItems
        for (let i = 1; i < items.count; i++) {
            if (items.get(i) === _deleteItem) {
                _mission.removeVisualItem(i)
                break
            }
        }
        _closeDeleteCard()
        _clearSelection()
    }

    // the card belongs to the map position it was opened at: moving the map closes it
    Connections {
        target: root.editorMap
        function onCenterChanged()    { if (deleteCard.visible) root._closeDeleteCard() }
        function onZoomLevelChanged() { if (deleteCard.visible) root._closeDeleteCard() }
    }
    Connections {
        target: _mission.visualItems
        function onCountChanged() { if (deleteCard.visible) root._closeDeleteCard() }
    }

    MapItemView {
        id:     splitView
        model:  root.visible && root.step === 0 ? root._splits : []
        delegate: MapQuickItem {
            coordinate:     modelData.coordinate
            anchorPoint.x:  sourceItem.width / 2
            anchorPoint.y:  sourceItem.height / 2
            z:              QGroundControl.zOrderWaypointLines + 1
            sourceItem: SplitIndicator {
                onClicked: root._insertAt(modelData.index, modelData.coordinate)
            }
        }
    }

    // 第 N 点 · 取消 / 删除 at the waypoint (same look as 开到这里 on the 作业 map)
    MapQuickItem {
        id:             deleteCard
        visible:        false
        coordinate:     root._deleteItem ? root._deleteItem.coordinate : QtPositioning.coordinate()
        anchorPoint.x:  sourceItem.width / 2
        anchorPoint.y:  sourceItem.height + 24 * HHUStyle.s
        z:              QGroundControl.zOrderMapItems + 4

        sourceItem: HHUCard {
            width:  260 * HHUStyle.s
            height: deleteColumn.implicitHeight + 32 * HHUStyle.s

            Column {
                id:         deleteColumn
                x:          16 * HHUStyle.s
                y:          16 * HHUStyle.s
                width:      parent.width - 32 * HHUStyle.s
                spacing:    4 * HHUStyle.s

                HHUText {
                    text:   root._deleteItem ? qsTr("Waypoint %1").arg(HHUState.waypointNumber(root._mission, root._deleteItem.sequenceNumber)) : ""
                    size:   18
                    bold:   true
                }
                Item { width: 1; height: 8 * HHUStyle.s }
                Row {
                    spacing: 10 * HHUStyle.s
                    HHUButton {
                        width:      (deleteColumn.width - 10 * HHUStyle.s) / 2
                        text:       qsTr("Cancel")
                        kind:       "plain"
                        size:       16
                        onClicked:  root._closeDeleteCard()
                    }
                    HHUButton {
                        width:      (deleteColumn.width - 10 * HHUStyle.s) / 2
                        text:       qsTr("Delete")
                        kind:       "red"
                        size:       16
                        onClicked:  root._deleteWaypoint()
                    }
                }
            }
        }
    }

    /// 清空 asks first; the cleared route goes back to the default speed (the vehicle's WP_SPEED)
    function _clearRoute() {
        mainWindow.hhuConfirm(root, qsTr("Clear the route"),
                                         qsTr("Clear %1 waypoints?").arg(_waypoints),
                                         qsTr("Clear"),
                                         function() { root.planMasterController.removeAll() })
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

    /// Highest route speed: the vehicle's SPEED_MAX / VCU_V_MAX (the lower one), 1.3 m/s when they cannot be read;
    /// rounded down to the 0.05 step (1.38 -> 1.35)
    readonly property real _maxSpeed: Math.floor((hhuSettings.vehicleMaxSpeed > 0 ? hhuSettings.vehicleMaxSpeed : 1.3) * 20 + 1e-6) / 20
    /// Route speed; a route without its own speed shows the vehicle's WP_SPEED, else the last speed set here
    /// (0.55 m/s at first), never above _maxSpeed
    readonly property real _speed: _speedSection && _speedSection.specifyFlightSpeed
                                   ? _speedSection.flightSpeed.rawValue
                                   : Math.min(hhuSettings.vehicleWpSpeed > 0 ? hhuSettings.vehicleWpSpeed
                                                                             : QGroundControl.settingsManager.appSettings.offlineEditingCruiseSpeed.rawValue,
                                              _maxSpeed)

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
            } else {
                root._checkUploadDone()
            }
        }
        function onSyncInProgressChanged() {
            if (!root.planMasterController.syncInProgress && root._uploading) {
                // dirtyForUpload is cleared after the mission sync ends (after the rally point leg),
                // so wait for it; a failed upload keeps it set and the timer gives up
                uploadStartTimer.restart()
                root._checkUploadDone()
            }
        }
    }
    property bool _uploading: false

    function _checkUploadDone() {
        if (_uploading && !planMasterController.syncInProgress && !planMasterController.dirtyForUpload) {
            _uploading = false
            _uploaded = true
            // A new route on the vehicle invalidates the resume point (断点续作)
            hhuWork.clearResume(QGroundControl.multiVehicleManager.activeVehicle)
        }
    }

    // an upload the vehicle refused never starts syncing, a failed one never clears dirtyForUpload
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

            // visible while there is more below, so the operator knows the panel scrolls
            ScrollBar.vertical: ScrollBar {
                policy:     stepFlick.contentHeight > stepFlick.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                width:      8 * HHUStyle.s
            }

            StackLayout {
                id:             stepStack
                // room for the scroll bar, so it does not cover the buttons' right edge (Cowork S7)
                width:          stepFlick.width - (stepFlick.contentHeight > stepFlick.height + 1 ? 14 * HHUStyle.s : 0)
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
                    HHUText {
                        visible:    root._waypoints === 0
                        text:       qsTr("Tap the map to add waypoints")
                        size:       15
                        color:      HHUStyle.text3
                    }
                    // delete: right click / long press a waypoint on the map (card there)
                    RowLayout {
                        Layout.fillWidth:   true
                        spacing:            8 * HHUStyle.s
                        HHUButton {
                            Layout.fillWidth:       true
                            Layout.preferredWidth:  2
                            text:                   qsTr("Add a waypoint at the vehicle")
                            icon:                   "pin"
                            kind:                   "outline"
                            size:                   16
                            h:                      56 * HHUStyle.s
                            enabled:                !!status.vehicle && status.vehicle.coordinate.isValid
                            onClicked:              root._addWaypointAtVehicle(text)
                        }
                        HHUButton {
                            Layout.fillWidth:       true
                            Layout.preferredWidth:  1
                            text:                   qsTr("Clear")
                            kind:                   "plain"
                            size:                   16
                            h:                      56 * HHUStyle.s
                            enabled:                root._waypoints > 0
                            onClicked:              root._clearRoute()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth:   true
                        Layout.topMargin:   8 * HHUStyle.s
                        Layout.bottomMargin: 28 * HHUStyle.s   // room for the stepper's out-of-range note below it
                        HHUText { Layout.fillWidth: true; text: qsTr("Speed"); size: 16; bold: true }
                        HHUStepper {
                            value:      root._speed
                            from:       0.1
                            to:         root._maxSpeed
                            editable:   true
                            step:       0.05
                            decimals:   2
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
            text:               qsTr("Tap the map to add a waypoint · drag to change · right click / long press to delete")
            size:               15
            bold:               true
            color:              "white"
        }
    }
}

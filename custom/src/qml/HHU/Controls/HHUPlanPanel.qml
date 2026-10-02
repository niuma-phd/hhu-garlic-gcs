import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning

import QGroundControl
import QGroundControl.Controls

/// 规划 page (设计稿 5a–5e): white panel on the left with four steps
///   ① 选地块  ② 画边界 (geofence)  ③ 排航线 (waypoints, one speed for the route)  ④ 检查上传
/// The map keeps QGC's editing (drag points); the step sets what a map click adds.
/// The plan is saved into the open field automatically when the step changes, before upload and
/// before another field is opened. Import / export are in step ① (and the ⋯ menu of a field).
HHUCard {
    id: root

    property var planView               ///< PlanView root (_editingLayer, _addWaypointOnClick, layers)
    property var planMasterController   ///< PlanView's PlanMasterController (has the file dialogs)
    property var editorMap

    property int step: 0

    width:  HHUStyle.planPanelW
    radius: HHUStyle.radiusCard

    readonly property var _mission: planMasterController.missionController
    readonly property var _fence:   planMasterController.geoFenceController
    readonly property int _waypoints: Math.max(0, _mission.visualItems.count - 1)

    HHUStatus { id: status }
    HHUFence { id: fence; geoFenceController: root._fence }

    // Field operations, name dialog and saving (no list shown: the list is step ①)
    HHUFieldPanel {
        id: fields
        planMasterController: root.planMasterController
    }

    // 在车的位置加点 + the boundary corners before the polygon exists (shown on the map)
    HHUVehiclePointTools {
        id:                     vehiclePoints
        visible:                false
        planMasterController:   root.planMasterController
        editorMap:              root.editorMap
        insertWaypoint:         function(coordinate) { root._addWaypoint(coordinate) }
    }

    HHUUploadCheck {
        id:                     checker
        visible:                false
        planMasterController:   root.planMasterController
    }

    // ---- Steps -------------------------------------------------------------------------------

    readonly property var _stepNames: [ qsTr("Field"), qsTr("Boundary"), qsTr("Route"), qsTr("Check") ]

    function _autoSave() {
        if (hhuFields.currentId !== "" && planMasterController.dirtyForSave) {
            fields.saveCurrent()
        }
    }

    function goTo(newStep) {
        // a plan without a field (imported, or started without one) gets a name before going on
        if (newStep > 0 && hhuFields.currentId === "" && (planMasterController.containsItems || _fence.polygons.count > 0)) {
            fields.saveCurrent()
            return
        }
        if (newStep > 0 && hhuFields.currentId === "") {
            fields.openNameDialog("new", "", "")
            return
        }
        _autoSave()
        step = newStep
    }

    // QGC replaces an unchanged editor with the route on the vehicle: show the open field again
    // whenever the 规划 page opens
    Connections {
        target: root.planView
        function onVisibleChanged() {
            if (root.planView.visible) {
                root._showCurrentField()
            }
        }
    }

    function _showCurrentField() {
        const id = hhuFields.currentId
        if (id !== "" && hhuFields.hasPlan(id) && !planMasterController.dirtyForSave && !planMasterController.syncInProgress) {
            planMasterController.loadFromFile(hhuFields.planFile(id))
        }
    }

    onStepChanged: _applyStep()
    Component.onCompleted: _applyStep()

    function _applyStep() {
        planView._addWaypointOnClick = step === 2
        planView._editingLayer = step === 1 ? planView._layerFence : planView._layerMission
        _setBoundaryEditable()
        if (step === 3) {
            _check = checker.check()
        }
    }

    // ---- Boundary --------------------------------------------------------------------------------

    function _inclusion() {
        for (let i = _fence.polygons.count - 1; i >= 0; i--) {
            if (_fence.polygons.get(i).inclusion) {
                return { polygon: _fence.polygons.get(i), index: i }
            }
        }
        return null
    }
    readonly property int _boundaryPoints: {
        const p = _fence.polygons.count >= 0 ? _inclusion() : null
        return p ? p.polygon.count : vehiclePoints._pendingFence.length
    }

    /// Drag handles on the boundary only while drawing it
    function _setBoundaryEditable() {
        for (let i = 0; i < _fence.polygons.count; i++) {
            _fence.polygons.get(i).interactive = step === 1
        }
    }

    Connections {
        target: root._fence.polygons
        function onCountChanged() { root._setBoundaryEditable() }
    }

    /// Map click while drawing the boundary
    function boundaryClicked(coordinate) {
        vehiclePoints._addFencePoint(coordinate)
    }

    function _undoBoundary() {
        const p = _inclusion()
        if (!p) {
            vehiclePoints._pendingFence = vehiclePoints._pendingFence.slice(0, -1)
            return
        }
        if (p.polygon.count > 3) {
            p.polygon.removeVertex(p.polygon.count - 1)
        } else {
            // back to loose corners
            const path = p.polygon.path
            vehiclePoints._pendingFence = path.slice(0, path.length - 1)
            _fence.deletePolygon(p.index)
        }
    }

    function _clearBoundary() {
        vehiclePoints._pendingFence = []
        _fence.clearAllInteractive()
    }

    // ---- Route -----------------------------------------------------------------------------------

    function _addWaypoint(coordinate) {
        if (!_mission.homePositionSet) {
            // home = where the vehicle is (route time / distance estimates start there)
            _mission.setHomePosition(status.vehicle && status.vehicle.coordinate.isValid ? status.vehicle.coordinate : coordinate)
        }
        _mission.insertSimpleMissionItem(coordinate, _mission.visualItems.count, true)
    }

    function _undoRoute() {
        if (_waypoints > 0) {
            _mission.removeVisualItem(_mission.visualItems.count - 1)
        }
    }

    readonly property var _speedSection: _mission.visualItems.count > 0 ? _mission.visualItems.get(0).speedSection : null
    readonly property real _speed: _speedSection && _speedSection.specifyFlightSpeed ? _speedSection.flightSpeed.rawValue : 1.2

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
                    // 断点续作 / progress card: which field is on the vehicle now
                    hhuWork.setVehicleField(QGroundControl.multiVehicleManager.activeVehicle, hhuFields.currentId)
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
        _autoSave()
        _uploading = true
        uploadStartTimer.restart()
        planMasterController.upload()
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

        StackLayout {
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            currentIndex:       root.step

            // ① 选地块 ---------------------------------------------------------------------
            ColumnLayout {
                spacing: 10 * HHUStyle.s

                HHUTextField {
                    id:                 search
                    Layout.fillWidth:   true
                    placeholderText:    qsTr("Search fields")
                }

                ListView {
                    id:                 fieldList
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true
                    clip:               true
                    spacing:            8 * HHUStyle.s
                    model:              hhuFields.fields.filter(f => search.text.trim() === "" || f.name.indexOf(search.text.trim()) >= 0)

                    delegate: Rectangle {
                        readonly property bool _current: modelData.id === hhuFields.currentId
                        width:          fieldList.width
                        height:         60 * HHUStyle.s
                        radius:         10 * HHUStyle.s
                        color:          _current ? HHUStyle.blueLight : (rowMouse.containsMouse ? HHUStyle.grey : "white")
                        border.color:   _current ? HHUStyle.blue : HHUStyle.border
                        border.width:   _current ? 2 : 1

                        MouseArea {
                            id:             rowMouse
                            anchors.fill:   parent
                            hoverEnabled:   true
                            cursorShape:    Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.id !== hhuFields.currentId) {
                                    root._autoSave()
                                    fields.load(modelData.id)
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            x:                      12 * HHUStyle.s
                            width:                  parent.width - x - moreButton.width - 8 * HHUStyle.s
                            spacing:                0
                            HHUText { Layout.fillWidth: true; text: modelData.name; size: 16; bold: true; elide: Text.ElideRight }
                            HHUText {
                                Layout.fillWidth: true
                                text:   (modelData.area > 0 ? hhuSettings.formatArea(modelData.area) + " · " : "") + fields._formatDate(modelData.modified)
                                size:   14
                                color:  HHUStyle.text3
                                elide:  Text.ElideRight
                            }
                        }

                        Item {
                            id:                     moreButton
                            anchors.right:          parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width:                  44 * HHUStyle.s
                            height:                 44 * HHUStyle.s
                            HHUText { anchors.centerIn: parent; text: "⋯"; size: 22; bold: true; color: HHUStyle.text2 }
                            MouseArea {
                                anchors.fill:   parent
                                cursorShape:    Qt.PointingHandCursor
                                onClicked:      fieldMenu.openFor(modelData, moreButton)
                            }
                        }
                    }
                }

                HHUText {
                    visible:            hhuFields.fields.length === 0
                    Layout.fillWidth:   true
                    text:               qsTr("No fields yet. Create one, or import a route / KML file.")
                    size:               15
                    color:              HHUStyle.text3
                    wrapMode:           Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth:   true
                    spacing:            8 * HHUStyle.s
                    HHUButton {
                        Layout.fillWidth:   true
                        text:               qsTr("+ New field")
                        kind:               "outline"
                        size:               16
                        onClicked: {
                            root._autoSave()
                            fields.openNameDialog("new", "", "")
                        }
                    }
                    HHUButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Import")
                        kind:               "plain"
                        size:               16
                        onClicked: {
                            root._autoSave()
                            hhuFields.currentId = ""     // the imported plan becomes a new field
                            root.planMasterController.loadFromSelectedFile()
                        }
                    }
                }
            }

            // ② 画边界 ---------------------------------------------------------------------
            ColumnLayout {
                spacing: 10 * HHUStyle.s

                Row {
                    spacing: 6 * HHUStyle.s
                    HHUText { text: String(root._boundaryPoints); number: true; size: 30; anchors.bottom: parent.bottom }
                    HHUText { text: qsTr("points (at least 3)"); size: 15; color: HHUStyle.text3; anchors.bottom: parent.bottom; bottomPadding: 4 }
                }
                HHUButton {
                    Layout.fillWidth:   true
                    text:               qsTr("Add a point at the vehicle")
                    icon:               "pin"
                    kind:               "outline"
                    size:               16
                    h:                  56 * HHUStyle.s
                    enabled:            !!status.vehicle && status.vehicle.coordinate.isValid
                    onClicked:          vehiclePoints._withPosition(text, vehiclePoints._addFencePoint)
                }
                RowLayout {
                    Layout.fillWidth:   true
                    spacing:            8 * HHUStyle.s
                    HHUButton { Layout.fillWidth: true; text: qsTr("Undo"); kind: "plain"; size: 16; enabled: root._boundaryPoints > 0; onClicked: root._undoBoundary() }
                    HHUButton { Layout.fillWidth: true; text: qsTr("Clear"); kind: "plain"; size: 16; enabled: root._boundaryPoints > 0; onClicked: root._clearBoundary() }
                }
                Item { Layout.fillHeight: true }
            }

            // ③ 排航线 ---------------------------------------------------------------------
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
                    onClicked:          vehiclePoints._withPosition(text, root._addWaypoint)
                }
                RowLayout {
                    Layout.fillWidth:   true
                    spacing:            8 * HHUStyle.s
                    HHUButton { Layout.fillWidth: true; text: qsTr("Undo"); kind: "plain"; size: 16; enabled: root._waypoints > 0; onClicked: root._undoRoute() }
                    HHUButton { Layout.fillWidth: true; text: qsTr("Clear"); kind: "plain"; size: 16; enabled: root._waypoints > 0; onClicked: root._mission.removeAll() }
                }
                RowLayout {
                    Layout.fillWidth:   true
                    Layout.topMargin:   8 * HHUStyle.s
                    HHUText { Layout.fillWidth: true; text: qsTr("Speed"); size: 16; bold: true }
                    HHUStepper {
                        value:      root._speed
                        from:       0.2
                        to:         3.0
                        step:       0.1
                        decimals:   1
                        unit:       "m/s"
                        onEdited:   (v) => root._setSpeed(v)
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // ④ 检查上传 -------------------------------------------------------------------
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
                    text:               qsTr("Tight turns, boundary, waypoint count and connection are all fine.")
                    size:               15
                    color:              HHUStyle.text3
                    wrapMode:           Text.WordWrap
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
                visible:            root.step < 3
                Layout.fillWidth:   true
                text:               qsTr("Next")
                kind:               "blue"
                size:               17
                h:                  56 * HHUStyle.s
                enabled:            root.step !== 1 || root._boundaryPoints >= 3
                onClicked:          root.goTo(root.step + 1)
            }
            HHUButton {
                visible:            root.step === 3 && !root._uploaded
                Layout.fillWidth:   true
                text:               root._uploading ? qsTr("Uploading…") : qsTr("Upload to vehicle")
                kind:               "green"
                size:               17
                h:                  56 * HHUStyle.s
                enabled:            root._check.errors.length === 0 && !root._uploading && !!status.vehicle && status.canControl
                onClicked:          root._upload()
            }
            HHUButton {
                visible:            root.step === 3 && root._uploaded
                Layout.fillWidth:   true
                text:               qsTr("Go to work")
                kind:               "green"
                size:               17
                h:                  56 * HHUStyle.s
                onClicked:          mainWindow.showFlyView()
            }
        }
    }

    // How to edit on the map, centered above the map while drawing (设计稿 5b / 5c)
    Rectangle {
        parent:         root.parent
        visible:        root.step === 1 || root.step === 2
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
            text:               root.step === 1 ? qsTr("Tap the map to add a point · drag to change")
                                                : qsTr("Tap the map to add a waypoint · drag to change")
            size:               15
            bold:               true
            color:              "white"
        }
    }

    // ⋯ menu of a field: rename, copy, export, delete
    Popup {
        id:             fieldMenu
        parent:         mainWindow.contentItem
        padding:        8 * HHUStyle.s
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var field: ({})

        function openFor(f, item) {
            field = f
            const p = item.mapToItem(parent, 0, item.height)
            x = Math.min(p.x, parent.width - width - 8)
            y = Math.min(p.y, parent.height - height - 8)
            open()
        }

        background: HHUCard {}

        contentItem: ColumnLayout {
            spacing: 4 * HHUStyle.s
            Repeater {
                model: [ { t: qsTr("Rename"), a: "rename" }, { t: qsTr("Copy"), a: "copy" },
                         { t: qsTr("Export"), a: "export" }, { t: qsTr("Delete"), a: "delete" } ]
                HHUButton {
                    Layout.fillWidth:   true
                    Layout.minimumWidth: 160 * HHUStyle.s
                    text:               modelData.t
                    kind:               "plain"
                    size:               16
                    h:                  44 * HHUStyle.s
                    onClicked: {
                        const f = fieldMenu.field
                        fieldMenu.close()
                        switch (modelData.a) {
                        case "rename":  fields.openNameDialog("rename", f.id, f.name); break
                        case "copy":    hhuFields.duplicate(f.id); break
                        case "export":
                            root._autoSave()
                            if (f.id !== hhuFields.currentId) fields.load(f.id)
                            root.planMasterController.saveToSelectedFile()
                            break
                        case "delete":  fields.confirmDelete(f.id, f.name); break
                        }
                    }
                }
            }
        }
    }
}

"""Generate QML overrides from upstream files with small, checked patches.

Instead of hand-copying large upstream QML files, each override here is
upstream + a list of exact-text patches. If an upstream upgrade changes the
anchor text the script stops with an error, so the patch gets re-checked.

    python custom/tools/gen_overrides.py

Output: custom/src/qml/generated/*.qml (aliased in custom.qrc).
"""
import pathlib
import re
import sys

CUSTOM = pathlib.Path(__file__).resolve().parent.parent
SRC = CUSTOM.parent / "src"
OUT = CUSTOM / "src" / "qml" / "generated"


def hide_block_with_object_name(object_name):
    """Set `visible: false` on the ToolStripAction that has the given objectName."""
    def apply(text):
        pat = re.compile(r'(objectName: "%s"\n(?:[^\n]*\n)*?\s*)visible: [^\n]*' % re.escape(object_name))
        new, n = pat.subn(r"\1visible: false // HHU: customer build", text, count=1)
        if n != 1:
            raise SystemExit(f"anchor not found: objectName {object_name}")
        return new
    return apply


def replace_once(old, new):
    def apply(text):
        if text.count(old) != 1:
            raise SystemExit(f"anchor must occur exactly once ({text.count(old)}x): {old!r}")
        return text.replace(old, new)
    return apply


def replace_tail(anchor, new):
    """Replace everything from anchor (must occur once) to the end of the file."""
    def apply(text):
        if text.count(anchor) != 1:
            raise SystemExit(f"anchor must occur exactly once ({text.count(anchor)}x): {anchor!r}")
        return text[:text.index(anchor)] + new
    return apply


def add_import(module):
    def apply(text):
        if f"import {module}\n" in text:
            return text
        return text.replace("import QGroundControl\n", f"import QGroundControl\nimport {module}\n", 1)
    return apply


OVERRIDES = {
    # Boundary editing: drag handles only, no polygon tool bar (Basic / Circular / Trace / KML)
    "FlightMap/MapItems/QGCMapPolygonVisuals.qml": [
        replace_once("""    function addToolbarVisuals() {
        if (_objMgrToolVisuals.empty) {
""", """    function addToolbarVisuals() {
        if (false /* HHU: no polygon tool bar */ && _objMgrToolVisuals.empty) {
"""),
    ],
    # Waypoint numbers (设计稿 3): white with blue number; current (作业) green; selected (规划) blue + yellow ring
    "PlanView/MissionItemIndexLabel.qml": [
        add_import("HHU.Controls"),
        replace_once("""    property string _index:             index === 0 || index === -1 ? label.charAt(0) : (showSequenceNumbers ? index : "")
""", """    property string _index:             index === 0 || index === -1 ? label.charAt(0) : (showSequenceNumbers ? index : "")

    readonly property bool  _hhuCurrent:    checked && !HHUState.planPage
    readonly property bool  _hhuSelected:   checked && HHUState.planPage
    readonly property color _hhuFill:       _hhuCurrent ? HHUStyle.green : (_hhuSelected ? HHUStyle.blue : "white")
    readonly property color _hhuStroke:     _hhuCurrent ? "white" : HHUStyle.blue
    readonly property color _hhuText:       (_hhuCurrent || _hhuSelected) ? "white" : HHUStyle.blue
"""),
        replace_once("""        width:                          _indicatorRadius * 2
        height:                         width
        color:                          root.color
        radius:                         _indicatorRadius

        QGCLabel {
            anchors.fill:           parent
            horizontalAlignment:    Text.AlignHCenter
            verticalAlignment:      Text.AlignVCenter
            color:                  "white"
""", """        width:                          _indicatorRadius * 2
        height:                         width
        color:                          _hhuFill
        radius:                         _indicatorRadius
        border.color:                   _hhuStroke
        border.width:                   2

        QGCLabel {
            anchors.fill:           parent
            anchors.margins:        2
            horizontalAlignment:    Text.AlignHCenter
            verticalAlignment:      Text.AlignVCenter
            color:                  _hhuText
            font.family:            HHUStyle.numberFamily
            font.bold:              true
"""),
        replace_once("""        width:          indicator.width * 2
        height:         width
        radius:         width * 0.5
        color:          Qt.rgba(0,0,0,0)
        border.color:   Qt.rgba(1,1,1,0.5)
        border.width:   1
        visible:        checked && highlightSelected
""", """        width:          indicator.width + 10
        height:         width
        radius:         width * 0.5
        color:          Qt.rgba(0,0,0,0)
        border.color:   HHUStyle.yellow
        border.width:   3
        visible:        _hhuSelected
"""),
    ],
    # Field boundary (geofence): bright blue, solid (设计稿 3; no dashes)
    "PlanView/GeoFenceMapVisuals.qml": [
        add_import("HHU.Controls"),
        replace_once("""    property color  _borderColor:               "orange"
    property int    _borderWidthInclusion:      2
""", """    property color  _borderColor:               HHUStyle.fence
    property int    _borderWidthInclusion:      4
"""),
    ],
    # All QGC dialogs (showMessageDialog etc.) in the HHU look: white card, big title, buttons in a grey footer
    "QmlControls/QGCPopupDialog.qml": [
        add_import("HHU.Controls"),
        replace_once("""    background: QGCMouseArea {
        width:  mainWindow.width
        height: mainWindow.height
""", """    background: QGCMouseArea {
        width:  mainWindow.width
        height: mainWindow.height

        Rectangle { anchors.fill: parent; color: HHUStyle.dim }   // HHU
"""),
        replace_tail("""    Rectangle {
        x:              mainLayout.x - _contentMargin
""", """    // HHU dialog card
    Rectangle {
        anchors.fill:   mainLayout
        color:          "white"
        radius:         HHUStyle.radiusDlg
    }

    ColumnLayout {
        id:                 mainLayout
        anchors.centerIn:   parent
        spacing:            0

        RowLayout {
            id:                     titleRowLayout
            Layout.fillWidth:       true
            Layout.leftMargin:      28 * HHUStyle.s
            Layout.rightMargin:     28 * HHUStyle.s
            Layout.topMargin:       24 * HHUStyle.s

            HHUText {
                id:                 titleLabel
                objectName:         "popupDialog_title"
                Layout.fillWidth:   true
                text:               root.title
                size:               26
                bold:               true
                elide:              Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth:       true
            Layout.margins:         28 * HHUStyle.s - _contentMargin
            Layout.topMargin:       10 * HHUStyle.s
            Layout.preferredWidth:  Math.max(400 * HHUStyle.s, Math.min(maxAvailableWidth, totalContentWidth))
            Layout.preferredHeight: Math.min(maxAvailableHeight, totalContentHeight)
            color:                  "white"

            property real totalContentWidth:    dialogContentParent.childrenRect.width + _contentMargin * 2
            property real totalContentHeight:   dialogContentParent.childrenRect.height + _contentMargin * 2
            property real maxAvailableWidth:    mainWindow.width - 80 * HHUStyle.s
            property real maxAvailableHeight:   mainWindow.height - titleRowLayout.height - footer.height - 80 * HHUStyle.s

            QGCFlickable {
                anchors.margins:    _contentMargin
                anchors.fill:       parent
                contentWidth:       dialogContentParent.childrenRect.width
                contentHeight:      dialogContentParent.childrenRect.height

                Item {
                    id:     dialogContentParent
                    focus:  true

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape && _rejectAllowed) {
                            _reject()
                            event.accepted = true
                        }
                    }
                }
            }
        }

        Rectangle {
            id:                     footer
            Layout.fillWidth:       true
            Layout.preferredHeight: 64 * HHUStyle.s + 32 * HHUStyle.s
            color:                  HHUStyle.grey
            radius:                 HHUStyle.radiusDlg

            Rectangle { width: parent.width; height: parent.radius; color: parent.color }
            Rectangle { width: parent.width; height: 1; color: HHUStyle.divider }

            RowLayout {
                anchors.fill:           parent
                anchors.leftMargin:     28 * HHUStyle.s
                anchors.rightMargin:    28 * HHUStyle.s
                spacing:                12 * HHUStyle.s

                Item { Layout.fillWidth: true }

                HHUButton {
                    id:                     rejectButton
                    objectName:             "popupDialog_rejectButton"
                    kind:                   "plain"
                    h:                      56 * HHUStyle.s
                    size:                   18
                    minWidth:               120
                    onClicked:              _reject()
                }

                HHUButton {
                    id:                     acceptButton
                    objectName:             "popupDialog_acceptButton"
                    kind:                   "blue"
                    h:                      56 * HHUStyle.s
                    size:                   18
                    minWidth:               120
                    onClicked:              _accept()
                }
            }
        }
    }
}
"""),
    ],
    # 航线页: waypoints only (需求说明 §6). The pattern button comes back as 地块覆盖 (Fields2Cover).
    "PlanView/PlanView.qml": [
        add_import("QGroundControl.PlanView"),
        hide_block_with_object_name("planToolStrip_takeoffButton"),
        hide_block_with_object_name("planToolStrip_patternButton"),
        hide_block_with_object_name("planToolStrip_roiButton"),
        hide_block_with_object_name("planToolStrip_landButton"),
        add_import("HHU.Controls"),
        # 规划 page (设计稿 5a–5e): the HHU step panel on the left replaces the tool strip, the plan tree
        # (right panel), the layer switcher and the toolbar actions; the map keeps QGC's editing
        replace_once("""        ToolStrip {
            id: toolStrip
            anchors.margins: _toolsMargin
            anchors.left: parent.left
            anchors.top: parent.top
""", """        HHUPlanPanel {
            id: hhuPlanPanel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: HHUStyle.margin * 0.75
            z: QGroundControl.zOrderWidgets
            planView: _root
            planMasterController: planMasterController  // the PlanMasterController id: has the file dialogs
            editorMap: editorMap
        }

        ToolStrip {
            id: toolStrip
            visible: false  // HHU: replaced by the step panel
            anchors.margins: _toolsMargin
            anchors.left: parent.left
            anchors.top: parent.top
"""),
        replace_once("""            maxHeight: parent.height - toolStrip.y
            visible: _editingLayer == _layerMission
""", """            maxHeight: parent.height - toolStrip.y
"""),
        replace_once("""        MapScale {
            anchors.margins: _toolsMargin
            anchors.left: toolStrip.right
            anchors.top: parent.top
""", """        MapScale {
            anchors.margins: _toolsMargin
            anchors.left: hhuPlanPanel.right
            anchors.top: parent.top
"""),
        replace_once("""                case _layerRally:
                    if (_rallyPointController.supported) {
""", """                case _layerFence:
                    hhuPlanPanel.boundaryClicked(coordinate)  // HHU: 画边界
                    break
                case _layerRally:
                    if (_rallyPointController.supported) {
"""),
        replace_once("""            z:                      QGroundControl.zOrderWidgets
            visible:                !_planMasterController.showCreateFromTemplate
""", """            z:                      QGroundControl.zOrderWidgets
            visible:                false  // HHU: the step chooses the layer
"""),
        replace_once("""            width: _rightPanelWidth
            planMasterController: _planMasterController
            editorMap: editorMap
""", """            width: 0  // HHU
            planMasterController: _planMasterController
            editorMap: editorMap
"""),
        # No template page: an empty plan goes straight to editing (需求说明 §6)
        replace_once("""            _planMasterController.start()
            _missionController.setCurrentPlanViewSeqNum(0, true)
        }
""", """            _planMasterController.start()
            _missionController.setCurrentPlanViewSeqNum(0, true)
            Qt.callLater(_root._hhuSkipTemplates)
        }

        onShowCreateFromTemplateChanged: Qt.callLater(_root._hhuSkipTemplates)
"""),
        replace_once("""    readonly property int   _decimalPlaces: 8
""", """    readonly property int   _decimalPlaces: 8

    // HHU: waypoint labels show the selected item (规划) or the vehicle's current item (作业)
    Binding { target: HHUState; property: "planPage"; value: _root.visible }

    function _hhuSkipTemplates() {
        if (_planMasterController.showCreateFromTemplate) {
            _planMasterController.userSelectedManualCreation = true
        }
    }
"""),
        # Without a vehicle QGC needs a planned home before inserting; the first click sets it
        replace_once("""                        objectName: "planToolStrip_waypointButton"
                        text: qsTr("Waypoint")
                        iconSource: "/res/waypoint.svg"
                        enabled: _missionController.flyThroughCommandsAllowed
""", """                        objectName: "planToolStrip_waypointButton"
                        text: qsTr("Waypoint")
                        iconSource: "/res/waypoint.svg"
                        enabled: _missionController.flyThroughCommandsAllowed || !_missionController.homePositionSet
"""),
        replace_once("""                    } else if (_addWaypointOnClick) {
""", """                    } else if (_addWaypointOnClick) {
                        if (!_missionController.homePositionSet) {
                            _missionController.setHomePosition(coordinate)  // HHU: no planned home UI
                        }
"""),
        # Route summary card at the bottom of the map
        replace_once("""        PlanViewRightPanel {
            id: rightPanel
""", """        HHUPlanSummary {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: HHUStyle.margin
            z: QGroundControl.zOrderWidgets
            showRoute: hhuPlanPanel.step >= 2
            missionController: _missionController
            geoFenceController: _geoFenceController
            visible: _missionController.visualItems.count > 1 || _geoFenceController.polygons.count > 0
        }

        // Waypoints where the vehicle cannot make the turn are ringed red (上传前检查)
        HHUUploadCheck {
            id: hhuTurnCheck
            visible: false
            live: true
            planMasterController: _planMasterController
        }

        MapItemView {
            id: hhuTightTurnView
            model: hhuTurnCheck.tightTurns
            delegate: MapQuickItem {
                coordinate: modelData.coordinate
                anchorPoint.x: sourceItem.width / 2
                anchorPoint.y: sourceItem.height / 2
                z: QGroundControl.zOrderMapItems + 2
                sourceItem: Rectangle {
                    width: ScreenTools.defaultFontPixelHeight * 2.6
                    height: width
                    radius: width / 2
                    color: "#40E5484D"
                    border.color: "#E5484D"
                    border.width: 3
                }
            }
            Component.onCompleted: editorMap.addMapItemView(hhuTightTurnView)
        }

        PlanViewRightPanel {
            id: rightPanel
            visible: false  // HHU: the step panel edits the plan
"""),
    ],
    # No planned home section (distance/time are estimated from the vehicle position)
    "PlanView/PlanInfoEditor.qml": [
        replace_once("""            id: plannedHomePositionSection
            Layout.fillWidth: true
""", """            id: plannedHomePositionSection
            Layout.fillWidth: true
            visible: false  // HHU
            checked: false  // HHU: hides the section content too
"""),
    ],
    # Layer switcher without rally points (geofence stays)
    "PlanView/PlanEditLayers.qml": [
        replace_once("""        { layer: layerFence,   nodeType: "fenceGroup",   icon: "/res/GeoFence.svg",   name: qsTr("GeoFence") },
        { layer: layerRally,   nodeType: "rallyGroup",   icon: "/res/RallyPoint.svg", name: qsTr("Rally Points") }
""", """        { layer: layerFence,   nodeType: "fenceGroup",   icon: "/res/GeoFence.svg",   name: qsTr("GeoFence") }
"""),
    ],
    # Plan tree without the rally point rows
    "PlanView/PlanTreeView.qml": [
        replace_once("""        implicitHeight: (loader.item ? loader.item.height : 1) + (separatorLine.visible ? separatorLine.height + root.rowSpacing : 0)
""", """        implicitHeight: _hhuHidden ? 0.01 : (loader.item ? loader.item.height : 1) + (separatorLine.visible ? separatorLine.height + root.rowSpacing : 0)
        visible: !_hhuHidden
        // HHU: no rally points, no mission-start settings row (speed is set under 默认值)
        // (0.01: TableView gives 0-height rows a default height)
        readonly property bool _hhuHidden: nodeType.startsWith("rally") || (nodeType === "missionItem" && !!nodeObject && nodeObject.sequenceNumber === 0)
"""),
    ],
    # Waypoint rows show the distance from the previous point
    "PlanView/MissionItemEditor.qml": [
        replace_once("""            id:                     commandLabel
            anchors.verticalCenter: parent.verticalCenter
            width:                  commandPicker.width
            height:                 commandPicker.height
            visible:                !missionItem.isCurrentItem || !missionItem.isSimpleItem || _waypointsOnlyMode || missionItem.isTakeoffItem
            verticalAlignment:      Text.AlignVCenter
            text:                   missionItem.commandName
""", """            id:                     commandLabel
            anchors.verticalCenter: parent.verticalCenter
            width:                  Math.min(implicitWidth, _root.width - parent.x - x - ScreenTools.defaultFontPixelHeight * (missionItem.isCurrentItem ? 2.5 : 0.5))
            elide:                  Text.ElideRight
            height:                 commandPicker.height
            visible:                !missionItem.isCurrentItem || !missionItem.isSimpleItem || _waypointsOnlyMode || missionItem.isTakeoffItem
            verticalAlignment:      Text.AlignVCenter
            text:                   missionItem.distance > 0 ? qsTr("%1 %2   %3 m").arg(missionItem.sequenceNumber).arg(missionItem.commandName).arg(missionItem.distance.toFixed(1)) : missionItem.sequenceNumber + " " + missionItem.commandName
"""),
    ],
    # Upload runs the route checks first
    "PlanView/PlanToolBarIndicators.qml": [
        add_import("HHU.Controls"),
        replace_once("""    function _uploadClicked() {
        _planMasterController.upload()
    }
""", """    function _uploadClicked() {
        hhuUploadCheck.run(function() {
            _planMasterController.upload()
            // 断点续作 needs to know which field is on the vehicle
            hhuWork.setVehicleField(QGroundControl.multiVehicleManager.activeVehicle, hhuFields.currentId)
        })
    }

    HHUUploadCheck {
        id: hhuUploadCheck
        visible: false
        planMasterController: root._planMasterController
    }

    HHUFieldPanel {
        id: hhuFieldPanel
        planMasterController: root._planMasterController
    }
"""),
        # 地块 button first; 保存 stores into the open field (需求说明 V1.0 §3.3 地块管理)
        replace_once("""    QGCButton {
        objectName: "planToolbar_openButton"
        text: qsTr("Open")
""", """    QGCButton {
        objectName: "planToolbar_fieldsButton"
        text: hhuFields.currentId !== "" ? qsTr("Field: %1").arg(hhuFields.current.name || "") : qsTr("Fields")
        iconSource: "/res/GeoFence.svg"
        primary: hhuFields.currentId === ""
        enabled: !_planMasterController.syncInProgress
        onClicked: { toolbarButtonClicked(); hhuFieldPanel.open() }
    }

    QGCButton {
        objectName: "planToolbar_openButton"
        text: qsTr("Import")
"""),
        replace_once("""    function _saveButtonClicked() {
        if (_planMasterController.currentPlanFile === "") {
            _planMasterController.saveToSelectedFile()
        } else {
            _planMasterController.saveToCurrent()
        }
    }
""", """    function _saveButtonClicked() {
        hhuFieldPanel.saveCurrent()
    }
"""),
        replace_once("""                        text: qsTr("Save as...")
""", """                        text: qsTr("Export .plan")
"""),
    ],
    # Waypoint editor: no altitude (rover, altitude always 0)
    "PlanView/SimpleItemEditor.qml": [
        add_import("QGroundControl.PlanView"),
        replace_once("                    spacing: _fieldSpacing\n                    visible: _specifiesAltitude\n",
                     "                    spacing: _fieldSpacing\n                    visible: false // HHU: rover, no altitude\n"),
        # Only the basic tab (speed); no camera / advanced (hold time, yaw ...) tabs
        replace_once("                property bool _advancedItemsAvailable: missionItem.comboboxFactsAdvanced.count > 0 || missionItem.textFieldFactsAdvanced.count > 0 || missionItem.nanFactsAdvanced.count > 0\n                property bool _cameraAvailable: missionItem.cameraSection.available\n",
                     "                property bool _advancedItemsAvailable: false  // HHU\n                property bool _cameraAvailable: false  // HHU: no camera\n"),
    ],
    # 作业 map: no upstream click menu (go to / orbit / ROI / set home are aircraft tools);
    # long press or right click = 开到指定点 (需求说明 V1.0 §3.2)
    "FlyView/FlyViewMap.qml": [
        add_import("HHU.Controls"),
        # Track: orange 5 px (设计稿 4.3)
        replace_once("""        id:         trajectoryPolyline
        line.width: 3
        line.color: "red"
""", """        id:         trajectoryPolyline
        line.width: 5
        line.color: HHUStyle.track
"""),
        replace_once("""    onMapClicked: (position) => {
        if (!globals.guidedControllerFlyView.guidedUIVisible &&
""", """    onMapPressAndHold: (position) => hhuGoto.request(_root.toCoordinate(Qt.point(position.x, position.y), false))
    onMapRightClicked: (position) => hhuGoto.request(_root.toCoordinate(Qt.point(position.x, position.y), false))

    HHUGotoHere {
        id: hhuGoto
        mapControl: _root
        planMasterController: _root.planMasterController
    }

    onMapClicked: (position) => {
        if (false /* HHU: menu disabled */ && !globals.guidedControllerFlyView.guidedUIVisible &&
"""),
    ],
    # Link types: serial, UDP, TCP, Bluetooth only (需求说明 V1.0 §4.1); no log replay / high latency
    "AppSettings/LinkConfigurationManager.qml": [
        add_import("QGroundControl.AppSettings"),
        replace_once("""                QGCCheckBoxSlider {
                    Layout.fillWidth:   true
                    text:               qsTr("High Latency")
""", """                QGCCheckBoxSlider {
                    Layout.fillWidth:   true
                    visible:            false // HHU
                    text:               qsTr("High Latency")
"""),
        replace_once("""                    model:                  _linkManager.linkTypeStrings
""", """                    // HHU: the first entries follow LinkConfiguration.LinkType up to Bluetooth
                    model:                  _linkManager.linkTypeStrings.slice(0, LinkConfiguration.TypeBluetooth + 1)
"""),
    ],
    # Mission defaults: no altitude frame / default altitude
    "PlanView/MissionDefaultsEditor.qml": [
        replace_once('            label: qsTr("Alt Frame")\n',
                     '            label: qsTr("Alt Frame")\n            visible: false // HHU\n'),
        replace_once('            label: qsTr("Waypoints Altitude")\n',
                     '            label: qsTr("Waypoints Altitude")\n            visible: false // HHU\n'),
    ],
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for rel, patches in OVERRIDES.items():
        text = (SRC / rel).read_text(encoding="utf-8")
        for patch in patches:
            text = patch(text)
        header = f"// GENERATED by custom/tools/gen_overrides.py from upstream src/{rel} - do not edit\n"
        (OUT / pathlib.Path(rel).name).write_text(header + text, encoding="utf-8")
        print("generated", rel)


if __name__ == "__main__":
    sys.exit(main())

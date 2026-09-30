import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls

/// 用车辆位置打点 (需求说明 V1.0 §3.3): drive the vehicle to a headland / field corner and add a
/// waypoint or a geofence corner at its position. Without RTK fixed the user is warned first.
/// Fence corners: the first two are kept as markers, the third creates the geofence polygon,
/// later ones are appended to it.
ColumnLayout {
    id: root

    property var planMasterController
    property var editorMap
    /// function(coordinate) inserting a waypoint after the current one (PlanView.insertSimpleItemAfterCurrent)
    property var insertWaypoint

    spacing: ScreenTools.defaultFontPixelWidth * 0.6
    visible: !!status.vehicle && status.vehicle.coordinate.isValid

    HHUStatus { id: status }

    readonly property var _fenceController: planMasterController ? planMasterController.geoFenceController : null

    /// Fence corners collected before the polygon exists
    property var _pendingFence: []

    function _withPosition(what, fn) {
        const coordinate = QtPositioning.coordinate(status.vehicle.coordinate.latitude, status.vehicle.coordinate.longitude)
        if (status.rtkFixed) {
            fn(coordinate)
            return
        }
        QGroundControl.showMessageDialog(root, what,
                                         qsTr("Position accuracy is not sufficient (%1). Add the point anyway?").arg(status.fixText),
                                         Dialog.Ok | Dialog.Cancel, function() { fn(coordinate) })
    }

    function _inclusionPolygon() {
        for (let i = _fenceController.polygons.count - 1; i >= 0; i--) {
            const polygon = _fenceController.polygons.get(i)
            if (polygon.inclusion) {
                return polygon
            }
        }
        return null
    }

    function _addFencePoint(coordinate) {
        const polygon = _inclusionPolygon()
        if (polygon) {
            polygon.appendVertex(coordinate)
            return
        }
        let pending = _pendingFence.concat([coordinate])
        if (pending.length < 3) {
            _pendingFence = pending
            return
        }
        // Create a polygon, then replace its default rectangle by the recorded corners
        _fenceController.addInclusionPolygon(pending[0], pending[2])
        const created = _inclusionPolygon()
        if (created) {
            created.clear()
            created.appendVertices(pending)
        }
        _pendingFence = []
    }

    Connections {
        target: root.planMasterController
        function onDirtyForUploadChanged() {
            // A cleared, uploaded or newly loaded plan drops the unfinished corners
            if (root.planMasterController && !root.planMasterController.dirtyForUpload) {
                root._pendingFence = []
            }
        }
    }

    HHUMapToolButton {
        Layout.fillWidth:   true
        text:               qsTr("Waypoint at vehicle")
        iconSource:         "/res/waypoint.svg"
        onClicked:          root._withPosition(text, root.insertWaypoint)
    }

    HHUMapToolButton {
        Layout.fillWidth:   true
        text:               root._pendingFence.length > 0
                            ? qsTr("Fence corner at vehicle (%1/3)").arg(root._pendingFence.length)
                            : qsTr("Fence corner at vehicle")
        iconSource:         "/res/GeoFence.svg"
        enabled:            !!root._fenceController
        onClicked:          root._withPosition(text, root._addFencePoint)
    }

    // Corners recorded before the polygon exists (added to the map, not to this layout)
    readonly property Item _pendingView: MapItemView {
        model:  root._pendingFence

        delegate: MapQuickItem {
            coordinate:     modelData
            anchorPoint.x:  sourceItem.width / 2
            anchorPoint.y:  sourceItem.height / 2
            z:              QGroundControl.zOrderMapItems + 2
            sourceItem: Rectangle {
                width:          ScreenTools.defaultFontPixelHeight
                height:         width
                radius:         width / 2
                color:          "#F2B705"
                border.color:   "black"
                border.width:   1
            }
        }
    }

    Component.onCompleted: {
        if (editorMap) {
            editorMap.addMapItemView(_pendingView)
        }
    }
}

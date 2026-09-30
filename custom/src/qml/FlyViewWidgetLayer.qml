import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import HHU.Controls

// HHU override of QGroundControl/FlyView/FlyViewWidgetLayer.qml
// Replaces the aircraft tool strip / instrument panel / telemetry bar with the
// 航线 switch (top left), work panel (right), progress card (bottom), map tools (bottom left)
// and the alarm banner (top center).
Item {
    id: _root

    property var    parentToolInsets
    property var    totalToolInsets:        _totalToolInsets
    property var    mapControl
    property var    viewer3DCameraController

    property var    _planMasterController:  globals.planMasterControllerFlyView
    property var    _missionController:     _planMasterController.missionController
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property real   _margin:                ScreenTools.defaultFontPixelWidth
    property bool   _hasRoute:              _missionController.visualItems.count > 1

    QGCToolInsets {
        id:                     _totalToolInsets
        leftEdgeTopInset:       parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset:    parentToolInsets.leftEdgeCenterInset
        leftEdgeBottomInset:    mapTools.x + mapTools.width + _margin
        rightEdgeTopInset:      workPanel.width + _margin
        rightEdgeCenterInset:   workPanel.width + _margin
        rightEdgeBottomInset:   workPanel.width + _margin
        topEdgeLeftInset:       routeSwitch.y + routeSwitch.height + _margin
        topEdgeCenterInset:     mapScale.y + mapScale.height + _margin
        topEdgeRightInset:      parentToolInsets.topEdgeRightInset
        bottomEdgeLeftInset:    (progress.visible ? progress.height : 0) + _margin
        bottomEdgeCenterInset:  (progress.visible ? progress.height : 0) + _margin
        bottomEdgeRightInset:   (progress.visible ? progress.height : 0) + _margin
    }

    // One-click switch to the 航线 page (需求说明 §3.1)
    HHUMapToolButton {
        id:                 routeSwitch
        anchors.left:       parent.left
        anchors.top:        parent.top
        z:                  QGroundControl.zOrderWidgets
        primary:            true
        text:               qsTr("Route")
        iconSource:         "/qmlimages/Plan.svg"
        onClicked:          mainWindow.showPlanView()
    }

    MapScale {
        id:                 mapScale
        anchors.left:       routeSwitch.right
        anchors.leftMargin: _margin
        anchors.verticalCenter: routeSwitch.verticalCenter
        mapControl:         _root.mapControl
        autoHide:           true
        visible:            QGroundControl.corePlugin.options.flyView.showMapScale
    }

    HHUWorkPanel {
        id:                     workPanel
        anchors.right:          parent.right
        anchors.verticalCenter: parent.verticalCenter
        planMasterController:   _planMasterController
        z:                      QGroundControl.zOrderWidgets
    }

    // Alarm banner + sound, link lost / restored handling (需求说明 V1.0 §3.6)
    HHUAlarms {
        anchors.top:                parent.top
        // below QGC's own vehicle error popup (top center), so both stay readable
        anchors.topMargin:          ScreenTools.defaultFontPixelHeight * 6
        anchors.horizontalCenter:   parent.horizontalCenter
        planMasterController:       _planMasterController
        mapControl:                 _root.mapControl
        z:                          QGroundControl.zOrderTopMost
    }

    HHUMissionProgress {
        id:                         progress
        anchors.bottom:             parent.bottom
        anchors.horizontalCenter:   parent.horizontalCenter
        missionController:          _missionController
        z:                          QGroundControl.zOrderWidgets
        visible:                    _hasRoute
    }

    ColumnLayout {
        id:                 mapTools
        anchors.left:       parent.left
        anchors.bottom:     parent.bottom
        spacing:            _margin * 0.6
        z:                  QGroundControl.zOrderWidgets
        visible:            !!_activeVehicle

        HHUMapToolButton {
            Layout.fillWidth: true
            text:           qsTr("Locate vehicle")
            iconSource:     "/InstrumentValueIcons/location-current.svg"
            enabled:        !!_activeVehicle && _activeVehicle.coordinate.isValid
            onClicked:      _root.mapControl.center = _activeVehicle.coordinate
        }
        HHUMapToolButton {
            Layout.fillWidth: true
            text:           qsTr("Clear track")
            iconSource:     "/InstrumentValueIcons/trash.svg"
            enabled:        !!_activeVehicle
            onClicked:      _activeVehicle.trajectoryPoints.clear()
        }
    }

    // 检查更新 at start-up (需求说明 V1.0 §3.8): offer the new version once
    property bool _updateOffered: false
    Connections {
        target: hhuService
        function onUpdateChanged() {
            if (hhuService.updateState === "available" && !_root._updateOffered) {
                _root._updateOffered = true
                QGroundControl.showMessageDialog(_root, qsTr("Software update"),
                                                 qsTr("Version %1 is available.").arg(hhuService.update.version)
                                                 + (hhuService.update.notes ? "

" + hhuService.update.notes : "")
                                                 + "

" + qsTr("Download and install now? The ground station closes for the installation."),
                                                 Dialog.Ok | Dialog.Cancel,
                                                 function() { hhuService.downloadAndInstall() })
            }
        }
    }

    // 作业记录, opened from the 校徽 menu
    HHUWorkRecords { id: hhuWorkRecords }
    Connections {
        target: hhuWork
        function onShowRecordsRequested() { hhuWorkRecords.open() }
    }

    VehicleWarnings {
        anchors.centerIn:   parent
        z:                  QGroundControl.zOrderTopMost
    }

    // No FlyViewMissionCompleteDialog: its "resume mission" rewrites the route on the vehicle and
    // conflicts with 断点续作 (HHUStartDialog); the work record is written by hhuWork instead
}

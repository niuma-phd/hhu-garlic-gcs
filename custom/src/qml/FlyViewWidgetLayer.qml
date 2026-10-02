import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import HHU.Controls

// HHU override of QGroundControl/FlyView/FlyViewWidgetLayer.qml (设计稿 4a–4j)
// Replaces the aircraft tool strip / instrument panel / telemetry bar with the progress card (bottom
// left), work buttons (bottom right), map tools (top right) and the alarm banners (top center).
Item {
    id: _root

    property var    parentToolInsets
    property var    totalToolInsets:        _totalToolInsets
    property var    mapControl
    property var    viewer3DCameraController

    property var    _planMasterController:  globals.planMasterControllerFlyView
    property var    _missionController:     _planMasterController.missionController
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property real   _margin:                HHUStyle.margin
    property bool   _hasRoute:              _missionController.visualItems.count > 1

    QGCToolInsets {
        id:                     _totalToolInsets
        leftEdgeTopInset:       parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset:    parentToolInsets.leftEdgeCenterInset
        leftEdgeBottomInset:    progress.visible ? progress.width + _margin : parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      mapTools.width + _margin
        rightEdgeCenterInset:   parentToolInsets.rightEdgeCenterInset
        rightEdgeBottomInset:   workPanel.width + _margin
        topEdgeLeftInset:       mapScale.y + mapScale.height + _margin
        topEdgeCenterInset:     alarms.y + alarms.height + _margin
        topEdgeRightInset:      mapTools.y + mapTools.height + _margin
        bottomEdgeLeftInset:    progress.visible ? progress.height + _margin * 1.25 : parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset:  parentToolInsets.bottomEdgeCenterInset
        bottomEdgeRightInset:   workPanel.height + _margin * 1.25
    }

    MapScale {
        id:                 mapScale
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.margins:    _margin
        mapControl:         _root.mapControl
        autoHide:           true
        visible:            QGroundControl.corePlugin.options.flyView.showMapScale
    }

    // Progress card (bottom left)
    HHUMissionProgress {
        id:                 progress
        anchors.left:       parent.left
        anchors.bottom:     parent.bottom
        anchors.leftMargin: _margin
        anchors.bottomMargin: _margin * 1.25
        missionController:  _missionController
        z:                  QGroundControl.zOrderWidgets
        visible:            _hasRoute && !!_activeVehicle
    }

    // Work buttons (bottom right), only those the current state allows
    HHUWorkPanel {
        id:                     workPanel
        anchors.right:          parent.right
        anchors.bottom:         parent.bottom
        anchors.rightMargin:    _margin
        anchors.bottomMargin:   _margin * 1.25
        // clear of the progress card on small screens
        maxWidth:               parent.width - (progress.visible ? progress.width + _margin : 0) - _margin * 2
        planMasterController:   _planMasterController
        z:                      QGroundControl.zOrderWidgets
    }

    // Map tools (top right)
    HHUCard {
        id:                     mapTools
        anchors.right:          parent.right
        anchors.top:            parent.top
        anchors.margins:        _margin
        width:                  toolColumn.implicitWidth + 8 * HHUStyle.s
        height:                 toolColumn.implicitHeight + 8 * HHUStyle.s
        radius:                 12 * HHUStyle.s
        z:                      QGroundControl.zOrderWidgets
        visible:                !!_activeVehicle

        Column {
            id:                 toolColumn
            anchors.centerIn:   parent

            Repeater {
                model: [
                    { icon: "locate", t: qsTr("Find vehicle") },
                    { icon: "trash",  t: qsTr("Clear track") }
                ]
                Rectangle {
                    width:  60 * HHUStyle.s
                    height: 60 * HHUStyle.s
                    radius: 9 * HHUStyle.s
                    color:  toolMouse.containsMouse ? HHUStyle.grey2 : "transparent"

                    Column {
                        anchors.centerIn:   parent
                        spacing:            2
                        HHUIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name:   modelData.icon
                            color:  HHUStyle.blue
                        }
                        HHUText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:   modelData.t
                            size:   14
                            bold:   true
                        }
                    }
                    MouseArea {
                        id:             toolMouse
                        anchors.fill:   parent
                        hoverEnabled:   true
                        cursorShape:    Qt.PointingHandCursor
                        onClicked: {
                            if (!_activeVehicle) {
                                return
                            }
                            if (index === 0) {
                                if (_activeVehicle.coordinate.isValid) {
                                    _root.mapControl.center = _activeVehicle.coordinate
                                }
                            } else {
                                _activeVehicle.trajectoryPoints.clear()
                            }
                        }
                    }
                }
            }
        }
    }

    // Alarm banners + sound, link lost / restored handling (需求说明 V1.0 §3.6)
    HHUAlarms {
        id:                         alarms
        anchors.top:                parent.top
        anchors.topMargin:          12 * HHUStyle.s
        anchors.horizontalCenter:   parent.horizontalCenter
        maxWidth:                   parent.width - (mapTools.width + _margin * 2) * 2
        planMasterController:       _planMasterController
        mapControl:                 _root.mapControl
        z:                          QGroundControl.zOrderTopMost
    }

    // 检查更新 at start-up (需求说明 V1.0 §3.8): offered once, not while the vehicle is working
    property bool _updateOffered: false
    readonly property bool _updatePending: hhuService.updateState === "available" && !_updateOffered
                                           && !(_activeVehicle && _activeVehicle.armed)
    on_UpdatePendingChanged: {
        if (_updatePending) {
            _updateOffered = true
            updateDialog.open()
        }
    }

    HHUDialog {
        id:         updateDialog
        title:      qsTr("New version %1").arg(hhuService.update ? hhuService.update.version : "")
        dialogWidth: 520

        HHUText {
            Layout.fillWidth:   true
            text:               (hhuService.update && hhuService.update.notes ? hhuService.update.notes + "\n" : "")
                                + qsTr("The ground station closes for the installation.")
            size:               17
            color:              HHUStyle.text2
            wrapMode:           Text.WordWrap
        }

        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Later"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; onClicked: updateDialog.close() },
            HHUButton { text: qsTr("Download and install"); kind: "blue"; size: 18; h: 56 * HHUStyle.s
                        onClicked: { updateDialog.close(); hhuService.downloadAndInstall() } }
        ]
    }

    VehicleWarnings {
        anchors.centerIn:   parent
        z:                  QGroundControl.zOrderTopMost
    }

    // No FlyViewMissionCompleteDialog: its "resume mission" rewrites the route on the vehicle and
    // conflicts with 断点续作 (HHUStartDialog)
}

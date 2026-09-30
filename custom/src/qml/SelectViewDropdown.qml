import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import HHU.Controls

// HHU override of QGroundControl/Toolbar/SelectViewDropdown.qml
// Only 作业 / 航线 / 作业记录 / 设置 / 退出. Vehicle setup and analyze tools are engineer-only (Mission Planner).
ToolIndicatorPage {
    id: root

    property real _toolButtonHeight: ScreenTools.defaultFontPixelHeight * 3

    contentComponent: Component {
        GridLayout {
            columns: 2
            columnSpacing: ScreenTools.defaultFontPixelWidth
            rowSpacing: columnSpacing

            SubMenuButton {
                objectName: "toolbar_viewFly"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Work")
                imageResource: "/hhu/tractor.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showFlyView()
                    }
                }
            }

            SubMenuButton {
                objectName: "toolbar_viewPlan"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Route")
                imageResource: "/qmlimages/Plan.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showPlanView()
                    }
                }
            }

            SubMenuButton {
                objectName: "toolbar_workRecords"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Work records")
                imageResource: "/InstrumentValueIcons/list.svg"
                onClicked: {
                    mainWindow.closeIndicatorDrawer()
                    hhuWork.requestShowRecords()   // the window lives on the 作业 page
                }
            }

            SubMenuButton {
                objectName: "toolbar_viewSettings"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Settings")
                imageResource: "/InstrumentValueIcons/cog.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showSettingsTool()
                    }
                }
            }

            SubMenuButton {
                objectName: "toolbar_viewClose"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Exit")
                imageResource: "/res/OpenDoor.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.close()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                spacing: 0

                QGCLabel {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Hohai University Garlic Seeder Ground Station")
                    font.pointSize: ScreenTools.smallFontPointSize
                    wrapMode: QGCLabel.WordWrap
                }

                QGCLabel {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Version %1").arg(hhuService.appVersion)
                    font.pointSize: ScreenTools.smallFontPointSize
                    wrapMode: QGCLabel.WrapAnywhere
                }
            }
        }
    }
}

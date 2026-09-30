import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.PlanView

// HHU override of QGroundControl/Toolbar/PlanViewToolBar.qml (brand block replaces the QGC logo button)
Rectangle {
    id: _root
    width: parent.width
    height: ScreenTools.toolbarHeight
    color: qgcPal.toolbarBackground

    property var planMasterController
    property bool showRallyPointsHelp: false

    signal toolbarButtonClicked()

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property real _controllerProgressPct: planMasterController.missionController.progressPct

    QGCPalette { id: qgcPal }

    /// Bottom single pixel divider
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: "black"
        visible: qgcPal.globalTheme === QGCPalette.Light
    }

    // HHU brand block (replaces the QGC logo button): opens the 作业 / 航线 / 设置 menu
    Rectangle {
        id: qgcButton
        objectName: "toolbar_qgcLogo"
        height: parent.height
        width: brandRow.implicitWidth + ScreenTools.defaultFontPixelWidth * 2
        color: "#004B97"

        RowLayout {
            id: brandRow
            anchors.centerIn: parent
            spacing: ScreenTools.defaultFontPixelWidth * 0.8

            Image {
                source: "qrc:/hhu/hhu_logo.svg"
                sourceSize.height: _root.height * 0.8
                Layout.preferredHeight: _root.height * 0.8
                Layout.preferredWidth: Layout.preferredHeight
                fillMode: Image.PreserveAspectFit
            }
            QGCLabel {
                text: qsTr("Route planning")
                color: "white"
                font.bold: true
                font.pointSize: ScreenTools.mediumFontPointSize
            }
            QGCColoredImage {
                source: "/InstrumentValueIcons/cheveron-down.svg"
                color: "white"
                height: ScreenTools.defaultFontPixelHeight * 0.8
                width: height
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mainWindow.showToolSelectDialog()
        }
    }

    QGCFlickable {
        id: toolsFlickable
        anchors.bottomMargin: 1
        anchors.left: qgcButton.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: settingsButton.left
        contentWidth: toolIndicators.width
        flickableDirection: Flickable.HorizontalFlick

        PlanToolBarIndicators {
            id: toolIndicators
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            planMasterController: _root.planMasterController
            showRallyPointsHelp: _root.showRallyPointsHelp
            onToolbarButtonClicked: _root.toolbarButtonClicked()
        }
    }

    // Settings (需求说明 §3.1: gear at the right of the top bar)
    QGCColoredImage {
        id: settingsButton
        anchors.right: parent.right
        anchors.rightMargin: ScreenTools.defaultFontPixelWidth * 1.5
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height * 0.45
        width: height
        sourceSize.height: height
        source: "/InstrumentValueIcons/cog.svg"
        color: "#004B97"

        MouseArea {
            anchors.fill: parent
            anchors.margins: -_root.height * 0.15
            cursorShape: Qt.PointingHandCursor
            onClicked: mainWindow.showSettingsTool()
        }
    }

        // Small mission download progress bar
    Rectangle {
        id: progressBar
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: 4
        width: _controllerProgressPct * parent.width
        color: qgcPal.colorGreen
        visible: false

        onVisibleChanged: {
            if (visible) {
                largeProgressBar._userHide = false
            }
        }
    }

    // Large mission download progress bar
    Rectangle {
        id: largeProgressBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height
        color: qgcPal.window
        visible: _showLargeProgress

        property bool _userHide: false
        property bool _showLargeProgress: progressBar.visible && !_userHide && qgcPal.globalTheme === QGCPalette.Light

        Connections {
            target: QGroundControl.multiVehicleManager
            function onActiveVehicleChanged(activeVehicle) { largeProgressBar._userHide = false }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: _controllerProgressPct * parent.width
            color: qgcPal.colorGreen
        }

        QGCLabel {
            anchors.centerIn: parent
            text: qsTr("Syncing Mission")
            font.pointSize: ScreenTools.largeFontPointSize
            visible: _controllerProgressPct !== 1
        }

        QGCLabel {
            anchors.centerIn: parent
            text: qsTr("Done")
            font.pointSize: ScreenTools.largeFontPointSize
            visible: _controllerProgressPct === 1
        }

        QGCLabel {
            anchors.margins: _margin
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: qsTr("Click anywhere to hide")

            property real _margin: ScreenTools.defaultFontPixelWidth / 2
        }

        MouseArea {
            anchors.fill: parent
            onClicked: largeProgressBar._userHide = true
        }
    }

    // Progress bar
    Connections {
        target: planMasterController.missionController

        function onProgressPctChanged(progressPct) {
            if (progressPct === 1) {
                if (_root.visible) {
                    resetProgressTimer.start()
                } else {
                    progressBar.visible = false
                }
            } else if (progressPct > 0) {
                progressBar.visible = true
            }
        }
    }

    Timer {
        id: resetProgressTimer
        interval: 3000
        onTriggered: progressBar.visible = false
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.Toolbar
import HHU.Controls

// HHU override of QGroundControl/Toolbar/FlyViewToolBar.qml
// Solid blue status bar: 校徽 | 连接 | 定位 | 模式 | 电量 | 底盘 ... 消息 | 设置. Keeps the upstream interface
// (guidedValueSlider, dropMainStatusIndicatorTool, GuidedActionConfirm host).
Item {
    required property var guidedValueSlider

    id:     control
    width:  parent.width
    height: ScreenTools.toolbarHeight

    property var    _guidedController:  globals.guidedControllerFlyView
    property real   _margins:           ScreenTools.defaultFontPixelWidth

    function _vcuModeText(mode) {
        switch (mode) {
        case 0:  return qsTr("Manual")
        case 1:  return qsTr("Remote control")
        case 2:  return qsTr("Auto")
        default: return qsTr("Mode %1").arg(mode)
        }
    }

    function dropMainStatusIndicatorTool() {
        mainStatusIndicator.dropMainStatusIndicator()
    }

    HHUStatus { id: status }

    Rectangle {
        anchors.fill:   parent
        color:          "#004B97"
    }

    RowLayout {
        anchors.fill:           parent
        anchors.leftMargin:     _margins * 0.5
        anchors.rightMargin:    _margins
        spacing:                _margins

        // Brand: opens the 作业 / 航线 / 设置 menu
        Item {
            Layout.fillHeight:      true
            Layout.preferredWidth:  brandRow.implicitWidth + _margins

            RowLayout {
                id:                     brandRow
                anchors.verticalCenter: parent.verticalCenter
                spacing:                _margins * 0.8

                Image {
                    source:                 "qrc:/hhu/hhu_logo.svg"
                    sourceSize.height:      control.height * 0.8
                    Layout.preferredHeight: control.height * 0.8
                    Layout.preferredWidth:  Layout.preferredHeight
                    fillMode:               Image.PreserveAspectFit
                }
                QGCColoredImage {
                    source:             "/InstrumentValueIcons/cheveron-down.svg"
                    color:              "white"
                    height:             ScreenTools.defaultFontPixelHeight * 0.8
                    width:              height
                }
            }

            MouseArea {
                anchors.fill:   parent
                cursorShape:    Qt.PointingHandCursor
                onClicked:      mainWindow.showToolSelectDialog()
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.margins: control.height * 0.2; color: "#4D86C2" }

        // 连接: state, link kind (4G / 串口 / 局域网 / 蓝牙), latency, packet loss, 只读; opens the connection settings
        HHUChip {
            title:      status.vehicle ? (status.connected ? (status.readOnly ? qsTr("Connected, read only") : qsTr("Connected")) : qsTr("Link lost"))
                                       : (hhu4G.active && hhu4G.state !== "online" ? qsTr("4G connecting") : qsTr("Not connected"))
            detail:     status.vehicle
                        ? [ status.linkTypeText,
                            hhuLink.latencyMs >= 0 ? qsTr("%1 ms").arg(hhuLink.latencyMs) : "",
                            qsTr("Loss %1%").arg(status.vehicle.mavlinkLossPercent.toFixed(0)) ].filter(t => t !== "").join(" · ")
                        : (hhu4G.active ? hhu4G.statusText : qsTr("Tap to connect"))
            dotColor:   status.connected ? (status.readOnly ? "#F2B705" : "#2FB344") : "#E5484D"
            onClicked:  mainWindow.showSettingsTool("Comm Links")
        }

        HHUChip {
            visible:    !!status.vehicle
            title:      status.fixText
            detail:     qsTr("%1 sats · HDOP %2").arg(status.satCount).arg(isNaN(status.hdop) ? "--" : status.hdop.toFixed(1))
            dotColor:   status.fixColor
            onClicked:  mainWindow.showSettingsTool("NTRIP/RTK")
        }

        HHUChip {
            visible:    !!status.vehicle
            title:      status.modeText
            detail:     status.armed ? qsTr("Armed") : qsTr("Disarmed")
            showDot:    false
            onClicked:  mainStatusIndicator.dropMainStatusIndicator()
        }

        HHUChip {
            visible:    !!status.vehicle && !isNaN(status.batteryPct)
            title:      qsTr("Battery %1%").arg(status.batteryPct.toFixed(0))
            detail:     isNaN(status.batteryVolts) ? "" : qsTr("%1 V").arg(status.batteryVolts.toFixed(1))
            dotColor:   status.batteryPct > 30 ? "#2FB344" : (status.batteryPct > 15 ? "#F2B705" : "#E5484D")
        }

        HHUChip {
            visible:    !!status.vehicle
            title:      !status.vcuValid ? qsTr("Chassis") : (hhuVcu.fault !== 0 ? qsTr("Chassis fault") : (hhuVcu.ok ? qsTr("Chassis ready") : qsTr("Chassis not ready")))
            detail:     !status.vcuValid ? qsTr("No data") : (hhuVcu.fault !== 0 ? status.faultText : control._vcuModeText(hhuVcu.mode))
            dotColor:   !status.vcuValid ? "#9AA5B1" : (hhuVcu.fault !== 0 ? "#E5484D" : (hhuVcu.ok ? "#2FB344" : "#F2B705"))
        }

        // Center: upstream slide-to-confirm for any guided action raised elsewhere
        Item {
            Layout.fillWidth:   true
            Layout.fillHeight:  true

            GuidedActionConfirm {
                id:                         guidedActionConfirm
                height:                     parent.height
                anchors.horizontalCenter:   parent.horizontalCenter
                guidedController:           control._guidedController
                guidedValueSlider:          control.guidedValueSlider
                messageDisplay:             guidedActionMessageDisplay
            }
        }

        HHUChip {
            visible:    !!status.vehicle && status.vehicle.messageCount > 0
            title:      qsTr("Messages")
            detail:     qsTr("%1 new").arg(status.vehicle ? status.vehicle.messageCount : 0)
            dotColor:   "#F2B705"
            onClicked:  mainStatusIndicator.dropMainStatusIndicator()
        }

        QGCColoredImage {
            source:                 "/InstrumentValueIcons/cog.svg"
            color:                  "white"
            Layout.preferredHeight: control.height * 0.45
            Layout.preferredWidth:  Layout.preferredHeight
            sourceSize.height:      Layout.preferredHeight

            MouseArea {
                anchors.fill:       parent
                anchors.margins:    -control.height * 0.15
                cursorShape:        Qt.PointingHandCursor
                onClicked:          mainWindow.showSettingsTool()
            }
        }
    }

    // Upstream status popup (connection details, vehicle messages); only its drawer is used
    MainStatusIndicator {
        id:         mainStatusIndicator
        visible:    false
        height:     control.height
    }

    Rectangle {
        id:                         guidedActionMessageDisplay
        anchors.top:                control.bottom
        anchors.topMargin:          _margins
        anchors.horizontalCenter:   parent.horizontalCenter
        width:                      messageLabel.contentWidth + (_margins * 2)
        height:                     messageLabel.contentHeight + (_margins * 2)
        color:                      qgcPal.windowTransparent
        radius:                     ScreenTools.defaultBorderRadius
        visible:                    guidedActionConfirm.visible

        QGCPalette { id: qgcPal }

        QGCLabel {
            id:         messageLabel
            x:          _margins
            y:          _margins
            width:      ScreenTools.defaultFontPixelWidth * 30
            wrapMode:   Text.WordWrap
            text:       guidedActionConfirm.message
        }
    }

    ParameterDownloadProgress {
        anchors.fill: parent
    }
}

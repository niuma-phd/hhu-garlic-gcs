import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.Toolbar
import HHU.Controls

// HHU override of QGroundControl/Toolbar/FlyViewToolBar.qml
// HHU status bar (shared with the 规划 page) with the slide-to-confirm in the middle. Keeps the upstream
// interface (guidedValueSlider, dropMainStatusIndicatorTool, GuidedActionConfirm host).
Item {
    required property var guidedValueSlider

    id:     control
    width:  parent.width
    height: HHUStyle.barH

    property var    _guidedController:  globals.guidedControllerFlyView
    property real   _margins:           ScreenTools.defaultFontPixelWidth

    function dropMainStatusIndicatorTool() {
        statusBar.dropMainStatusIndicator()
    }

    HHUStatusBar {
        id:             statusBar
        anchors.fill:   parent
        page:           "work"

        // Upstream slide-to-confirm for any guided action raised elsewhere
        GuidedActionConfirm {
            id:                         guidedActionConfirm
            height:                     parent.height
            anchors.horizontalCenter:   parent.horizontalCenter
            guidedController:           control._guidedController
            guidedValueSlider:          control.guidedValueSlider
            messageDisplay:             guidedActionMessageDisplay
        }
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

        // GuidedActionConfirm fades the message out through these (as in the upstream toolbar)
        PropertyAnimation {
            id:         messageOpacityAnimation
            target:     guidedActionMessageDisplay
            property:   "opacity"
            from:       1
            to:         0
            duration:   500
        }

        Timer {
            id:             messageFadeTimer
            interval:       4000
            onTriggered:    messageOpacityAnimation.start()
        }
    }

    ParameterDownloadProgress {
        anchors.fill: parent
    }
}

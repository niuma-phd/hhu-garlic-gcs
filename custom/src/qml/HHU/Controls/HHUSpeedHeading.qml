import QtQuick
import QtQuick.Layouts

import QGroundControl

/// Speed and heading card at the top left of the 作业 page, the same while idle, on a waypoint route,
/// on an AB line or driving to a target point. Speed is the flight controller's EKF ground speed
/// (VFR_HUD), not the VCU's; heading is the nose direction, 0° = north. "—" while the link is lost.
HHUCard {
    id: root

    width:          row.implicitWidth + HHUStyle.cardPad * 2
    height:         row.implicitHeight + HHUStyle.cardPad * 1.25
    visible:        !!status.vehicle

    HHUStatus { id: status }

    readonly property real _speed:   status.connected ? status.vehicle.groundSpeed.rawValue : NaN     ///< m/s
    readonly property real _heading: status.connected ? status.vehicle.heading.rawValue : NaN         ///< deg

    function _compass(deg) {
        const names = [ qsTr("N"), qsTr("NE"), qsTr("E"), qsTr("SE"), qsTr("S"), qsTr("SW"), qsTr("W"), qsTr("NW") ]
        return names[Math.round((((deg % 360) + 360) % 360) / 45) % 8]
    }

    RowLayout {
        id:                 row
        anchors.centerIn:   parent
        spacing:            10 * HHUStyle.s

        HHUText { text: qsTr("Speed"); size: 15; color: HHUStyle.text3; Layout.alignment: Qt.AlignBaseline }
        HHUText {
            id:     speedValue
            text:   isNaN(root._speed) ? "—" : (Math.abs(root._speed) * 3.6).toFixed(1)
            number: true
            size:   24
            Layout.alignment: Qt.AlignBaseline
        }
        HHUText { text: "km/h"; size: 15; color: HHUStyle.text2; Layout.alignment: Qt.AlignBaseline }

        Rectangle {
            Layout.preferredWidth:  1
            Layout.preferredHeight: speedValue.height * 0.8
            Layout.leftMargin:      6 * HHUStyle.s
            Layout.rightMargin:     6 * HHUStyle.s
            color:                  HHUStyle.divider
        }

        HHUText { text: qsTr("Heading"); size: 15; color: HHUStyle.text3; Layout.alignment: Qt.AlignBaseline }
        HHUText {
            text:   isNaN(root._heading) ? "—" : Math.round((((root._heading % 360) + 360) % 360)) % 360 + "°"
            number: true
            size:   24
            Layout.alignment: Qt.AlignBaseline
        }
        HHUText {
            visible: !isNaN(root._heading)
            text:    root._compass(root._heading)
            size:    15
            color:   HHUStyle.text2
            Layout.alignment: Qt.AlignBaseline
        }
    }
}

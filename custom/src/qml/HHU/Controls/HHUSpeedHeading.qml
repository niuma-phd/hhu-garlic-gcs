import QtQuick
import QtQuick.Layouts

import QGroundControl

/// Speed and heading card at the top left of the 作业 page, the same while idle, on a waypoint route,
/// on an AB line or driving to a target point. Two short lines, no labels: speed (km/h) on top, below it
/// an arrow pointing the nose direction on the north-up map and the heading in degrees (0° = north).
/// Speed is the flight controller's EKF ground speed (VFR_HUD), not the VCU's. "—" while the link is lost.
HHUCard {
    id: root

    width:          column.implicitWidth + HHUStyle.cardPad * 1.5
    height:         column.implicitHeight + HHUStyle.cardPad
    visible:        !!status.vehicle

    HHUStatus { id: status }

    readonly property real _speed:   status.connected ? status.vehicle.groundSpeed.rawValue : NaN     ///< m/s
    readonly property real _heading: status.connected ? status.vehicle.heading.rawValue : NaN         ///< deg

    ColumnLayout {
        id:                 column
        anchors.centerIn:   parent
        spacing:            2 * HHUStyle.s

        Row {
            spacing: 4 * HHUStyle.s
            HHUText {
                id:     speedValue
                text:   isNaN(root._speed) ? "—" : (Math.abs(root._speed) * 3.6).toFixed(1)
                number: true
                size:   24
            }
            HHUText {
                anchors.baseline:   speedValue.baseline
                text:               "km/h"
                size:               14
                color:              HHUStyle.text2
            }
        }

        Row {
            spacing: 4 * HHUStyle.s
            // arrow.svg points east: turned by heading − 90°
            HHUIcon {
                anchors.verticalCenter: headingValue.verticalCenter
                visible:    !isNaN(root._heading)
                name:       "arrow"
                size:       20
                color:      HHUStyle.blue
                rotation:   root._heading - 90
            }
            HHUText {
                id:     headingValue
                text:   isNaN(root._heading) ? "—" : Math.round((((root._heading % 360) + 360) % 360)) % 360 + "°"
                number: true
                size:   20
            }
        }
    }
}

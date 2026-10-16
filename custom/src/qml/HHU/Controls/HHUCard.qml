import QtQuick
import QtQuick.Effects

/// White card floating on the map: solid (never transparent), rounded, drop shadow.
/// Clicks and wheel turns on the card never reach the map below: a click on blank card space or on a
/// disabled button used to add a waypoint hidden under the 规划 panel (issue #6).
Rectangle {
    color:  "white"
    radius: HHUStyle.radiusCard

    // first child: below everything the card holds
    MouseArea {
        anchors.fill:       parent
        acceptedButtons:    Qt.AllButtons
        onWheel:            (wheel) => wheel.accepted = true
    }

    layer.enabled: visible
    layer.effect: MultiEffect {
        shadowEnabled:          true
        shadowColor:            HHUStyle.shadow
        shadowBlur:             0.6
        shadowVerticalOffset:   4
        shadowHorizontalOffset: 0
    }
}

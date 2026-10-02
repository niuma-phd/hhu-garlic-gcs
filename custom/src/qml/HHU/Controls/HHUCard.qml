import QtQuick
import QtQuick.Effects

/// White card floating on the map: solid (never transparent), rounded, drop shadow.
Rectangle {
    color:  "white"
    radius: HHUStyle.radiusCard

    layer.enabled: visible
    layer.effect: MultiEffect {
        shadowEnabled:          true
        shadowColor:            HHUStyle.shadow
        shadowBlur:             0.6
        shadowVerticalOffset:   4
        shadowHorizontalOffset: 0
    }
}

import QtQuick
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import HHU.Controls

/// HHU override of QGroundControl/FlightMap/MapItems/VehicleMapItem.qml (设计稿 3):
/// top view of the seeder, nose = heading. While the link is lost the vehicle turns grey with a red
/// dashed ring (its last known position).
MapQuickItem {
    id: _root

    property var    vehicle                                                         /// Vehicle object
    property var    map
    property double heading:        vehicle ? vehicle.heading.value : Number.NaN    ///< Vehicle heading, NAN for none
    property real   size:           ScreenTools.defaultFontPixelHeight * 3          /// Default size for icon, most usage overrides this

    anchorPoint.x:  vehicleItem.width  / 2
    anchorPoint.y:  vehicleItem.height / 2
    visible:        coordinate.isValid

    property var    _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool   _lost:          vehicle === _activeVehicle && hhuLink.linkLost
    readonly property real _iconHeight: 46 * HHUStyle.s

    sourceItem: Item {
        id:         vehicleItem
        width:      _root._iconHeight * 1.5
        height:     width
        opacity:    _root.vehicle === _root._activeVehicle ? 1.0 : 0.5

        // last position ring
        Canvas {
            anchors.fill:   parent
            visible:        _root._lost
            onVisibleChanged: requestPaint()
            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.strokeStyle = HHUStyle.red
                c.lineWidth = 3
                c.setLineDash([6, 5])
                c.beginPath()
                c.arc(width / 2, height / 2, width / 2 - 3, 0, Math.PI * 2)
                c.stroke()
            }
        }

        Image {
            id:                 vehicleIcon
            anchors.centerIn:   parent
            source:             _root._lost ? "qrc:/hhu/vehicle_top_lost.svg" : "qrc:/hhu/vehicle_top.svg"
            mipmap:             true
            height:             _root._iconHeight
            sourceSize.height:  height * 2
            fillMode:           Image.PreserveAspectFit
            transform: Rotation {
                origin.x:       vehicleIcon.width  / 2
                origin.y:       vehicleIcon.height / 2
                angle:          isNaN(_root.heading) ? 0 : _root.heading
            }
        }
    }
}

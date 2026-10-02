import QtQuick
import QtLocation
import QtPositioning

import QGroundControl

/// HHU override of QGroundControl/FlightMap/MapItems/MissionLineView.qml (设计稿 3):
/// route legs as a white line with a dark outline, readable on the satellite map.
MapItemView {
    property bool showSpecialVisual: false

    delegate: MapItemGroup {
        id: leg

        property var  _path: {
            if (!object || !object.coordinate1.isValid || !object.coordinate2.isValid) {
                return []
            }
            return [ object.coordinate1, object.coordinate2 ]
        }

        MapPolyline {
            line.width: 7
            line.color: "#B314202E"
            z:          QGroundControl.zOrderWaypointLines
            path:       leg._path
        }
        MapPolyline {
            line.width: 3
            line.color: "white"   // no terrain check for a ground vehicle
            z:          QGroundControl.zOrderWaypointLines
            path:       leg._path
        }
    }
}

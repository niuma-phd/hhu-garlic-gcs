pragma Singleton
import QtQuick

/// UI state shared between the 作业 page parts (map, progress card, work buttons).
QtObject {
    /// The 规划 page is shown (waypoint labels: selected item there, vehicle's current item on 作业)
    property bool planPage:     false
    /// 开到指定点: target the vehicle was sent to (invalid when none) and the distance at that moment
    property var  gotoTarget:   null
    property real gotoStartDist: 0
}

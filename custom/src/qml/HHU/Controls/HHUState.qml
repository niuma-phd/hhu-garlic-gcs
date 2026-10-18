pragma Singleton
import QtQuick

import QGroundControl

/// UI state shared between the 作业 page parts (map, progress card, work buttons).
QtObject {
    /// The 规划 page is shown (waypoint labels: selected item there, vehicle's current item on 作业)
    property bool planPage:     false
    /// 开到指定点: target the vehicle was sent to (invalid when none) and the distance at that moment
    property var  gotoTarget:   null
    property real gotoStartDist: 0

    /// 规划 page: a waypoint was right clicked / long pressed (HHUPlanPanel shows the delete card)
    signal waypointMenuRequested(var missionItem)
    function requestWaypointMenu(missionItem) {
        // waypoints only: not the planned home (sequence 0) or other items
        if (planPage && missionItem && missionItem.sequenceNumber > 0
                && missionItem.specifiesCoordinate && !missionItem.isStandaloneCoordinate) {
            waypointMenuRequested(missionItem)
        }
    }

    // ---- 航点序号 ↔ 任务序号 (issue #6 D12) ------------------------------------------------------
    // The customer counts waypoints 1, 2, 3 … in route order. The vehicle counts mission items: a
    // speed set for the route puts DO_CHANGE_SPEED at sequence 1, so the first waypoint is item 2.
    // Shown numbers use the waypoint number; commands to the vehicle keep the mission sequence.
    // Waypoints are the visual items the route line goes through (as in the progress card).

    /// Mission sequence numbers of the waypoints, in route order
    function waypointSeqs(missionController) {
        let seqs = []
        const items = missionController ? missionController.visualItems : null
        if (items) {
            for (let i = 1; i < items.count; i++) {
                const item = items.get(i)
                if (item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                    seqs.push(item.sequenceNumber)
                }
            }
        }
        return seqs
    }

    /// Waypoint number (1-based) of a mission sequence number; a sequence number between waypoints
    /// (e.g. the speed command) gives the waypoint after it. 0 when no waypoint is at or after it.
    function waypointNumber(missionController, seq) {
        const items = missionController ? missionController.visualItems : null
        if (!items) return 0
        let number = 0
        for (let i = 1; i < items.count; i++) {
            const item = items.get(i)
            if (item.specifiesCoordinate && !item.isStandaloneCoordinate) {
                number++
                if (item.sequenceNumber >= seq) return number
            }
        }
        return 0
    }

    // ---- One vehicle at a time (issue #6) --------------------------------------------------
    // Our vehicles all use system id 1: two links at once feed the same QGC vehicle with the data of
    // two vehicles. So a new connection first asks to disconnect the one in use
    // (mainWindow.hhuConnectExclusive).

    /// Names of the connections in use (4G and radio / LAN links). A 4G connection that never reached
    /// the vehicle (vehicle offline, retrying) is not in use: a new connection just stops it (disconnectAll).
    function connectionsInUse() {
        let names = []
        let bridgeUp = false    // the 4G bridge link, made once the vehicle was reached
        const configs = QGroundControl.linkManager.linkConfigurations
        for (let i = 0; i < configs.count; i++) {
            const config = configs.get(i)
            if (!config.link) continue
            if (hhu4G.active && config.dynamic && config.name.startsWith("4G ")) {
                bridgeUp = true
                continue
            }
            names.push(config.name)
        }
        if (hhu4G.active && (hhu4G.state === "online" || bridgeUp)) {
            const c = hhu4G.configs[hhu4G.activeIndex]
            names.unshift(c ? c.name : "4G")
        }
        return names
    }

    function disconnectAll() {
        if (hhu4G.active) {
            hhu4G.disconnectLink()
        }
        const configs = QGroundControl.linkManager.linkConfigurations
        for (let i = configs.count - 1; i >= 0; i--) {
            const config = configs.get(i)
            if (config.link) {
                QGroundControl.linkManager.disconnectLinkConfiguration(config)
            }
        }
    }

    // ---- Map names shown to the customer (issue #6) ------------------------------------------
    // QGC lists map providers / types / elevation sources and tile sets by their internal English
    // names, which are also the saved setting values: only the shown text is translated.

    function mapNameText(name) {
        switch (name) {
        case "TianDiTu":            return qsTr("TianDiTu")
        case "Bing":                return qsTr("Bing")
        case "Google":              return qsTr("Google")
        case "Esri":                return qsTr("Esri")
        case "Satellite":           return qsTr("Satellite")
        case "Road":                return qsTr("Road map")
        case "Street":              return qsTr("Street map")
        case "Street Map":          return qsTr("Street map")
        case "Hybrid":              return qsTr("Hybrid")
        case "Terrain":             return qsTr("Terrain")
        case "Copernicus":          return qsTr("Copernicus elevation")
        case "Default Tile Set":    return qsTr("Default tile set")
        default:                    return name
        }
    }

    function mapNameList(names) {
        return names.map(n => mapNameText(n))
    }
}

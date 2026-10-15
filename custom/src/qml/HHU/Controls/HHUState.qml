pragma Singleton
import QtQuick
import QtQuick.Dialogs

import QGroundControl

/// UI state shared between the 作业 page parts (map, progress card, work buttons).
QtObject {
    /// The 规划 page is shown (waypoint labels: selected item there, vehicle's current item on 作业)
    property bool planPage:     false
    /// 开到指定点: target the vehicle was sent to (invalid when none) and the distance at that moment
    property var  gotoTarget:   null
    property real gotoStartDist: 0

    // ---- One vehicle at a time (issue #6) --------------------------------------------------
    // Our vehicles all use system id 1: two links at once feed the same QGC vehicle with the data of
    // two vehicles. So a new connection first asks to disconnect the one in use.

    /// Names of the connections in use (4G and radio / LAN links)
    function connectionsInUse() {
        let names = []
        if (hhu4G.active) {
            const c = hhu4G.configs[hhu4G.activeIndex]
            names.push(c ? c.name : "4G")
        }
        const configs = QGroundControl.linkManager.linkConfigurations
        for (let i = 0; i < configs.count; i++) {
            const config = configs.get(i)
            if (!config.link) continue
            if (hhu4G.active && config.dynamic && config.name.startsWith("4G ")) continue   // the 4G bridge
            names.push(config.name)
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

    /// Runs connectFunction for the connection `name`; when another one is in use, after asking to drop it
    function connectExclusive(owner, name, connectFunction) {
        const inUse = connectionsInUse()
        if (inUse.length === 0) {
            connectFunction()
            return
        }
        QGroundControl.showMessageDialog(owner, qsTr("Switch connection"),
                                         qsTr("Connected to %1. Only one vehicle can be connected at a time. Disconnect it and connect to %2?")
                                             .arg(inUse.join(qsTr(", "))).arg(name),
                                         Dialog.Ok | Dialog.Cancel,
                                         function() {
                                             disconnectAll()
                                             connectFunction()
                                         })
    }
}

import QtQuick

import QGroundControl

/// Derived vehicle state shared by the HHU toolbar, work panel and alarms.
/// Customer wording per 需求说明 V1.0 §2.2 / §3.1.
QtObject {
    id: root

    readonly property var   vehicle:        QGroundControl.multiVehicleManager.activeVehicle
    /// Link lost after hhuSettings.linkLostSec without vehicle data (高级设置 连接中断判定时间;
    /// QGC's own heartbeat timeout is fixed and not used for the customer display)
    readonly property bool  linkLost:       !!vehicle && hhuLink.linkLost
    readonly property bool  connected:      !!vehicle && !linkLost
    /// 4G connection with read-only access (another GCS controls the vehicle): no control, no upload
    readonly property bool  readOnly:       !!vehicle && hhuLink.linkType === "4g" && hhu4G.readOnly
    /// Connected with control rights
    readonly property bool  canControl:     connected && !readOnly
    readonly property bool  armed:          !!vehicle && vehicle.armed
    readonly property string flightMode:    vehicle ? vehicle.flightMode : ""

    readonly property bool  inAuto:         !!vehicle && flightMode === vehicle.missionFlightMode
    readonly property bool  inPause:        !!vehicle && flightMode === vehicle.pauseFlightMode
    readonly property bool  inReturn:       !!vehicle && (flightMode === vehicle.rtlFlightMode || flightMode === vehicle.smartRTLFlightMode)
    readonly property bool  inGuided:       !!vehicle && flightMode === vehicle.gotoFlightMode
    /// The route was driven to its end; the vehicle waits there (Rover holds in AUTO) until 停车上锁 / 返回
    readonly property bool  routeDone:      !!vehicle && armed && hhuWork.completed && !inReturn && !inGuided

    /// Link kind shown in the status bar: 4G / 串口 / 局域网 / 蓝牙
    readonly property string linkTypeText: {
        switch (hhuLink.linkType) {
        case "4g":          return "4G"
        case "serial":      return qsTr("Serial")
        case "udp":
        case "tcp":         return qsTr("LAN")
        case "bluetooth":   return qsTr("Bluetooth")
        default:            return ""
        }
    }

    // GPS_FIX_TYPE: 5 = RTK float, 6 = RTK fixed
    readonly property int   fixType:        vehicle ? vehicle.gps.lock.rawValue : 0
    readonly property int   satCount:       vehicle ? vehicle.gps.count.rawValue : 0
    readonly property real  hdop:           vehicle ? vehicle.gps.hdop.rawValue : NaN
    readonly property bool  rtkFixed:       fixType >= 6
    readonly property bool  rtkFloat:       fixType === 5

    // Chassis battery (VCU_SOC / VCU_BATV from vcu_can.lua) when fresh, otherwise the autopilot battery
    readonly property bool  vcuValid:       !!vehicle && hhuVcu.valid
    readonly property var   battery:        vehicle && vehicle.batteries.count > 0 ? vehicle.batteries.get(0) : null
    readonly property real  batteryPct:     vcuValid && !isNaN(hhuVcu.soc) ? hhuVcu.soc : (battery ? battery.percentRemaining.rawValue : NaN)
    readonly property real  batteryVolts:   vcuValid && !isNaN(hhuVcu.batV) ? hhuVcu.batV : (battery ? battery.voltage.rawValue : NaN)

    /// "0x1A 电机过流" style text for the current VCU fault ("" when there is no fault)
    readonly property string faultText: {
        if (!vcuValid || hhuVcu.fault === 0) return ""
        const desc = hhuConfig.faultText(hhuVcu.fault)
        return "0x" + hhuVcu.fault.toString(16).toUpperCase() + (desc !== "" ? " " + desc : "")
    }

    readonly property string modeText: {
        if (!vehicle)   return qsTr("Offline")
        if (!armed)     return qsTr("Standby")
        if (routeDone)  return qsTr("Done")
        if (inAuto)     return qsTr("Working")
        if (inPause)    return qsTr("Paused")
        if (inReturn)   return qsTr("Returning")
        if (inGuided)   return qsTr("Going to target")
        return qsTr("Manual")
    }

    readonly property string fixText: {
        if (!vehicle)       return qsTr("No position")
        if (rtkFixed)       return qsTr("RTK fixed")
        if (rtkFloat)       return qsTr("RTK float")
        if (fixType >= 3)   return qsTr("Single point")
        return qsTr("No fix")
    }

    readonly property color fixColor: rtkFixed ? "#2FB344" : (rtkFloat ? "#F2B705" : "#E5484D")

    // Panel look shared by the HHU cards: 户外高对比度 makes them opaque with heavier borders
    readonly property color panelColor:     hhuSettings.highContrast ? "#FFFFFF" : "#E6FFFFFF"
    readonly property real  panelBorder:    hhuSettings.highContrast ? 3 : 1
    readonly property color labelColor:     hhuSettings.highContrast ? "#000000" : "#5B6B7F"
}

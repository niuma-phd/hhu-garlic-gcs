import QtQuick
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import HHU.AB

/// 直线测试 on the 作业 page (engineeringTuning only, hhuStraight): the start dialog (距离 / 车速 / 往返),
/// the live card while the vehicle drives (横向偏差 big, 航向偏差, 车速, 已走 / 剩余, deviation curve over
/// the distance), the result dialog after each run (per leg, compared with the run before and the
/// parameters changed since) and the test line on the map. The run itself is HHUStraightTest (C++).
HHUCard {
    id: root

    property var mapControl

    readonly property bool  _have:      typeof hhuStraight !== "undefined" && !!hhuStraight
    readonly property bool  _active:    _have && hhuStraight.active

    width:      HHUStyle.cardW * 1.15
    height:     cardColumn.implicitHeight + HHUStyle.cardPad * 2
    visible:    _active

    HHUStatus { id: status }

    /// Opens the start dialog (map tools button 直线)
    function openStart() {
        if (!_have) {
            return
        }
        const blockers = status.driveBlockers()
        if (!status.canControl) {
            messageDialog.show(qsTr("Straight line test"), qsTr("Not connected or read-only connection"))
        } else if (status.armed) {
            messageDialog.show(qsTr("Straight line test"), qsTr("Stop and lock the vehicle first"))
        } else if (blockers.length > 0) {
            messageDialog.show(qsTr("Cannot start"), blockers.join("\n"))
        } else {
            startDialog.open()
        }
    }

    function _side(v) {
        return isNaN(v) ? "—" : (Math.abs(v) < 0.005 ? "0.00 m" : (v > 0 ? qsTr("L") : qsTr("R")) + " " + Math.abs(v).toFixed(2) + " m")
    }
    function _xtrackColor(v) {
        const a = Math.abs(v)
        return isNaN(v) ? HHUStyle.text : (a > 0.5 ? HHUStyle.red : (a > 0.2 ? HHUStyle.yellowText : HHUStyle.green))
    }
    function _f(v, d, unit) {
        return (v === undefined || isNaN(v)) ? "—" : Number(v).toFixed(d) + (unit || "")
    }

    // ---- Start dialog ------------------------------------------------------------------------------

    property real _distance:    30
    property int  _speedKind:   0       ///< 0 作业, 1 运输, 2 自定义
    property real _customKmh:   3
    property bool _roundTrip:   false
    readonly property real _speedMps: _speedKind === 0 ? hhuConfig.abSpeedWork : (_speedKind === 1 ? hhuConfig.abSpeedTransport : _customKmh / 3.6)

    HHUDialog {
        id:             startDialog
        title:          qsTr("Straight line test")
        subtitle:       qsTr("The vehicle drives straight ahead along its current heading.")
        dialogWidth:    560

        GridLayout {
            Layout.fillWidth:   true
            columns:            2
            columnSpacing:      16 * HHUStyle.s
            rowSpacing:         14 * HHUStyle.s

            HHUText { text: qsTr("Distance"); size: 17; color: HHUStyle.text2 }
            HHUStepper {
                value:      root._distance
                from:       5
                to:         200
                step:       5
                unit:       "m"
                onEdited:   (v) => root._distance = v
            }

            HHUText { text: qsTr("Speed"); size: 17; color: HHUStyle.text2; Layout.alignment: Qt.AlignTop; Layout.topMargin: 10 * HHUStyle.s }
            ColumnLayout {
                spacing: 8 * HHUStyle.s
                RowLayout {
                    spacing: 8 * HHUStyle.s
                    Repeater {
                        model: [ qsTr("Work %1 km/h").arg((hhuConfig.abSpeedWork * 3.6).toFixed(1)),
                                 qsTr("Transport %1 km/h").arg((hhuConfig.abSpeedTransport * 3.6).toFixed(1)),
                                 qsTr("Custom") ]
                        HHUButton {
                            text:       modelData
                            kind:       root._speedKind === index ? "blue" : "plain"
                            size:       15
                            h:          44 * HHUStyle.s
                            onClicked:  root._speedKind = index
                        }
                    }
                }
                HHUStepper {
                    visible:    root._speedKind === 2
                    value:      root._customKmh
                    from:       0.5
                    to:         10
                    step:       0.5
                    decimals:   1
                    unit:       "km/h"
                    onEdited:   (v) => root._customKmh = v
                }
            }

            HHUText { text: qsTr("Round trip"); size: 17; color: HHUStyle.text2 }
            RowLayout {
                spacing: 8 * HHUStyle.s
                HHUButton { text: qsTr("One way"); kind: !root._roundTrip ? "blue" : "plain"; size: 15; h: 44 * HHUStyle.s; onClicked: root._roundTrip = false }
                HHUButton { text: qsTr("There and back"); kind: root._roundTrip ? "blue" : "plain"; size: 15; h: 44 * HHUStyle.s; onClicked: root._roundTrip = true }
            }
        }
        HHUText {
            Layout.fillWidth:   true
            text:               qsTr("Make sure the way ahead is free for %1 m%2. Emergency stop works at any time.")
                                    .arg(root._distance.toFixed(0)).arg(root._roundTrip ? qsTr(" and room to turn at the end") : "")
            size:               15
            color:              HHUStyle.text3
            wrapMode:           Text.WordWrap
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Cancel"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: startDialog.close() },
            HHUButton {
                text: qsTr("Start"); icon: "play"; kind: "green"; size: 18; h: 56 * HHUStyle.s; minWidth: 140
                onClicked: {
                    startDialog.close()
                    const blockers = status.driveBlockers()
                    if (blockers.length > 0) {
                        messageDialog.show(qsTr("Cannot start"), blockers.join("\n"))
                        return
                    }
                    const error = hhuStraight.start(root._distance, root._speedMps, root._roundTrip)
                    if (error !== "") {
                        messageDialog.show(qsTr("Cannot start"), error)
                    }
                }
            }
        ]
    }

    HHUDialog {
        id: messageDialog
        function show(t, m) { title = t; messageText.text = m; open() }
        HHUText { id: messageText; Layout.fillWidth: true; size: 17; color: HHUStyle.text2; wrapMode: Text.WordWrap }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Close"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: messageDialog.close() }
        ]
    }

    // ---- Live card ---------------------------------------------------------------------------------

    ColumnLayout {
        id:                 cardColumn
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.margins:    HHUStyle.cardPad
        spacing:            6 * HHUStyle.s

        RowLayout {
            Layout.fillWidth: true
            HHUText {
                Layout.fillWidth:   true
                text:   !root._have ? "" : hhuStraight.phase === HHUStraightTest.Starting ? qsTr("Straight line test · starting")
                        : hhuStraight.phase === HHUStraightTest.Stopping ? qsTr("Straight line test · stopping")
                        : (hhuStraight.roundTrip ? qsTr("Straight line test · leg %1 / 2").arg(hhuStraight.leg) : qsTr("Straight line test"))
                size:   15
                color:  HHUStyle.text3
                elide:  Text.ElideRight
            }
            HHUText {
                text:   root._have ? (root._f(hhuStraight.speedSet * 3.6, 1) + " km/h") : ""
                size:   15
                color:  HHUStyle.text3
            }
        }

        RowLayout {
            Layout.fillWidth: true
            HHUText { text: qsTr("Cross-track"); size: 16; color: HHUStyle.text2; Layout.alignment: Qt.AlignBaseline }
            Item { Layout.fillWidth: true }
            HHUText {
                text:   root._have ? root._side(hhuStraight.xtrack) : "—"
                number: true
                size:   34
                bold:   true
                color:  root._have ? root._xtrackColor(hhuStraight.xtrack) : HHUStyle.text
                Layout.alignment: Qt.AlignBaseline
            }
        }

        GridLayout {
            Layout.fillWidth:   true
            columns:            4
            columnSpacing:      8 * HHUStyle.s
            rowSpacing:         2 * HHUStyle.s
            HHUText { text: qsTr("Heading"); size: 14; color: HHUStyle.text3 }
            HHUText { text: root._have ? root._f(hhuStraight.headingErr, 1, "°") : "—"; number: true; size: 17; Layout.fillWidth: true }
            HHUText { text: qsTr("Speed"); size: 14; color: HHUStyle.text3 }
            HHUText { text: root._have ? root._f(hhuStraight.speed * 3.6, 1, " km/h") : "—"; number: true; size: 17; Layout.fillWidth: true }
            HHUText { text: qsTr("Driven"); size: 14; color: HHUStyle.text3 }
            HHUText { text: root._have ? root._f(Math.max(0, hhuStraight.along), 1, " m") : "—"; number: true; size: 17 }
            HHUText { text: qsTr("Left"); size: 14; color: HHUStyle.text3 }
            HHUText { text: root._have && !isNaN(hhuStraight.along) ? Math.max(0, hhuStraight.length - hhuStraight.along).toFixed(1) + " m" : "—"; number: true; size: 17 }
        }

        // cross-track over the distance: 0 line in the middle, + (left) up
        Canvas {
            id:                     chart
            Layout.fillWidth:       true
            Layout.preferredHeight: 80 * HHUStyle.s
            readonly property var points: root._have ? hhuStraight.chart : []
            onPointsChanged: requestPaint()
            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.fillStyle = HHUStyle.grey2
                c.fillRect(0, 0, width, height)
                const len = root._have ? Math.max(1, hhuStraight.length) : 1
                let ymax = 0.3
                for (let i = 0; i < points.length; i++) ymax = Math.max(ymax, Math.abs(points[i].x))
                ymax = Math.ceil(ymax * 10) / 10
                const mid = height / 2
                const ys = (height / 2 - 6) / ymax
                // ±0.2 m band
                c.fillStyle = "#1A2FB344"
                c.fillRect(0, mid - 0.2 * ys, width, 0.4 * ys)
                c.strokeStyle = HHUStyle.text3
                c.lineWidth = 1
                c.beginPath(); c.moveTo(0, mid); c.lineTo(width, mid); c.stroke()
                c.fillStyle = HHUStyle.text3
                c.font = Math.round(12 * HHUStyle.s) + "px sans-serif"
                c.fillText("+" + ymax.toFixed(1) + " m " + qsTr("L"), 4, 14)
                c.fillText("-" + ymax.toFixed(1) + " m " + qsTr("R"), 4, height - 4)
                if (points.length < 2) return
                c.strokeStyle = HHUStyle.blue
                c.lineWidth = 2
                c.beginPath()
                for (let j = 0; j < points.length; j++) {
                    const x = Math.max(0, Math.min(width, points[j].s / len * width))
                    const y = mid - points[j].x * ys
                    if (j === 0) c.moveTo(x, y); else c.lineTo(x, y)
                }
                c.stroke()
            }
        }

        HHUButton {
            Layout.fillWidth:   true
            text:               qsTr("Stop test")
            icon:               "close"
            kind:               "outline"
            size:               16
            h:                  48 * HHUStyle.s
            onClicked:          hhuStraight.stop()
        }
    }

    // ---- Result dialog -----------------------------------------------------------------------------

    Connections {
        target:     root._have ? hhuStraight : null
        function onFinished() { resultDialog.open() }
    }

    function _prevLeg(leg) {
        const prev = hhuStraight.previous
        for (let i = 0; i < prev.length; i++) {
            if (prev[i].leg === leg) return prev[i]
        }
        return null
    }
    /// "0.08 m（上一趟 0.12 ↓）": lower is better for these
    function _cmp(v, p, d, unit) {
        let t = _f(v, d, unit)
        if (p !== null && p !== undefined && !isNaN(p) && !isNaN(v)) {
            t += "  (" + Number(p).toFixed(d) + (Math.abs(v) < Math.abs(p) ? " ↓" : (Math.abs(v) > Math.abs(p) ? " ↑" : "")) + ")"
        }
        return t
    }
    /// where the vehicle stopped: "+0.30 m past" / "1.04 m short"
    function _stop(v) {
        return (v === undefined || isNaN(v)) ? "—" : (v >= 0 ? qsTr("%1 m past").arg(v.toFixed(2)) : qsTr("%1 m short").arg((-v).toFixed(2)))
    }

    HHUDialog {
        id:             resultDialog
        title:          qsTr("Straight line test result")
        subtitle:       root._have && hhuStraight.message !== "" ? qsTr("Stopped early: %1").arg(hhuStraight.message) : ""
        dialogWidth:    760

        // metrics × legs; "(上一趟 …)" under each value when there is a run before
        GridLayout {
            id:             resultGrid
            Layout.fillWidth: true
            readonly property var legs: root._have ? hhuStraight.results : []
            readonly property var rows: [
                { t: qsTr("Steady part RMS"),       k: "steadyRms",  d: 3, u: " m", cmp: true },
                { t: qsTr("Max cross-track"),       k: "max",        d: 3, u: " m", cmp: true },
                { t: qsTr("Bias"),                  k: "bias",       side: true },
                { t: qsTr("Crossings (weaving)"),   k: "crossings",  d: 0, u: "" },
                { t: qsTr("Heading RMS"),           k: "headingRms", d: 2, u: "°", cmp: true },
                { t: qsTr("Mean speed"),            k: "speedMean",  d: 2, u: " km/h", kmh: true },
                { t: qsTr("Stop at the end"),       k: "overshoot",  stop: true }
            ]
            columns:        1 + legs.length
            columnSpacing:  24 * HHUStyle.s
            rowSpacing:     3 * HHUStyle.s

            Item { width: 1; height: 1 }
            Repeater {
                model: resultGrid.legs
                HHUText {
                    text:   (modelData.leg === 1 ? qsTr("Leg 1 (there)") : qsTr("Leg 2 (back)")) + (modelData.aborted ? " · " + qsTr("aborted") : "")
                    size:   16
                    bold:   true
                }
            }
            Repeater {
                model: resultGrid.rows.length * (1 + resultGrid.legs.length)
                HHUText {
                    readonly property int  row: Math.floor(index / (1 + resultGrid.legs.length))
                    readonly property int  col: index % (1 + resultGrid.legs.length)
                    readonly property var  m:   resultGrid.rows[row]
                    readonly property var  r:   col > 0 ? resultGrid.legs[col - 1] : null
                    readonly property var  p:   col > 0 ? root._prevLeg(r.leg) : null
                    size:   col === 0 ? 15 : 16
                    color:  col === 0 ? HHUStyle.text3 : HHUStyle.text
                    number: col > 0
                    text: {
                        if (col === 0) return m.t
                        const v = r[m.k]
                        if (m.side) return root._side(v) + (p ? "  (" + root._side(p[m.k]) + ")" : "")
                        if (m.stop) return root._stop(v) + (p ? "  (" + root._stop(p[m.k]) + ")" : "")
                        if (m.kmh) return root._f(v * 3.6, 1, m.u) + " / " + root._f(r.speedSet * 3.6, 1, "")
                        if (m.k === "crossings") return (v < 0 ? "—" : String(v)) + (p && !isNaN(p[m.k]) ? "  (" + p[m.k] + ")" : "")
                        return root._cmp(v, p ? p[m.k] : null, m.d, m.u)
                    }
                }
            }
        }
        HHUText {
            Layout.fillWidth:   true
            visible:            root._have && hhuStraight.previous.length > 0
            text:               qsTr("In brackets: the run before.")
            size:               13
            color:              HHUStyle.text3
        }
        HHUText {
            Layout.fillWidth:   true
            visible:            root._have && hhuStraight.previous.length > 0
            text:               !root._have ? "" : hhuStraight.changedParams.length > 0
                                    ? qsTr("Changed since the run before: %1").arg(hhuStraight.changedParams.join(", "))
                                    : qsTr("No tuning list parameter changed since the run before.")
            size:               15
            color:              HHUStyle.text2
            wrapMode:           Text.WordWrap
        }
        HHUText {
            Layout.fillWidth:   true
            text:               root._have ? qsTr("Saved in %1").arg(hhuStraight.folder) : ""
            size:               13
            color:              HHUStyle.text3
            wrapMode:           Text.WrapAnywhere
        }
        footerItems: [
            HHUButton { text: qsTr("Open folder"); kind: "plain"; size: 16; h: 56 * HHUStyle.s; onClicked: hhuStraight.openFolder() },
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Close"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: resultDialog.close() },
            HHUButton { text: qsTr("Run again"); icon: "play"; kind: "blue"; size: 18; h: 56 * HHUStyle.s; minWidth: 140
                        onClicked: { resultDialog.close(); root.openStart() } }
        ]
    }

    // ---- Test line on the map ----------------------------------------------------------------------

    MapPolyline {
        id:         testLine
        visible:    root._active
        line.width: 3
        line.color: HHUStyle.blue
        path:       root._have ? [ hhuStraight.lineStart, hhuStraight.lineEnd ] : []
        z:          QGroundControl.zOrderMapItems + 2
    }

    Component.onCompleted: {
        if (mapControl) {
            mapControl.addMapItem(testLine)
        }
    }
}

import QtQuick
import QtQuick.Shapes

import QGroundControl

/// AB lines of the open field (hhuAB) drawn over a map, the same on the 规划 and 作业 pages:
/// 未走 grey dashed + number, current blue thick + arrow, 完成 green solid, 跳过 grey thin + number
/// struck through. Every line has a small arrow in its driving direction.
/// Drawn in screen coordinates (QtLocation map lines cannot be dashed) and redrawn when the map moves.
Item {
    id: root

    property var map                ///< the map this lies on (parent)
    property int current: -1        ///< 0-based line drawn as current

    anchors.fill:   parent
    z:              QGroundControl.zOrderWaypointLines - 1

    readonly property color _grey:  "#5B6B7F"
    readonly property color _blue:  HHUStyle.blue
    readonly property color _green: HHUStyle.green

    property int _rev: 0
    function _redraw() { _rev++ }
    Connections {
        target: root.map
        function onCenterChanged()      { root._redraw() }
        function onZoomLevelChanged()   { root._redraw() }
        function onBearingChanged()     { root._redraw() }
        function onTiltChanged()        { root._redraw() }
        function onWidthChanged()       { root._redraw() }
        function onHeightChanged()      { root._redraw() }
    }

    /// Screen geometry of all lines, by kind
    readonly property var _geo: {
        const rev = _rev
        let out = { pending: [], done: [], skipped: [], current: [], arrows: [], currentArrows: [], labels: [] }
        if (!map || !visible) {
            return out
        }
        const lines = hhuAB.lines
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i]
            const p1 = map.fromCoordinate(l.start, false)
            const p2 = map.fromCoordinate(l.end, false)
            if (isNaN(p1.x) || isNaN(p2.x)) {
                continue
            }
            const seg = [ p1, p2 ]
            const isCurrent = i === current
            if (isCurrent) {
                out.current.push(seg)
            } else if (l.status === 1) {
                out.done.push(seg)
            } else if (l.status === 2) {
                out.skipped.push(seg)
            } else {
                out.pending.push(seg)
            }
            const dx = p2.x - p1.x, dy = p2.y - p1.y
            const len = Math.sqrt(dx * dx + dy * dy)
            if (len < 1) {
                continue
            }
            const ux = dx / len, uy = dy / len
            // arrow (chevron) in the middle, pointing along the driving direction
            const size = (isCurrent ? 16 : 9) * HHUStyle.s
            if (len > size * 3) {
                const mx = p1.x + dx / 2, my = p1.y + dy / 2
                const tip = Qt.point(mx + ux * size / 2, my + uy * size / 2)
                const bx = mx - ux * size / 2, by = my - uy * size / 2
                const chevron = [ Qt.point(bx - uy * size / 2, by + ux * size / 2), tip, Qt.point(bx + uy * size / 2, by - ux * size / 2) ]
                if (isCurrent) {
                    out.currentArrows.push(chevron)
                } else {
                    out.arrows.push(chevron)
                }
            }
            // number before the start
            const off = 16 * HHUStyle.s
            out.labels.push({ n: l.n, x: p1.x - ux * off, y: p1.y - uy * off, status: l.status, current: isCurrent })
        }
        return out
    }

    Shape {
        anchors.fill:   parent
        layer.enabled:  true
        layer.samples:  4

        ShapePath {
            strokeColor:    root._grey
            strokeWidth:    2
            fillColor:      "transparent"
            strokeStyle:    ShapePath.DashLine
            dashPattern:    [ 4, 3 ]
            capStyle:       ShapePath.FlatCap
            PathMultiline { paths: root._geo.pending }
        }
        ShapePath {
            strokeColor:    "#998995A3"
            strokeWidth:    1
            fillColor:      "transparent"
            PathMultiline { paths: root._geo.skipped }
        }
        ShapePath {
            strokeColor:    root._green
            strokeWidth:    3
            fillColor:      "transparent"
            PathMultiline { paths: root._geo.done }
        }
        ShapePath {
            strokeColor:    root._grey
            strokeWidth:    2
            fillColor:      "transparent"
            joinStyle:      ShapePath.MiterJoin
            PathMultiline { paths: root._geo.arrows }
        }
        ShapePath {
            strokeColor:    root._blue
            strokeWidth:    6
            fillColor:      "transparent"
            capStyle:       ShapePath.RoundCap
            PathMultiline { paths: root._geo.current }
        }
        ShapePath {
            strokeColor:    "white"
            strokeWidth:    3
            fillColor:      "transparent"
            joinStyle:      ShapePath.MiterJoin
            PathMultiline { paths: root._geo.currentArrows }
        }
    }

    Repeater {
        model: root._geo.labels
        Rectangle {
            x:              modelData.x - width / 2
            y:              modelData.y - height / 2
            width:          Math.max(height, label.implicitWidth + 8 * HHUStyle.s)
            height:         20 * HHUStyle.s
            radius:         height / 2
            color:          modelData.current ? root._blue : (modelData.status === 1 ? root._green : "white")
            border.color:   modelData.current ? root._blue : (modelData.status === 1 ? root._green : root._grey)
            border.width:   1
            opacity:        modelData.status === 2 && !modelData.current ? 0.75 : 1
            HHUText {
                id:                 label
                anchors.centerIn:   parent
                text:               modelData.n
                size:               13
                number:             true
                font.strikeout:     modelData.status === 2
                color:              modelData.current || modelData.status === 1 ? "white" : HHUStyle.text
            }
        }
    }
}

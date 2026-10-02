import QtQuick
import QtQuick.Layouts

/// 开始作业 with 断点续作 (设计稿 4i): "车周围没有人" reminder, start point as two big choices
/// (接着上次 is preselected when there is a resume point, else 从头开始), 选其他航点 for any waypoint,
/// slide to start.
/// openStart(waypointCount, firstSeq, lastSeq, resumeSeq, fieldName, callback(seq))
HHUDialog {
    id: root

    property int    firstSeq:   1
    property int    lastSeq:    1
    property int    resumeSeq:  0
    property int    waypoints:  0
    property string fieldName
    property int    choice:     0   ///< 0 first, 1 resume, 2 chosen
    property int    chosenSeq:  1
    property var    _callback:  null

    readonly property bool _resumeValid: resumeSeq > firstSeq && resumeSeq <= lastSeq

    title:          qsTr("Start work")
    subtitle:       (fieldName !== "" ? fieldName + " · " : "") + qsTr("%1 waypoints").arg(waypoints)
    dialogWidth:    560

    function openStart(waypointCount, first, last, resume, field, callback) {
        waypoints   = waypointCount
        firstSeq    = first
        lastSeq     = last
        resumeSeq   = resume
        fieldName   = field
        choice      = _resumeValid ? 1 : 0
        chosenSeq   = _resumeValid ? resume : first
        _callback   = callback
        slide.reset()
        open()
    }

    function _selectedSeq() {
        switch (choice) {
        case 1:  return resumeSeq
        case 2:  return chosenSeq
        default: return firstSeq
        }
    }

    component Choice: Rectangle {
        id: choiceItem
        property string label
        property string detail
        property bool   selected
        property bool   available: true
        signal picked
        Layout.fillWidth:       true
        Layout.preferredHeight: 64 * HHUStyle.s
        radius:                 12 * HHUStyle.s
        color:                  selected ? HHUStyle.blueLight : "white"
        border.color:           selected ? HHUStyle.blue : HHUStyle.border
        border.width:           2
        opacity:                available ? 1 : 0.5
        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            x:                      16 * HHUStyle.s
            spacing:                0
            HHUText { text: choiceItem.label; size: 18; bold: true; color: choiceItem.selected ? HHUStyle.blue : HHUStyle.text }
            HHUText { text: choiceItem.detail; size: 14; color: HHUStyle.text2 }
        }
        MouseArea {
            anchors.fill:   parent
            enabled:        choiceItem.available
            cursorShape:    Qt.PointingHandCursor
            onClicked:      choiceItem.picked()
        }
    }

    // 车周围没有人
    Rectangle {
        Layout.fillWidth:       true
        Layout.preferredHeight: 52 * HHUStyle.s
        radius:                 12 * HHUStyle.s
        color:                  HHUStyle.yellowLight
        border.color:           HHUStyle.yellow
        border.width:           2
        RowLayout {
            anchors.fill:           parent
            anchors.leftMargin:     14 * HHUStyle.s
            spacing:                12 * HHUStyle.s
            HHUIcon { name: "warning"; color: "#8A5A00" }
            HHUText { Layout.fillWidth: true; text: qsTr("Nobody is near the vehicle"); size: 18; bold: true }
        }
    }

    GridLayout {
        Layout.fillWidth:   true
        columns:            2
        columnSpacing:      10 * HHUStyle.s

        Choice {
            label:      qsTr("Continue last run")
            detail:     root._resumeValid ? qsTr("From waypoint %1").arg(root.resumeSeq) : qsTr("No record for this field")
            selected:   root.choice === 1
            available:  root._resumeValid
            onPicked:   root.choice = 1
        }
        Choice {
            label:      qsTr("From the beginning")
            detail:     qsTr("From waypoint %1").arg(root.firstSeq)
            selected:   root.choice === 0
            onPicked:   root.choice = 0
        }
    }

    // 选其他航点
    RowLayout {
        Layout.fillWidth:       true
        Layout.minimumHeight:   44 * HHUStyle.s
        spacing:                12 * HHUStyle.s

        HHUText {
            text:   root.choice === 2 ? qsTr("Start from waypoint") : qsTr("Choose another waypoint ›")
            size:   15
            bold:   true
            color:  HHUStyle.blue
            MouseArea {
                anchors.fill:       parent
                anchors.margins:    -10
                cursorShape:        Qt.PointingHandCursor
                onClicked:          root.choice = 2
            }
        }

        HHUStepper {
            visible:    root.choice === 2
            value:      root.chosenSeq
            from:       root.firstSeq
            to:         Math.max(root.firstSeq, root.lastSeq)
            onEdited:   (v) => root.chosenSeq = v
        }
        Item { Layout.fillWidth: true }
    }

    footerItems: [
        HHUButton {
            text:       qsTr("Cancel")
            kind:       "plain"
            size:       18
            h:          64 * HHUStyle.s
            minWidth:   120
            onClicked:  root.close()
        },
        HHUSlide {
            id:                 slide
            Layout.fillWidth:   true
            text:               qsTr("Slide to start")
            color:              HHUStyle.green
            onAccepted: {
                const cb = root._callback
                const seq = root._selectedSeq()
                root.close()
                if (cb) {
                    cb(seq)
                }
            }
        }
    ]
}

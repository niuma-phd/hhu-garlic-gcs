import QtQuick
import QtQuick.Layouts

/// 开始作业 with 断点续作 (设计稿 4i): "车周围没有人" reminder, start point as two big choices
/// (接着上次 is preselected when there is a resume point, else 从头开始), 选其他航点 for any waypoint,
/// slide to start.
/// Works in waypoint numbers 1 … waypointCount as shown on the map (HHUState.waypointNumber), the
/// caller turns the chosen number into the mission sequence for the vehicle.
/// openStart(waypointCount, resumeNumber, callback(number)) - resumeNumber 0 = no resume point
HHUDialog {
    id: root

    property int    resumeNumber:   0
    property int    waypoints:      0
    property int    choice:         0   ///< 0 first, 1 resume, 2 chosen
    property int    chosenNumber:   1
    property var    _callback:      null

    readonly property bool _resumeValid: resumeNumber > 1 && resumeNumber <= waypoints

    title:          qsTr("Start work")
    subtitle:       qsTr("%1 waypoints").arg(waypoints)
    dialogWidth:    560

    function openStart(waypointCount, resume, callback) {
        waypoints       = waypointCount
        resumeNumber    = resume
        choice          = _resumeValid ? 1 : 0
        chosenNumber    = _resumeValid ? resume : 1
        _callback   = callback
        slide.reset()
        open()
    }

    function _selectedNumber() {
        switch (choice) {
        case 1:  return resumeNumber
        case 2:  return chosenNumber
        default: return 1
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
            detail:     root._resumeValid ? qsTr("From waypoint %1").arg(root.resumeNumber) : qsTr("No record")
            selected:   root.choice === 1
            available:  root._resumeValid
            onPicked:   root.choice = 1
        }
        Choice {
            label:      qsTr("From the beginning")
            detail:     qsTr("From waypoint %1").arg(1)
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
            value:      root.chosenNumber
            from:       1
            to:         Math.max(1, root.waypoints)
            onEdited:   (v) => root.chosenNumber = v
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
                const number = root._selectedNumber()
                root.close()
                if (cb) {
                    cb(number)
                }
            }
        }
    ]
}

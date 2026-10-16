import QtQuick
import QtQuick.Layouts

/// − value + control (设计稿 2h), e.g. 1.2 m/s or a waypoint number.
/// `editable`: the value can also be typed (Enter or leaving the field applies it); a value outside
/// from … to is set to the limit and a short note says so.
Rectangle {
    id: root

    property real   value:      0
    property real   from:       0
    property real   to:         100
    property real   step:       1
    property int    decimals:   0
    property string unit
    property bool   editable:   false

    signal edited(real value)

    property string _hint

    implicitWidth:  row.implicitWidth
    implicitHeight: 52 * HHUStyle.s
    radius:         10 * HHUStyle.s
    border.color:   HHUStyle.border
    border.width:   2
    color:          "white"

    function _fmt(v) { return v.toFixed(decimals) }

    function _set(v) {
        v = Math.max(from, Math.min(to, Number((Math.round(v / step) * step).toFixed(decimals))))
        if (v !== value) {
            edited(v)
        }
    }

    /// Typed value: limited to from … to, the operator is told when it was changed
    function _commit(text) {
        const typed = parseFloat(text.replace(",", "."))
        if (isNaN(typed)) {
            input.text = _fmt(value)
            return
        }
        if (typed < from || typed > to) {
            const limit = typed < from ? from : to
            _hint = qsTr("Allowed %1 – %2 %3, set to %4").arg(_fmt(from)).arg(_fmt(to)).arg(unit).arg(_fmt(limit))
            hintTimer.restart()
        }
        _set(typed)
        input.text = _fmt(value)
    }

    Timer {
        id:             hintTimer
        interval:       4000
        onTriggered:    root._hint = ""
    }

    HHUText {
        anchors.top:        parent.bottom
        anchors.topMargin:  4 * HHUStyle.s
        anchors.right:      parent.right
        visible:            root._hint !== ""
        text:               root._hint
        size:               14
        color:              HHUStyle.red
        z:                  1
    }

    RowLayout {
        id:             row
        anchors.fill:   parent
        spacing:        0

        component StepButton: Item {
            id: stepButton
            property string glyph
            property bool   available
            signal pressed
            Layout.preferredWidth:  48 * HHUStyle.s
            Layout.fillHeight:      true
            opacity:                available ? 1 : 0.35
            HHUText { anchors.centerIn: parent; text: stepButton.glyph; size: 22; bold: true }
            MouseArea {
                anchors.fill:   parent
                enabled:        stepButton.available
                cursorShape:    Qt.PointingHandCursor
                onClicked:      stepButton.pressed()
                onPressAndHold: repeat.start()
                onReleased:     repeat.stop()
                Timer { id: repeat; interval: 120; repeat: true; onTriggered: stepButton.pressed() }
            }
        }

        StepButton { glyph: "−"; available: root.value > root.from; onPressed: root._set(root.value - root.step) }
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: HHUStyle.border }
        HHUText {
            visible:                !root.editable
            Layout.minimumWidth:    80 * HHUStyle.s
            Layout.leftMargin:      12 * HHUStyle.s
            Layout.rightMargin:     12 * HHUStyle.s
            horizontalAlignment:    Text.AlignHCenter
            text:                   root.value.toFixed(root.decimals) + (root.unit !== "" ? " " + root.unit : "")
            number:                 true
            size:                   18
        }
        // typed value: tap to select, Enter / leaving the field applies it
        Row {
            visible:                root.editable
            Layout.minimumWidth:    80 * HHUStyle.s
            Layout.leftMargin:      12 * HHUStyle.s
            Layout.rightMargin:     12 * HHUStyle.s
            Layout.alignment:       Qt.AlignVCenter
            spacing:                4 * HHUStyle.s

            TextInput {
                id:                     input
                width:                  Math.max(contentWidth, 44 * HHUStyle.s)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment:    TextInput.AlignHCenter
                font.family:            HHUStyle.numberFamily
                font.pixelSize:         HHUStyle.px(18)
                font.weight:            Font.Bold
                color:                  HHUStyle.text
                selectByMouse:          true
                selectionColor:         HHUStyle.blue
                inputMethodHints:       Qt.ImhFormattedNumbersOnly
                validator:              RegularExpressionValidator { regularExpression: /^[0-9]{0,3}([.,][0-9]{0,2})?$/ }
                onActiveFocusChanged: {
                    if (activeFocus) {
                        selectAll()
                    } else {
                        root._commit(text)
                    }
                }
                onAccepted:             { root._commit(text); focus = false }
                Keys.onEscapePressed:   { text = root._fmt(root.value); focus = false }

                Binding on text {
                    when:           !input.activeFocus
                    value:          root._fmt(root.value)
                    restoreMode:    Binding.RestoreNone   // keep the number (selected) while typing
                }

                Rectangle {
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    anchors.top:    parent.bottom
                    height:         2
                    color:          input.activeFocus ? HHUStyle.blue : HHUStyle.border
                }
            }
            HHUText {
                visible:                    root.unit !== ""
                anchors.verticalCenter:     parent.verticalCenter
                text:                       root.unit
                number:                     true
                size:                       18
            }
        }
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: HHUStyle.border }
        StepButton { glyph: "+"; available: root.value < root.to; onPressed: root._set(root.value + root.step) }
    }
}

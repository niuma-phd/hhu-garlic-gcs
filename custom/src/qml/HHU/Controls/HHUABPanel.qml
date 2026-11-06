import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl

/// 规划 page, AB线 mode: field (新建 / 打开 / 保存 / 另存), 记A / 记B, 垄宽 / 方向 / 条数, the line list
/// (从这条开始, 跳过 / 恢复) and 开始AB作业. Titles, values, buttons and states only (no help texts).
Item {
    id: root

    property var editorMap

    HHUStatus { id: status }

    onVisibleChanged: if (visible) flick.contentY = 0

    readonly property bool _locked:     hhuABRun.active      ///< no editing while a line is driven
    readonly property bool _canRecord:  !!status.vehicle && status.vehicle.coordinate.isValid
                                        && (status.positionOk || !hhuConfig.abRequireRtkFixed) && hhuAB.recording === 0 && !_locked
    readonly property bool _hasLines:   hhuAB.lines.length > 0

    function _centerOnLines() {
        if (hhuAB.hasA && hhuAB.hasB) {
            editorMap.center = hhuAB.a.atDistanceAndAzimuth(hhuAB.abLength / 2, hhuAB.abBearing)
        } else if (hhuAB.hasA) {
            editorMap.center = hhuAB.a
        }
    }

    // ---- Field files ---------------------------------------------------------------------------

    function _save() {
        if (hhuAB.name === "") {
            nameDialog.openFor(false)
        } else if (!hhuAB.save()) {
            messageDialog.show(qsTr("Save failed"), hhuAB.folder())
        }
    }

    /// does `then` once the field has a name (asks for one first)
    property var _afterName: null

    HHUDialog {
        id:     nameDialog
        title:  _saveAs ? qsTr("Save as") : qsTr("Save field")

        property bool _saveAs: false

        function openFor(saveAs) {
            _saveAs = saveAs
            nameField.text = saveAs && hhuAB.name !== "" ? hhuAB.name : ""
            nameError.text = ""
            open()
            nameField.forceActiveFocus()
        }
        function _accept() {
            const name = nameField.text.trim()
            if (name === "" || /[\\\/:*?"<>|]/.test(name)) {
                nameError.text = qsTr("Invalid name")
                return
            }
            if (hhuAB.fieldExists(name) && name !== hhuAB.name) {
                nameError.text = qsTr("Name already used")
                return
            }
            if (!hhuAB.saveAs(name)) {
                nameError.text = qsTr("Save failed")
                return
            }
            close()
            const then = root._afterName
            root._afterName = null
            if (then) then()
        }
        onClosed: root._afterName = null

        HHUTextField {
            id:                 nameField
            Layout.fillWidth:   true
            placeholderText:    qsTr("Field name")
            onAccepted:         nameDialog._accept()
        }
        HHUText {
            id:         nameError
            visible:    text !== ""
            color:      HHUStyle.red
            size:       15
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Cancel"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: nameDialog.close() },
            HHUButton { text: qsTr("Save"); kind: "blue"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: nameDialog._accept() }
        ]
    }

    HHUDialog {
        id:             openDialog
        title:          qsTr("Open field")
        dialogWidth:    560

        property var _list: []
        function show() {
            _list = hhuAB.fieldList()
            open()
        }

        HHUText {
            visible:    openDialog._list.length === 0
            text:       qsTr("No saved fields")
            color:      HHUStyle.text3
        }
        ListView {
            Layout.fillWidth:       true
            Layout.preferredHeight: Math.min(contentHeight, 420 * HHUStyle.s)
            clip:                   true
            spacing:                6 * HHUStyle.s
            model:                  openDialog._list
            delegate: Rectangle {
                width:          ListView.view.width
                height:         56 * HHUStyle.s
                radius:         10 * HHUStyle.s
                color:          openMouse.pressed ? HHUStyle.grey2 : HHUStyle.grey
                border.color:   modelData.name === hhuAB.name ? HHUStyle.blue : "transparent"
                border.width:   2
                RowLayout {
                    anchors.fill:       parent
                    anchors.leftMargin: 14 * HHUStyle.s
                    anchors.rightMargin: 14 * HHUStyle.s
                    spacing:            10 * HHUStyle.s
                    HHUText { Layout.fillWidth: true; text: modelData.name; size: 17; bold: true; elide: Text.ElideRight }
                    HHUText { text: modelData.done + "/" + modelData.count; number: true; size: 16; color: HHUStyle.text3 }
                    HHUText { text: modelData.modified; number: true; size: 15; color: HHUStyle.text3 }
                }
                MouseArea {
                    id:             openMouse
                    anchors.fill:   parent
                    cursorShape:    Qt.PointingHandCursor
                    onClicked: {
                        openDialog.close()
                        if (!hhuAB.open(modelData.name)) {
                            messageDialog.show(qsTr("Open failed"), modelData.name)
                        } else {
                            root._centerOnLines()
                        }
                    }
                }
            }
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Close"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: openDialog.close() }
        ]
    }

    HHUDialog {
        id: messageDialog
        function show(t, m) {
            title = t
            messageText.text = m
            open()
        }
        HHUText {
            id:                 messageText
            Layout.fillWidth:   true
            size:               17
            color:              HHUStyle.text2
            wrapMode:           Text.WordWrap
        }
        footerItems: [
            Item { Layout.fillWidth: true },
            HHUButton { text: qsTr("Close"); kind: "plain"; size: 18; h: 56 * HHUStyle.s; minWidth: 120; onClicked: messageDialog.close() }
        ]
    }

    function _newField() {
        if (hhuAB.dirty && (hhuAB.hasA || hhuAB.hasB)) {
            mainWindow.hhuConfirm(root, qsTr("New field"), qsTr("Discard the unsaved changes?"), qsTr("Discard"), function() { hhuAB.newField() })
        } else {
            hhuAB.newField()
        }
    }

    function _openField() {
        if (hhuAB.dirty && (hhuAB.hasA || hhuAB.hasB)) {
            mainWindow.hhuConfirm(root, qsTr("Open field"), qsTr("Discard the unsaved changes?"), qsTr("Discard"), function() { openDialog.show() })
        } else {
            openDialog.show()
        }
    }

    function _record(which) {
        if ((which === 1 && hhuAB.hasA) || (which === 2 && hhuAB.hasB)) {
            mainWindow.hhuConfirm(root, which === 1 ? qsTr("Record A") : qsTr("Record B"),
                                  which === 1 ? qsTr("Record A again?") : qsTr("Record B again?"),
                                  qsTr("Record"), function() { hhuAB.record(which) })
        } else {
            hhuAB.record(which)
        }
    }

    Connections {
        target: hhuAB
        function onRecordingChanged() {
            if (hhuAB.recording === 0 && hhuAB.recordError !== "") {
                messageDialog.show(qsTr("Point not recorded"),
                                   hhuAB.recordError === "rtk" ? qsTr("RTK fixed lost") : qsTr("No vehicle position"))
            } else if (hhuAB.recording === 0 && hhuAB.hasA && hhuAB.hasB) {
                root._centerOnLines()
            }
        }
    }

    // ---- 开始AB作业 ------------------------------------------------------------------------------

    function _startWork() {
        if (hhuAB.name === "" || hhuAB.dirty) {
            // the progress is written back to the field file
            if (hhuAB.name === "") {
                _afterName = _startWork
                nameDialog.openFor(false)
                return
            }
            if (!hhuAB.save()) {
                messageDialog.show(qsTr("Save failed"), hhuAB.folder())
                return
            }
        }
        if (hhuABRun.checkWorkEnable() !== 0) {
            messageDialog.show(qsTr("Cannot start"), qsTr("Work link is off on the vehicle (VCU_WORK_EN=0)"))
            return
        }
        mainWindow.showFlyView()
        HHUState.requestABStart(hhuAB.selected)
    }

    // ---- Layout ------------------------------------------------------------------------------------
    // Everything scrolls in one piece on short screens (the line list included); 开始AB作业 stays at the bottom

    ColumnLayout {
        anchors.fill:   parent
        spacing:        10 * HHUStyle.s

        Flickable {
            id:                 flick
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            clip:               true
            contentWidth:       width
            contentHeight:      content.implicitHeight
            boundsBehavior:     Flickable.StopAtBounds
            interactive:        contentHeight > height
            readonly property bool _scrolls: contentHeight > height + 1
            ScrollBar.vertical: ScrollBar {
                policy: flick._scrolls ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                width:  8 * HHUStyle.s
            }

            ColumnLayout {
                id:         content
                width:      flick.width - (flick._scrolls ? 14 * HHUStyle.s : 0)
                spacing:    10 * HHUStyle.s

                // field: name + 新建 / 打开 / 保存 / 另存
                HHUText {
                    Layout.fillWidth:   true
                    text:               (hhuAB.name !== "" ? hhuAB.name : qsTr("Unsaved field")) + (hhuAB.dirty && hhuAB.name !== "" ? " *" : "")
                    size:               17
                    bold:               true
                    elide:              Text.ElideRight
                }
                GridLayout {
                    Layout.fillWidth:   true
                    columns:            4
                    columnSpacing:      6 * HHUStyle.s
                    rowSpacing:         6 * HHUStyle.s
                    enabled:            !root._locked
                    HHUButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: qsTr("New");     kind: "plain"; size: 15; h: 44 * HHUStyle.s; onClicked: root._newField() }
                    HHUButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: qsTr("Open");    kind: "plain"; size: 15; h: 44 * HHUStyle.s; onClicked: root._openField() }
                    HHUButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: qsTr("Save");    kind: "plain"; size: 15; h: 44 * HHUStyle.s; enabled: hhuAB.hasA || hhuAB.hasB; onClicked: root._save() }
                    HHUButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: qsTr("Save as"); kind: "plain"; size: 15; h: 44 * HHUStyle.s; enabled: hhuAB.hasA || hhuAB.hasB; onClicked: nameDialog.openFor(true) }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: HHUStyle.divider }

                // 记A / 记B
                RowLayout {
                    Layout.fillWidth:   true
                    spacing:            8 * HHUStyle.s
                    Repeater {
                        model: [ 1, 2 ]
                        HHUButton {
                            Layout.fillWidth:   true
                            Layout.preferredWidth: 1
                            readonly property bool _has: modelData === 1 ? hhuAB.hasA : hhuAB.hasB
                            text:       hhuAB.recording === modelData ? qsTr("Recording…")
                                                                      : (modelData === 1 ? qsTr("Record A") : qsTr("Record B")) + (_has ? " ✓" : "")
                            icon:       "pin"
                            kind:       _has ? "outline" : "blue"
                            size:       16
                            h:          52 * HHUStyle.s
                            enabled:    root._canRecord
                            onClicked:  root._record(modelData)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth:   true
                    visible:            hhuAB.hasA && hhuAB.hasB
                    spacing:            16 * HHUStyle.s
                    Row {
                        spacing: 6 * HHUStyle.s
                        HHUText { text: qsTr("AB length"); size: 15; color: HHUStyle.text3; anchors.verticalCenter: parent.verticalCenter }
                        HHUText { text: isNaN(hhuAB.abLength) ? "—" : hhuAB.abLength.toFixed(2) + " m"; number: true; size: 18 }
                    }
                    Row {
                        spacing: 6 * HHUStyle.s
                        HHUText { text: qsTr("Bearing"); size: 15; color: HHUStyle.text3; anchors.verticalCenter: parent.verticalCenter }
                        HHUText { text: isNaN(hhuAB.abBearing) ? "—" : hhuAB.abBearing.toFixed(1) + "°"; number: true; size: 18 }
                    }
                }

                // 垄宽 / 方向 / 条数
                RowLayout {
                    Layout.fillWidth:   true
                    Layout.bottomMargin: 18 * HHUStyle.s    // room for the stepper's out-of-range note
                    enabled:            !root._locked
                    HHUText { Layout.fillWidth: true; text: qsTr("Row width"); size: 16; bold: true }
                    HHUStepper {
                        value:      hhuAB.rowWidth
                        from:       0.1
                        to:         5
                        step:       0.01
                        decimals:   2
                        editable:   true
                        unit:       "m"
                        onEdited:   (v) => hhuAB.rowWidth = v
                    }
                }
                RowLayout {
                    Layout.fillWidth:   true
                    enabled:            !root._locked
                    HHUText { Layout.fillWidth: true; text: qsTr("Side"); size: 16; bold: true }
                    Row {
                        spacing: 4 * HHUStyle.s
                        Repeater {
                            model: [ { t: qsTr("Left"), left: true }, { t: qsTr("Right"), left: false } ]
                            HHUButton {
                                text:       modelData.t
                                kind:       hhuAB.left === modelData.left ? "blue" : "plain"
                                size:       16
                                h:          48 * HHUStyle.s
                                minWidth:   72
                                onClicked:  hhuAB.left = modelData.left
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth:   true
                    Layout.bottomMargin: 18 * HHUStyle.s
                    enabled:            !root._locked
                    HHUText { Layout.fillWidth: true; text: qsTr("Lines"); size: 16; bold: true }
                    HHUStepper {
                        value:      hhuAB.count
                        from:       1
                        to:         200
                        step:       1
                        editable:   true
                        onEdited:   (v) => hhuAB.count = v
                    }
                }

                // AB 线运行设置: 所有地块共用, 改了立即用于下一次对准 / 作业
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: HHUStyle.divider }
                HHUText { text: qsTr("Run settings (all fields)"); size: 15; color: HHUStyle.text3 }
                Repeater {
                    model: [
                        { t: qsTr("Transport speed"), key: "speedTransport", k: 3.6, from: 0.5, to: 5,  step: 0.1, dec: 1, unit: "km/h" },
                        { t: qsTr("Work speed"),      key: "speedWork",      k: 3.6, from: 0.5, to: 2,  step: 0.1, dec: 1, unit: "km/h" },
                        { t: qsTr("Lead-in length"),  key: "leadLc",         k: 1,   from: 1,   to: 30, step: 1,   dec: 0, unit: "m" },
                        { t: qsTr("Alignment point before A"), key: "leadD", k: 1,   from: 0,   to: 10, step: 0.5, dec: 1, unit: "m" }
                    ]
                    RowLayout {
                        Layout.fillWidth:   true
                        Layout.bottomMargin: 18 * HHUStyle.s
                        enabled:            !root._locked
                        HHUText { Layout.fillWidth: true; text: modelData.t; size: 16; bold: true }
                        HHUStepper {
                            value:      hhuAB[modelData.key] * modelData.k
                            from:       modelData.from
                            to:         modelData.to
                            step:       modelData.step
                            decimals:   modelData.dec
                            editable:   true
                            unit:       modelData.unit
                            onEdited:   (v) => hhuAB[modelData.key] = v / modelData.k
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: HHUStyle.divider; visible: root._hasLines }

                HHUText {
                    visible:    root._hasLines
                    text:       qsTr("Done %1/%2").arg(hhuAB.doneCount).arg(hhuAB.count)
                    number:     true
                    size:       15
                    color:      HHUStyle.text3
                }

                // line list: tap = 从这条开始; 跳过 / 恢复
                Repeater {
                    model: root._hasLines ? hhuAB.lines : []
                    Rectangle {
                        id:                     lineRow
                        Layout.fillWidth:       true
                        Layout.preferredHeight: 48 * HHUStyle.s
                        radius:                 10 * HHUStyle.s
                        readonly property bool _sel: index === hhuAB.selected
                        color:          _sel ? HHUStyle.blueLight : HHUStyle.grey
                        border.color:   _sel ? HHUStyle.blue : "transparent"
                        border.width:   2
                        MouseArea {
                            anchors.fill:   parent
                            enabled:        !root._locked
                            cursorShape:    Qt.PointingHandCursor
                            onClicked: {
                                hhuAB.selected = index
                                root.editorMap.center = modelData.start
                            }
                        }
                        RowLayout {
                            anchors.fill:       parent
                            anchors.leftMargin: 12 * HHUStyle.s
                            anchors.rightMargin: 6 * HHUStyle.s
                            spacing:            8 * HHUStyle.s
                            HHUText {
                                Layout.preferredWidth: 40 * HHUStyle.s
                                text:           modelData.n
                                number:         true
                                size:           18
                                font.strikeout: modelData.status === 2
                                color:          modelData.status === 2 ? HHUStyle.text3 : HHUStyle.text
                            }
                            HHUText {
                                Layout.fillWidth: true
                                text:   modelData.status === 1 ? qsTr("Done") : (modelData.status === 2 ? qsTr("Skipped") : qsTr("Not driven"))
                                size:   15
                                color:  modelData.status === 1 ? HHUStyle.green : HHUStyle.text3
                            }
                            HHUText {
                                visible:    lineRow._sel
                                text:       qsTr("Start here")
                                size:       14
                                bold:       true
                                color:      HHUStyle.blue
                            }
                            HHUButton {
                                visible:    modelData.status !== 1
                                enabled:    !root._locked
                                text:       modelData.status === 2 ? qsTr("Restore") : qsTr("Skip")
                                kind:       "plain"
                                size:       14
                                h:          36 * HHUStyle.s
                                minWidth:   64
                                onClicked:  hhuAB.setLineStatus(index, modelData.status === 2 ? 0 : 2)
                            }
                        }
                    }
                }
            }
        }

        HHUButton {
            Layout.fillWidth:   true
            text:               qsTr("Start AB work")
            icon:               "play"
            kind:               "green"
            size:               17
            h:                  56 * HHUStyle.s
            enabled:            root._hasLines && !root._locked && status.canControl
                                && !!hhuAB.lines[hhuAB.selected] && hhuAB.lines[hhuAB.selected].status !== 2
            onClicked:          root._startWork()
        }
    }
}

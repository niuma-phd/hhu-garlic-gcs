"""Generate QML overrides from upstream files with small, checked patches.

Instead of hand-copying large upstream QML files, each override here is
upstream + a list of exact-text patches. If an upstream upgrade changes the
anchor text the script stops with an error, so the patch gets re-checked.

    python custom/tools/gen_overrides.py

Output: custom/src/qml/generated/*.qml (aliased in custom.qrc).
"""
import pathlib
import re
import sys

CUSTOM = pathlib.Path(__file__).resolve().parent.parent
SRC = CUSTOM.parent / "src"
OUT = CUSTOM / "src" / "qml" / "generated"


def hide_block_with_object_name(object_name):
    """Set `visible: false` on the ToolStripAction that has the given objectName."""
    def apply(text):
        pat = re.compile(r'(objectName: "%s"\n(?:[^\n]*\n)*?\s*)visible: [^\n]*' % re.escape(object_name))
        new, n = pat.subn(r"\1visible: false // HHU: customer build", text, count=1)
        if n != 1:
            raise SystemExit(f"anchor not found: objectName {object_name}")
        return new
    return apply


def replace_once(old, new):
    def apply(text):
        if text.count(old) != 1:
            raise SystemExit(f"anchor must occur exactly once ({text.count(old)}x): {old!r}")
        return text.replace(old, new)
    return apply


def replace_n(old, new, n):
    def apply(text):
        if text.count(old) != n:
            raise SystemExit(f"anchor must occur {n}x ({text.count(old)}x): {old!r}")
        return text.replace(old, new)
    return apply


def replace_tail(anchor, new):
    """Replace everything from anchor (must occur once) to the end of the file."""
    def apply(text):
        if text.count(anchor) != 1:
            raise SystemExit(f"anchor must occur exactly once ({text.count(anchor)}x): {anchor!r}")
        return text[:text.index(anchor)] + new
    return apply


def add_import(module):
    def apply(text):
        if f"import {module}\n" in text:
            return text
        return text.replace("import QGroundControl\n", f"import QGroundControl\nimport {module}\n", 1)
    return apply


OVERRIDES = {
    # Settings pages: content left-aligned under the page title (设计稿 6a), at most 820 px wide
    "AppSettings/SettingsPage.qml": [
        add_import("HHU.Controls"),
        replace_once("""            x:          Math.max(0, root.width / 2 - width / 2)
            width:      Math.max(implicitWidth, ScreenTools.defaultFontPixelWidth * 50)
""", """            x:          0
            width:      Math.min(Math.max(implicitWidth, ScreenTools.defaultFontPixelWidth * 50), Math.max(820 * HHUStyle.s, root.width * 0.6), root.width)
"""),
    ],
    # Settings (设计稿 6a): the top bar keeps only 作业 / 规划 (none highlighted), no back button or title
    "MainWindow/MainWindow.qml": [
        add_import("HHU.Controls"),
        replace_once("""            height:         ScreenTools.toolbarHeight
            color:          qgcPal.toolbarBackground

            RowLayout {
                id:                 toolDrawerToolbarLayout
""", """            height:         HHUStyle.barH
            color:          "white"

            HHUStatusBar {
                anchors.fill:   parent
                page:           "settings"
            }

            RowLayout {
                id:                 toolDrawerToolbarLayout
                visible:            false  // HHU
"""),
        # No yellow critical message banner ("车辆错误" / "收到更多错误"): the vehicle messages are in the
        # bell list, the reasons that block work in the 暂时不能开始 card (issue #6)
        replace_once("""    function showCriticalVehicleMessage(message) {
        if (suppressCriticalVehicleMessages) {
""", """    function showCriticalVehicleMessage(message) {
        if (true) {  // HHU: never shown, see the bell list
"""),
        # QGC app messages (issue #6): the "Configuration tasks remain" dialog is dropped (no vehicle setup
        # pages here); "HHU-GCS" (QGC_APP_NAME, kept for the settings path) is shown as 无人车地面站
        replace_once("""    function _showMessageDialogWorker(owner, dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null, bypassNavigationCheck = false) {
        let dialog = simpleMessageDialogComponent.createObject(owner, { title: dialogTitle, text: dialogText, buttons: buttons, acceptFunction: acceptFunction, closeFunction: closeFunction, bypassNavigationCheck: bypassNavigationCheck })
""", """    function _showMessageDialogWorker(owner, dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null, bypassNavigationCheck = false, extraProperties = null) {
        let properties = { title: dialogTitle, text: dialogText, buttons: buttons, acceptFunction: acceptFunction, closeFunction: closeFunction, bypassNavigationCheck: bypassNavigationCheck }
        let dialog = simpleMessageDialogComponent.createObject(owner, Object.assign(properties, extraProperties || {}))
"""),
        # HHU confirmations in one style (issue #6): title = what happens, accept button = the verb
        # (删除 / 清空 / 断开并连接), reject = 取消
        replace_once("""    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {""", """    function hhuConfirm(owner, title, text, acceptText, acceptFunction) {
        _showMessageDialogWorker(owner, title, text, Dialog.Ok | Dialog.Cancel, acceptFunction, null, false,
                                 { acceptText: acceptText, rejectText: qsTr("Cancel") })
    }

    /// One vehicle at a time: connecting asks first to drop the connection in use (HHUState)
    function hhuConnectExclusive(owner, name, connectFunction) {
        const inUse = HHUState.connectionsInUse()
        if (inUse.length === 0) {
            HHUState.disconnectAll()    // stops a 4G connection still waiting for the vehicle
            connectFunction()
            return
        }
        hhuConfirm(owner, qsTr("Switch connection"),
                   qsTr("Connected to %1. Only one vehicle can be connected at a time. Disconnect it and connect to %2?")
                       .arg(inUse.join(qsTr(", "))).arg(name),
                   qsTr("Disconnect and connect"),
                   function() {
                       HHUState.disconnectAll()
                       connectFunction()
                   })
    }

    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {"""),
        # Close checks (车辆仍在连接 etc.): 退出 / 取消 instead of 是 / 否 (issue #6)
        replace_n("""true /* bypassNavigationCheck */)""", """true /* bypassNavigationCheck */, { acceptText: qsTr("Exit"), rejectText: qsTr("Cancel") })""", 3),
        replace_once("""    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {
        _showMessageDialogWorker(mainWindow, dialogTitle, dialogText)
    }
""", """    // HHU: customer wording of QGC app messages; false = not shown
    function _hhuAppMessage(msg) {
        if (msg.text.indexOf(qsTranslate("AutoPilotPlugin", "Configuration tasks remain before this vehicle is ready to fly. See Vehicle Configuration for details.")) >= 0
                || msg.text.indexOf("Configuration tasks remain") >= 0) {
            console.warn("HHU: setup message not shown:", msg.text)
            return false
        }
        const name = Qt.application.name
        const display = Qt.application.displayName
        msg.title = msg.title.split(name).join(display)
        msg.text = msg.text.split(name).join(display)
        return true
    }

    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {
        let msg = { title: dialogTitle, text: dialogText }
        if (!_hhuAppMessage(msg)) {
            return
        }
        _showMessageDialogWorker(mainWindow, msg.title, msg.text)
    }
"""),
        replace_once("""    function _showRebootVehicleDialog(dialogTitle, dialogText) {
        _showMessageDialogWorker(mainWindow, dialogTitle,
                                 dialogText + " " + qsTr("Click Ok to reboot the vehicle now."),""", """    function _showRebootVehicleDialog(dialogTitle, dialogText) {
        let msg = { title: dialogTitle, text: dialogText }
        _hhuAppMessage(msg)
        _showMessageDialogWorker(mainWindow, msg.title,
                                 msg.text + " " + qsTr("Click Ok to reboot the vehicle now."),"""),
    ],
    # Settings groups (设计稿 6a–6d): white cards with a light border on the grey settings page
    "QmlControls/SettingsGroupLayout.qml": [
        add_import("HHU.Controls"),
        replace_once("""    property string defaultBorderColor  : QGroundControl.globalPalette.groupBorder
""", """    property string defaultBorderColor  : HHUStyle.settingsBorder
"""),
        replace_once("""        color:              "transparent"
        border.color:       outerBorderColor
        border.width:       showBorder ? 1 : 0
        radius:             ScreenTools.defaultFontPixelHeight / 2
""", """        color:              showBorder ? "white" : "transparent"
        border.color:       outerBorderColor
        border.width:       showBorder ? 1 : 0
        radius:             12 * HHUStyle.s
"""),
        replace_once("""                height:     1
                color:      QGroundControl.globalPalette.groupBorder
""", """                height:     1
                color:      HHUStyle.divider
"""),
        # group subtitle (离线地图 “下载地图瓦片，供无网络时使用”) in the normal text size (Cowork S2)
        replace_once("""            text:               headingDescription
            wrapMode:           Text.WordWrap
            font.pointSize:     ScreenTools.smallFontPointSize
""", """            text:               headingDescription
            wrapMode:           Text.WordWrap
"""),
    ],
    # Map waypoint labels (规划 and 作业) count waypoints 1, 2, 3 … instead of the mission sequence
    # (a route speed is mission item 1, so the first waypoint would read "2" - issue #6 D12)
    "FlightMap/MapItems/MissionItemIndicator.qml": [
        add_import("HHU.Controls"),
        replace_once("""            index:              missionItem.abbreviation.charAt(0) > 'A' && missionItem.abbreviation.charAt(0) < 'z' ? -1 : missionItem.sequenceNumber
""", """            index:              missionItem.abbreviation.charAt(0) > 'A' && missionItem.abbreviation.charAt(0) < 'z' ? -1 : _hhuNumber
"""),
        replace_once("""            property bool _isCurrentItem:   missionItem ? missionItem.isCurrentItem || missionItem.hasCurrentChildItem : false
""", """            property bool _isCurrentItem:   missionItem ? missionItem.isCurrentItem || missionItem.hasCurrentChildItem : false
            // HHU: waypoint number; the planned home (sequence 0) keeps index 0, shown as its letter
            property int  _hhuNumber:       missionItem.sequenceNumber === 0 || !missionItem.masterController ? missionItem.sequenceNumber
                                                : HHUState.waypointNumber(missionItem.masterController.missionController, missionItem.sequenceNumber)
"""),
        # 规划 page: right click (or long press, see MissionItemIndexLabel) a waypoint → delete card
        replace_once("""            onClicked:          _item.clicked()
""", """            onClicked:          _item.clicked()
            onHhuPressAndHold:  HHUState.requestWaypointMenu(_item.missionItem)

            MouseArea {
                anchors.fill:       parent
                enabled:            HHUState.planPage
                acceptedButtons:    Qt.RightButton
                onPressed:          HHUState.requestWaypointMenu(_item.missionItem)
            }
"""),
    ],
    # The selected waypoint (drag handle on top of it): long press → delete card, a drag does not
    "FlightMap/MapItems/MissionItemIndicatorDrag.qml": [
        replace_once("""import QGroundControl.Controls
""", """import QGroundControl.Controls
import HHU.Controls
"""),
        replace_once("""        onClicked: {
            focus = true
            itemDragger.clicked()
        }
""", """        onClicked: {
            focus = true
            itemDragger.clicked()
        }
        pressAndHoldInterval: 600
        onPressAndHold: {
            if (itemIndicator && itemIndicator.missionItem) {
                HHUState.requestWaypointMenu(itemIndicator.missionItem)
            }
        }
"""),
    ],
    # Clicking a waypoint on the 作业 map: the confirmation names the waypoint number, the command
    # (_actionData) stays the mission sequence. Served from /Custom, so the module's own types
    # (CustomGuidedActionsController) need the module import.
    "FlyView/GuidedActionsController.qml": [
        add_import("QGroundControl.FlyView"),
        add_import("HHU.Controls"),
        replace_once("""             property string setWaypointMessage:                qsTr("Adjust current waypoint to %1").arg(_actionData)
""", """             property string setWaypointMessage:                qsTr("Adjust current waypoint to %1").arg(HHUState.waypointNumber(missionController, _actionData) || _actionData)
"""),
    ],
    # Waypoint numbers (设计稿 3): white with blue number; current (作业) green; selected (规划) blue + yellow ring
    "PlanView/MissionItemIndexLabel.qml": [
        add_import("HHU.Controls"),
        replace_once("""    signal clicked(point position)
""", """    signal clicked(point position)
    signal hhuPressAndHold  // HHU: 规划 page long press → delete card
"""),
        replace_once("""        onClicked: (mouse) => {
            focus = true
            parent.clicked(Qt.point(mouse.x, mouse.y))
        }
""", """        onClicked: (mouse) => {
            focus = true
            parent.clicked(Qt.point(mouse.x, mouse.y))
        }
        pressAndHoldInterval: 600
        onPressAndHold: parent.hhuPressAndHold()
"""),
        replace_once("""    property string _index:             index === 0 || index === -1 ? label.charAt(0) : (showSequenceNumbers ? index : "")
""", """    property string _index:             index === 0 || index === -1 ? label.charAt(0) : (showSequenceNumbers ? index : "")

    readonly property bool  _hhuCurrent:    checked && !HHUState.planPage
    readonly property bool  _hhuSelected:   checked && HHUState.planPage
    readonly property color _hhuFill:       _hhuCurrent ? HHUStyle.green : (_hhuSelected ? HHUStyle.blue : "white")
    readonly property color _hhuStroke:     _hhuCurrent ? "white" : HHUStyle.blue
    readonly property color _hhuText:       (_hhuCurrent || _hhuSelected) ? "white" : HHUStyle.blue
"""),
        replace_once("""        width:                          _indicatorRadius * 2
        height:                         width
        color:                          root.color
        radius:                         _indicatorRadius

        QGCLabel {
            anchors.fill:           parent
            horizontalAlignment:    Text.AlignHCenter
            verticalAlignment:      Text.AlignVCenter
            color:                  "white"
""", """        width:                          _indicatorRadius * 2
        height:                         width
        color:                          _hhuFill
        radius:                         _indicatorRadius
        border.color:                   _hhuStroke
        border.width:                   2

        QGCLabel {
            anchors.fill:           parent
            anchors.margins:        2
            horizontalAlignment:    Text.AlignHCenter
            verticalAlignment:      Text.AlignVCenter
            color:                  _hhuText
            font.family:            HHUStyle.numberFamily
            font.bold:              true
"""),
        replace_once("""        width:          indicator.width * 2
        height:         width
        radius:         width * 0.5
        color:          Qt.rgba(0,0,0,0)
        border.color:   Qt.rgba(1,1,1,0.5)
        border.width:   1
        visible:        checked && highlightSelected
""", """        width:          indicator.width + 10
        height:         width
        radius:         width * 0.5
        color:          Qt.rgba(0,0,0,0)
        border.color:   HHUStyle.yellow
        border.width:   3
        visible:        _hhuSelected
"""),
    ],
    # All QGC dialogs (showMessageDialog etc.) in the HHU look: white card, big title, buttons in a grey footer
    "QmlControls/QGCPopupDialog.qml": [
        add_import("HHU.Controls"),
        # Own button words (e.g. 退出 / 取消) instead of the standard ones
        replace_once("""    property bool   bypassNavigationCheck:  false
""", """    property bool   bypassNavigationCheck:  false
    property string acceptText:             ""  // HHU
    property string rejectText:             ""  // HHU
"""),
        replace_once("""        closePolicy = Popup.NoAutoClose
""", """        if (acceptText !== "") acceptButton.text = acceptText  // HHU
        if (rejectText !== "") rejectButton.text = rejectText  // HHU

        closePolicy = Popup.NoAutoClose
"""),
        replace_once("""    background: QGCMouseArea {
        width:  mainWindow.width
        height: mainWindow.height
""", """    background: QGCMouseArea {
        width:  mainWindow.width
        height: mainWindow.height

        Rectangle { anchors.fill: parent; color: HHUStyle.dim }   // HHU
"""),
        replace_tail("""    Rectangle {
        x:              mainLayout.x - _contentMargin
""", """    // HHU dialog card
    Rectangle {
        anchors.fill:   mainLayout
        color:          "white"
        radius:         HHUStyle.radiusDlg
    }

    ColumnLayout {
        id:                 mainLayout
        anchors.centerIn:   parent
        spacing:            0

        RowLayout {
            id:                     titleRowLayout
            Layout.fillWidth:       true
            Layout.leftMargin:      28 * HHUStyle.s
            Layout.rightMargin:     28 * HHUStyle.s
            Layout.topMargin:       24 * HHUStyle.s

            HHUText {
                id:                 titleLabel
                objectName:         "popupDialog_title"
                Layout.fillWidth:   true
                text:               root.title
                size:               26
                bold:               true
                elide:              Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth:       true
            Layout.margins:         28 * HHUStyle.s - _contentMargin
            Layout.topMargin:       10 * HHUStyle.s
            Layout.preferredWidth:  Math.max(400 * HHUStyle.s, Math.min(maxAvailableWidth, totalContentWidth))
            Layout.preferredHeight: Math.min(maxAvailableHeight, totalContentHeight)
            color:                  "white"

            property real totalContentWidth:    dialogContentParent.childrenRect.width + _contentMargin * 2 + 2
            property real totalContentHeight:   dialogContentParent.childrenRect.height + _contentMargin * 2 + 2
            property real maxAvailableWidth:    mainWindow.width - 80 * HHUStyle.s
            property real maxAvailableHeight:   mainWindow.height - titleRowLayout.height - footer.height - 80 * HHUStyle.s

            QGCFlickable {
                anchors.margins:    _contentMargin
                anchors.fill:       parent
                contentWidth:       dialogContentParent.childrenRect.width
                contentHeight:      dialogContentParent.childrenRect.height

                Item {
                    id:     dialogContentParent
                    focus:  true

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape && _rejectAllowed) {
                            _reject()
                            event.accepted = true
                        }
                    }
                }
            }
        }

        Rectangle {
            id:                     footer
            Layout.fillWidth:       true
            Layout.preferredHeight: 64 * HHUStyle.s + 32 * HHUStyle.s
            color:                  HHUStyle.grey
            radius:                 HHUStyle.radiusDlg

            Rectangle { width: parent.width; height: parent.radius; color: parent.color }
            Rectangle { width: parent.width; height: 1; color: HHUStyle.divider }

            RowLayout {
                anchors.fill:           parent
                anchors.leftMargin:     28 * HHUStyle.s
                anchors.rightMargin:    28 * HHUStyle.s
                spacing:                12 * HHUStyle.s

                Item { Layout.fillWidth: true }

                HHUButton {
                    id:                     rejectButton
                    objectName:             "popupDialog_rejectButton"
                    kind:                   "plain"
                    h:                      56 * HHUStyle.s
                    size:                   18
                    minWidth:               120
                    onClicked:              _reject()
                }

                HHUButton {
                    id:                     acceptButton
                    objectName:             "popupDialog_acceptButton"
                    kind:                   "blue"
                    h:                      56 * HHUStyle.s
                    size:                   18
                    minWidth:               120
                    onClicked:              _accept()
                }
            }
        }
    }
}
"""),
    ],
    # Text of every QGC message dialog (退出确认, 删除连接 …) in the card body size (issue #6)
    "QmlControls/QGCSimpleMessageDialog.qml": [
        add_import("HHU.Controls"),
        replace_once("""            wrapMode:               Text.WordWrap
""", """            wrapMode:               Text.WordWrap
            font.pixelSize:         HHUStyle.bodyFontSize
            color:                  HHUStyle.text2
"""),
    ],
    # QGC's base font = the HHU body size (issue #6): labels, buttons, group headings and fields of the
    # QGC controls match the card text and follow the 字号 setting; 界面缩放 still scales on top
    "QmlControls/ScreenTools.qml": [
        add_import("HHU.Controls"),
        replace_once("""                platformFontPointSize = _defaultFont.font.pointSize;
""", """                platformFontPointSize = HHUStyle.bodyFontSize * 0.75;  // HHU: px -> pt at 96 logical dpi
"""),
        replace_once("""    onRealPixelDensityChanged: {""", """    // HHU: 字号 changed
    Connections {
        target: HHUStyle
        function onBodyFontSizeChanged() {
            if (!ScreenToolsController.isMobile) {
                platformFontPointSize = HHUStyle.bodyFontSize * 0.75
                _setBasePointSize(platformFontPointSize * QGroundControl.settingsManager.appSettings.uiScalePercent.value / 100)
            }
        }
    }

    onRealPixelDensityChanged: {"""),
    ],
    # Smallest window: fixed logical size instead of 100 × character width, which outgrew a 1920×1080
    # screen at 150 % once the base font follows the card text (1280×720 at 150 % ≈ 853×480 is the design minimum)
    "MainWindow/MainWindowSavedState.qml": [
        replace_once("""            window.minimumWidth = Math.min(ScreenTools.defaultFontPixelWidth * 100, Screen.width)
            window.minimumHeight = Math.min(ScreenTools.defaultFontPixelWidth * 50, Screen.height)
""", """            window.minimumWidth = Math.min(800, Screen.width)    // HHU
            window.minimumHeight = Math.min(450, Screen.height)  // HHU
"""),
    ],
    # Map settings in Chinese (issue #6): the lists keep the internal names (they are the saved
    # values), the combo boxes show HHUState.mapNameText()
    "AppSettings/MapProviderSettings.qml": [
        add_import("HHU.Controls"),
        replace_once("""        label: qsTr("Provider")
        model: _mapEngineManager.mapProviderList

        onActivated: (index) => {
            _mapProviderFact.rawValue = comboBox.textAt(index)
            _mapTypeFact.rawValue = _mapEngineManager.mapTypeList(comboBox.textAt(index))[0]
        }

        Component.onCompleted: {
            var index = comboBox.find(_mapProviderFact.rawValue)
""", """        label: qsTr("Provider")
        model: HHUState.mapNameList(_names)

        readonly property var _names: _mapEngineManager.mapProviderList

        onActivated: (index) => {
            _mapProviderFact.rawValue = _names[index]
            _mapTypeFact.rawValue = _mapEngineManager.mapTypeList(_names[index])[0]
        }

        Component.onCompleted: {
            var index = _names.indexOf(_mapProviderFact.rawValue)
"""),
        replace_once("""        label: qsTr("Type")
        model: _mapEngineManager.mapTypeList(_mapProviderFact.rawValue)

        onActivated: (index) => { _mapTypeFact.rawValue = comboBox.textAt(index) }

        Component.onCompleted: {
            var index = comboBox.find(_mapTypeFact.rawValue)
""", """        label: qsTr("Type")
        model: HHUState.mapNameList(_names)

        readonly property var _names: _mapEngineManager.mapTypeList(_mapProviderFact.rawValue)

        onActivated: (index) => { _mapTypeFact.rawValue = _names[index] }

        Component.onCompleted: {
            var index = _names.indexOf(_mapTypeFact.rawValue)
"""),
        replace_once("""        label: qsTr("Elevation Provider")
        model: _mapEngineManager.elevationProviderList

        onActivated: (index) => { _elevationProviderFact.rawValue = comboBox.textAt(index) }

        Component.onCompleted: {
            var index = comboBox.find(_elevationProviderFact.rawValue)
""", """        label: qsTr("Elevation Provider")
        model: HHUState.mapNameList(_names)

        readonly property var _names: _mapEngineManager.elevationProviderList

        onActivated: (index) => { _elevationProviderFact.rawValue = _names[index] }

        Component.onCompleted: {
            var index = _names.indexOf(_elevationProviderFact.rawValue)
"""),
    ],
    "AppSettings/OfflineMapInfo.qml": [
        add_import("HHU.Controls"),
        replace_once("""        text:               tileSet.name
""", """        text:               HHUState.mapNameText(tileSet.name)
"""),
        replace_once("""        text:   tileSet.downloadStatus + (_tileCount > 0 ? " (" + _tileCount + " tiles)" : "")
""", """        text:   tileSet.downloadStatus + (_tileCount > 0 ? " " + qsTr("(%1 tiles)").arg(_tileCount) : "")
"""),
    ],
    # No small slider end values (alarm volume): the number field beside the slider shows the value
    "QmlControls/QGCSlider.qml": [
        replace_n("""        visible: control.showBoundaryValues
""", """        visible: false  // HHU: the value is in the number field next to it; ends were covered by the knob
""", 2),
    ],
    # 航线页: waypoints only (需求说明 §6). The pattern button comes back as 地块覆盖 (Fields2Cover).
    "PlanView/PlanView.qml": [
        add_import("QGroundControl.PlanView"),
        hide_block_with_object_name("planToolStrip_takeoffButton"),
        hide_block_with_object_name("planToolStrip_patternButton"),
        hide_block_with_object_name("planToolStrip_roiButton"),
        hide_block_with_object_name("planToolStrip_landButton"),
        add_import("HHU.Controls"),
        # 规划 page: the HHU step panel on the left replaces the tool strip, the plan tree
        # (right panel), the layer switcher and the toolbar actions; the map keeps QGC's editing
        replace_once("""        ToolStrip {
            id: toolStrip
            anchors.margins: _toolsMargin
            anchors.left: parent.left
            anchors.top: parent.top
""", """        HHUPlanPanel {
            id: hhuPlanPanel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: HHUStyle.margin * 0.75
            z: QGroundControl.zOrderWidgets
            planView: _root
            planMasterController: planMasterController  // the PlanMasterController id: has the file dialogs
            editorMap: editorMap
        }

        ToolStrip {
            id: toolStrip
            visible: false  // HHU: replaced by the step panel
            anchors.margins: _toolsMargin
            anchors.left: parent.left
            anchors.top: parent.top
"""),
        replace_once("""            maxHeight: parent.height - toolStrip.y
            visible: _editingLayer == _layerMission
""", """            maxHeight: parent.height - toolStrip.y
"""),
        replace_once("""        MapScale {
            anchors.margins: _toolsMargin
            anchors.left: toolStrip.right
            anchors.top: parent.top
""", """        MapScale {
            anchors.margins: _toolsMargin
            anchors.left: hhuPlanPanel.right
            anchors.top: parent.top
"""),
        replace_once("""            z:                      QGroundControl.zOrderWidgets
            visible:                !_planMasterController.showCreateFromTemplate
""", """            z:                      QGroundControl.zOrderWidgets
            visible:                false  // HHU: the step chooses the layer
"""),
        replace_once("""            width: _rightPanelWidth
            planMasterController: _planMasterController
            editorMap: editorMap
""", """            width: 0  // HHU
            planMasterController: _planMasterController
            editorMap: editorMap
"""),
        # No template page: an empty plan goes straight to editing (需求说明 §6)
        replace_once("""            _planMasterController.start()
            _missionController.setCurrentPlanViewSeqNum(0, true)
        }
""", """            _planMasterController.start()
            _missionController.setCurrentPlanViewSeqNum(0, true)
            Qt.callLater(_root._hhuSkipTemplates)
        }

        onShowCreateFromTemplateChanged: Qt.callLater(_root._hhuSkipTemplates)
"""),
        replace_once("""    readonly property int   _decimalPlaces: 8
""", """    readonly property int   _decimalPlaces: 8

    // HHU: waypoint labels show the selected item (规划) or the vehicle's current item (作业)
    Binding { target: HHUState; property: "planPage"; value: _root.visible }

    function _hhuSkipTemplates() {
        if (_planMasterController.showCreateFromTemplate) {
            _planMasterController.userSelectedManualCreation = true
        }
    }
"""),
        # Without a vehicle QGC needs a planned home before inserting; the first click sets it
        replace_once("""                        objectName: "planToolStrip_waypointButton"
                        text: qsTr("Waypoint")
                        iconSource: "/res/waypoint.svg"
                        enabled: _missionController.flyThroughCommandsAllowed
""", """                        objectName: "planToolStrip_waypointButton"
                        text: qsTr("Waypoint")
                        iconSource: "/res/waypoint.svg"
                        enabled: _missionController.flyThroughCommandsAllowed || !_missionController.homePositionSet
"""),
        replace_once("""                    } else if (_addWaypointOnClick) {
                        insertSimpleItemAfterCurrent(coordinate)
""", """                    } else if (_addWaypointOnClick) {
                        if (!_missionController.homePositionSet) {
                            _missionController.setHomePosition(coordinate)  // HHU: no planned home UI
                        }
                        hhuPlanPanel.mapClicked(coordinate)  // HHU: appends at the end, closes the delete card
"""),
        # Every segment gets its own + (HHUPlanPanel), not only the one before the selected point
        replace_once("""                z: QGroundControl.zOrderWaypointLines + 1
                visible: _editingLayer == _layerMission

                sourceItem: SplitIndicator {
""", """                z: QGroundControl.zOrderWaypointLines + 1
                visible: false  // HHU: HHUPlanPanel shows a + on every segment

                sourceItem: SplitIndicator {
"""),
        replace_once("""            mapName: "MissionEditor"
""", """            mapName: "MissionEditor"
            Keys.onEscapePressed: hhuPlanPanel.escapePressed()
            Keys.onDeletePressed: hhuPlanPanel.deletePressed()
"""),
        # Waypoints where the vehicle cannot make the turn are ringed red (上传前检查)
        replace_once("""        PlanViewRightPanel {
            id: rightPanel
""", """        HHUUploadCheck {
            id: hhuTurnCheck
            visible: false
            live: true
            planMasterController: _planMasterController
        }

        MapItemView {
            id: hhuTightTurnView
            model: hhuTurnCheck.tightTurns
            delegate: MapQuickItem {
                coordinate: modelData.coordinate
                anchorPoint.x: sourceItem.width / 2
                anchorPoint.y: sourceItem.height / 2
                z: QGroundControl.zOrderMapItems + 2
                sourceItem: Rectangle {
                    width: ScreenTools.defaultFontPixelHeight * 2.6
                    height: width
                    radius: width / 2
                    color: "#40E5484D"
                    border.color: "#E5484D"
                    border.width: 3
                }
            }
            Component.onCompleted: editorMap.addMapItemView(hhuTightTurnView)
        }

        PlanViewRightPanel {
            id: rightPanel
            visible: false  // HHU: the step panel edits the plan
"""),
    ],
    # No planned home section (distance/time are estimated from the vehicle position)
    "PlanView/PlanInfoEditor.qml": [
        replace_once("""            id: plannedHomePositionSection
            Layout.fillWidth: true
""", """            id: plannedHomePositionSection
            Layout.fillWidth: true
            visible: false  // HHU
            checked: false  // HHU: hides the section content too
"""),
    ],
    # Plan tree without the rally point rows
    "PlanView/PlanTreeView.qml": [
        replace_once("""        implicitHeight: (loader.item ? loader.item.height : 1) + (separatorLine.visible ? separatorLine.height + root.rowSpacing : 0)
""", """        implicitHeight: _hhuHidden ? 0.01 : (loader.item ? loader.item.height : 1) + (separatorLine.visible ? separatorLine.height + root.rowSpacing : 0)
        visible: !_hhuHidden
        // HHU: no rally points, no mission-start settings row (speed is set under 默认值)
        // (0.01: TableView gives 0-height rows a default height)
        readonly property bool _hhuHidden: nodeType.startsWith("rally") || (nodeType === "missionItem" && !!nodeObject && nodeObject.sequenceNumber === 0)
"""),
    ],
    # Waypoint rows show the distance from the previous point
    "PlanView/MissionItemEditor.qml": [
        replace_once("""            id:                     commandLabel
            anchors.verticalCenter: parent.verticalCenter
            width:                  commandPicker.width
            height:                 commandPicker.height
            visible:                !missionItem.isCurrentItem || !missionItem.isSimpleItem || _waypointsOnlyMode || missionItem.isTakeoffItem
            verticalAlignment:      Text.AlignVCenter
            text:                   missionItem.commandName
""", """            id:                     commandLabel
            anchors.verticalCenter: parent.verticalCenter
            width:                  Math.min(implicitWidth, _root.width - parent.x - x - ScreenTools.defaultFontPixelHeight * (missionItem.isCurrentItem ? 2.5 : 0.5))
            elide:                  Text.ElideRight
            height:                 commandPicker.height
            visible:                !missionItem.isCurrentItem || !missionItem.isSimpleItem || _waypointsOnlyMode || missionItem.isTakeoffItem
            verticalAlignment:      Text.AlignVCenter
            text:                   missionItem.distance > 0 ? qsTr("%1 %2   %3 m").arg(missionItem.sequenceNumber).arg(missionItem.commandName).arg(missionItem.distance.toFixed(1)) : missionItem.sequenceNumber + " " + missionItem.commandName
"""),
    ],
    # Upload runs the route checks first
    "PlanView/PlanToolBarIndicators.qml": [
        add_import("HHU.Controls"),
        replace_once("""    function _uploadClicked() {
        _planMasterController.upload()
    }
""", """    function _uploadClicked() {
        hhuUploadCheck.run(function() {
            _planMasterController.sendToVehicle()
            // A new route on the vehicle invalidates the resume point (断点续作)
            hhuWork.clearResume(QGroundControl.multiVehicleManager.activeVehicle)
        })
    }

    HHUUploadCheck {
        id: hhuUploadCheck
        visible: false
        planMasterController: root._planMasterController
    }
"""),
    ],
    # Waypoint editor: no altitude (rover, altitude always 0)
    "PlanView/SimpleItemEditor.qml": [
        add_import("QGroundControl.PlanView"),
        replace_once("                    spacing: _fieldSpacing\n                    visible: _specifiesAltitude\n",
                     "                    spacing: _fieldSpacing\n                    visible: false // HHU: rover, no altitude\n"),
        # Only the basic tab (speed); no camera / advanced (hold time, yaw ...) tabs
        replace_once("                property bool _advancedItemsAvailable: missionItem.comboboxFactsAdvanced.count > 0 || missionItem.textFieldFactsAdvanced.count > 0 || missionItem.nanFactsAdvanced.count > 0\n                property bool _cameraAvailable: missionItem.cameraSection.available\n",
                     "                property bool _advancedItemsAvailable: false  // HHU\n                property bool _cameraAvailable: false  // HHU: no camera\n"),
    ],
    # 作业 map: no upstream click menu (go to / orbit / ROI / set home are aircraft tools);
    # long press or right click = 开到指定点 (需求说明 V1.0 §3.2)
    "FlyView/FlyViewMap.qml": [
        add_import("HHU.Controls"),
        # Track: orange 5 px (设计稿 4.3)
        replace_once("""        id:         trajectoryPolyline
        line.width: 3
        line.color: "red"
""", """        id:         trajectoryPolyline
        line.width: 5
        line.color: HHUStyle.track
"""),
        replace_once("""    onMapClicked: (position) => {
        if (!globals.guidedControllerFlyView.guidedUIVisible &&
""", """    onMapPressAndHold: (position) => hhuGoto.request(_root.toCoordinate(Qt.point(position.x, position.y), false))
    onMapRightClicked: (position) => hhuGoto.request(_root.toCoordinate(Qt.point(position.x, position.y), false))

    HHUGotoHere {
        id: hhuGoto
        mapControl: _root
    }

    onMapClicked: (position) => {
        if (false /* HHU: menu disabled */ && !globals.guidedControllerFlyView.guidedUIVisible &&
"""),
    ],
    # Link types: serial, UDP, TCP, Bluetooth only (需求说明 V1.0 §4.1); no log replay / high latency
    "AppSettings/LinkConfigurationManager.qml": [
        add_import("QGroundControl.AppSettings"),
        add_import("HHU.Controls"),
        # Link parameter pages (SerialSettings.qml …) are named relative to the upstream file; this
        # override lives under qrc:/Custom, where they do not exist, so the add / edit dialog showed
        # only the type and no parameters
        replace_once("""                    source: editingConfig && editingConfig.settingsURL ? editingConfig.settingsURL : ""
""", """                    source: editingConfig && editingConfig.settingsURL ? "qrc:/qml/QGroundControl/AppSettings/" + editingConfig.settingsURL : ""
"""),
        # One vehicle at a time (issue #6): ask before dropping the connection in use
        # edit / delete icons as tall as the buttons next to them (they looked small, Cowork R4)
        replace_n("""                height:                 ScreenTools.minTouchPixels
""", """                height:                 Math.max(ScreenTools.minTouchPixels, ScreenTools.implicitButtonHeight)
""", 2),
        replace_once("""                    onClicked:  QGroundControl.showMessageDialog(
                                    _root,
                                    qsTr("Delete Link"),
                                    qsTr("Are you sure you want to delete '%1'?").arg(object.name),
                                    Dialog.Ok | Dialog.Cancel,
                                    function () {
                                        _linkManager.removeConfiguration(object)
                                    })
""", """                    onClicked:  mainWindow.hhuConfirm(_root, qsTr("Delete connection"),
                                                      qsTr("Delete the connection \\"%1\\"?").arg(object.name),
                                                      qsTr("Delete"),
                                                      function () { _linkManager.removeConfiguration(object) })
"""),
        replace_once("""                        _linkManager.createConnectedLink(object)
""", """                        mainWindow.hhuConnectExclusive(_root, object.name, function() { _linkManager.createConnectedLink(object) })
"""),
        replace_once("""                QGCCheckBoxSlider {
                    Layout.fillWidth:   true
                    text:               qsTr("High Latency")
""", """                QGCCheckBoxSlider {
                    Layout.fillWidth:   true
                    visible:            false // HHU
                    text:               qsTr("High Latency")
"""),
        replace_once("""                    model:                  _linkManager.linkTypeStrings
""", """                    // HHU: the first entries follow LinkConfiguration.LinkType up to Bluetooth
                    model:                  _linkManager.linkTypeStrings.slice(0, LinkConfiguration.TypeBluetooth + 1)
"""),
    ],
    # Mission defaults: no altitude frame / default altitude
    "PlanView/MissionDefaultsEditor.qml": [
        replace_once('            label: qsTr("Alt Frame")\n',
                     '            label: qsTr("Alt Frame")\n            visible: false // HHU\n'),
        replace_once('            label: qsTr("Waypoints Altitude")\n',
                     '            label: qsTr("Waypoints Altitude")\n            visible: false // HHU\n'),
    ],
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for rel, patches in OVERRIDES.items():
        text = (SRC / rel).read_text(encoding="utf-8")
        for patch in patches:
            text = patch(text)
        header = f"// GENERATED by custom/tools/gen_overrides.py from upstream src/{rel} - do not edit\n"
        (OUT / pathlib.Path(rel).name).write_text(header + text, encoding="utf-8")
        print("generated", rel)


if __name__ == "__main__":
    sys.exit(main())

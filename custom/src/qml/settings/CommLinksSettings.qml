import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import HHU.Controls
import QGroundControl.FactControls
import QGroundControl.Controls
import QGroundControl.AppSettings

// HHU replacement of the generated QGroundControl/AppSettings/CommLinksSettings.qml
// 连接 (需求说明 V1.0 §4): 4G connection (HHU4GLink), saved links (serial radio / UDP / TCP /
// Bluetooth, see the LinkConfigurationManager override), automatic connection of USB radios,
// traffic of this and all connections. No NMEA GPS.
SettingsPage {
    objectName: "settingsPage_CommLinks"

    property var _autoConnect: QGroundControl.settingsManager.autoConnectSettings

    // ---- 4G ------------------------------------------------------------------------------

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("4G connection")

        Repeater {
            model: hhu4G.configs

            RowLayout {
                id:                 configRow
                Layout.fillWidth:   true
                Layout.preferredWidth: parent ? parent.width : implicitWidth  // buttons of every row right aligned
                spacing:            ScreenTools.defaultFontPixelWidth

                readonly property bool _isActive: hhu4G.activeIndex === index

                ColumnLayout {
                    Layout.fillWidth:       true
                    Layout.preferredWidth:  1     // takes what the buttons leave, long texts elide
                    spacing: 0
                    QGCLabel {
                        Layout.fillWidth: true
                        elide:          Text.ElideRight
                        text:           modelData.name + (modelData.tls ? "" : "  " + qsTr("(not encrypted)"))
                        font.bold:      configRow._isActive
                        font.pixelSize: HHUStyle.bodyFontSize
                    }
                    QGCLabel {
                        Layout.fillWidth: true
                        wrapMode:       Text.WrapAtWordBoundaryOrAnywhere
                        text:           qsTr("%1:%2 · vehicle %3").arg(modelData.host).arg(modelData.port).arg(modelData.vehicle)
                        font.pixelSize: HHUStyle.bodyFontSize
                        color:          "#5B6B7F"
                    }
                    QGCLabel {
                        Layout.fillWidth: true
                        visible:        configRow._isActive && hhu4G.statusText !== ""
                        text:           hhu4G.statusText + (hhu4G.state === "retrying" && hhu4G.retryInSec > 0 ? qsTr(" (retry in %1 s)").arg(hhu4G.retryInSec) : "")
                        font.pixelSize: HHUStyle.bodyFontSize
                        color:          hhu4G.state === "online" ? (hhu4G.readOnly ? "#B7791F" : "#1F8A3B") : (hhu4G.state === "failed" ? "#B42318" : "#B7791F")
                        wrapMode:       Text.WordWrap
                    }
                }
                QGCButton {
                    text:       qsTr("Edit")
                    enabled:    !configRow._isActive
                    onClicked:  fourGDialog.openFor(index, modelData)
                }
                QGCButton {
                    text:       qsTr("Delete")
                    enabled:    !configRow._isActive
                    onClicked:  mainWindow.hhuConfirm(configRow, qsTr("Delete connection"),
                                                      qsTr("Delete the 4G connection \"%1\"?").arg(modelData.name),
                                                      qsTr("Delete"),
                                                      function() { hhu4G.removeConfig(index) })
                }
                QGCButton {
                    text:       configRow._isActive ? qsTr("Disconnect") : qsTr("Connect")
                    primary:    !configRow._isActive
                    onClicked:  configRow._isActive ? hhu4G.disconnectLink()
                                                    : mainWindow.hhuConnectExclusive(configRow, modelData.name, function() { hhu4G.connectTo(index) })
                }
            }
        }

        LabelledButton {
            Layout.fillWidth:   true
            label:              qsTr("Add a 4G connection")
            buttonText:         qsTr("Add")
            onClicked:          fourGDialog.openNew()
        }

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            text:                   qsTr("Through 4G the vehicle is reached via the server. The link can be slow or drop out: it is not an emergency stop. Stop the vehicle with its emergency stop button or the remote control.")
            font.pixelSize:         HHUStyle.bodyFontSize
            wrapMode:               Text.WordWrap
        }
    }

    // ---- Radio / LAN links -----------------------------------------------------------------

    ColumnLayout {
        Layout.fillWidth:   true
        spacing:            0

        LinkConfigurationManager {
            Layout.fillWidth: true
        }
    }

    QGCLabel {
        Layout.fillWidth:   true
        Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 60
        text:               qsTr("Tip: switch on \"Automatically Connect on Start\" for the link you use, so the ground station reconnects to the vehicle by itself.")
        font.pixelSize:     HHUStyle.bodyFontSize
        wrapMode:           Text.WordWrap
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Automatic connection")

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("USB radio (SiK)")
            fact:               _autoConnect.autoConnectSiKRadio
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Controller connected by USB cable")
            fact:               _autoConnect.autoConnectPixhawk
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("LAN (UDP port 14550)")
            fact:               _autoConnect.autoConnectUDP
        }
    }

    // ---- Traffic ---------------------------------------------------------------------------

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Data traffic")

        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("This connection (up / down)")
            labelText:          hhuLink.formatBytes(hhuLink.sessionUpBytes) + " / " + hhuLink.formatBytes(hhuLink.sessionDownBytes)
        }
        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Total (up / down)")
            labelText:          hhuLink.formatBytes(hhuLink.totalUpBytes) + " / " + hhuLink.formatBytes(hhuLink.totalDownBytes)
        }
        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Latency")
            labelText:          hhuLink.latencyMs >= 0 ? qsTr("%1 ms").arg(hhuLink.latencyMs) : "--"
        }
        LabelledButton {
            Layout.fillWidth:   true
            label:              qsTr("Reset the counters")
            buttonText:         qsTr("Reset")
            onClicked:          hhuLink.resetTraffic()
        }
    }

    // ---- 4G connection editor ----------------------------------------------------------------

    Popup {
        id:             fourGDialog
        parent:         mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
        anchors.centerIn: parent
        modal:          true
        focus:          true
        padding:        ScreenTools.defaultFontPixelWidth * 2
        // Only 取消 / Esc close it: a click next to the dialog used to drop the input without a word (issue #6)
        closePolicy:    Popup.CloseOnEscape

        property int    editIndex: -1
        property bool   hasPassword: false
        property bool   advanced:    false

        function openFor(index, config) {
            editIndex = index
            nameEdit.text = config.name || ""
            hostEdit.text = config.host || ""
            portEdit.text = (config.port || 7000).toString()
            tlsSwitch.checked = config.tls !== false
            caEdit.text = config.caFile || ""
            vehicleEdit.text = config.vehicle || ""
            // 服务器 / 端口 / 加密 / 证书 are set by after-sales: folded away unless still missing
            advanced = hostEdit.text === ""
            passwordEdit.text = ""
            hasPassword = !!config.hasPassword
            showPassword.checked = false
            open()
        }

        /// A new connection uses the server of the saved one: 服务器 / 端口 / 加密 / 证书 are the same for
        /// every vehicle and are folded away under 高级, so the customer only enters 车辆编号 and 密码
        function openNew() {
            const list = hhu4G.configs
            const base = list.length > 0 ? list[Math.max(0, hhu4G.activeIndex)] : null
            openFor(-1, { name: "", host: base ? base.host : "", port: base ? base.port : 7000,
                          tls: base ? base.tls : true, caFile: base ? base.caFile : "", vehicle: "" })
        }

        function _savedName() {
            return nameEdit.text.trim() !== "" ? nameEdit.text : "4G " + vehicleEdit.text.trim()
        }

        function save() {
            const index = hhu4G.saveConfig(editIndex, {
                name:     _savedName(),
                host:     hostEdit.text,
                port:     parseInt(portEdit.text) || 7000,
                tls:      tlsSwitch.checked,
                caFile:   caEdit.text,
                vehicle:  vehicleEdit.text,
                password: passwordEdit.text
            })
            close()
            return index
        }

        readonly property var  _missing: {
            let list = []
            if (vehicleEdit.text.trim() === "")             list.push(qsTr("Vehicle number"))
            if (passwordEdit.text === "" && !hasPassword)   list.push(qsTr("Password"))
            if (hostEdit.text.trim() === "")                list.push(qsTr("Server address (under Advanced)"))
            return list
        }
        readonly property bool _complete: _missing.length === 0

        QGCPalette { id: dlgPal; colorGroupEnabled: true }

        background: Rectangle {
            color:          dlgPal.window
            radius:         ScreenTools.defaultFontPixelHeight * 0.5
            border.color:   "#004B97"
            border.width:   2
        }

        FileDialog {
            id:             caDialog
            title:          qsTr("Server CA certificate")
            nameFilters:    [ qsTr("Certificates (*.crt *.pem *.cer)"), qsTr("All files (*)") ]
            onAccepted:     caEdit.text = selectedFile.toString().replace(/^file:\/{3}/, "")
        }

        contentItem: GridLayout {
            columns:        2
            columnSpacing:  ScreenTools.defaultFontPixelWidth
            rowSpacing:     ScreenTools.defaultFontPixelHeight * 0.4

            QGCLabel {
                Layout.columnSpan:  2
                text:               fourGDialog.editIndex < 0 ? qsTr("Add a 4G connection") : qsTr("Edit the 4G connection")
                font.bold:          true
                font.pixelSize:     HHUStyle.px(20)
            }

            QGCLabel { text: qsTr("Name"); font.pixelSize: HHUStyle.bodyFontSize }
            QGCTextField { id: nameEdit; font.pixelSize: HHUStyle.bodyFontSize; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 30; placeholderText: qsTr("4G + vehicle number") }

            QGCLabel { text: qsTr("Vehicle number"); font.pixelSize: HHUStyle.bodyFontSize }
            QGCTextField { id: vehicleEdit; font.pixelSize: HHUStyle.bodyFontSize; Layout.fillWidth: true }

            QGCLabel { text: qsTr("Password"); font.pixelSize: HHUStyle.bodyFontSize }
            RowLayout {
                QGCTextField {
                    id:                 passwordEdit
                    Layout.fillWidth:   true
                    Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 24
                    font.pixelSize:     HHUStyle.bodyFontSize
                    echoMode:           showPassword.checked ? TextInput.Normal : TextInput.Password
                    placeholderText:    fourGDialog.hasPassword ? qsTr("Saved (leave empty to keep)") : ""
                }
                QGCCheckBox { id: showPassword; text: qsTr("Show"); font.pixelSize: HHUStyle.bodyFontSize }
            }

            // encryption state in one line; details for after-sales below
            QGCLabel {
                Layout.columnSpan:  2
                text:               tlsSwitch.checked ? (caEdit.text === "" ? qsTr("Encryption on · factory preset, nothing to set")
                                                                            : qsTr("Encryption on · own certificate"))
                                                      : qsTr("Encryption off")
                color:              tlsSwitch.checked ? "#1E8E3E" : "#D32F2F"
                font.pixelSize:     HHUStyle.bodyFontSize
            }

            QGCLabel {
                Layout.columnSpan:  2
                text:               (fourGDialog.advanced ? "▾ " : "▸ ") + qsTr("Advanced (after-sales)")
                font.bold:          true
                font.pixelSize:     HHUStyle.bodyFontSize
                color:              "#004B97"
                MouseArea {
                    anchors.fill:   parent
                    cursorShape:    Qt.PointingHandCursor
                    onClicked:      fourGDialog.advanced = !fourGDialog.advanced
                }
            }

            QGCLabel { text: qsTr("Server address"); visible: fourGDialog.advanced; font.pixelSize: HHUStyle.bodyFontSize }
            QGCTextField { id: hostEdit; font.pixelSize: HHUStyle.bodyFontSize; visible: fourGDialog.advanced; Layout.fillWidth: true; placeholderText: "gcs.example.com" }

            QGCLabel { text: qsTr("Port"); visible: fourGDialog.advanced; font.pixelSize: HHUStyle.bodyFontSize }
            QGCTextField { id: portEdit; font.pixelSize: HHUStyle.bodyFontSize; visible: fourGDialog.advanced; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10; validator: IntValidator { bottom: 1; top: 65535 } }

            QGCLabel { text: qsTr("Encryption (TLS)"); visible: fourGDialog.advanced; font.pixelSize: HHUStyle.bodyFontSize }
            QGCCheckBoxSlider { id: tlsSwitch; visible: fourGDialog.advanced }

            QGCLabel {
                Layout.columnSpan:  2
                visible:            fourGDialog.advanced && !tlsSwitch.checked
                text:               qsTr("Without encryption the password is sent as plain text.")
                font.pixelSize:     HHUStyle.bodyFontSize
                color:              "#B42318"
            }

            QGCLabel { text: qsTr("CA certificate"); visible: fourGDialog.advanced && tlsSwitch.checked; font.pixelSize: HHUStyle.bodyFontSize }
            RowLayout {
                visible: fourGDialog.advanced && tlsSwitch.checked
                QGCTextField { id: caEdit; font.pixelSize: HHUStyle.bodyFontSize; Layout.fillWidth: true; placeholderText: qsTr("Built in (factory preset)") }
                QGCButton { text: qsTr("Import…"); onClicked: caDialog.open() }
            }

            // why 保存 is grey
            QGCLabel {
                Layout.columnSpan:  2
                visible:            !fourGDialog._complete
                text:               qsTr("Still to fill in: %1").arg(fourGDialog._missing.join(qsTr(", ")))
                color:              "#B42318"
                font.pixelSize:     HHUStyle.bodyFontSize
            }

            RowLayout {
                Layout.columnSpan:  2
                Layout.alignment:   Qt.AlignRight
                QGCButton { text: qsTr("Cancel"); onClicked: fourGDialog.close() }
                QGCButton {
                    text:       qsTr("Save")
                    enabled:    fourGDialog._complete
                    onClicked:  fourGDialog.save()
                }
                QGCButton {
                    text:       qsTr("Save and connect")
                    primary:    true
                    enabled:    fourGDialog._complete
                    onClicked: {
                        const name = fourGDialog._savedName()
                        const index = fourGDialog.save()
                        mainWindow.hhuConnectExclusive(fourGDialog.parent, name, function() { hhu4G.connectTo(index) })
                    }
                }
            }
        }
    }
}

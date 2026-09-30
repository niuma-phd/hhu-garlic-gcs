import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
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
                spacing:            ScreenTools.defaultFontPixelWidth

                readonly property bool _isActive: hhu4G.activeIndex === index

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QGCLabel {
                        text:       modelData.name + (modelData.tls ? "" : "  " + qsTr("(not encrypted)"))
                        font.bold:  configRow._isActive
                    }
                    QGCLabel {
                        text:           qsTr("%1:%2 · vehicle %3").arg(modelData.host).arg(modelData.port).arg(modelData.vehicle)
                        font.pointSize: ScreenTools.smallFontPointSize
                        color:          "#5B6B7F"
                    }
                    QGCLabel {
                        Layout.fillWidth: true
                        visible:        configRow._isActive && hhu4G.statusText !== ""
                        text:           hhu4G.statusText + (hhu4G.state === "retrying" && hhu4G.retryInSec > 0 ? qsTr(" (retry in %1 s)").arg(hhu4G.retryInSec) : "")
                        font.pointSize: ScreenTools.smallFontPointSize
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
                    onClicked:  QGroundControl.showMessageDialog(configRow, qsTr("Delete"),
                                                                 qsTr("Delete the 4G connection \"%1\"?").arg(modelData.name),
                                                                 Dialog.Yes | Dialog.Cancel,
                                                                 function() { hhu4G.removeConfig(index) })
                }
                QGCButton {
                    text:       configRow._isActive ? qsTr("Disconnect") : qsTr("Connect")
                    primary:    !configRow._isActive
                    onClicked:  configRow._isActive ? hhu4G.disconnectLink() : hhu4G.connectTo(index)
                }
            }
        }

        LabelledButton {
            Layout.fillWidth:   true
            label:              qsTr("Add a 4G connection")
            buttonText:         qsTr("Add")
            onClicked:          fourGDialog.openFor(-1, { name: "4G", host: "", port: 7000, tls: true, caFile: "", vehicle: "" })
        }

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            text:                   qsTr("Through 4G the vehicle is reached via the server. The link can be slow or drop out: it is not an emergency stop. Stop the vehicle with its emergency stop button or the remote control.")
            font.pointSize:         ScreenTools.smallFontPointSize
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
        font.pointSize:     ScreenTools.smallFontPointSize
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

        property int    editIndex: -1
        property bool   hasPassword: false

        function openFor(index, config) {
            editIndex = index
            nameEdit.text = config.name || ""
            hostEdit.text = config.host || ""
            portEdit.text = (config.port || 7000).toString()
            tlsSwitch.checked = config.tls !== false
            caEdit.text = config.caFile || ""
            vehicleEdit.text = config.vehicle || ""
            passwordEdit.text = ""
            hasPassword = !!config.hasPassword
            showPassword.checked = false
            open()
        }

        function save() {
            const index = hhu4G.saveConfig(editIndex, {
                name:     nameEdit.text,
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

        readonly property bool _complete: hostEdit.text.trim() !== "" && vehicleEdit.text.trim() !== "" && (passwordEdit.text !== "" || hasPassword)

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
                font.pointSize:     ScreenTools.mediumFontPointSize
            }

            QGCLabel { text: qsTr("Name") }
            QGCTextField { id: nameEdit; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 30 }

            QGCLabel { text: qsTr("Server address") }
            QGCTextField { id: hostEdit; Layout.fillWidth: true; placeholderText: "gcs.example.com" }

            QGCLabel { text: qsTr("Port") }
            QGCTextField { id: portEdit; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10; validator: IntValidator { bottom: 1; top: 65535 } }

            QGCLabel { text: qsTr("Encryption (TLS)") }
            QGCCheckBoxSlider { id: tlsSwitch }

            QGCLabel {
                Layout.columnSpan:  2
                visible:            !tlsSwitch.checked
                text:               qsTr("Without encryption the password is sent as plain text.")
                color:              "#B42318"
            }

            QGCLabel { text: qsTr("CA certificate"); visible: tlsSwitch.checked }
            RowLayout {
                visible: tlsSwitch.checked
                QGCTextField { id: caEdit; Layout.fillWidth: true; placeholderText: qsTr("Optional, for a private server") }
                QGCButton { text: qsTr("Import…"); onClicked: caDialog.open() }
            }

            QGCLabel { text: qsTr("Vehicle number") }
            QGCTextField { id: vehicleEdit; Layout.fillWidth: true }

            QGCLabel { text: qsTr("Password") }
            RowLayout {
                QGCTextField {
                    id:                 passwordEdit
                    Layout.fillWidth:   true
                    echoMode:           showPassword.checked ? TextInput.Normal : TextInput.Password
                    placeholderText:    fourGDialog.hasPassword ? qsTr("Saved (leave empty to keep)") : ""
                }
                QGCCheckBox { id: showPassword; text: qsTr("Show") }
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
                    onClicked:  hhu4G.connectTo(fourGDialog.save())
                }
            }
        }
    }
}

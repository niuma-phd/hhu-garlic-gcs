import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings

// HHU replacement of the generated QGroundControl/AppSettings/NTRIPSettings.qml
// RTK 差分 (需求说明 V1.0 §3.5): provider presets, account, mountpoint (typed or from the list),
// 测试连接, 保存 (after a successful test; 4G: to the server, otherwise corrections are forwarded from
// this computer by QGC's NTRIP client), 清除账号. No separate correction status: the status bar
// 定位 shows the result.
SettingsPage {
    objectName: "settingsPage_HHUNtrip"

    readonly property var _account: hhuNtrip.account
    readonly property bool _via4G: hhu4G.active
    property bool _saveAfterTest: false
    property string _result
    property color _resultColor: "#5B6B7F"

    function _fill() {
        const acc = hhuNtrip.account
        const providers = hhuNtrip.providers
        let index = providers.length    // 自定义
        for (let i = 0; i < providers.length; i++) {
            if (providers[i].name === acc.provider) index = i
        }
        providerCombo.currentIndex = acc.host ? index : 0
        hostEdit.text = acc.host || (providers.length > 0 ? providers[0].host : "")
        portEdit.text = (acc.port || (providers.length > 0 ? providers[0].port : 2101)).toString()
        userEdit.text = acc.user || ""
        mountEdit.text = acc.mount || ""
        passwordEdit.text = ""
    }

    Component.onCompleted: _fill()

    function _test(thenSave) {
        _saveAfterTest = thenSave
        _result = qsTr("Testing…")
        _resultColor = "#5B6B7F"
        hhuNtrip.test(hostEdit.text, parseInt(portEdit.text), userEdit.text, passwordEdit.text, mountEdit.text)
    }

    function _accountFromForm() {
        return {
            provider: providerCombo.currentIndex < hhuNtrip.providers.length ? hhuNtrip.providers[providerCombo.currentIndex].name : "",
            host:     hostEdit.text.trim(),
            port:     parseInt(portEdit.text),
            user:     userEdit.text.trim(),
            password: passwordEdit.text,
            mount:    mountEdit.text.trim()
        }
    }

    function _save() {
        const acc = _accountFromForm()
        if (_via4G) {
            _result = qsTr("Sending the account to the server…")
            hhu4G.updateNtrip({ host: acc.host, port: acc.port, user: acc.user, mount: acc.mount,
                                password: acc.password !== "" ? acc.password : hhuNtrip.password() })
            pending4GAccount = acc
        } else {
            hhuNtrip.save(acc)
            hhuNtrip.applyForwarding(true)
            _result = qsTr("Saved. Corrections are sent to the vehicle from this computer.")
            _resultColor = "#1F8A3B"
        }
    }

    property var pending4GAccount: null

    Connections {
        target: hhuNtrip
        function onTestFinished(code, message) {
            _result = message
            _resultColor = code === "ok" ? "#1F8A3B" : "#B42318"
            if (code === "ok" && _saveAfterTest) {
                _save()
            }
            _saveAfterTest = false
        }
    }

    Connections {
        target: hhu4G
        function onNtripUpdateFinished(ok, message) {
            if (ok && pending4GAccount) {
                hhuNtrip.save(pending4GAccount)
            }
            pending4GAccount = null
            _result = ok ? qsTr("RTK account updated") : message
            _resultColor = ok ? "#1F8A3B" : "#B42318"
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("RTK correction account")

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            wrapMode:               Text.WordWrap
            font.pointSize:         ScreenTools.smallFontPointSize
            text: _via4G ? qsTr("4G connection: the account is sent to the server, which delivers the corrections to the vehicle.")
                         : qsTr("Radio / LAN connection: this computer logs in to the RTK service and forwards the corrections to the vehicle. The computer needs internet access.")
        }

        LabelledComboBox {
            id:                 providerCombo
            Layout.fillWidth:   true
            label:              qsTr("Provider")
            model:              hhuNtrip.providers.map(p => p.name).concat([ qsTr("Custom") ])
            onActivated: (index) => {
                if (index < hhuNtrip.providers.length) {
                    hostEdit.text = hhuNtrip.providers[index].host
                    portEdit.text = hhuNtrip.providers[index].port.toString()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            QGCLabel { text: qsTr("Address"); Layout.fillWidth: true }
            QGCTextField { id: hostEdit; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 28 }
        }
        RowLayout {
            Layout.fillWidth: true
            QGCLabel { text: qsTr("Port"); Layout.fillWidth: true }
            QGCTextField { id: portEdit; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10; validator: IntValidator { bottom: 1; top: 65535 } }
        }
        RowLayout {
            Layout.fillWidth: true
            QGCLabel { text: qsTr("User name"); Layout.fillWidth: true }
            QGCTextField { id: userEdit; Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 28 }
        }
        RowLayout {
            Layout.fillWidth: true
            QGCLabel { text: qsTr("Password"); Layout.fillWidth: true }
            QGCTextField {
                id:                     passwordEdit
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 20
                echoMode:               showPassword.checked ? TextInput.Normal : TextInput.Password
                placeholderText:        _account.hasPassword ? qsTr("Saved") : ""
            }
            QGCCheckBox { id: showPassword; text: qsTr("Show") }
        }
        RowLayout {
            Layout.fillWidth: true
            QGCLabel { text: qsTr("Mountpoint"); Layout.fillWidth: true }
            // typed, or picked from the list fetched from the caster (QGCComboBox cannot be edited)
            QGCTextField {
                id:                     mountEdit
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 14
            }
            QGCComboBox {
                visible:                hhuNtrip.mountpoints.length > 0
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 14
                model:                  [ qsTr("Choose…") ].concat(hhuNtrip.mountpoints)
                onActivated: (index) => {
                    if (index > 0) {
                        mountEdit.text = hhuNtrip.mountpoints[index - 1]
                    }
                    currentIndex = 0
                }
            }
            QGCButton {
                text:       qsTr("Get list")
                enabled:    !hhuNtrip.testing && hostEdit.text !== ""
                onClicked: {
                    _result = qsTr("Getting the mountpoint list…")
                    _resultColor = "#5B6B7F"
                    hhuNtrip.fetchMountpoints(hostEdit.text, parseInt(portEdit.text), userEdit.text, passwordEdit.text)
                }
            }
        }

        QGCLabel {
            Layout.fillWidth:       true
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 60
            visible:                _result !== ""
            text:                   _result
            color:                  _resultColor
            wrapMode:               Text.WordWrap
        }

        RowLayout {
            Layout.alignment:   Qt.AlignRight
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCButton {
                text:       qsTr("Clear account")
                enabled:    !!_account.host
                onClicked:  QGroundControl.showMessageDialog(hostEdit, qsTr("Clear account"),
                                                             qsTr("Remove the RTK account saved on this computer?"),
                                                             Dialog.Yes | Dialog.Cancel,
                                                             function() { hhuNtrip.clear(); _fill(); _result = "" })
            }
            QGCButton {
                text:       qsTr("Test connection")
                enabled:    !hhuNtrip.testing && hostEdit.text !== "" && mountEdit.text !== ""
                onClicked:  _test(false)
            }
            QGCButton {
                text:       qsTr("Save")
                primary:    true
                enabled:    !hhuNtrip.testing && hostEdit.text !== "" && mountEdit.text !== "" && userEdit.text !== ""
                            && (passwordEdit.text !== "" || _account.hasPassword)
                            && !(_via4G && (hhu4G.state !== "online" || hhu4G.readOnly))
                onClicked:  _test(true)     // saved only after a successful test
            }
        }

        QGCLabel {
            Layout.fillWidth:       true
            visible:                _via4G && hhu4G.readOnly
            text:                   qsTr("Read-only connection: the RTK account cannot be changed.")
            color:                  "#B7791F"
        }
    }
}

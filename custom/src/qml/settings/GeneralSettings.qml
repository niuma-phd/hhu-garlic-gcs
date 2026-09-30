import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.FactControls
import QGroundControl.Controls
import QGroundControl.AppSettings

// HHU replacement of the generated QGroundControl/AppSettings/GeneralSettings.qml
// 通用 (需求说明 V1.0 §3.4): 语言、单位、界面缩放、字号、户外高对比度, plus the alarm volume.
SettingsPage {
    objectName: "settingsPage_General"

    property var _appSettings:      QGroundControl.settingsManager.appSettings
    property var _unitsSettings:    QGroundControl.settingsManager.unitsSettings

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Display")

        LabelledFactComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Language")
            fact:               _appSettings.qLocaleLanguage
            indexModel:         false
        }

        LabelledFactIncrementer {
            Layout.fillWidth:   true
            label:              qsTr("Interface scale")
            fact:               _appSettings.uiScalePercent
        }

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Font size")
            model:              [ qsTr("Standard"), qsTr("Large"), qsTr("Extra large") ]
            currentIndex:       hhuSettings.fontSize
            onActivated:        (index) => hhuSettings.fontSize = index
        }

        QGCLabel {
            Layout.fillWidth:   true
            text:               qsTr("Font size applies to the status bar, work buttons, cards and alarms. Interface scale enlarges everything.")
            font.pointSize:     ScreenTools.smallFontPointSize
            wrapMode:           Text.WordWrap
        }

        QGCCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Map labels (place names, roads)")
            checked:            hhuSettings.mapLabels
            onClicked:          hhuSettings.mapLabels = checked
        }

        QGCCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Outdoor high contrast")
            checked:            hhuSettings.highContrast
            onClicked:          hhuSettings.highContrast = checked
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Units")

        LabelledFactComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Speed")
            fact:               _unitsSettings.speedUnits
            indexModel:         false
        }

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Area")
            model:              [ qsTr("Mu"), qsTr("Hectare") ]
            currentIndex:       hhuSettings.areaUnit
            onActivated:        (index) => hhuSettings.areaUnit = index
        }

        LabelledLabel {
            Layout.fillWidth:   true
            label:              qsTr("Distance")
            labelText:          qsTr("Meters")
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Sound")

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            FactTextFieldSlider {
                Layout.fillWidth:       true
                label:                  qsTr("Alarm volume")
                fact:                   _appSettings.audioVolume
                showEnableCheckbox:     true
                enableCheckBoxChecked:  !_appSettings.audioMuted.rawValue
                onEnableCheckboxClicked: {
                    if (enableCheckBoxChecked && _appSettings.audioVolume.rawValue <= 0) {
                        _appSettings.audioVolume.rawValue = 75
                    }
                    _appSettings.audioMuted.rawValue = !enableCheckBoxChecked
                }
            }
            QGCButton {
                text:       qsTr("Test")
                enabled:    !_appSettings.audioMuted.rawValue && _appSettings.audioVolume.rawValue > 0
                onClicked:  QGroundControl.testAudioOutput()
            }
        }
    }
}

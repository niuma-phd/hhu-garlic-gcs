import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// 地块管理 on the 航线 page (需求说明 V1.0 §3.3): list with name, area, last work time, search,
/// new / rename / copy / delete; a click loads the field's geofence and route into the editor.
/// saveCurrent() stores the editor contents into the open field (or asks for a new field first).
Popup {
    id:             root
    parent:         mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
    anchors.centerIn: parent
    modal:          true
    focus:          true
    closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding:        ScreenTools.defaultFontPixelWidth * 2
    width:          Math.min(ScreenTools.defaultFontPixelWidth * 80, parent ? parent.width * 0.9 : 800)
    height:         Math.min(ScreenTools.defaultFontPixelHeight * 34, parent ? parent.height * 0.9 : 600)

    property var planMasterController

    readonly property var _fenceController: planMasterController ? planMasterController.geoFenceController : null

    HHUFence { id: fence; geoFenceController: root._fenceController }

    // ---- Operations --------------------------------------------------------------------------

    function _confirmDiscard(action) {
        if (planMasterController.dirtyForSave) {
            QGroundControl.showMessageDialog(root, qsTr("Fields"),
                                             qsTr("The route being edited has unsaved changes. Discard them?"),
                                             Dialog.Yes | Dialog.Cancel, action)
        } else {
            action()
        }
    }

    function load(id) {
        _confirmDiscard(function() {
            hhuFields.currentId = id
            if (hhuFields.hasPlan(id)) {
                planMasterController.loadFromFile(hhuFields.planFile(id))
            } else {
                planMasterController.removeAll()
            }
            root.close()
        })
    }

    /// Saves the editor contents into the open field; without one, asks for a new field
    function saveCurrent() {
        if (hhuFields.currentId === "") {
            nameDialog.openFor("saveNew", "", "")
            return
        }
        _saveInto(hhuFields.currentId)
    }

    function _saveInto(id) {
        if (planMasterController.saveToFile(hhuFields.planFile(id))) {
            hhuFields.setArea(id, fence.area())
            hhuFields.touch(id)
        }
    }

    function _formatDate(iso) {
        if (!iso) return qsTr("Never")
        const d = new Date(iso)
        return isNaN(d.getTime()) ? iso : d.toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm")
    }

    readonly property var _shown: hhuFields.fields.filter(f => searchField.text.trim() === "" || f.name.indexOf(searchField.text.trim()) >= 0)

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    background: Rectangle {
        color:          qgcPal.window
        radius:         ScreenTools.defaultFontPixelHeight * 0.5
        border.color:   "#004B97"
        border.width:   2
    }

    contentItem: ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight * 0.6

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel {
                text:               qsTr("Fields")
                font.pointSize:     ScreenTools.largeFontPointSize * hhuSettings.fontScale
                font.bold:          true
                color:              "#004B97"
            }
            QGCTextField {
                id:                 searchField
                Layout.fillWidth:   true
                placeholderText:    qsTr("Search by name")
            }
            QGCButton {
                text:       qsTr("New field")
                primary:    true
                onClicked:  nameDialog.openFor("new", "", "")
            }
            QGCButton {
                text:       qsTr("Close")
                onClicked:  root.close()
            }
        }

        // Open field: work width
        RowLayout {
            Layout.fillWidth:   true
            visible:            hhuFields.currentId !== ""
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel {
                text:       qsTr("Open field: %1").arg(hhuFields.current.name || "")
                font.bold:  true
            }
            Item { Layout.fillWidth: true }
            QGCLabel { text: qsTr("Work width (m)") }
            QGCTextField {
                id:                     swathField
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 8
                text:                   (hhuFields.current.swath || 0).toString()
                validator:              DoubleValidator { bottom: 0; top: 50; decimals: 2 }
                onEditingFinished:      if (acceptableInput) hhuFields.setSwath(hhuFields.currentId, parseFloat(text))
            }
        }

        Rectangle {
            Layout.fillWidth:   true
            height:             1
            color:              "#D9E3EF"
        }

        QGCLabel {
            Layout.fillWidth:       true
            visible:                root._shown.length === 0
            horizontalAlignment:    Text.AlignHCenter
            text:                   hhuFields.fields.length === 0
                                    ? qsTr("No fields yet. Draw the field boundary as a geofence and the route, then tap Save; or create a field here first.")
                                    : qsTr("No field matches the search.")
            wrapMode:               Text.WordWrap
        }

        ListView {
            id:                 list
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            clip:               true
            model:              root._shown
            spacing:            ScreenTools.defaultFontPixelHeight * 0.3

            delegate: Rectangle {
                width:      list.width
                height:     row.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.6
                radius:     ScreenTools.defaultFontPixelHeight * 0.3
                color:      modelData.id === hhuFields.currentId ? "#E6EEF7" : (rowMouse.containsMouse ? "#F2F5F9" : "transparent")
                border.color: modelData.id === hhuFields.currentId ? "#004B97" : "#D9E3EF"
                border.width: 1

                MouseArea {
                    id:             rowMouse
                    anchors.fill:   parent
                    hoverEnabled:   true
                    cursorShape:    Qt.PointingHandCursor
                    onClicked:      root.load(modelData.id)
                }

                RowLayout {
                    id:                 row
                    anchors.left:       parent.left
                    anchors.right:      parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins:    ScreenTools.defaultFontPixelWidth
                    spacing:            ScreenTools.defaultFontPixelWidth

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QGCLabel {
                            text:               modelData.name
                            font.bold:          true
                            font.pointSize:     ScreenTools.mediumFontPointSize * hhuSettings.fontScale
                        }
                        QGCLabel {
                            text: qsTr("Area %1 · Width %2 m · Last work %3")
                                  .arg(hhuSettings.areaUnit >= 0 ? hhuSettings.formatArea(modelData.area || 0) : "")
                                  .arg((modelData.swath || 0).toFixed(2))
                                  .arg(root._formatDate(modelData.lastWork))
                            color:          "#5B6B7F"
                            font.pointSize: ScreenTools.smallFontPointSize * hhuSettings.fontScale
                        }
                    }
                    QGCButton {
                        text:       qsTr("Rename")
                        onClicked:  nameDialog.openFor("rename", modelData.id, modelData.name)
                    }
                    QGCButton {
                        text:       qsTr("Copy")
                        onClicked:  hhuFields.duplicate(modelData.id)
                    }
                    QGCButton {
                        text:       qsTr("Delete")
                        onClicked:  QGroundControl.showMessageDialog(root, qsTr("Delete field"),
                                                                     qsTr("Delete field \"%1\" with its boundary and route? Work records are kept.").arg(modelData.name),
                                                                     Dialog.Yes | Dialog.Cancel,
                                                                     function() { hhuFields.remove(modelData.id) })
                    }
                }
            }
        }
    }

    // ---- Name dialog (new / rename / save as new field) ---------------------------------------

    Popup {
        id:             nameDialog
        parent:         mainWindow.contentItem  // Overlay.overlay is not resolved inside Loader-created pages
        anchors.centerIn: parent
        modal:          true
        focus:          true
        padding:        ScreenTools.defaultFontPixelWidth * 2

        property string mode    ///< "new", "rename", "saveNew"
        property string fieldId

        function openFor(mode, id, name) {
            nameDialog.mode = mode
            nameDialog.fieldId = id
            nameInput.text = name
            newSwath.text = "1.2"
            errorLabel.text = ""
            open()
            nameInput.forceActiveFocus()
        }

        function accept() {
            const name = nameInput.text.trim()
            if (name === "") {
                errorLabel.text = qsTr("Enter a name.")
                return
            }
            if (hhuFields.nameExists(name, fieldId)) {
                errorLabel.text = qsTr("A field with this name already exists.")
                return
            }
            const swath = parseFloat(newSwath.text) || 0
            close()
            if (mode === "rename") {
                hhuFields.rename(fieldId, name)
            } else if (mode === "saveNew") {
                const id = hhuFields.create(name, swath)
                hhuFields.currentId = id
                root._saveInto(id)
            } else {
                root._confirmDiscard(function() {
                    const id = hhuFields.create(name, swath)
                    hhuFields.currentId = id
                    root.planMasterController.removeAll()
                    root.close()
                })
            }
        }

        background: Rectangle {
            color:          qgcPal.window
            radius:         ScreenTools.defaultFontPixelHeight * 0.5
            border.color:   "#004B97"
            border.width:   2
        }

        contentItem: ColumnLayout {
            spacing: ScreenTools.defaultFontPixelHeight * 0.6

            QGCLabel {
                text: nameDialog.mode === "rename" ? qsTr("Rename field")
                                                   : (nameDialog.mode === "saveNew" ? qsTr("Save as new field") : qsTr("New field"))
                font.bold:      true
                font.pointSize: ScreenTools.mediumFontPointSize * hhuSettings.fontScale
            }
            RowLayout {
                spacing: ScreenTools.defaultFontPixelWidth
                QGCLabel { text: qsTr("Name") }
                QGCTextField {
                    id:                     nameInput
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 30
                    onAccepted:             nameDialog.accept()
                }
            }
            RowLayout {
                visible: nameDialog.mode !== "rename"
                spacing: ScreenTools.defaultFontPixelWidth
                QGCLabel { text: qsTr("Work width (m)") }
                QGCTextField {
                    id:                     newSwath
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 8
                    validator:              DoubleValidator { bottom: 0; top: 50; decimals: 2 }
                }
            }
            QGCLabel {
                id:         errorLabel
                visible:    text !== ""
                color:      "#B42318"
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                QGCButton { text: qsTr("Cancel"); onClicked: nameDialog.close() }
                QGCButton { text: qsTr("OK"); primary: true; onClicked: nameDialog.accept() }
            }
        }
    }
}

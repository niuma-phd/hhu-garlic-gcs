import QtQuick

// HHU override for engineer-only tool pages (vehicle setup, analyze tools).
// Any deep link into these pages returns straight to the main view.
Item {
    function showParametersPanel() { }
    function showVehicleComponentPanel(vehicleComponent) { }

    Component.onCompleted: Qt.callLater(mainWindow.showFlyView)
}

import QtQuick

import QGroundControl.Controls

/// Line icon of the HHU set (res/icons/ui), colored.
QGCColoredImage {
    property string name
    property real   size: 24

    source:             name !== "" ? "qrc:/hhu/icons/" + name + ".svg" : ""
    width:              size * HHUStyle.s
    height:             width
    sourceSize.height:  height
    fillMode:           Image.PreserveAspectFit
    color:              HHUStyle.text
}

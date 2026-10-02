import QtQuick

/// Text in the HHU design font. `size` is the design pixel size (scaled by 字号);
/// `number` switches to the Barlow digits (tabular) used for values.
Text {
    property real size:     16
    property bool number:   false
    property bool bold:     false

    color:                  HHUStyle.text
    font.family:            number ? HHUStyle.numberFamily : HHUStyle.fontFamily
    font.pixelSize:         HHUStyle.px(size)
    font.weight:            (number || bold) ? Font.Bold : Font.Normal
    font.features:          number ? { "tnum": 1 } : ({})
    verticalAlignment:      Text.AlignVCenter
    textFormat:             Text.PlainText
}

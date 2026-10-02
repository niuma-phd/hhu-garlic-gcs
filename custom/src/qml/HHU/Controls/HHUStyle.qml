pragma Singleton
import QtQuick

/// Design tokens of the HHU ground station UI (设计稿 design_handoff_ground_station, §4).
/// Sizes are in logical pixels at the 1366×768 design size; `s` applies the 字号 setting (×1.15 / ×1.3).
/// `compact` (1280×720 at 150 %, i.e. about 853×480) is set from the main window size by HHUStatusBar.
QtObject {
    // ---- Colors ---------------------------------------------------------------------------
    readonly property color blue:           "#004B97"
    readonly property color blueLight:      "#E8F0F9"
    readonly property color green:          "#1E8E3E"
    readonly property color greenLight:     "#E6F4EA"
    readonly property color yellow:         "#F2A900"
    readonly property color yellowText:     "#2B1F00"
    readonly property color yellowLight:    "#FFF4D6"
    readonly property color red:            "#D32F2F"
    readonly property color redLight:       "#FDECEC"
    readonly property color text:           "#14202E"
    readonly property color text2:          "#2E3B4A"
    readonly property color text3:          "#4A5868"
    readonly property color neutral:        "#8995A3"
    readonly property color disabledBg:     "#C9D0D8"
    readonly property color disabledText:   "#4A5868"
    readonly property color border:         "#C9D2DC"
    readonly property color divider:        "#E1E6EC"
    readonly property color settingsBorder: "#D5DBE3"
    readonly property color grey:           "#F3F5F8"
    readonly property color grey2:          "#EEF2F6"
    readonly property color track:          "#FF8A00"
    readonly property color fence:          "#39A0FF"
    readonly property color shadow:         "#4D000000"     ///< 30 % black, floating cards
    readonly property color dim:            "#9E0E1620"     ///< dialog backdrop

    // ---- Fonts ----------------------------------------------------------------------------
    readonly property string fontFamily:    "HarmonyOS Sans SC"
    readonly property string numberFamily:  "Barlow"

    // ---- Scale ----------------------------------------------------------------------------
    property bool compact: false
    readonly property real s: hhuSettings.fontScale

    /// Font pixel size: design px × 字号
    function px(size) { return Math.round(size * s) }

    readonly property real barH:        (compact ? 52 : 60) * s
    readonly property real tabH:        (compact ? 40 : 46) * s
    readonly property real tabPad:      (compact ? 14 : 20) * s
    readonly property real statusPad:   (compact ? 10 : 16) * s
    readonly property real btnH:        (compact ? 56 : 72) * s
    readonly property real btnFont:     (compact ? 18 : 22) * s
    readonly property real cardW:       (compact ? 250 : 320) * s
    readonly property real cardPad:     (compact ? 12 : 16) * s
    readonly property real pctFont:     (compact ? 32 : 44) * s
    readonly property real planPanelW:  (compact ? 320 : 384) * s
    readonly property real bannerW:     640 * s
    readonly property real margin:      16 * s
    readonly property real touch:       48 * s      ///< common button height (44 minimum)
    readonly property real radiusCtl:   10 * s
    readonly property real radiusCard:  14 * s
    readonly property real radiusDlg:   18 * s
}

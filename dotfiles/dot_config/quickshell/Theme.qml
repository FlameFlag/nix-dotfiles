pragma Singleton
import QtQuick

// Catppuccin + Neobrutalism tokens — supports live flavor/accent switching
// Design system ported from flameflag-site: grain texture, beveled borders,
// multi-level shadow depths, and full 4-flavor × 14-accent palette.
QtObject {
    property string flavor: "frappe"
    property string accentName: "blue"

    readonly property var flavorNames: ["latte", "frappe", "macchiato", "mocha"]
    readonly property var flavorLabels: ({ "latte": "LATTE", "frappe": "FRAPPE", "macchiato": "MACCHIATO", "mocha": "MOCHA" })
    readonly property var accentNames: ["blue", "red", "green", "yellow", "peach", "mauve", "pink", "teal", "lavender", "flamingo", "rosewater", "sapphire", "sky", "maroon"]

    readonly property var palettes: ({
        "latte":     { base: "#eff1f5", mantle: "#e6e9ef", crust: "#dce0e8", surface0: "#ccd0da", surface1: "#bcc0cc", surface2: "#acb0be", overlay0: "#9ca0b0", overlay1: "#8c8fa1", overlay2: "#7c7f93", subtext0: "#6c6f85", subtext1: "#5c5f77", text: "#4c4f69", blue: "#1e66f5", red: "#d20f39", green: "#40a02b", yellow: "#df8e1d", peach: "#fe640b", mauve: "#8839ef", pink: "#ea76cb", teal: "#179299", lavender: "#7287fd", flamingo: "#dd7878", rosewater: "#dc8a78", sapphire: "#209fb5", sky: "#04a5e5", maroon: "#e64553" },
        "frappe":    { base: "#303446", mantle: "#292c3c", crust: "#232634", surface0: "#414559", surface1: "#51576d", surface2: "#626880", overlay0: "#626880", overlay1: "#737994", overlay2: "#838ba7", subtext0: "#a5adce", subtext1: "#b5bfe2", text: "#c6d0f5", blue: "#8caaee", red: "#e78284", green: "#a6d189", yellow: "#e5c890", peach: "#ef9f76", mauve: "#ca9ee6", pink: "#f4b8e4", teal: "#81c8be", lavender: "#babbf1", flamingo: "#eebebe", rosewater: "#f2d5cf", sapphire: "#85c1dc", sky: "#99d1db", maroon: "#ea999c" },
        "macchiato": { base: "#24273a", mantle: "#1e2030", crust: "#181926", surface0: "#363a4f", surface1: "#494d64", surface2: "#5b6078", overlay0: "#6e738d", overlay1: "#8087a2", overlay2: "#939ab7", subtext0: "#a5adcb", subtext1: "#b8c0e0", text: "#cad3f5", blue: "#8aadf4", red: "#ed8796", green: "#a6da95", yellow: "#eed49f", peach: "#f5a97f", mauve: "#c6a0f6", pink: "#f5bde6", teal: "#8bd5ca", lavender: "#b7bdf8", flamingo: "#f0c6c6", rosewater: "#f4dbd6", sapphire: "#7dc4e4", sky: "#91d7e3", maroon: "#ee99a0" },
        "mocha":     { base: "#1e1e2e", mantle: "#181825", crust: "#11111b", surface0: "#313244", surface1: "#45475a", surface2: "#585b70", overlay0: "#6c7086", overlay1: "#7f849c", overlay2: "#9399b2", subtext0: "#a6adc8", subtext1: "#bac2de", text: "#cdd6f4", blue: "#89b4fa", red: "#f38ba8", green: "#a6e3a1", yellow: "#f9e2af", peach: "#fab387", mauve: "#cba6f7", pink: "#f5c2e7", teal: "#94e2d5", lavender: "#b4befe", flamingo: "#f2cdcd", rosewater: "#f5e0dc", sapphire: "#74c7ec", sky: "#89dceb", maroon: "#eba0ac" }
    })

    // Whether current flavor is light
    readonly property bool isLight: flavor === "latte"

    // Base palette (updated on flavor change)
    property color base: "#303446"
    property color mantle: "#292c3c"
    property color crust: "#232634"
    property color surface0: "#414559"
    property color surface1: "#51576d"
    property color surface2: "#626880"
    property color overlay0: "#626880"
    property color overlay1: "#737994"
    property color overlay2: "#838ba7"
    property color subtext0: "#a5adce"
    property color subtext1: "#b5bfe2"
    property color text: "#c6d0f5"

    // Accent colors (updated on flavor change)
    property color blue: "#8caaee"
    property color red: "#e78284"
    property color green: "#a6d189"
    property color yellow: "#e5c890"
    property color peach: "#ef9f76"
    property color mauve: "#ca9ee6"
    property color pink: "#f4b8e4"
    property color teal: "#81c8be"
    property color lavender: "#babbf1"
    property color flamingo: "#eebebe"
    property color rosewater: "#f2d5cf"
    property color sapphire: "#85c1dc"
    property color sky: "#99d1db"
    property color maroon: "#ea999c"

    // Active accent
    readonly property color accent: blue

    // --- Neobrutalism depth tokens (ported from flameflag-site) ---

    // Shadow color: accent mixed 70% with black (matches color-mix(in oklch, accent 70%, black))
    property color shadowColor: Qt.darker(accent, 2.2)

    // Standard shadow (6px — cards, bar)
    readonly property int shadowX: 6
    readonly property int shadowY: 6
    // Small shadow (3px — buttons, swatches)
    readonly property int shadowSmallX: 3
    readonly property int shadowSmallY: 3
    // Large shadow (8px — dialogs, elevated panels)
    readonly property int shadowLargeX: 8
    readonly property int shadowLargeY: 8

    // Bevel intensities (ported from flameflag-site)
    // Top/left highlight
    readonly property real bevelLightTop: 0.25
    readonly property real bevelLightLeft: 0.20
    // Bottom/right shadow
    readonly property real bevelDarkBottom: 0.12
    readonly property real bevelDarkRight: 0.15
    // Pressed inset
    readonly property real pressedInsetTop: 0.25
    readonly property real pressedInsetLeft: 0.20

    // Grain texture opacity (the repeating-conic-gradient dot pattern)
    readonly property real grainOpacity: 0.03

    // Site uses 3px borders with foreground color
    readonly property int borderWidth: 3
    property color borderColor: "#c6d0f5"
    // Beveled border colors (ported from flameflag-site color-mix)
    property color borderTopColor: Qt.lighter(borderColor, 1.45)
    property color borderLeftColor: Qt.lighter(borderColor, 1.40)
    property color borderBottomColor: Qt.darker(borderColor, 1.65)
    property color borderRightColor: Qt.darker(borderColor, 1.60)

    // Typography
    readonly property string fontHeading: "Montserrat"
    readonly property string fontBody: "Google Sans Flex"
    readonly property string fontMono: "JetBrains Mono"
    readonly property int fontWeightHeading: Font.DemiBold

    onFlavorChanged: _apply()
    onAccentNameChanged: _apply()

    function setTheme(f, a) {
        flavor = f
        accentName = a
    }

    function _apply() {
        var p = palettes[flavor]
        if (!p) return

        base = p.base
        mantle = p.mantle
        crust = p.crust
        surface0 = p.surface0
        surface1 = p.surface1
        surface2 = p.surface2
        overlay0 = p.overlay0
        overlay1 = p.overlay1
        overlay2 = p.overlay2
        subtext0 = p.subtext0
        subtext1 = p.subtext1
        text = p.text

        blue = p.blue
        red = p.red
        green = p.green
        yellow = p.yellow
        peach = p.peach
        mauve = p.mauve
        pink = p.pink
        teal = p.teal
        lavender = p.lavender
        flamingo = p.flamingo
        rosewater = p.rosewater
        sapphire = p.sapphire
        sky = p.sky
        maroon = p.maroon

        accent = p[accentName] || p.blue
        shadowColor = Qt.darker(accent, 2.2)
        borderColor = p.text
        borderTopColor = Qt.lighter(borderColor, 1.45)
        borderLeftColor = Qt.lighter(borderColor, 1.40)
        borderBottomColor = Qt.darker(borderColor, 1.65)
        borderRightColor = Qt.darker(borderColor, 1.60)
    }

    function accentColor(name) {
        var p = palettes[flavor]
        return p ? p[name] : "#8caaee"
    }

    function flavorPreview(f) {
        return palettes[f] || palettes["frappe"]
    }

    Component.onCompleted: _apply()
}

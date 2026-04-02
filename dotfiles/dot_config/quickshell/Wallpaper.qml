import Quickshell
import Quickshell.Wayland
import QtQuick

// Full-screen wallpaper on the Background layer.
// Renders a themed background that switches between light/dark flavors,
// using the dotted grain pattern from flameflag-site and subtle accent accents.
PanelWindow {
    id: wallpaper

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    color: Theme.base

    // Main gradient background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.mantle }
            GradientStop { position: 0.4; color: Theme.base }
            GradientStop { position: 1.0; color: Theme.crust }
        }
    }

    // Subtle accent radial glow in the center
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.6
        radius: width / 2
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.accent
            opacity: Theme.isLight ? 0.04 : 0.06
        }
    }

    // Dotted grid pattern overlay (the flameflag-site grain texture)
    Canvas {
        id: wallpaperGrain
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        property color currentBase: Theme.base
        onCurrentBaseChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // Dot grid — 4px tiles matching repeating-conic-gradient
            var op = Theme.isLight ? 0.04 : 0.025;
            ctx.fillStyle = Qt.rgba(0, 0, 0, op);
            for (var y = 0; y < height; y += 4) {
                for (var x = 0; x < width; x += 4) {
                    ctx.fillRect(x, y, 2, 2);
                }
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // Decorative corner accent marks (neobrutalism touch)
    Repeater {
        model: 4
        Rectangle {
            property int corner: index
            // 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right
            x: (corner % 2 === 0) ? 32 : wallpaper.width - 32 - width
            y: (corner < 2) ? 32 : wallpaper.height - 32 - height
            width: 48
            height: 48
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            opacity: 0.15
        }
    }

    // Subtle horizontal rule at 1/3 and 2/3
    Repeater {
        model: 2
        Rectangle {
            x: wallpaper.width * 0.15
            y: wallpaper.height * (index === 0 ? 0.33 : 0.67)
            width: wallpaper.width * 0.7
            height: 1
            color: Theme.overlay0
            opacity: 0.12
        }
    }

    Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }
}

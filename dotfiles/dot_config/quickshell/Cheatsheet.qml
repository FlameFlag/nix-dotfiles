import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Full-screen overlay — toggled via /tmp/.qs-cheatsheet flag file
PanelWindow {
    id: overlay

    property bool shown: false

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: shown
    mask: shown ? null : emptyMask

    Region { id: emptyMask }

    // Watch the flag file reactively instead of polling
    FileView {
        id: flagFile
        path: "/tmp/.qs-cheatsheet"
        watchChanges: true
        printErrors: false
        onLoaded: overlay.shown = true
        onLoadFailed: overlay.shown = false
        onFileChanged: this.reload()
    }

    // Process for removing the flag file on dismiss
    Process {
        id: rmProc
        command: ["rm", "-f", "/tmp/.qs-cheatsheet"]
    }

    function dismiss() {
        overlay.shown = false;
        rmProc.running = true;
    }

    onShownChanged: {
        if (shown) escHandler.forceActiveFocus()
    }

    // Grab keyboard and consume all keys — Escape dismisses, rest are swallowed
    Item {
        id: escHandler
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) overlay.dismiss()
            event.accepted = true
        }
    }

    // Click-to-dismiss backdrop
    MouseArea {
        anchors.fill: parent
        visible: overlay.shown
        onClicked: overlay.dismiss()
    }

    // Dim backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)
        visible: overlay.shown

        // Cheatsheet card
        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.88, 960)
            height: Math.min(contentCol.implicitHeight + 40, parent.height * 0.88)

            // Shadow (elevated — large dialog)
            Rectangle {
                x: Theme.shadowLargeX; y: Theme.shadowLargeY
                width: parent.width; height: parent.height
                color: Theme.shadowColor
            }

            Rectangle {
                id: card
                anchors.fill: parent
                color: Theme.base
                border.width: Theme.borderWidth
                border.color: Theme.borderColor

                // Grain texture
                GrainOverlay {
                    anchors.fill: parent
                    anchors.margins: Theme.borderWidth
                    clip: true
                }

                // Inner bevel
                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.borderWidth }
                    height: 1; color: Qt.rgba(1, 1, 1, Theme.bevelLightTop)
                }
                Rectangle {
                    anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: Theme.borderWidth }
                    width: 1; color: Qt.rgba(1, 1, 1, Theme.bevelLightLeft)
                }
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: Theme.borderWidth }
                    height: 1; color: Qt.rgba(0, 0, 0, Theme.bevelDarkRight)
                }
                Rectangle {
                    anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: Theme.borderWidth }
                    width: 1; color: Qt.rgba(0, 0, 0, Theme.bevelDarkBottom)
                }
            }

            Flickable {
                anchors { fill: parent; margins: 20 }
                contentHeight: contentCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: contentCol
                    width: parent.width
                    spacing: 14

                    // Header
                    Row {
                        width: parent.width
                        spacing: 12

                        // Accent badge
                        Rectangle {
                            width: titleText.implicitWidth + 24
                            height: 30
                            color: Theme.accent
                            border.width: Theme.borderWidth
                            border.color: Theme.borderColor

                            Rectangle {
                                z: -1; x: 4; y: 4
                                width: parent.width; height: parent.height
                                color: Theme.shadowColor
                            }

                            Text {
                                id: titleText
                                anchors.centerIn: parent
                                text: "NIRI CHEATSHEET"
                                color: Theme.base
                                font.family: Theme.fontHeading
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                            }
                        }

                        // Dismiss hint
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "click anywhere or press  MOD + ?"
                            color: Theme.overlay1
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }

                    // Keybind grid
                    GridLayout {
                        id: grid
                        width: parent.width
                        columns: 3
                        columnSpacing: 12
                        rowSpacing: 8

                        // Section: Apps
                        CheatSection { label: "APPS"; Layout.columnSpan: 3 }
                        CheatBind { keys: "MOD + Return"; action: "Terminal (ghostty)" }
                        CheatBind { keys: "MOD + D"; action: "Launcher (anyrun)" }
                        CheatBind { keys: "MOD + Q"; action: "Close window" }

                        // Section: Focus
                        CheatSection { label: "FOCUS"; Layout.columnSpan: 3 }
                        CheatBind { keys: "MOD + H / L"; action: "Focus left / right" }
                        CheatBind { keys: "MOD + J / K"; action: "Focus down / up" }
                        CheatBind { keys: ""; action: "" }

                        // Section: Move
                        CheatSection { label: "MOVE"; Layout.columnSpan: 3 }
                        CheatBind { keys: "MOD + Shift + H / L"; action: "Move column left / right" }
                        CheatBind { keys: "MOD + Shift + J / K"; action: "Move window down / up" }
                        CheatBind { keys: ""; action: "" }

                        // Section: Layout
                        CheatSection { label: "LAYOUT"; Layout.columnSpan: 3 }
                        CheatBind { keys: "MOD + F"; action: "Maximize column" }
                        CheatBind { keys: "MOD + Shift + F"; action: "Fullscreen" }
                        CheatBind { keys: "MOD + R"; action: "Cycle column width" }
                        CheatBind { keys: "MOD + - / ="; action: "Column width -/+ 10%" }
                        CheatBind { keys: "MOD + Shift + - / ="; action: "Window height -/+ 10%" }
                        CheatBind { keys: "MOD + , / ."; action: "Consume / expel window" }

                        // Section: Workspaces
                        CheatSection { label: "WORKSPACES"; Layout.columnSpan: 3 }
                        CheatBind { keys: "MOD + 1–9"; action: "Focus workspace" }
                        CheatBind { keys: "MOD + Shift + 1–9"; action: "Move to workspace" }
                        CheatBind { keys: ""; action: "" }

                        // Section: Screenshots
                        CheatSection { label: "SCREENSHOTS"; Layout.columnSpan: 3 }
                        CheatBind { keys: "Print"; action: "Region screenshot" }
                        CheatBind { keys: "MOD + Print"; action: "Window screenshot" }
                        CheatBind { keys: "Ctrl + Print"; action: "Screen screenshot" }

                        // Section: Media
                        CheatSection { label: "MEDIA & BRIGHTNESS"; Layout.columnSpan: 3 }
                        CheatBind { keys: "XF86AudioRaise / Lower"; action: "Volume +/- 5%" }
                        CheatBind { keys: "XF86AudioMute"; action: "Toggle mute" }
                        CheatBind { keys: "XF86Brightness Up / Down"; action: "Brightness +/- 5%" }

                        // Section: Session
                        CheatSection { label: "SESSION"; Layout.columnSpan: 3 }
                        CheatBind { keys: "MOD + Shift + E"; action: "Quit niri" }
                        CheatBind { keys: "MOD + Shift + P"; action: "Power off monitors" }
                        CheatBind { keys: "MOD + ?"; action: "Toggle this cheatsheet" }
                    }
                }
            }
        }
    }
}

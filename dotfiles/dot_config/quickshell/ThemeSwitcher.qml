import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: overlay

    required property bool show
    signal dismissed()

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: show
    mask: show ? null : emptyMask

    Region { id: emptyMask }

    // Dismiss on Escape
    Item {
        focus: overlay.show
        Keys.onEscapePressed: overlay.dismissed()
    }

    // Click-to-dismiss backdrop
    MouseArea {
        anchors.fill: parent
        visible: overlay.show
        onClicked: overlay.dismissed()
    }

    // Persist theme via FileView — watches for external changes too
    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/theme"
        blockLoading: true
        watchChanges: true
        onLoaded: {
            var parts = this.text().trim().split(" ");
            if (parts.length >= 2) {
                Theme.setTheme(parts[0], parts[1]);
            }
        }
        onFileChanged: this.reload()
    }

    // Process for ensuring directory exists before writing
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/quickshell"]
        onExited: (code) => {
            if (code === 0) {
                themeFile.setText(Theme.flavor + " " + Theme.accentName + "\n");
            }
        }
    }

    function saveTheme() {
        mkdirProc.running = true;
    }

    // Card
    Item {
        visible: overlay.show
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 60
        width: Math.min(cardContent.implicitWidth + 48, parent.width * 0.9)
        height: cardContent.implicitHeight + 48

        // Shadow
        Rectangle {
            z: -1
            x: Theme.shadowX; y: Theme.shadowY
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

            // Inner bevel — top/left
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.margins: Theme.borderWidth
                height: 1; color: Qt.rgba(1, 1, 1, Theme.bevelLightTop)
            }
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                anchors.margins: Theme.borderWidth
                width: 1; color: Qt.rgba(1, 1, 1, Theme.bevelLightLeft)
            }
            // Inner bevel — bottom/right
            Rectangle {
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                anchors.margins: Theme.borderWidth
                height: 1; color: Qt.rgba(0, 0, 0, Theme.bevelDarkRight)
            }
            Rectangle {
                anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: Theme.borderWidth
                width: 1; color: Qt.rgba(0, 0, 0, Theme.bevelDarkBottom)
            }
        }

        ColumnLayout {
            id: cardContent
            anchors.centerIn: parent
            spacing: 16

            // Header
            Row {
                spacing: 12

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
                        text: "THEME"
                        color: Theme.base
                        font.family: Theme.fontHeading
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.flavorLabels[Theme.flavor] + " / " + Theme.accentName.toUpperCase()
                    color: Theme.overlay1
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }

            // Flavor section
            ColumnLayout {
                spacing: 8

                Text {
                    text: "FLAVOR"
                    color: Theme.subtext0
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }

                RowLayout {
                    spacing: 8

                    Repeater {
                        model: Theme.flavorNames

                        delegate: Item {
                            required property string modelData
                            property bool active: Theme.flavor === modelData
                            property bool hovered: flavorHover.hovered

                            implicitWidth: flavorBtn.width
                            implicitHeight: flavorBtn.height

                            transform: Translate { y: hovered && !active ? -2 : 0; Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } } }

                            // Shadow (hidden on active)
                            Rectangle {
                                visible: !parent.active
                                z: -1
                                x: flavorBtn.x + Theme.shadowSmallX
                                y: flavorBtn.y + Theme.shadowSmallY
                                width: flavorBtn.width; height: flavorBtn.height
                                color: Theme.shadowColor
                            }

                            Rectangle {
                                id: flavorBtn
                                width: flavorRow.implicitWidth + 20
                                height: 32
                                color: active ? Theme.accent : Theme.surface0
                                border.width: Theme.borderWidth
                                border.color: Theme.borderColor

                                // Bevel (inactive)
                                Rectangle {
                                    visible: !active
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.margins: Theme.borderWidth
                                    height: 1; color: Qt.rgba(1, 1, 1, 0.18)
                                }
                                Rectangle {
                                    visible: !active
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                                    anchors.margins: Theme.borderWidth
                                    width: 1; color: Qt.rgba(1, 1, 1, 0.12)
                                }
                                // Pressed inset (active)
                                Rectangle {
                                    visible: active
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.margins: Theme.borderWidth
                                    height: 2; color: Qt.rgba(0, 0, 0, 0.25)
                                }
                                Rectangle {
                                    visible: active
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                                    anchors.margins: Theme.borderWidth
                                    width: 2; color: Qt.rgba(0, 0, 0, 0.2)
                                }

                                Row {
                                    id: flavorRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    // Color preview dot
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12; height: 12
                                        color: Theme.flavorPreview(modelData).base
                                        border.width: 2
                                        border.color: Theme.flavorPreview(modelData).text
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Theme.flavorLabels[modelData]
                                        color: active ? Theme.base : Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.setTheme(modelData, Theme.accentName)
                                    overlay.saveTheme()
                                }
                            }

                            HoverHandler { id: flavorHover }
                        }
                    }
                }
            }

            // Accent section
            ColumnLayout {
                spacing: 8

                Text {
                    text: "ACCENT"
                    color: Theme.subtext0
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }

                GridLayout {
                    columns: 7
                    columnSpacing: 8
                    rowSpacing: 8

                    Repeater {
                        model: Theme.accentNames

                        delegate: Item {
                            required property string modelData
                            property bool active: Theme.accentName === modelData
                            property bool hovered: accentHover.hovered

                            implicitWidth: 40
                            implicitHeight: 48

                            transform: Translate { y: hovered && !active ? -2 : 0; Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } } }

                            // Shadow
                            Rectangle {
                                visible: !parent.active
                                z: -1
                                x: swatch.x + 2
                                y: swatch.y + 2
                                width: swatch.width; height: swatch.height
                                color: Qt.darker(Theme.accentColor(modelData), 2.2)
                            }

                            Rectangle {
                                id: swatch
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                width: 32; height: 32
                                color: Theme.accentColor(modelData)
                                border.width: active ? 3 : 2
                                border.color: active ? Theme.text : Theme.borderColor

                                // Check mark for active
                                Text {
                                    visible: active
                                    anchors.centerIn: parent
                                    text: "\u2713"
                                    color: Qt.colorEqual(Theme.accentColor(modelData), Theme.text) ? Theme.base : Theme.text
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                }

                                // Pressed inset (active)
                                Rectangle {
                                    visible: active
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.margins: parent.border.width
                                    height: 2; color: Qt.rgba(0, 0, 0, 0.25)
                                }
                                Rectangle {
                                    visible: active
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                                    anchors.margins: parent.border.width
                                    width: 2; color: Qt.rgba(0, 0, 0, 0.2)
                                }
                            }

                            Text {
                                anchors.top: swatch.bottom
                                anchors.topMargin: 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.substring(0, 3).toUpperCase()
                                color: active ? Theme.text : Theme.overlay1
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                font.weight: active ? Font.Bold : Font.Normal
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.setTheme(Theme.flavor, modelData)
                                    overlay.saveTheme()
                                }
                            }

                            HoverHandler { id: accentHover }
                        }
                    }
                }
            }
        }
    }
}

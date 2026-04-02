import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    Wallpaper {}
    Cheatsheet {}
    CalendarPopup {
        show: clock.calendarVisible
        onDismissed: clock.calendarVisible = false
    }
    ThemeSwitcher {
        show: themeBtn.themeVisible
        onDismissed: themeBtn.themeVisible = false
    }

    PanelWindow {
        id: bar

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 54
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 54

        Item {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 0

            // Hard offset shadow (accent-tinted, behind bar)
            Rectangle {
                x: barBg.x + Theme.shadowX
                y: barBg.y + Theme.shadowY
                width: barBg.width
                height: barBg.height
                color: Theme.shadowColor
            }

            // Bar background
            Rectangle {
                id: barBg
                anchors.fill: parent
                anchors.bottomMargin: 8
                color: Theme.surface0
                border.width: Theme.borderWidth
                border.color: Theme.text

                // Grain texture overlay
                GrainOverlay {
                    anchors.fill: parent
                    anchors.margins: Theme.borderWidth
                    clip: true
                }

                // Inner bevel — top/left light edge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: Theme.borderWidth
                    anchors.leftMargin: Theme.borderWidth
                    anchors.rightMargin: Theme.borderWidth
                    height: 1
                    color: Qt.rgba(1, 1, 1, Theme.bevelLightTop)
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Theme.borderWidth
                    anchors.leftMargin: Theme.borderWidth
                    anchors.bottomMargin: Theme.borderWidth
                    width: 1
                    color: Qt.rgba(1, 1, 1, Theme.bevelLightLeft)
                }

                // Inner bevel — bottom/right dark edge
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottomMargin: Theme.borderWidth
                    anchors.leftMargin: Theme.borderWidth
                    anchors.rightMargin: Theme.borderWidth
                    height: 1
                    color: Qt.rgba(0, 0, 0, Theme.bevelDarkBottom)
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Theme.borderWidth
                    anchors.rightMargin: Theme.borderWidth
                    anchors.bottomMargin: Theme.borderWidth
                    width: 1
                    color: Qt.rgba(0, 0, 0, Theme.bevelDarkRight)
                }
            }

            RowLayout {
                anchors.left: barBg.left
                anchors.right: barBg.right
                anchors.top: barBg.top
                anchors.bottom: barBg.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Workspaces {
                    Layout.alignment: Qt.AlignVCenter
                }

                // Separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 2
                    height: 18
                    color: Theme.overlay0
                }

                Item { Layout.fillWidth: true }

                Clock {
                    id: clock
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // Separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 2
                    height: 18
                    color: Theme.overlay0
                }

                SysTray {
                    Layout.alignment: Qt.AlignVCenter
                    panelWindow: bar
                }

                // Separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 2
                    height: 18
                    color: Theme.overlay0
                }

                BatteryIndicator {
                    Layout.alignment: Qt.AlignVCenter
                }

                // Separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 2
                    height: 18
                    color: Theme.overlay0
                }

                // Theme switcher button
                Item {
                    id: themeBtn
                    property bool themeVisible: false
                    property bool hovered: themeHover.hovered

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26
                    implicitHeight: 26

                    // Hover lift via transform so layout position isn't affected
                    transform: Translate { y: themeBtn.hovered && !themeBtn.themeVisible ? -2 : 0; Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } } }

                    Rectangle {
                        visible: !themeBtn.themeVisible
                        z: -1
                        x: themeBtnBg.x + Theme.shadowSmallX
                        y: themeBtnBg.y + Theme.shadowSmallY
                        width: themeBtnBg.width; height: themeBtnBg.height
                        color: Theme.shadowColor
                    }

                    Rectangle {
                        id: themeBtnBg
                        anchors.fill: parent
                        color: Theme.accent
                        border.width: Theme.borderWidth
                        border.color: Theme.borderColor

                        // 2x2 color grid preview
                        Grid {
                            anchors.centerIn: parent
                            columns: 2; rows: 2; spacing: 2
                            Rectangle { width: 6; height: 6; color: Theme.red }
                            Rectangle { width: 6; height: 6; color: Theme.green }
                            Rectangle { width: 6; height: 6; color: Theme.blue }
                            Rectangle { width: 6; height: 6; color: Theme.yellow }
                        }

                        // Bevel (not pressed)
                        Rectangle {
                            visible: !themeBtn.themeVisible
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.margins: Theme.borderWidth
                            height: 1; color: Qt.rgba(1, 1, 1, 0.25)
                        }
                        Rectangle {
                            visible: !themeBtn.themeVisible
                            anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.margins: Theme.borderWidth
                            width: 1; color: Qt.rgba(1, 1, 1, 0.2)
                        }
                        // Pressed inset
                        Rectangle {
                            visible: themeBtn.themeVisible
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.margins: Theme.borderWidth
                            height: 2; color: Qt.rgba(0, 0, 0, 0.25)
                        }
                        Rectangle {
                            visible: themeBtn.themeVisible
                            anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.margins: Theme.borderWidth
                            width: 2; color: Qt.rgba(0, 0, 0, 0.2)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeBtn.themeVisible = !themeBtn.themeVisible
                    }

                    HoverHandler { id: themeHover }
                }
            }
        }
    }
}

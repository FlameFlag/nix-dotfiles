import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

RowLayout {
    spacing: 6

    required property var panelWindow

    Repeater {
        model: SystemTray.items

        delegate: Item {
            required property var modelData
            property bool hovered: trayHover.hovered

            implicitWidth: 26
            implicitHeight: 26

            // Hover lift
            transform: Translate { y: hovered ? -2 : 0; Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } } }

            // Hard shadow
            Rectangle {
                z: -1
                x: trayBg.x + Theme.shadowSmallX
                y: trayBg.y + Theme.shadowSmallY
                width: trayBg.width; height: trayBg.height
                color: Theme.shadowColor
            }

            Rectangle {
                id: trayBg
                anchors.fill: parent
                color: Theme.surface0
                border.width: Theme.borderWidth
                border.color: Theme.borderColor

                // Top/left bevel
                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: Theme.borderWidth
                    height: 1; color: Qt.rgba(1, 1, 1, 0.18)
                }
                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                    anchors.margins: Theme.borderWidth
                    width: 1; color: Qt.rgba(1, 1, 1, 0.12)
                }
                // Bottom/right bevel
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: Theme.borderWidth
                    height: 1; color: Qt.rgba(0, 0, 0, 0.15)
                }
                Rectangle {
                    anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: Theme.borderWidth
                    width: 1; color: Qt.rgba(0, 0, 0, 0.12)
                }

                IconImage {
                    anchors.centerIn: parent
                    source: modelData.icon
                    implicitSize: 16
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: event => {
                    if (event.button === Qt.LeftButton) {
                        modelData.activate();
                    } else if (event.button === Qt.MiddleButton) {
                        modelData.secondaryActivate();
                    } else if (event.button === Qt.RightButton) {
                        modelData.display(panelWindow, event.x, event.y);
                    }
                }
            }

            HoverHandler { id: trayHover }
        }
    }
}

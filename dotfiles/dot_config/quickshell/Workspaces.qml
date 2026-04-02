import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

RowLayout {
    spacing: 4

    property var workspaces: []

    // Event stream for real-time workspace updates
    Process {
        id: eventProc
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    var evt = JSON.parse(data);
                    if ("WorkspacesChanged" in evt ||
                        "WorkspaceActivated" in evt ||
                        "WorkspaceActiveWindowChanged" in evt) {
                        workspaceProc.running = true;
                    }
                } catch (e) {}
            }
        }
        onRunningChanged: {
            if (!running) running = true;
        }
    }

    // Fetch full workspace list
    Process {
        id: workspaceProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    workspaces = JSON.parse(data).sort((a, b) => a.idx - b.idx);
                } catch (e) {}
            }
        }
    }

    // Initial fetch
    Component.onCompleted: workspaceProc.running = true

    // Process for focus-workspace action
    Process {
        id: focusProc
        property string target: ""
        command: ["niri", "msg", "action", "focus-workspace", target]
    }

    Repeater {
        model: workspaces

        delegate: Item {
            required property var modelData

            property bool active: modelData.is_focused
            property bool occupied: modelData.active_window_id !== null
            property bool hovered: hover.hovered

            implicitWidth: 26
            implicitHeight: 26

            // Hover lift
            y: hovered && !active ? -2 : 0
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

            // Hard shadow (hidden on active = pressed state)
            Rectangle {
                visible: !parent.active
                z: -1
                x: btn.x + Theme.shadowSmallX
                y: btn.y + Theme.shadowSmallY
                width: btn.width
                height: btn.height
                color: Theme.shadowColor
            }

            Rectangle {
                id: btn
                anchors.fill: parent
                color: active ? Theme.accent : (occupied ? Theme.surface1 : Theme.surface0)
                border.width: Theme.borderWidth
                border.color: Theme.borderColor

                // Bevel highlight (inactive only)
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
            }

            Text {
                anchors.centerIn: btn
                text: modelData.idx
                color: active ? Theme.base : Theme.text
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Bold
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    focusProc.target = modelData.idx.toString();
                    focusProc.running = true;
                }
            }

            HoverHandler {
                id: hover
            }
        }
    }
}

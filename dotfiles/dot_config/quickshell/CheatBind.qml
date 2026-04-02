import QtQuick
import QtQuick.Layouts

// A single keybind row: [key badge] [action label]
RowLayout {
    property string keys: ""
    property string action: ""

    spacing: 8
    Layout.fillWidth: true
    visible: keys !== ""

    // Key badge
    Rectangle {
        implicitWidth: Math.max(keyText.implicitWidth + 16, 40)
        implicitHeight: 22
        color: Theme.surface0
        border.width: Theme.borderWidth
        border.color: Theme.overlay0

        // Hard shadow
        Rectangle {
            z: -1; x: 3; y: 3
            width: parent.width; height: parent.height
            color: Theme.shadowColor
        }

        // Bevel
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.borderWidth }
            height: 1; color: Qt.rgba(1, 1, 1, 0.15)
        }
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: Theme.borderWidth }
            height: 1; color: Qt.rgba(0, 0, 0, 0.15)
        }

        Text {
            id: keyText
            anchors.centerIn: parent
            text: keys
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }

    // Action description
    Text {
        Layout.fillWidth: true
        text: action
        color: Theme.subtext1
        font.family: Theme.fontBody
        font.pixelSize: 12
        elide: Text.ElideRight
    }
}

import QtQuick
import QtQuick.Layouts

// Section header label for the cheatsheet grid
Item {
    property string label: ""
    implicitHeight: 22
    Layout.fillWidth: true

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: labelText.implicitWidth + 16
        height: 18
        color: Theme.surface0
        border.width: 2
        border.color: Theme.overlay0

        Text {
            id: labelText
            anchors.centerIn: parent
            text: label
            color: Theme.accent
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.2
        }
    }

    // Horizontal rule after label
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.surface1
        z: -1
    }
}

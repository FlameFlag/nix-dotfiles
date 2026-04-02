import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

RowLayout {
    spacing: 8

    property string batteryLevel: "BAT"

    FileView {
        id: batteryFile
        path: "/sys/class/power_supply/BAT0/capacity"
        onLoaded: {
            var val = this.text().trim();
            if (val.length > 0) batteryLevel = "BAT " + val + "%";
        }
    }

    // Refresh every 30 seconds
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batteryFile.reload()
    }

    Rectangle {
        implicitWidth: batteryText.implicitWidth + 18
        implicitHeight: 26
        color: Theme.surface0
        border.width: Theme.borderWidth
        border.color: Theme.borderColor

        // Hard shadow
        Rectangle {
            z: -1
            x: Theme.shadowSmallX
            y: Theme.shadowSmallY
            width: parent.width
            height: parent.height
            color: Theme.shadowColor
        }

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

        Text {
            id: batteryText
            anchors.centerIn: parent
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 0.3
            text: batteryLevel
        }
    }
}

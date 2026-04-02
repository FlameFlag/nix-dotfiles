import QtQuick
import QtQuick.Layouts

Rectangle {
    id: clockBox

    property bool calendarVisible: false
    property date currentDate: new Date()

    implicitWidth: clockLayout.implicitWidth + 24
    implicitHeight: 26
    color: Theme.accent
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

    // Top/left bevel highlight
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: Theme.borderWidth
        height: 1; color: Qt.rgba(1, 1, 1, 0.25)
    }
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.margins: Theme.borderWidth
        width: 1; color: Qt.rgba(1, 1, 1, 0.2)
    }
    // Bottom/right bevel shadow
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

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: clockBox.calendarVisible = !clockBox.calendarVisible
    }

    RowLayout {
        id: clockLayout
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: timeText
            color: Theme.base
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }

        Text {
            text: "—"
            color: Theme.base
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: Font.Bold
        }

        Text {
            id: dateText
            color: Theme.base
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            clockBox.currentDate = new Date()
            timeText.text = Qt.formatDateTime(clockBox.currentDate, "HH:mm:ss")
            dateText.text = Qt.formatDateTime(clockBox.currentDate, "ddd, MMM d").toUpperCase()
        }
    }
}

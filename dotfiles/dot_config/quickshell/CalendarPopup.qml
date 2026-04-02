import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: overlay

    required property bool show
    signal dismissed()
    property date currentDate: new Date()

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

    // Calendar card
    Rectangle {
        id: calCard
        visible: overlay.show
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 60

        width: calendarContent.implicitWidth + 40
        height: calendarContent.implicitHeight + 40
        color: Theme.surface0
        border.width: Theme.borderWidth
        border.color: Theme.borderColor

        // Hard shadow
        Rectangle {
            z: -1
            x: Theme.shadowX
            y: Theme.shadowY
            width: parent.width
            height: parent.height
            color: Theme.shadowColor
        }

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

        property int viewYear: overlay.currentDate.getFullYear()
        property int viewMonth: overlay.currentDate.getMonth()

        // Trackpad/mouse scroll to navigate months
        WheelHandler {
            onWheel: event => {
                if (event.angleDelta.y > 0) {
                    calCard.prevMonth();
                } else if (event.angleDelta.y < 0) {
                    calCard.nextMonth();
                }
            }
        }

        function prevMonth() {
            if (viewMonth === 0) {
                viewMonth = 11;
                viewYear--;
            } else {
                viewMonth--;
            }
        }

        function nextMonth() {
            if (viewMonth === 11) {
                viewMonth = 0;
                viewYear++;
            } else {
                viewMonth++;
            }
        }

        ColumnLayout {
            id: calendarContent
            anchors.centerIn: parent
            spacing: 8

            // Month/year header with nav
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Rectangle {
                    width: 22; height: 22
                    color: navLeftMa.containsMouse ? Theme.surface2 : "transparent"
                    border.width: 2; border.color: Theme.overlay0

                    Text {
                        anchors.centerIn: parent
                        text: "<"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: navLeftMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calCard.prevMonth()
                    }
                }

                Text {
                    id: monthYearLabel
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    Layout.minimumWidth: 180
                }

                Rectangle {
                    width: 22; height: 22
                    color: navRightMa.containsMouse ? Theme.surface2 : "transparent"
                    border.width: 2; border.color: Theme.overlay0

                    Text {
                        anchors.centerIn: parent
                        text: ">"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: navRightMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calCard.nextMonth()
                    }
                }
            }

            // Day-of-week headers
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 0
                Repeater {
                    model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
                    Text {
                        width: 38; height: 24
                        text: modelData
                        color: Theme.overlay2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Calendar grid
            Grid {
                Layout.alignment: Qt.AlignHCenter
                columns: 7
                spacing: 0

                Repeater {
                    model: 42

                    Rectangle {
                        width: 38; height: 34
                        color: {
                            if (!dayData.inMonth) return "transparent"
                            if (dayData.isToday) return Theme.accent
                            if (dayMa.containsMouse) return Theme.surface2
                            return "transparent"
                        }
                        border.width: dayData.isToday ? 2 : 0
                        border.color: Theme.borderColor

                        property var dayData: {
                            var y = calCard.viewYear
                            var m = calCard.viewMonth
                            var firstDay = new Date(y, m, 1)
                            var startDow = (firstDay.getDay() + 6) % 7
                            var dayNum = index - startDow + 1
                            var d = new Date(y, m, dayNum)
                            var today = overlay.currentDate
                            var isToday = (d.getFullYear() === today.getFullYear() &&
                                           d.getMonth() === today.getMonth() &&
                                           d.getDate() === today.getDate())
                            return {
                                date: d,
                                day: d.getDate(),
                                inMonth: d.getMonth() === m,
                                isToday: isToday
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: dayData.day
                            color: {
                                if (dayData.isToday) return Theme.base
                                if (!dayData.inMonth) return Theme.overlay0
                                return Theme.text
                            }
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            font.weight: dayData.isToday ? Font.Bold : Font.Normal
                        }

                        MouseArea {
                            id: dayMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }
        }

        onViewMonthChanged: updateHeader()
        onViewYearChanged: updateHeader()

        function updateHeader() {
            var months = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                          "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
            monthYearLabel.text = months[viewMonth] + " " + viewYear
        }

        Component.onCompleted: updateHeader()
    }

    // Reset to current month when opened
    onShowChanged: {
        if (show) {
            currentDate = new Date()
            calCard.viewYear = currentDate.getFullYear()
            calCard.viewMonth = currentDate.getMonth()
            calCard.updateHeader()
        }
    }
}

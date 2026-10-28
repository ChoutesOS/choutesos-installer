import QtQuick

Rectangle {
    id: btn
    property string text: ""
    property bool primary: true
    property bool active: true
    signal clicked()

    implicitWidth: label.implicitWidth + 56
    implicitHeight: 46
    radius: 12
    opacity: btn.active ? 1 : 0.4
    border.width: 1
    border.color: btn.primary ? "#9660F8" : "#34304A"
    color: {
        if (btn.primary) return (mouse.containsMouse && btn.active) ? "#7A3FF0" : "#5B18E5"
        return (mouse.containsMouse && btn.active) ? "#2A2640" : "#1E1B30"
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: "#F2F0FA"
        font.pixelSize: 15
        font.weight: Font.Medium
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { if (btn.active) btn.clicked() }
    }
}

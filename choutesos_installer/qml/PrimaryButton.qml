import QtQuick

Rectangle {
    id: btn
    property string text: ""
    property bool primary: true
    property bool active: true
    signal clicked()

    implicitWidth: Math.max(label.implicitWidth + 64, 150)
    implicitHeight: 48
    radius: 24
    opacity: btn.active ? 1 : 0.35
    scale: (mouse.pressed && btn.active) ? 0.97 : 1
    border.width: 1
    border.color: btn.primary ? "#9660F8" : "#34304A"
    color: {
        if (btn.primary) return (mouse.containsMouse && btn.active) ? "#7A3FF0" : "#5B18E5"
        return (mouse.containsMouse && btn.active) ? "#2A2640" : "#1A1729"
    }

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 90 } }
    Behavior on opacity { NumberAnimation { duration: 200 } }

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

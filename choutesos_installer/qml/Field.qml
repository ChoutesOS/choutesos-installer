import QtQuick
import QtQuick.Controls

Item {
    id: root
    property alias text: input.text
    property string label: ""
    property string placeholder: ""
    property bool password: false
    property bool reveal: false
    property string hint: ""
    signal edited(string value)

    implicitWidth: 360
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: root.width
        spacing: 6

        Text {
            text: root.label
            color: "#B9B5CE"
            font.pixelSize: 13
        }

        TextField {
            id: input
            width: col.width
            height: 46
            placeholderText: root.placeholder
            echoMode: (root.password && !root.reveal) ? TextInput.Password : TextInput.Normal
            color: "#F2F0FA"
            placeholderTextColor: "#6F6B86"
            font.pixelSize: 15
            leftPadding: 16
            rightPadding: root.password ? 70 : 16
            selectByMouse: true
            onTextEdited: root.edited(text)
            background: Rectangle {
                radius: 12
                color: "#14121F"
                border.width: 1
                border.color: input.activeFocus ? "#9660F8" : "#2C2842"
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            Text {
                visible: root.password
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: root.reveal ? "Hide" : "Show"
                color: "#9660F8"
                font.pixelSize: 13
                font.weight: Font.Medium
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reveal = !root.reveal
                }
            }
        }

        Text {
            visible: root.hint !== ""
            text: root.hint
            color: "#F2A0AE"
            font.pixelSize: 12
        }
    }
}

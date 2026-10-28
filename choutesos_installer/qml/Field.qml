import QtQuick
import QtQuick.Controls

Item {
    id: root
    property alias text: input.text
    property string label: ""
    property string placeholder: ""
    property bool password: false
    property string hint: ""
    signal edited(string value)

    implicitWidth: 320
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
            height: 44
            placeholderText: root.placeholder
            echoMode: root.password ? TextInput.Password : TextInput.Normal
            color: "#F2F0FA"
            placeholderTextColor: "#6F6B86"
            font.pixelSize: 15
            leftPadding: 14
            selectByMouse: true
            onTextEdited: root.edited(text)
            background: Rectangle {
                radius: 10
                color: "#14121F"
                border.width: 1
                border.color: input.activeFocus ? "#9660F8" : "#2C2842"
            }
        }

        Text {
            visible: root.hint !== ""
            text: root.hint
            color: "#8D89A3"
            font.pixelSize: 12
        }
    }
}

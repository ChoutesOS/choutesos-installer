import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property string title: ""
    property var items: []
    property string current: ""
    property string query: ""
    signal picked(string value, string label)

    readonly property var filtered: {
        var q = root.query.toLowerCase()
        if (q === "")
            return root.items
        var out = []
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].label.toLowerCase().indexOf(q) >= 0)
                out.push(root.items[i])
        }
        return out
    }

    color: "#14121F"
    radius: 14
    border.color: "#2C2842"
    border.width: 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Text {
            text: root.title
            color: "#F2F0FA"
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        TextField {
            id: search
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            placeholderText: "Search"
            placeholderTextColor: "#6F6B86"
            color: "#F2F0FA"
            font.pixelSize: 14
            leftPadding: 12
            onTextChanged: root.query = text
            background: Rectangle {
                radius: 8
                color: "#0E0C18"
                border.width: 1
                border.color: search.activeFocus ? "#9660F8" : "#2C2842"
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered
            ScrollBar.vertical: ScrollBar { }

            delegate: Rectangle {
                width: list.width - 8
                height: 38
                radius: 8
                color: modelData.value === root.current ? "#5B18E5" : (rowMouse.containsMouse ? "#201C33" : "transparent")

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    width: parent.width - 24
                    text: modelData.label
                    color: "#F2F0FA"
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.picked(modelData.value, modelData.label)
                }
            }
        }
    }
}

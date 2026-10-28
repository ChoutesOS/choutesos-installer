import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1120
    height: 720
    minimumWidth: 960
    minimumHeight: 640
    visible: true
    title: "ChoutesOS Installer"
    color: "#0B0A12"

    readonly property var pageNames: ["Welcome", "Region", "Disk", "Account", "Summary", "Install"]

    // -- choices -----------------------------------------------------------
    property int page: 0
    property string language: "en_US.UTF-8"
    property string languageName: "English"
    property string timezone: "UTC"
    property string keymap: "us"
    property string disk: ""
    property string diskLabel: ""
    property string filesystem: "ext4"
    property string fullname: ""
    property string username: ""
    property string hostname: "choutesos"
    property string password: ""
    property string password2: ""
    property bool autologin: false
    property bool userEdited: false

    // -- installation state ------------------------------------------------
    property bool installing: false
    property bool finished: false
    property bool failed: false
    property real progress: 0
    property string statusText: "Starting..."
    property string logText: ""
    property string errorText: ""
    property var problems: []
    property bool showLog: false

    property var languageItems: []
    property var timezoneItems: []
    property var keymapItems: []
    property var diskItems: []

    function usernameOk(u) { return /^[a-z_][a-z0-9_-]{0,31}$/.test(u) }
    function hostnameOk(h) { return /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(h) }

    readonly property bool accountValid: usernameOk(username) && password.length > 0
                                         && password === password2 && hostnameOk(hostname)

    function pageValid() {
        if (page === 2) return disk !== ""
        if (page === 3) return accountValid
        return true
    }

    function config() {
        return {
            disk: disk, filesystem: filesystem, hostname: hostname, username: username,
            fullname: fullname, password: password, autologin: autologin,
            timezone: timezone, locale: language, keymap: keymap
        }
    }

    function refreshDisks() {
        diskItems = controller.disks()
        var found = false
        for (var i = 0; i < diskItems.length; i++)
            if (diskItems[i].path === disk) found = true
        if (!found) { disk = ""; diskLabel = "" }
    }

    function startInstall() {
        problems = controller.validate(config())
        if (problems.length > 0)
            return
        page = 5
        installing = true
        finished = false
        failed = false
        progress = 0
        logText = ""
        controller.install(config())
    }

    Component.onCompleted: {
        languageItems = controller.languages()
        timezoneItems = controller.timezones()
        keymapItems = controller.keymaps()
        refreshDisks()
    }

    Connections {
        target: controller
        function onProgressChanged(value, label) {
            win.progress = value
            win.statusText = label
        }
        function onLogLine(line) {
            win.logText += line + "\n"
        }
        function onInstallFinished(ok, message) {
            win.installing = false
            win.finished = true
            win.failed = !ok
            win.errorText = message
            if (ok) win.progress = 100
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 270
            color: "#100E1B"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 8

                Image {
                    source: "../assets/logo.png"
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Text {
                    text: "ChoutesOS"
                    color: "#F2F0FA"
                    font.pixelSize: 26
                    font.weight: Font.Bold
                }
                Text {
                    text: "Installer"
                    color: "#9660F8"
                    font.pixelSize: 14
                }

                Item { Layout.preferredHeight: 28 }

                Repeater {
                    model: win.pageNames
                    delegate: RowLayout {
                        spacing: 14
                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 13
                            color: index < win.page ? "#5B18E5" : (index === win.page ? "#9660F8" : "#1E1B30")
                            Text {
                                anchors.centerIn: parent
                                text: index < win.page ? "\u2713" : (index + 1)
                                color: "#FFFFFF"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                        }
                        Text {
                            text: modelData
                            color: index === win.page ? "#F2F0FA" : "#8D89A3"
                            font.pixelSize: 15
                            font.weight: index === win.page ? Font.DemiBold : Font.Normal
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Text {
                    visible: controller.isDemo()
                    text: "Demo mode: nothing will be changed on this computer."
                    color: "#F0B35A"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 12
                }
            }
        }

        // ---------------------------------------------------------- content
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 36
            spacing: 18

            Text {
                text: {
                    if (win.page === 0) return "Welcome to ChoutesOS"
                    if (win.page === 1) return "Language, time and keyboard"
                    if (win.page === 2) return "Where should ChoutesOS be installed?"
                    if (win.page === 3) return "Create your account"
                    if (win.page === 4) return "Ready to install"
                    return win.finished ? (win.failed ? "Installation failed" : "All done!") : "Installing ChoutesOS"
                }
                color: "#F2F0FA"
                font.pixelSize: 30
                font.weight: Font.Bold
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page

                // 0 - welcome
                Item {
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 18
                        Image {
                            source: "../assets/logo.png"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 150
                            Layout.preferredHeight: 150
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                        Text {
                            text: "A fast, polished system for gaming and daily use."
                            color: "#B9B5CE"
                            font.pixelSize: 18
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "This installer works fully offline and takes a few minutes.\nYou will need at least 20 GB of free disk space."
                            color: "#8D89A3"
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                // 1 - region
                RowLayout {
                    spacing: 16
                    ListPicker {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        title: "Language"
                        items: win.languageItems
                        current: win.language
                        onPicked: function (value, label) { win.language = value; win.languageName = label }
                    }
                    ListPicker {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        title: "Time zone"
                        items: win.timezoneItems
                        current: win.timezone
                        onPicked: function (value, label) { win.timezone = value }
                    }
                    ListPicker {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        title: "Keyboard layout"
                        items: win.keymapItems
                        current: win.keymap
                        onPicked: function (value, label) { win.keymap = value }
                    }
                }

                // 2 - disk
                ColumnLayout {
                    spacing: 14
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        radius: 12
                        color: "#2A1A1F"
                        border.color: "#6B2F3A"
                        border.width: 1
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 16
                            width: parent.width - 32
                            text: "The selected disk will be erased completely. Back up anything you want to keep first."
                            color: "#F2C4CC"
                            wrapMode: Text.WordWrap
                            font.pixelSize: 14
                        }
                    }

                    ListView {
                        id: diskList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        model: win.diskItems
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            width: diskList.width
                            height: 72
                            radius: 14
                            color: win.disk === modelData.path ? "#241848" : "#14121F"
                            border.width: 2
                            border.color: win.disk === modelData.path ? "#9660F8" : "#2C2842"

                            ColumnLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 18
                                spacing: 3
                                Text {
                                    text: modelData.model
                                    color: "#F2F0FA"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: modelData.path + "  \u00b7  " + modelData.sizeGb + " GB"
                                          + (modelData.transport !== "" ? "  \u00b7  " + modelData.transport : "")
                                    color: "#8D89A3"
                                    font.pixelSize: 13
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { win.disk = modelData.path; win.diskLabel = modelData.model }
                            }
                        }
                    }

                    Text {
                        visible: win.diskItems.length === 0
                        text: "No suitable disk was found (8 GB or larger)."
                        color: "#8D89A3"
                        font.pixelSize: 15
                    }

                    RowLayout {
                        spacing: 12
                        Text { text: "File system"; color: "#B9B5CE"; font.pixelSize: 14 }
                        Repeater {
                            model: [
                                { value: "ext4", label: "ext4  \u00b7  simple and fast" },
                                { value: "btrfs", label: "Btrfs  \u00b7  compression and snapshots" }
                            ]
                            delegate: Rectangle {
                                implicitWidth: fsLabel.implicitWidth + 32
                                implicitHeight: 40
                                radius: 10
                                color: win.filesystem === modelData.value ? "#241848" : "#14121F"
                                border.width: 1
                                border.color: win.filesystem === modelData.value ? "#9660F8" : "#2C2842"
                                Text {
                                    id: fsLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: "#F2F0FA"
                                    font.pixelSize: 14
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: win.filesystem = modelData.value
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        PrimaryButton {
                            text: "Refresh disks"
                            primary: false
                            onClicked: win.refreshDisks()
                        }
                    }
                }

                // 3 - account
                Item {
                    ColumnLayout {
                        width: Math.min(parent.width, 520)
                        spacing: 14

                        Field {
                            Layout.fillWidth: true
                            label: "Your name"
                            placeholder: "Full name"
                            onEdited: function (value) {
                                win.fullname = value
                                if (!win.userEdited) {
                                    var first = value.trim().split(" ")[0].toLowerCase().replace(/[^a-z0-9_-]/g, "")
                                    win.username = first
                                    userField.text = first
                                }
                            }
                        }
                        Field {
                            id: userField
                            Layout.fillWidth: true
                            label: "Username"
                            placeholder: "username"
                            hint: (win.username !== "" && !win.usernameOk(win.username))
                                  ? "Use lowercase letters, digits, _ or - and start with a letter." : ""
                            onEdited: function (value) { win.userEdited = true; win.username = value }
                        }
                        Field {
                            Layout.fillWidth: true
                            label: "Computer name"
                            text: win.hostname
                            hint: !win.hostnameOk(win.hostname) ? "Letters, digits and hyphens only." : ""
                            onEdited: function (value) { win.hostname = value }
                        }
                        Field {
                            Layout.fillWidth: true
                            label: "Password"
                            password: true
                            onEdited: function (value) { win.password = value }
                        }
                        Field {
                            Layout.fillWidth: true
                            label: "Confirm password"
                            password: true
                            hint: (win.password2 !== "" && win.password !== win.password2) ? "The passwords do not match." : ""
                            onEdited: function (value) { win.password2 = value }
                        }
                        RowLayout {
                            spacing: 12
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: win.autologin ? "#5B18E5" : "#14121F"
                                border.width: 1
                                border.color: win.autologin ? "#9660F8" : "#2C2842"
                                Text {
                                    anchors.centerIn: parent
                                    visible: win.autologin
                                    text: "\u2713"
                                    color: "#FFFFFF"
                                    font.pixelSize: 15
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: win.autologin = !win.autologin
                                }
                            }
                            Text {
                                text: "Log in automatically"
                                color: "#B9B5CE"
                                font.pixelSize: 14
                            }
                        }
                    }
                }

                // 4 - summary
                ColumnLayout {
                    spacing: 14
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: summaryGrid.implicitHeight + 40
                        radius: 14
                        color: "#14121F"
                        border.width: 1
                        border.color: "#2C2842"

                        GridLayout {
                            id: summaryGrid
                            anchors.fill: parent
                            anchors.margins: 20
                            columns: 2
                            columnSpacing: 30
                            rowSpacing: 10
                            Text { text: "Language"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.languageName; color: "#F2F0FA"; font.pixelSize: 14 }
                            Text { text: "Time zone"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.timezone; color: "#F2F0FA"; font.pixelSize: 14 }
                            Text { text: "Keyboard"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.keymap; color: "#F2F0FA"; font.pixelSize: 14 }
                            Text { text: "Disk"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.diskLabel + "  (" + win.disk + ", " + win.filesystem + ")"; color: "#F2F0FA"; font.pixelSize: 14 }
                            Text { text: "Account"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.username + (win.fullname !== "" ? "  (" + win.fullname + ")" : ""); color: "#F2F0FA"; font.pixelSize: 14 }
                            Text { text: "Computer name"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.hostname; color: "#F2F0FA"; font.pixelSize: 14 }
                            Text { text: "Automatic login"; color: "#8D89A3"; font.pixelSize: 14 }
                            Text { text: win.autologin ? "Yes" : "No"; color: "#F2F0FA"; font.pixelSize: 14 }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        radius: 12
                        color: "#2A1A1F"
                        border.color: "#6B2F3A"
                        border.width: 1
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 16
                            width: parent.width - 32
                            text: "Everything on " + win.disk + " will be erased when you click Install."
                            color: "#F2C4CC"
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                        }
                    }
                    Text {
                        visible: win.problems.length > 0
                        text: win.problems.join("\n")
                        color: "#F2C4CC"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Item { Layout.fillHeight: true }
                }

                // 5 - install
                ColumnLayout {
                    spacing: 16
                    Text {
                        text: win.finished ? (win.failed ? "Something went wrong." : "ChoutesOS is installed. Restart to start using it.") : win.statusText
                        color: win.failed ? "#F2C4CC" : "#B9B5CE"
                        font.pixelSize: 17
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16
                        radius: 8
                        color: "#1E1B30"
                        Rectangle {
                            width: parent.width * Math.min(win.progress, 100) / 100
                            height: parent.height
                            radius: 8
                            color: win.failed ? "#C0485A" : "#7A3FF0"
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                    Text {
                        text: Math.round(win.progress) + " %"
                        color: "#8D89A3"
                        font.pixelSize: 14
                    }
                    Text {
                        visible: win.failed
                        text: win.errorText
                        color: "#F2C4CC"
                        font.pixelSize: 13
                        wrapMode: Text.WrapAnywhere
                        Layout.fillWidth: true
                    }
                    PrimaryButton {
                        text: win.showLog ? "Hide details" : "Show details"
                        primary: false
                        onClicked: win.showLog = !win.showLog
                    }
                    ScrollView {
                        visible: win.showLog
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            readOnly: true
                            text: win.logText
                            color: "#B9B5CE"
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: TextEdit.WrapAnywhere
                            background: Rectangle { color: "#0E0C18"; radius: 10; border.color: "#2C2842"; border.width: 1 }
                        }
                    }
                    Item { Layout.fillHeight: !win.showLog }
                }
            }

            // ------------------------------------------------------ footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Item { Layout.fillWidth: true }
                PrimaryButton {
                    visible: win.page > 0 && win.page < 5
                    text: "Back"
                    primary: false
                    onClicked: win.page = win.page - 1
                }
                PrimaryButton {
                    visible: win.page < 4
                    text: win.page === 0 ? "Get started" : "Next"
                    active: win.pageValid()
                    onClicked: win.page = win.page + 1
                }
                PrimaryButton {
                    visible: win.page === 4
                    text: "Install"
                    onClicked: win.startInstall()
                }
                PrimaryButton {
                    visible: win.page === 5 && win.finished && !win.failed
                    text: "Restart now"
                    onClicked: controller.reboot()
                }
                PrimaryButton {
                    visible: win.page === 5 && win.finished && win.failed
                    text: "Close"
                    primary: false
                    onClicked: controller.quit()
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: (controller !== null && controller.isDemo()) ? Window.Windowed : Window.FullScreen
    width: 1280
    height: 800
    minimumWidth: 960
    minimumHeight: 640
    title: "ChoutesOS Installer"
    color: "#0B0A12"

    // 0 welcome, 1 requirements, 2 disk, 3 summary, 4 installing / done
    property int page: 0
    property string disk: ""
    property string diskLabel: ""
    property int diskSize: 0
    property string filesystem: "ext4"

    property var checkItems: []
    property int revealed: 0
    property bool canInstall: false
    property var diskItems: []
    property var problems: []

    property bool installing: false
    property bool finished: false
    property bool failed: false
    property real progress: 0
    property string statusText: "Starting..."
    property string logText: ""
    property string errorText: ""
    property bool showLog: false
    property int tip: 0

    readonly property var tips: [
        { title: "Built for gaming", text: "Steam, MangoHud, GameMode and Vulkan are ready as soon as you log in." },
        { title: "Fast and smooth", text: "The XanMod kernel and a tuned system keep everything responsive." },
        { title: "Made to be yours", text: "Change the look of your desktop in Settings: profiles, wallpapers, bar and dock." },
        { title: "Always up to date", text: "ChoutesOS updates come straight from packages.choutes.com." }
    ]

    component PageBox: Item {
        property int idx: 0
        property int current: 0
        anchors.fill: parent
        opacity: current === idx ? 1 : 0
        visible: opacity > 0.01
        x: current === idx ? 0 : (current > idx ? -70 : 70)
        Behavior on opacity { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    function refreshDisks() {
        diskItems = controller.disks()
        var found = false
        for (var i = 0; i < diskItems.length; i++)
            if (diskItems[i].path === disk) found = true
        if (!found) { disk = ""; diskLabel = "" }
    }

    function startChecks() {
        checkItems = controller.checks()
        revealed = 0
        var ok = true
        for (var i = 0; i < checkItems.length; i++)
            if (checkItems[i].status === "fail") ok = false
        canInstall = ok
        revealTimer.restart()
    }

    function config() {
        return { disk: disk, filesystem: filesystem }
    }

    function startInstall() {
        problems = controller.validate(config())
        if (problems.length > 0)
            return
        page = 4
        installing = true
        finished = false
        failed = false
        progress = 0
        logText = ""
        controller.install(config())
    }

    function goNext() {
        if (page === 0) { startChecks(); page = 1 }
        else if (page === 1) { refreshDisks(); page = 2 }
        else if (page === 2) page = 3
        else if (page === 3) startInstall()
    }

    Component.onCompleted: refreshDisks()

    Timer {
        id: revealTimer
        interval: 420
        repeat: true
        onTriggered: {
            if (win.revealed < win.checkItems.length) win.revealed += 1
            else stop()
        }
    }

    Timer {
        id: tipTimer
        interval: 6000
        repeat: true
        running: win.page === 4 && !win.finished
        onTriggered: tipAnim.start()
    }

    Connections {
        target: controller
        function onProgressChanged(value, label) {
            win.progress = value
            win.statusText = label
        }
        function onLogLine(line) { win.logText += line + "\n" }
        function onInstallFinished(ok, message) {
            win.installing = false
            win.finished = true
            win.failed = !ok
            win.errorText = message
            if (ok) win.progress = 100
        }
    }

    // ------------------------------------------------------------ background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#150B30" }
            GradientStop { position: 0.55; color: "#0B0A12" }
            GradientStop { position: 1.0; color: "#08070D" }
        }
    }
    Rectangle {
        id: glow
        width: win.width * 0.9
        height: width
        radius: width / 2
        x: -width * 0.25
        y: -height * 0.62
        color: "#5B18E5"
        opacity: 0.16
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 0.26; duration: 5000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.12; duration: 5000; easing.type: Easing.InOutSine }
        }
    }

    // ------------------------------------------------------------ pages
    Item {
        id: stage
        anchors.fill: parent
        anchors.leftMargin: 80
        anchors.rightMargin: 80
        anchors.topMargin: 60
        anchors.bottomMargin: 150

        // 0 - welcome
        PageBox {
            idx: 0
            current: win.page
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 22
                Image {
                    id: heroLogo
                    source: "../assets/logo.png"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 150
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.06; duration: 2200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 2200; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: "Welcome to ChoutesOS"
                    color: "#F2F0FA"
                    font.pixelSize: 48
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "A fast, polished system for gaming and daily use."
                    color: "#B9B5CE"
                    font.pixelSize: 19
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    visible: controller !== null && controller.isDemo()
                    text: "Demo mode: nothing will be changed on this computer."
                    color: "#F0B35A"
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // 1 - requirements
        PageBox {
            idx: 1
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 760)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18

                Text {
                    text: "Checking your computer"
                    color: "#F2F0FA"
                    font.pixelSize: 36
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Making sure ChoutesOS runs well on this device."
                    color: "#8D89A3"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }

                Repeater {
                    model: win.checkItems
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 68
                        radius: 16
                        color: "#14121F"
                        border.width: 1
                        border.color: modelData.status === "fail" ? "#6B2F3A" : "#2C2842"
                        opacity: index < win.revealed ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 320 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 16
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 15
                                color: modelData.status === "ok" ? "#1F7A4A" : (modelData.status === "warn" ? "#8A6A1E" : "#9A2F40")
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.status === "ok" ? "\u2713" : (modelData.status === "warn" ? "!" : "\u2715")
                                    color: "#FFFFFF"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: modelData.title; color: "#F2F0FA"; font.pixelSize: 16; font.weight: Font.DemiBold }
                                Text {
                                    text: modelData.detail
                                    color: "#8D89A3"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: win.revealed >= win.checkItems.length && !win.canInstall
                    text: "This computer cannot run ChoutesOS, so the installation cannot continue."
                    color: "#F2C4CC"
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // 2 - disk
        PageBox {
            idx: 2
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 860)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 16

                Text {
                    text: "Where should ChoutesOS be installed?"
                    color: "#F2F0FA"
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 14
                    color: "#2A1A1F"
                    border.color: "#6B2F3A"
                    border.width: 1
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 18
                        width: parent.width - 36
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
                    spacing: 12
                    model: win.diskItems
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        width: diskList.width
                        height: 82
                        radius: 18
                        color: win.disk === modelData.path ? "#241848" : "#14121F"
                        border.width: 2
                        border.color: win.disk === modelData.path ? "#9660F8" : "#2C2842"
                        scale: diskMouse.containsMouse ? 1.01 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 22
                            anchors.rightMargin: 22
                            spacing: 18
                            Rectangle {
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 46
                                radius: 12
                                color: "#1E1B30"
                                Text { anchors.centerIn: parent; text: "\u25A3"; color: "#9660F8"; font.pixelSize: 24 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text { text: modelData.model; color: "#F2F0FA"; font.pixelSize: 18; font.weight: Font.DemiBold }
                                Text {
                                    text: modelData.path + "  \u00b7  " + modelData.sizeGb + " GB"
                                          + (modelData.transport !== "" ? "  \u00b7  " + modelData.transport : "")
                                    color: "#8D89A3"
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                visible: win.disk === modelData.path
                                text: "\u2713"
                                color: "#9660F8"
                                font.pixelSize: 26
                            }
                        }
                        MouseArea {
                            id: diskMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { win.disk = modelData.path; win.diskLabel = modelData.model; win.diskSize = modelData.sizeGb }
                        }
                    }
                }
                Text {
                    visible: win.diskItems.length === 0
                    text: "No suitable disk was found (30 GB or larger)."
                    color: "#8D89A3"
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignHCenter
                }

                RowLayout {
                    spacing: 12
                    Layout.alignment: Qt.AlignHCenter
                    Text { text: "File system"; color: "#B9B5CE"; font.pixelSize: 14 }
                    Repeater {
                        model: [
                            { value: "ext4", label: "ext4  \u00b7  simple and fast" },
                            { value: "btrfs", label: "Btrfs  \u00b7  compression and snapshots" }
                        ]
                        delegate: Rectangle {
                            implicitWidth: fsLabel.implicitWidth + 36
                            implicitHeight: 42
                            radius: 21
                            color: win.filesystem === modelData.value ? "#241848" : "#14121F"
                            border.width: 1
                            border.color: win.filesystem === modelData.value ? "#9660F8" : "#2C2842"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { id: fsLabel; anchors.centerIn: parent; text: modelData.label; color: "#F2F0FA"; font.pixelSize: 14 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.filesystem = modelData.value
                            }
                        }
                    }
                    PrimaryButton { text: "Refresh"; primary: false; onClicked: win.refreshDisks() }
                }
            }
        }

        // 3 - summary
        PageBox {
            idx: 3
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 700)
                anchors.centerIn: parent
                spacing: 20

                Text {
                    text: "Ready to install"
                    color: "#F2F0FA"
                    font.pixelSize: 38
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: sumGrid.implicitHeight + 44
                    radius: 18
                    color: "#14121F"
                    border.width: 1
                    border.color: "#2C2842"
                    GridLayout {
                        id: sumGrid
                        anchors.fill: parent
                        anchors.margins: 22
                        columns: 2
                        columnSpacing: 30
                        rowSpacing: 12
                        Text { text: "Disk"; color: "#8D89A3"; font.pixelSize: 15 }
                        Text { text: win.diskLabel + "  (" + win.disk + ", " + win.diskSize + " GB)"; color: "#F2F0FA"; font.pixelSize: 15 }
                        Text { text: "File system"; color: "#8D89A3"; font.pixelSize: 15 }
                        Text { text: win.filesystem === "btrfs" ? "Btrfs" : "ext4"; color: "#F2F0FA"; font.pixelSize: 15 }
                        Text { text: "Next"; color: "#8D89A3"; font.pixelSize: 15 }
                        Text { text: "After restarting, you set up your account."; color: "#F2F0FA"; font.pixelSize: 15 }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 14
                    color: "#2A1A1F"
                    border.color: "#6B2F3A"
                    border.width: 1
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 18
                        width: parent.width - 36
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
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // 4 - installing / done
        PageBox {
            idx: 4
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 760)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20

                Image {
                    source: "../assets/logo.png"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Text {
                    text: win.finished ? (win.failed ? "The installation failed" : "ChoutesOS is installed") : "Installing ChoutesOS"
                    color: "#F2F0FA"
                    font.pixelSize: 36
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: win.finished
                          ? (win.failed ? "Something went wrong." : "Remove the installation USB drive, then restart.")
                          : win.statusText
                    color: win.failed ? "#F2C4CC" : "#B9B5CE"
                    font.pixelSize: 17
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
                    radius: 5
                    color: "#1E1B30"
                    Rectangle {
                        width: parent.width * Math.min(win.progress, 100) / 100
                        height: parent.height
                        radius: 5
                        color: win.failed ? "#C0485A" : "#7A3FF0"
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    text: Math.round(win.progress) + " %"
                    color: "#8D89A3"
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    visible: !win.finished
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: 18
                    color: "#14121F"
                    border.width: 1
                    border.color: "#2C2842"
                    clip: true
                    Column {
                        id: tipBox
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: win.tips[win.tip].title
                            color: "#F2F0FA"
                            font.pixelSize: 19
                            font.weight: Font.DemiBold
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: win.tips[win.tip].text
                            color: "#8D89A3"
                            font.pixelSize: 14
                            width: 600
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    SequentialAnimation {
                        id: tipAnim
                        NumberAnimation { target: tipBox; property: "opacity"; to: 0; duration: 220 }
                        ScriptAction { script: win.tip = (win.tip + 1) % win.tips.length }
                        NumberAnimation { target: tipBox; property: "opacity"; to: 1; duration: 320 }
                    }
                }

                Text {
                    visible: win.failed
                    text: win.errorText
                    color: "#F2C4CC"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                }
                PrimaryButton {
                    text: win.showLog ? "Hide details" : "Show details"
                    primary: false
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: win.showLog = !win.showLog
                }
                ScrollView {
                    visible: win.showLog
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
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
            }
        }
    }

    // ------------------------------------------------------------ footer
    RowLayout {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 80
        anchors.rightMargin: 80
        anchors.bottomMargin: 56
        spacing: 14

        Row {
            spacing: 10
            Repeater {
                model: 5
                delegate: Rectangle {
                    width: index === win.page ? 26 : 8
                    height: 8
                    radius: 4
                    color: index === win.page ? "#9660F8" : (index < win.page ? "#5B18E5" : "#2C2842")
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 260 } }
                }
            }
        }
        Item { Layout.fillWidth: true }

        PrimaryButton {
            visible: win.page === 1 && win.revealed >= win.checkItems.length && !win.canInstall
            text: "Shut down"
            primary: false
            onClicked: controller.powerOff()
        }
        PrimaryButton {
            visible: win.page > 0 && win.page < 4
            text: "Back"
            primary: false
            onClicked: win.page = win.page - 1
        }
        PrimaryButton {
            visible: win.page < 3
            text: "Continue"
            active: win.page === 0
                    || (win.page === 1 && win.revealed >= win.checkItems.length && win.canInstall)
                    || (win.page === 2 && win.disk !== "")
            onClicked: win.goNext()
        }
        PrimaryButton {
            visible: win.page === 3
            text: "Install"
            onClicked: win.goNext()
        }
        PrimaryButton {
            visible: win.page === 4 && win.finished && !win.failed
            text: "Restart now"
            onClicked: controller.reboot()
        }
        PrimaryButton {
            visible: win.page === 4 && win.finished && win.failed
            text: "Shut down"
            primary: false
            onClicked: controller.powerOff()
        }
    }
}

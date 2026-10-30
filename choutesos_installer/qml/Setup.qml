import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: win
    visible: true
    visibility: (controller !== null && controller.isDemo()) ? Window.Windowed : Window.FullScreen
    width: 1280
    height: 800
    minimumWidth: 960
    minimumHeight: 640
    title: "ChoutesOS Setup"
    color: "#0B0A12"

    // 0 hello, 1 region, 2 internet, 3 account, 4 updates, 5 welcome
    property int page: 0

    property string language: "en_US.UTF-8"
    property string languageName: "English"
    property string timezone: "UTC"
    property string keymap: "us"
    property var languageItems: []
    property var timezoneItems: []
    property var keymapItems: []
    property string regionError: ""

    property var wifiList: []
    property bool online: false
    property bool ethernet: false
    property string selectedSsid: ""
    property bool selectedSecure: false
    property string wifiPassword: ""
    property string wifiMessage: ""
    property bool connecting: false

    property string fullname: ""
    property string username: ""
    property string hostname: "choutesos"
    property string password: ""
    property string password2: ""
    property bool autologin: false
    property bool userEdited: false
    property string avatarPath: ""
    property var avatarItems: []
    property string accountError: ""
    property bool creating: false

    property real updPercent: 0
    property string updLabel: "Looking for updates"
    property string updState: "running"     // running | reboot | checking | error
    property string updMessage: ""

    property int wStep: 0
    property bool finishing: false
    property int greetIndex: 0
    readonly property var greetings: ["Hello", "Halo", "Hola", "Bonjour", "Hallo", "Ciao", "Ol\u00e1", "\u3053\u3093\u306b\u3061\u306f", "\uc548\ub155\ud558\uc138\uc694", "\u4f60\u597d", "\u041f\u0440\u0438\u0432\u0435\u0442", "\u0645\u0631\u062d\u0628\u0627"]

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

    function usernameOk(u) { return /^[a-z_][a-z0-9_-]{0,31}$/.test(u) }
    function hostnameOk(h) { return /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(h) }

    readonly property bool accountValid: usernameOk(username) && password.length > 0
                                         && password === password2 && hostnameOk(hostname)

    function refreshInternet() {
        var st = controller.internet()
        online = st.online
        ethernet = st.ethernet
    }

    function refreshWifi() {
        wifiList = controller.wifi()
    }

    function enterInternet() {
        refreshInternet()
        refreshWifi()
    }

    function startUpdates() {
        updPercent = 0
        updLabel = "Looking for updates"
        updState = "running"
        page = 4
        controller.startUpdates()
    }

    function toWelcome() {
        controller.setStage("welcome")
        wStep = 0
        page = 5
        welcomeTimer.restart()
    }

    function next() {
        if (page === 0) {
            page = 1
        } else if (page === 1) {
            var r = controller.applyRegion({ locale: language, timezone: timezone, keymap: keymap })
            if (!r.ok) { regionError = r.message; return }
            regionError = ""
            page = 2
            enterInternet()
        } else if (page === 2) {
            page = 3
        } else if (page === 3) {
            if (!accountValid || creating) return
            creating = true
            var a = controller.createAccount({
                username: username, fullname: fullname, password: password,
                hostname: hostname, autologin: autologin, avatar: avatarPath })
            creating = false
            if (!a.ok) { accountError = a.message; return }
            accountError = ""
            refreshInternet()
            if (online) startUpdates()
            else toWelcome()
        }
    }

    Component.onCompleted: {
        languageItems = controller.languages()
        timezoneItems = controller.timezones()
        keymapItems = controller.keymaps()
        avatarItems = controller.avatars()
        if (avatarItems.length > 0) avatarPath = avatarItems[0].path
        var st = controller.stage()
        if (st === "after-update") {
            page = 4
            updState = "checking"
            updLabel = "Checking that everything works"
            checkTimer.start()
        } else if (st === "welcome") {
            toWelcome()
        }
    }

    Timer {
        id: greetTimer
        interval: 2300
        repeat: true
        running: win.page === 0
        onTriggered: greetAnim.start()
    }
    Timer {
        id: netTimer
        interval: 3500
        repeat: true
        running: win.page === 2
        onTriggered: { win.refreshInternet(); if (!win.connecting) win.refreshWifi() }
    }
    Timer {
        id: checkTimer
        interval: 5500
        onTriggered: { controller.verify(); win.toWelcome() }
    }
    Timer {
        id: welcomeTimer
        interval: 900
        repeat: true
        onTriggered: { if (win.wStep < 4) win.wStep += 1; else stop() }
    }
    Timer {
        id: rebootTimer
        interval: 3500
        onTriggered: controller.rebootNow()
    }

    Connections {
        target: controller
        function onUpdateProgress(value, label) {
            win.updPercent = value
            win.updLabel = label
        }
        function onUpdateFinished(ok, reboot, message) {
            if (!ok) {
                win.updState = "error"
                win.updMessage = message
                return
            }
            win.updPercent = 100
            if (reboot) {
                controller.setStage("after-update")
                win.updState = "reboot"
                win.updLabel = "Restarting to finish the updates"
                rebootTimer.start()
            } else {
                win.toWelcome()
            }
        }
    }

    FileDialog {
        id: photoDialog
        title: "Choose a photo"
        nameFilters: ["Images (*.png *.jpg *.jpeg)"]
        onAccepted: {
            var p = controller.importPhoto(selectedFile.toString())
            if (p !== "") win.avatarPath = p
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
        width: win.width * 0.9
        height: width
        radius: width / 2
        x: win.width * 0.35
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
        anchors.topMargin: 50
        anchors.bottomMargin: 140

        // 0 - hello
        PageBox {
            idx: 0
            current: win.page
            Column {
                anchors.centerIn: parent
                spacing: 26
                Text {
                    id: greetText
                    text: win.greetings[win.greetIndex]
                    color: "#F2F0FA"
                    font.pixelSize: 96
                    font.weight: Font.Bold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Let's set up your computer"
                    color: "#8D89A3"
                    font.pixelSize: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
            SequentialAnimation {
                id: greetAnim
                NumberAnimation { target: greetText; property: "opacity"; to: 0; duration: 300 }
                ScriptAction { script: win.greetIndex = (win.greetIndex + 1) % win.greetings.length }
                NumberAnimation { target: greetText; property: "opacity"; to: 1; duration: 400 }
            }
        }

        // 1 - language and region
        PageBox {
            idx: 1
            current: win.page
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                Text {
                    text: "Language and region"
                    color: "#F2F0FA"
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                Text {
                    visible: win.regionError !== ""
                    text: win.regionError
                    color: "#F2C4CC"
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // 2 - internet
        PageBox {
            idx: 2
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 760)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 14

                Text {
                    text: "Connect to the internet"
                    color: "#F2F0FA"
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: win.online ? (win.ethernet ? "You are connected with a network cable." : "You are connected.")
                                     : "An internet connection lets ChoutesOS install the latest updates. You can skip this step."
                    color: win.online ? "#7FD6A0" : "#8D89A3"
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                ListView {
                    id: wifiView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 10
                    model: win.wifiList
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        width: wifiView.width
                        height: 62
                        radius: 16
                        color: win.selectedSsid === modelData.ssid ? "#241848" : "#14121F"
                        border.width: 1
                        border.color: win.selectedSsid === modelData.ssid ? "#9660F8" : "#2C2842"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 14
                            Text { text: "\u2301"; color: "#9660F8"; font.pixelSize: 22 }
                            Text { text: modelData.ssid; color: "#F2F0FA"; font.pixelSize: 16; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { visible: modelData.secure; text: "\u26BF"; color: "#8D89A3"; font.pixelSize: 15 }
                            Text { visible: modelData.connected; text: "Connected"; color: "#7FD6A0"; font.pixelSize: 13 }
                            Text { text: modelData.signal + "%"; color: "#8D89A3"; font.pixelSize: 13 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                win.selectedSsid = modelData.ssid
                                win.selectedSecure = modelData.secure
                                win.wifiPassword = ""
                                win.wifiMessage = ""
                                if (!modelData.secure) {
                                    win.connecting = true
                                    var r = controller.connectWifi(modelData.ssid, "")
                                    win.connecting = false
                                    win.wifiMessage = r.ok ? "" : r.message
                                    win.refreshInternet()
                                }
                            }
                        }
                    }
                    Text {
                        visible: win.wifiList.length === 0
                        anchors.centerIn: parent
                        text: win.ethernet ? "" : "No Wi-Fi networks found."
                        color: "#8D89A3"
                        font.pixelSize: 15
                    }
                }

                RowLayout {
                    visible: win.selectedSsid !== "" && win.selectedSecure
                    Layout.fillWidth: true
                    spacing: 12
                    Field {
                        Layout.fillWidth: true
                        label: "Password for " + win.selectedSsid
                        password: true
                        onEdited: function (value) { win.wifiPassword = value }
                    }
                    PrimaryButton {
                        text: win.connecting ? "Connecting..." : "Connect"
                        active: !win.connecting && win.wifiPassword.length > 0
                        Layout.alignment: Qt.AlignBottom
                        onClicked: {
                            win.connecting = true
                            var r = controller.connectWifi(win.selectedSsid, win.wifiPassword)
                            win.connecting = false
                            win.wifiMessage = r.ok ? "" : r.message
                            win.refreshInternet()
                        }
                    }
                }
                Text {
                    visible: win.wifiMessage !== ""
                    text: win.wifiMessage
                    color: "#F2C4CC"
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // 3 - account
        PageBox {
            idx: 3
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 560)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: "Create your account"
                    color: "#F2F0FA"
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }

                Row {
                    spacing: 10
                    Layout.alignment: Qt.AlignHCenter
                    Repeater {
                        model: win.avatarItems
                        delegate: Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: "transparent"
                            border.width: 3
                            border.color: win.avatarPath === modelData.path ? "#9660F8" : "transparent"
                            scale: avMouse.containsMouse ? 1.08 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                source: "file://" + modelData.path
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                            }
                            MouseArea {
                                id: avMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.avatarPath = modelData.path
                            }
                        }
                    }
                    Rectangle {
                        width: 52
                        height: 52
                        radius: 26
                        color: "#14121F"
                        border.width: 1
                        border.color: "#2C2842"
                        Text { anchors.centerIn: parent; text: "+"; color: "#9660F8"; font.pixelSize: 26 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: photoDialog.open()
                        }
                    }
                }

                Field {
                    Layout.fillWidth: true
                    label: "Full name"
                    placeholder: "Your name"
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
                Field {
                    Layout.fillWidth: true
                    label: "Computer name"
                    text: win.hostname
                    hint: !win.hostnameOk(win.hostname) ? "Letters, digits and hyphens only." : ""
                    onEdited: function (value) { win.hostname = value }
                }
                RowLayout {
                    spacing: 12
                    Rectangle {
                        width: 24
                        height: 24
                        radius: 7
                        color: win.autologin ? "#5B18E5" : "#14121F"
                        border.width: 1
                        border.color: win.autologin ? "#9660F8" : "#2C2842"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text { anchors.centerIn: parent; visible: win.autologin; text: "\u2713"; color: "#FFFFFF"; font.pixelSize: 15 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.autologin = !win.autologin }
                    }
                    Text { text: "Log in automatically"; color: "#B9B5CE"; font.pixelSize: 14 }
                }
                Text {
                    visible: win.accountError !== ""
                    text: win.accountError
                    color: "#F2C4CC"
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // 4 - updates
        PageBox {
            idx: 4
            current: win.page
            ColumnLayout {
                width: Math.min(parent.width, 700)
                anchors.centerIn: parent
                spacing: 20

                Image {
                    source: "../assets/logo.png"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 110
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.05; duration: 1800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: win.updState === "checking" ? "Almost there" : (win.updState === "reboot" ? "Restarting soon" : "Getting the latest updates")
                    color: "#F2F0FA"
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: win.updState === "error" ? win.updMessage : win.updLabel
                    color: win.updState === "error" ? "#F2C4CC" : "#B9B5CE"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }
                Rectangle {
                    visible: win.updState !== "checking"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
                    radius: 5
                    color: "#1E1B30"
                    Rectangle {
                        width: parent.width * Math.min(win.updPercent, 100) / 100
                        height: parent.height
                        radius: 5
                        color: win.updState === "error" ? "#C0485A" : "#7A3FF0"
                        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    visible: win.updState === "running" || win.updState === "reboot"
                    text: Math.round(win.updPercent) + " %"
                    color: "#8D89A3"
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    visible: win.updState === "running"
                    text: "This can take a while. Your computer may restart, then you continue setting up."
                    color: "#6F6B86"
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }
                PrimaryButton {
                    visible: win.updState === "error"
                    text: "Continue without updating"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: win.toWelcome()
                }
            }
        }

        // 5 - welcome
        PageBox {
            idx: 5
            current: win.page
            Column {
                anchors.centerIn: parent
                spacing: 24
                Image {
                    source: "../assets/logo.png"
                    width: 170
                    height: 170
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: win.wStep >= 1 ? 1 : 0
                    scale: win.wStep >= 1 ? 1 : 0.6
                    Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 900; easing.type: Easing.OutBack } }
                }
                Text {
                    text: "Welcome to ChoutesOS"
                    color: "#F2F0FA"
                    font.pixelSize: 56
                    font.weight: Font.Bold
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: win.wStep >= 2 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                }
                Text {
                    text: "Fast, smooth and made for you."
                    color: "#B9B5CE"
                    font.pixelSize: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: win.wStep >= 3 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // ------------------------------------------------------------ finishing overlay
    Rectangle {
        anchors.fill: parent
        color: "#0B0A12"
        opacity: win.finishing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 500 } }
        Text {
            anchors.centerIn: parent
            text: "Starting ChoutesOS..."
            color: "#B9B5CE"
            font.pixelSize: 20
        }
    }

    // ------------------------------------------------------------ footer
    RowLayout {
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
                model: 6
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
            visible: win.page === 2
            text: "Skip"
            primary: false
            onClicked: win.next()
        }
        PrimaryButton {
            visible: win.page === 1 || win.page === 3
            text: "Back"
            primary: false
            onClicked: win.page = win.page - 1
        }
        PrimaryButton {
            visible: win.page <= 3
            text: win.page === 0 ? "Continue" : (win.page === 3 ? (win.creating ? "Creating..." : "Create account") : "Continue")
            active: (win.page !== 2 || win.online) && (win.page !== 3 || (win.accountValid && !win.creating))
            onClicked: win.next()
        }
        PrimaryButton {
            visible: win.page === 5 && win.wStep >= 4 && !win.finishing
            text: "Get started"
            onClicked: { win.finishing = true; controller.finishSetup(win.autologin) }
        }
    }
}

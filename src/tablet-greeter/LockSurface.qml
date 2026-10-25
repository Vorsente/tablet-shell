// Shared login / lock screen (iPadOS-like): wallpaper, big clock and date, notifications (lock),
// swipe up / tap / type to reveal the password; the wallpaper blurs behind it.
// Used by the login screen (tablet-greeter, greetd) and by the lock screen (kscreenlocker); both
// read the same settings (cfg, from /var/lib/tablet-greeter/lock.conf, edited in Настройки).
//
// auth: adapter object of the wrapper with
//   fullName, avatar, busy, passwordless, mode ("login" | "lock"),
//   touchFirst (optional: false = a hardware keyboard is there, the on-screen one stays down),
//   login(password), unlockNow(), powerOff(), reboot(), suspend(), signals failed(msg), succeeded()
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "Tr.js" as Tr

Item {
    id: root

    required property QtObject auth
    property var cfg: ({})
    property Item wallpaperItem: null           // lock screen: Plasma's wallpaper item
    property string wallpaperFile: ""           // login screen: an image file
    property var notifications: null            // lock screen: notification model
    property var player: null                   // lock screen: the MPRIS player playing now
    readonly property bool showPlayer: auth.mode === "lock" && !!player && !!player.track
                                       && String(opt("showMedia", true)) === "true"

    readonly property bool pixel: String(opt("shellStyle", "apple")) === "pixel"
    readonly property color pixelSurface: "#312E3A"
    readonly property color pixelOnSurface: "#F1EBF5"
    function opt(key, def) {
        const v = cfg[key];
        return v === undefined || v === "" ? def : v;
    }
    readonly property bool clock24: String(opt("clock24", true)) === "true"
    readonly property bool showDate: String(opt("showDate", true)) === "true"
    readonly property real clockScale: Number(opt("clockScale", 100)) / 100
    readonly property bool clockBold: opt("clockWeight", "bold") === "bold"
    readonly property bool blurOn: String(opt("blur", true)) === "true"
    readonly property real blurAmount: Number(opt("blurAmount", 100)) / 100
    readonly property real dim: Number(opt("dim", 25)) / 100
    readonly property bool showHint: String(opt("showHint", true)) === "true"
    readonly property string osk: opt("osk", "auto")            // auto | always | button
    readonly property bool showUser: String(opt("showUser", true)) === "true"
    readonly property bool powerButtons: auth.mode === "login" && String(opt("powerButtons", true)) === "true"
    readonly property bool showNotifications: auth.mode === "lock" && String(opt("showNotifications", true)) === "true"
    readonly property bool notificationText: String(opt("notificationText", true)) === "true"

    readonly property real u: Math.min(width / 64, height / 40)
    property bool unlocking: false
    property bool leaving: false
    property string password: ""
    property string message: ""
    property bool touchKeyboard: osk === "always"

    focus: true
    Keys.onPressed: event => {
        if (root.leaving) {
            return;
        }
        if (!root.unlocking) {
            root.reveal(false);
        }
        if (root.osk !== "always") {
            root.touchKeyboard = false;
        }
        if (event.key === Qt.Key_Escape) {
            root.unlocking = false;
            root.password = "";
        } else if (event.key === Qt.Key_Backspace) {
            root.password = root.password.slice(0, -1);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit();
        } else if (event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
            root.password += event.text;
            root.message = "";
        }
        event.accepted = true;
    }

    // show the password panel; by touch the on-screen keyboard comes along (osk "auto")
    function reveal(byTouch) {
        if (auth.passwordless) {
            auth.unlockNow();
            return;
        }
        unlocking = true;
        if (byTouch && osk === "auto" && auth.touchFirst !== false) {
            touchKeyboard = true;
        }
    }
    function submit() {
        if (root.password.length === 0 || auth.busy) {
            return;
        }
        auth.login(root.password);
    }

    Connections {
        target: root.auth
        function onFailed(message) {
            root.message = message;
            root.password = "";
            shake.restart();
        }
        function onSucceeded() {
            root.leaving = true;
        }
    }

    // ---- wallpaper ----
    Image {
        id: wallpaperImage
        anchors.fill: parent
        source: root.wallpaperFile ? "file://" + root.wallpaperFile : ""
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.wallpaperFile && !root.wallpaperItem
        gradient: Gradient {
            GradientStop { position: 0; color: "#1c2a4a" }
            GradientStop { position: 1; color: "#05070d" }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: root.wallpaperItem ? root.wallpaperItem : wallpaperImage
        visible: !!root.wallpaperItem || !!root.wallpaperFile
        blurEnabled: root.blurOn
        blurMax: 64
        blur: root.unlocking ? root.blurAmount : 0
        brightness: -(root.unlocking ? Math.min(0.6, root.dim + 0.15) : root.dim)
        Behavior on blur { NumberAnimation { duration: 250 } }
        Behavior on brightness { NumberAnimation { duration: 250 } }
    }

    // ---- clock ----
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            interval = 60000 - root.now.getSeconds() * 1000 - root.now.getMilliseconds() + 50;
            restart();
        }
    }

    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.unlocking ? root.height * 0.06 : root.height * 0.12
        scale: root.unlocking ? 0.55 : 1
        transformOrigin: Item.Top
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate
            text: root.now.toLocaleDateString(Tr.locale(), "dddd, d MMMM")
            color: "white"
            font.family: root.pixel ? "Noto Sans" : "Inter"
            font.pixelSize: root.u * 1.4 * root.clockScale
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                const time = Qt.formatTime(root.now, root.clock24 ? "HH:mm" : "h:mm");
                return root.pixel && !root.unlocking && root.height > root.width ? time.replace(":", "\n") : time;
            }
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 0.85
            color: "white"
            font.family: root.pixel ? "Noto Sans" : "Inter"
            font.pixelSize: root.u * (root.pixel ? 6.5 : 8) * root.clockScale
            font.weight: root.pixel ? Font.Medium : (root.clockBold ? Font.Bold : Font.Light)
            font.letterSpacing: root.pixel ? 0 : -root.u * 0.15
            font.features: { "tnum": 1 }
        }
    }

    // ---- now playing (lock screen) ----
    Rectangle {
        id: media
        anchors.horizontalCenter: parent.horizontalCenter
        y: clock.y + clock.height + root.u * 1.2
        width: Math.min(root.width * 0.5, root.u * 26)
        height: root.showPlayer ? root.u * 4.4 : 0
        visible: root.showPlayer && !root.unlocking
        radius: root.pixel ? root.u * 2.2 : root.u * 0.9
        color: root.pixel ? root.pixelSurface : Qt.rgba(1, 1, 1, 0.2)

        Rectangle {    // cover
            id: cover
            x: root.u * 0.6
            anchors.verticalCenter: parent.verticalCenter
            width: root.u * 3.2
            height: width
            radius: root.u * 0.5
            color: Qt.rgba(1, 1, 1, 0.15)
            clip: true
            Image {
                anchors.fill: parent
                source: root.player && root.player.artUrl ? root.player.artUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: !(root.player && root.player.artUrl)
                text: "♪"
                color: "white"
                font.pixelSize: root.u * 1.4
            }
        }
        Column {
            anchors.left: cover.right
            anchors.leftMargin: root.u * 0.7
            anchors.right: controls.left
            anchors.rightMargin: root.u * 0.5
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: root.player ? root.player.track : ""
                color: "white"
                elide: Text.ElideRight
                font.family: root.pixel ? "Noto Sans" : "Inter"
                font.pixelSize: root.u * 0.8
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: root.player ? (root.player.artist || root.player.identity || "") : ""
                color: Qt.rgba(1, 1, 1, 0.7)
                elide: Text.ElideRight
                font.family: root.pixel ? "Noto Sans" : "Inter"
                font.pixelSize: root.u * 0.7
            }
        }
        Row {
            id: controls
            anchors.right: parent.right
            anchors.rightMargin: root.u * 0.6
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.u * 0.2
            Repeater {
                model: [
                    { glyph: "⏮", enabled: root.player && root.player.canGoPrevious, act: "Previous" },
                    { glyph: root.player && root.player.playbackStatus === 2 ? "⏸" : "▶", enabled: root.player && root.player.canControl, act: "PlayPause" },
                    { glyph: "⏭", enabled: root.player && root.player.canGoNext, act: "Next" },
                ]
                Item {
                    required property var modelData
                    width: root.u * 2
                    height: width
                    opacity: modelData.enabled ? 1 : 0.35
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        color: "white"
                        font.pixelSize: root.u * 1.1
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !!modelData.enabled
                        onClicked: root.player[modelData.act]()
                    }
                }
            }
        }
    }

    // ---- notifications (lock screen) ----
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: clock.y + clock.height + root.u * 1.2 + (media.visible ? media.height + root.u * 0.5 : 0)
        width: Math.min(root.width * 0.5, root.u * 26)
        spacing: root.u * 0.4
        visible: root.showNotifications && !root.unlocking && !!root.notifications
        Repeater {
            model: root.showNotifications ? root.notifications : null
            delegate: Rectangle {
                required property int index
                required property var model
                visible: index < 3
                width: parent.width
                height: visible ? noteColumn.implicitHeight + root.u * 1.0 : 0
                radius: root.pixel ? root.u * 1.5 : root.u * 0.9
                color: root.pixel ? "#34313D" : Qt.rgba(1, 1, 1, 0.2)
                Column {
                    id: noteColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: root.u * 0.8
                    Text {
                        width: parent.width
                        text: model.applicationName || ""
                        color: Qt.rgba(1, 1, 1, 0.75)
                        elide: Text.ElideRight
                        font.family: root.pixel ? "Noto Sans" : "Inter"
                        font.pixelSize: root.u * 0.65
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        width: parent.width
                        text: root.notificationText ? (model.summary || "") : Tr.t("Новое уведомление")
                        color: "white"
                        elide: Text.ElideRight
                        font.family: root.pixel ? "Noto Sans" : "Inter"
                        font.pixelSize: root.u * 0.85
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // swipe up / tap anywhere: show the password panel
    MouseArea {
        anchors.fill: parent
        enabled: !root.unlocking
        onReleased: root.reveal(true)
    }

    // home indicator + hint at the bottom
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.u * 1.2
        spacing: root.u * 0.5
        opacity: root.unlocking ? 0 : 0.9
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showHint
            text: root.auth.passwordless ? Tr.t("Проведите вверх, чтобы открыть") : Tr.t("Проведите вверх, чтобы войти")
            color: "white"
            font.family: root.pixel ? "Noto Sans" : "Inter"
            font.pixelSize: root.u * 0.75
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.u * 7
            height: root.u * 0.28
            radius: height / 2
            color: "white"
        }
    }

    // ---- password panel ----
    ColumnLayout {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.unlocking ? root.height * (root.touchKeyboard ? 0.24 : 0.3) : root.height * 0.42
        opacity: root.unlocking ? 1 : 0
        visible: opacity > 0
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        spacing: root.u * 0.7

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.showUser
            implicitWidth: root.u * 4.2
            implicitHeight: implicitWidth
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.2)
            clip: true
            Image {
                anchors.fill: parent
                source: root.auth.avatar
                visible: root.auth.avatar.length > 0 && status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(width, height)
            }
            Text {
                anchors.centerIn: parent
                visible: root.auth.avatar.length === 0
                text: root.auth.fullName.charAt(0).toUpperCase()
                color: "white"
                font.family: root.pixel ? "Noto Sans" : "Inter"
                font.pixelSize: parent.width * 0.42
                font.weight: Font.DemiBold
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: root.showUser
            text: root.auth.fullName
            color: "white"
            font.family: root.pixel ? "Noto Sans" : "Inter"
            font.pixelSize: root.u * 1.1
            font.weight: Font.DemiBold
        }
        Rectangle {
            id: field
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.u * 15
            implicitHeight: root.u * 2.4
            radius: root.pixel ? height / 2 : height / 2
            color: root.pixel ? root.pixelSurface : Qt.rgba(1, 1, 1, 0.18)
            border.color: Qt.rgba(1, 1, 1, 0.3)
            border.width: 1
            transform: Translate { id: shakeX }
            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: shakeX; property: "x"; to: root.u * 0.6; duration: 50 }
                NumberAnimation { target: shakeX; property: "x"; to: -root.u * 0.6; duration: 100 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
            }
            Text {
                id: entry
                anchors.centerIn: parent
                width: parent.width - root.u * 4
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideLeft
                text: root.password.length ? "●".repeat(root.password.length) : (root.auth.busy ? "" : Tr.t("Пароль"))
                color: root.password.length ? "white" : Qt.rgba(1, 1, 1, 0.6)
                font.family: root.pixel ? "Noto Sans" : "Inter"
                font.pixelSize: root.password.length ? root.u * 0.8 : root.u * 0.9
                font.letterSpacing: root.password.length ? root.u * 0.15 : 0
            }
            // text cursor: after the dots, or in front of the "Пароль" hint while empty
            Rectangle {
                id: caret
                readonly property real gap: root.u * 0.25
                x: root.password.length
                   ? entry.x + (entry.width + Math.min(entry.contentWidth, entry.width)) / 2 + gap
                   : entry.x + (entry.width - entry.contentWidth) / 2 - gap - width
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Math.round(root.u * 0.1))
                height: root.u * 1.1
                radius: width / 2
                color: "white"
                visible: root.unlocking && !root.leaving && !root.auth.busy
                SequentialAnimation on opacity {
                    id: blink
                    running: caret.visible
                    loops: Animation.Infinite
                    PropertyAction { value: 1 }
                    PauseAnimation { duration: 550 }
                    NumberAnimation { to: 0; duration: 120 }
                    PauseAnimation { duration: 330 }
                    NumberAnimation { to: 1; duration: 120 }
                }
                // solid while typing
                Connections {
                    target: root
                    function onPasswordChanged() { blink.restart(); }
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: root.u * 0.3
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - root.u * 0.6
                height: width
                radius: width / 2
                color: root.password.length ? "white" : Qt.rgba(1, 1, 1, 0.25)
                Text {
                    anchors.centerIn: parent
                    text: root.auth.busy ? "…" : "→"
                    color: root.password.length ? "black" : "white"
                    font.pixelSize: parent.height * 0.55
                    font.weight: Font.Bold
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.submit()
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: parent.height
                onClicked: {
                    root.forceActiveFocus();
                    if (root.auth.touchFirst !== false || root.osk === "always") {
                        root.touchKeyboard = true;
                    }
                }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.message
            visible: text.length > 0
            color: "#FF6961"
            font.family: root.pixel ? "Noto Sans" : "Inter"
            font.pixelSize: root.u * 0.8
            font.weight: Font.DemiBold
        }
    }

    // power buttons (login screen) and the keyboard toggle
    component RoundButton: Rectangle {
        property string glyph
        property string caption
        signal activated()
        width: root.u * 2.6
        height: width
        radius: width / 2
        color: area.pressed ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.18)
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: "white"
            font.pixelSize: parent.height * 0.42
        }
        Text {
            anchors.top: parent.bottom
            anchors.topMargin: root.u * 0.25
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.caption
            color: "white"
            font.family: root.pixel ? "Noto Sans" : "Inter"
            font.pixelSize: root.u * 0.6
        }
        MouseArea {
            id: area
            anchors.fill: parent
            onClicked: parent.activated()
        }
    }
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.u * 1.6
        anchors.bottomMargin: root.touchKeyboard ? keyboard.height + root.u * 1.2 : root.u * 2.2
        visible: root.unlocking && !root.leaving && root.powerButtons
        spacing: root.u * 2.4
        RoundButton { glyph: "⏾"; caption: Tr.t("Сон"); onActivated: root.auth.suspend() }
        RoundButton { glyph: "↻"; caption: Tr.t("Перезагрузка"); onActivated: root.auth.reboot() }
        RoundButton { glyph: "⏻"; caption: Tr.t("Выключить"); onActivated: root.auth.powerOff() }
    }
    RoundButton {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: root.u * 1.6
        anchors.bottomMargin: root.touchKeyboard ? keyboard.height + root.u * 1.2 : root.u * 2.2
        visible: root.unlocking && !root.leaving
        glyph: "⌨"
        caption: Tr.t("Клавиатура")
        onActivated: root.touchKeyboard = !root.touchKeyboard
    }

    Keyboard {
        pixel: root.pixel
        id: keyboard
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.touchKeyboard && root.unlocking ? root.height - height : root.height
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        u: root.u
        onTyped: text => { root.password += text; root.message = ""; }
        onBackspace: root.password = root.password.slice(0, -1)
        onEnter: root.submit()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
}

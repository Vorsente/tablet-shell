// Volume / brightness indicator: while a key changes the volume, the screen or keyboard brightness
// (or the microphone, a player), a capsule at the top shows the level as a row of bars, about 1.5 s.
// Other Plasma OSD messages (keyboard layout, Wi-Fi on/off...) appear in the same capsule as text.
// Touches pass through. Data: shell.osdRequested (org.kde.osdService calls seen by tabletshell).
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    flags: Qt.WindowTransparentForInput
    title: Tr.t("Индикатор громкости")
    width: Math.round(gu * 21)
    height: Math.round(gu * (pixel ? 4.4 : 3.8))

    LayerShell.Window.scope: "tabletshell-osd"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.margins.top: Math.round(gu * 2.6)
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property real gu: Kirigami.Units.gridUnit
    readonly property bool pixel: uiStyle.pixel
    readonly property bool materialDark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
    readonly property color ink: pixel ? (materialDark ? "#F4EFF4" : "#1D1B20") : "white"
    readonly property color fill: pixel ? (materialDark ? "#36343B" : "#ECE6F0") : Qt.rgba(0.11, 0.11, 0.13, 0.62)
    readonly property color rim: pixel ? (materialDark ? "#49454F" : "#CAC4D0") : Qt.rgba(1, 1, 1, 0.14)
    readonly property color lit: pixel ? (materialDark ? "#D0BCFF" : "#6750A4") : "white"
    readonly property color unlit: pixel ? (materialDark ? "#49454F" : "#E6E0E9") : Qt.rgba(1, 1, 1, 0.2)
    readonly property int segments: 16

    property string icon: ""
    property string label: ""
    property real level: 0          // 0..1 of the bars
    property bool textOnly: false
    property int percent: 0
    property real shown: 0

    Behavior on level {
        enabled: win.shown > 0.5 && !win.textOnly
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // member and arguments of the org.kde.osdService call
    function show(member, args) {
        const n = i => parseInt(args[i]) || 0;
        const on = args[0] === "true";
        switch (member) {
        case "volumeChanged": {
            const max = args.length > 1 ? Math.max(n(1), 1) : 100;
            const v = n(0);
            bars(v <= 0 ? "audio-volume-muted-symbolic"
                        : v < 34 ? "audio-volume-low-symbolic" : v < 67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic",
                 v <= 0 ? Tr.t("Без звука") : Tr.t("Громкость"), v, max);
            break;
        }
        case "microphoneVolumeChanged":
            bars(n(0) <= 0 ? "microphone-sensitivity-muted-symbolic" : "audio-input-microphone-symbolic",
                 n(0) <= 0 ? Tr.t("Микрофон выключен") : Tr.t("Микрофон"), n(0), 100);
            break;
        case "mediaPlayerVolumeChanged":
            bars(args[2] || "audio-volume-high-symbolic", args[1] || Tr.t("Громкость"), n(0), 100);
            break;
        case "brightnessChanged":
        case "screenBrightnessChanged":
            bars("display-brightness-symbolic", Tr.t("Яркость"), n(0), 100);
            break;
        case "keyboardBrightnessChanged":
            bars("input-keyboard-brightness-symbolic", Tr.t("Подсветка клавиатуры"), n(0), 100);
            break;
        case "showText":
            text(args[0], args[1]);
            break;
        case "kbdLayoutChanged":
            text("input-keyboard-symbolic", args[0]);
            break;
        case "virtualDesktopChanged":
            text("virtual-desktops-symbolic", args[0]);
            break;
        case "powerProfileChanged":
            text("battery-profile-performance-symbolic", args[0]);
            break;
        case "wifiEnabledChanged":
            text(on ? "network-wireless-on-symbolic" : "network-wireless-offline-symbolic", on ? Tr.t("Wi-Fi включён") : Tr.t("Wi-Fi выключен"));
            break;
        case "bluetoothEnabledChanged":
            text(on ? "network-bluetooth-symbolic" : "network-bluetooth-inactive-symbolic", on ? Tr.t("Bluetooth включён") : Tr.t("Bluetooth выключен"));
            break;
        case "touchpadEnabledChanged":
            text(on ? "input-touchpad-on-symbolic" : "input-touchpad-off-symbolic", on ? Tr.t("Тачпад включён") : Tr.t("Тачпад выключен"));
            break;
        case "hide":
            hideTimer.stop();
            fadeOut.start();
            break;
        }
    }

    function bars(iconName, title, value, max) {
        percent = Math.round(value);
        icon = iconName;
        label = title;
        level = Math.max(0, Math.min(1, value / max));   // jumps when coming from a text message
        textOnly = false;
        reveal();
    }

    function text(iconName, title) {
        if (!title) {
            return;
        }
        icon = iconName || "dialog-information-symbolic";
        label = title;
        textOnly = true;
        reveal();
    }

    function reveal() {
        fadeOut.stop();
        visible = true;
        if (shown < 1) {
            fadeIn.start();
        }
        hideTimer.restart();
    }

    NumberAnimation { id: fadeIn; target: win; property: "shown"; to: 1; duration: 140; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: fadeOut
        NumberAnimation { target: win; property: "shown"; to: 0; duration: 220; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }
    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: fadeOut.start()
    }

    // Apple: KWin blurs behind the dark glass capsule
    onVisibleChanged: if (visible) shell.blurBehind(win, pixel ? [] : [{ x: 0, y: 0, width: width, height: height, radius: height / 2 }])

    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: win.pixel ? win.gu * 1.4 : height / 2
        color: win.fill
        border.width: 1
        border.color: win.rim
        opacity: win.shown
        scale: 0.92 + 0.08 * win.shown
        transformOrigin: Item.Top

        Kirigami.Icon {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: win.gu * (win.pixel ? 1.1 : 1.2)
            anchors.verticalCenter: parent.verticalCenter
            source: win.icon
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: implicitWidth
            isMask: true
            color: win.pixel ? win.lit : win.ink
        }

        Column {
            anchors.left: glyph.right
            anchors.leftMargin: win.gu * 0.8
            anchors.right: parent.right
            anchors.rightMargin: win.gu * 1.3
            anchors.verticalCenter: parent.verticalCenter
            spacing: win.gu * 0.3

            Item {
                width: parent.width
                height: title.height
                Text {
                    id: title
                    text: win.label
                    color: win.ink
                    elide: Text.ElideRight
                    width: parent.width - (number.visible ? number.width + win.gu * 0.5 : 0)
                    font.family: Kirigami.Theme.defaultFont.family
                    font.pixelSize: win.gu * 0.78
                    font.weight: Font.DemiBold
                }
                Text {
                    id: number
                    anchors.right: parent.right
                    visible: !win.textOnly
                    text: win.percent + "%"
                    color: win.ink
                    opacity: 0.7
                    font.family: Kirigami.Theme.defaultFont.family
                    font.pixelSize: win.gu * 0.72
                    font.features: { "tnum": 1 }
                }
            }

            // the bars: lit up to the level, the last one partly
            Row {
                id: row
                visible: !win.textOnly
                width: parent.width
                spacing: win.pixel ? win.gu * 0.22 : win.gu * 0.18
                readonly property real barWidth: (width - spacing * (win.segments - 1)) / win.segments
                Repeater {
                    model: win.segments
                    Rectangle {
                        required property int index
                        readonly property real part: Math.max(0, Math.min(1, win.level * win.segments - index))
                        width: row.barWidth
                        height: win.gu * (win.pixel ? 0.55 : 0.42)
                        radius: win.pixel ? height / 2 : height * 0.35
                        color: win.unlit
                        Rectangle {
                            width: parent.width * parent.part
                            height: parent.height
                            radius: parent.radius
                            color: win.lit
                            visible: parent.part > 0
                        }
                    }
                }
            }
        }
    }
}

// Volume / brightness indicator: while a key changes the volume, the screen or keyboard brightness
// (or the microphone, a player), a capsule at the top shows the level as a row of bars, about 1.5 s.
// Other Plasma OSD messages (keyboard layout, Wi-Fi on/off...) appear in the same capsule as text.
// Volume, microphone and screen brightness can be changed right there: drag along the bars; a tap on
// the icon mutes / unmutes. The percentage is optional (tabletrc [Effects] osdPercent).
// Data: shell.osdRequested (org.kde.osdService calls seen by tabletshell).
import QtQuick
import QtQuick.Window

import org.kde.plasma.private.volume as PA
import org.kde.plasma.private.mobileshell.screenbrightnessplugin as ScreenBrightness

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Индикатор громкости")
    width: Math.round(gu * 21)
    height: Math.round(gu * (pixel ? 4.4 : 3.8))

    LayerShell.Window.scope: "tabletshell-osd"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.margins.top: Math.round(gu * 2.6)
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property real gu: (Kirigami.Units.gridUnit * uiStyle.dp)
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
    property bool showPercent: true
    // what the bars stand for: "volume", "mic", "brightness" can be changed here, "" cannot
    property string kind: ""
    property real max: 100         // percent at full bars (volume may go to 150 %)

    ScreenBrightness.ScreenBrightnessUtil { id: brightness }

    Behavior on level {
        enabled: win.shown > 0.5 && !win.textOnly && !drag.pressed
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // member and arguments of the org.kde.osdService call
    function show(member, args) {
        const n = i => parseInt(args[i]) || 0;
        const on = args[0] === "true";
        switch (member) {
        case "volumeChanged": {
            const max = args.length > 1 ? Math.max(n(1), 1) : 100;
            volumeBars(n(0), max);
            break;
        }
        case "microphoneVolumeChanged":
            micBars(n(0));
            break;
        case "mediaPlayerVolumeChanged":
            bars(args[2] || "audio-volume-high-symbolic", args[1] || Tr.t("Громкость"), n(0), 100, "");
            break;
        case "brightnessChanged":
        case "screenBrightnessChanged":
            bars("display-brightness-symbolic", Tr.t("Яркость"), n(0), 100, "brightness");
            break;
        case "keyboardBrightnessChanged":
            bars("input-keyboard-brightness", Tr.t("Подсветка клавиатуры"), n(0), 100, "");
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
            text(on ? "network-wireless-symbolic" : "network-wireless-disconnected-symbolic", on ? Tr.t("Wi-Fi включён") : Tr.t("Wi-Fi выключен"));
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

    function volumeBars(v, top) {
        bars(v <= 0 ? "audio-volume-muted-symbolic"
                    : v < 34 ? "audio-volume-low-symbolic" : v < 67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic",
             v <= 0 ? Tr.t("Без звука") : Tr.t("Громкость"), v, top, "volume");
    }

    function micBars(v) {
        bars(v <= 0 ? "microphone-sensitivity-muted-symbolic" : "audio-input-microphone-symbolic",
             v <= 0 ? Tr.t("Микрофон выключен") : Tr.t("Микрофон"), v, 100, "mic");
    }

    function bars(iconName, title, value, top, what) {
        percent = Math.round(value);
        icon = iconName;
        label = title;
        kind = what;
        max = top;
        level = Math.max(0, Math.min(1, value / top));   // jumps when coming from a text message
        textOnly = false;
        reveal();
    }

    // dragged along the bars: v = 0..1 of the bars
    function setLevel(v) {
        const value = Math.round(v * max);
        if (kind === "volume" && PA.PreferredDevice.sink) {
            PA.PreferredDevice.sink.muted = false;
            PA.PreferredDevice.sink.volume = Math.round(value / 100 * 65536);
            volumeBars(value, max);
        } else if (kind === "mic" && PA.PreferredDevice.source) {
            PA.PreferredDevice.source.muted = false;
            PA.PreferredDevice.source.volume = Math.round(value / 100 * 65536);
            micBars(value);
        } else if (kind === "brightness" && brightness.maxBrightness > 0) {
            brightness.brightness = Math.max(1, Math.round(v * brightness.maxBrightness));
            bars("display-brightness-symbolic", Tr.t("Яркость"), Math.max(1, value), 100, "brightness");
        }
    }

    // tap on the icon: mute / unmute the speakers or the microphone
    function toggleMute() {
        const device = kind === "volume" ? PA.PreferredDevice.sink : kind === "mic" ? PA.PreferredDevice.source : null;
        if (!device) {
            return;
        }
        device.muted = !device.muted;
        const value = device.muted ? 0 : Math.round(device.volume / 65536 * 100);
        if (kind === "volume") {
            volumeBars(value, max);
        } else {
            micBars(value);
        }
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
        showPercent = shell.effectOn("osdPercent", true);
        visible = true;
        if (shown < 1) {
            fadeIn.start();
        }
        if (!drag.pressed && !iconTap.pressed) {
            hideTimer.restart();
        }
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
        onTriggered: if (!drag.pressed) fadeOut.start()
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
            implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
            implicitHeight: implicitWidth
            isMask: true
            color: win.pixel ? win.lit : win.ink
            scale: iconTap.pressed ? 0.85 : 1
            MouseArea {
                id: iconTap
                anchors.fill: parent
                anchors.margins: -win.gu * 0.7
                enabled: win.kind === "volume" || win.kind === "mic"
                onClicked: win.toggleMute()
                onReleased: hideTimer.restart()
            }
        }

        // drag along the bars (the whole width right of the icon, the full height) to set the level
        MouseArea {
            id: drag
            anchors.left: column.left
            anchors.right: column.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            enabled: !win.textOnly && win.kind !== ""
            preventStealing: true
            function apply(x) {
                const p = mapToItem(row, x, 0).x;
                win.setLevel(Math.max(0, Math.min(1, p / row.width)));
            }
            onPressed: m => {
                hideTimer.stop();
                apply(m.x);
            }
            onPositionChanged: m => apply(m.x)
            onReleased: hideTimer.restart()
            onCanceled: hideTimer.restart()
        }

        Column {
            id: column
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
                    visible: !win.textOnly && win.showPercent
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

// Mode change animation: a short full-screen scene shown when the device changes mode. The keyboard
// dock snaps onto the tablet (PC), comes off (tablet), a monitor gets plugged in (dock), the screen
// turns into a sheet of paper (typewriter) or warms up (reading). It also covers the panels while
// they are being reshaped behind it. Touches pass through.
// D-Bus org.ipad.TabletShell ModeTransition(from, to): tablet|pc|dock|typewriter|reading, an empty
// side means the current device mode (tabletd calls it, so do the typewriter and reading-mode scripts).
// Sounds (tabletrc [Modes] transitionSound) are cues on the same timeline: sounds/make-sounds.py
// makes them, the typewriter scene borrows the typewriter's own key and bell sounds.
import QtQuick
import QtQuick.Window
import QtMultimedia

import org.kde.layershell as LayerShell
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    flags: Qt.WindowTransparentForInput
    title: Tr.t("Смена режима")

    LayerShell.Window.scope: "tabletshell-mode"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // ---- scene state, all 0..1 -----------------------------------------------------------------
    property real scrim: 0
    property real zoom: 0     // the camera flies into the device's screen at the end
    property real kb: 0       // keyboard attached
    property real lift: 0     // tablet lifted off the keyboard
    property real bump: 0     // tablet settling onto the keyboard (pulse)
    property real glow: 0     // connector pins light up (pulse)
    property real mon: 0      // external monitor present
    property real cable: 0
    property real monOn: 0    // monitor screen lit
    property real home: 1     // tablet screen: home screen icons
    property real desk: 0     // tablet screen: desktop with a window
    property real paper: 0    // typewriter page
    property real typed: 0    // lines typed on it
    property real warm: 0     // reading mode
    property string caption: ""
    property string subtitle: ""

    readonly property var props: ["scrim", "zoom", "kb", "lift", "bump", "glow", "mon", "cable", "monOn",
                                  "home", "desk", "paper", "typed", "warm"]

    // ---- timeline: keyframes per property, evaluated from one clock ------------------------------
    property real t: 0
    property var tracks: ({})
    // the scene plays up to holdEnd, then waits for ready() (tabletd: the new mode is in place)
    // before it flies into the screen and dissolves into the real one
    property real holdEnd: 0
    property real total: 0
    property bool isReady: false
    property bool waiting: false
    property rect zoomRect: Qt.rect(0, 0, 1, 1)

    function ease(kind, p) {
        switch (kind) {
        case "in": return p * p * p;
        case "out": return 1 - Math.pow(1 - p, 3);
        case "back": { const c = 1.6; return 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2); }
        case "inout": return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(2 - 2 * p, 3) / 2;
        case "pulse": return Math.sin(Math.PI * p);
        default: return p;   // linear
        }
    }
    onTChanged: {
        for (const name in tracks) {
            const keys = tracks[name];
            let v = keys[0].from;
            for (const k of keys) {
                if (t < k.at) {
                    break;
                }
                const p = Math.min(1, (t - k.at) / k.dur);
                v = k.ease === "pulse" ? (p < 1 ? ease("pulse", p) : 0) : k.from + (k.to - k.from) * ease(k.ease, p);
            }
            win[name] = v;
        }
        while (cue < cues.length && cues[cue].at <= t) {
            sfx(cues[cue++].name);
        }
    }

    // ---- sounds ---------------------------------------------------------------------------------
    property bool sound: false
    property var cues: []
    property int cue: 0
    readonly property string soundDir: "file://" + shell.env("HOME") + "/.local/share/tabletshell/sounds/"
    readonly property string typewriterDir: "file://" + shell.env("HOME") + "/.local/share/typewriter/sounds/"
    SoundEffect { id: snapSound; source: win.soundDir + "snap.wav"; volume: 0.7 }
    SoundEffect { id: releaseSound; source: win.soundDir + "release.wav"; volume: 0.6 }
    SoundEffect { id: connectSound; source: win.soundDir + "connect.wav"; volume: 0.5 }
    SoundEffect { id: disconnectSound; source: win.soundDir + "disconnect.wav"; volume: 0.5 }
    SoundEffect { id: warmSound; source: win.soundDir + "warm.wav"; volume: 0.5 }
    SoundEffect { id: whooshSound; source: win.soundDir + "whoosh.wav"; volume: 0.45 }
    SoundEffect { id: keySound; source: win.typewriterDir + "key.wav"; volume: 0.4 }
    SoundEffect { id: bellSound; source: win.typewriterDir + "return.wav"; volume: 0.4 }
    function sfx(name) {
        if (!sound) {
            return;
        }
        const effect = { snap: snapSound, release: releaseSound, connect: connectSound, disconnect: disconnectSound,
                         warm: warmSound, whoosh: whooshSound, key: keySound, bell: bellSound }[name];
        effect.stop();
        effect.play();
    }

    function deviceMode() {
        return shell.tabletMode ? "tablet" : "pc";
    }
    function base(mode) {
        const s = { kb: 0, mon: 0, cable: 0, monOn: 0, home: 1, desk: 0, paper: 0, typed: 0, warm: 0 };
        const pc = { kb: 1, home: 0, desk: 1 };
        if (mode === "pc" || mode === "dock") {
            Object.assign(s, pc);
        }
        if (mode === "dock") {
            Object.assign(s, { mon: 1, cable: 1, monOn: 1 });
        }
        if (mode === "typewriter" || mode === "reading") {
            Object.assign(s, base(deviceMode()), mode === "typewriter" ? { paper: 1, typed: 1 } : { warm: 1 });
        }
        return s;
    }

    function play(from, to, withSound) {
        from = from || deviceMode();
        to = to || deviceMode();
        const a = base(from), b = base(to);
        const now = Object.assign({ scrim: 0, zoom: 0, lift: 0, bump: 0, glow: 0 }, a);
        const tr = {};
        function key(name, value, at, dur, kind) {
            (tr[name] = tr[name] || []).push({ from: now[name], to: value, at: at, dur: dur, ease: kind || "out" });
            if (kind !== "pulse") {
                now[name] = value;
            }
        }
        function pulse(name, at, dur) {
            (tr[name] = tr[name] || []).push({ from: 0, to: 0, at: at, dur: dur, ease: "pulse" });
        }
        const cs = [];
        function cueAt(at, name) {
            cs.push({ at: at, name: name });
        }
        function screens(at) {
            if (a.home !== b.home) {
                key("home", b.home, at, 400);
                key("desk", b.desk, at, 400);
            }
        }

        key("scrim", 1, 0, 200);
        let c = 300;
        // first take away what goes, then the keyboard, then add what comes
        if (a.mon > b.mon) {
            key("monOn", 0, c, 250);
            key("cable", 0, c + 150, 300, "in");
            key("mon", 0, c + 250, 400, "in");
            cueAt(c, "disconnect");
            c += 700;
        }
        if (a.paper > b.paper) {
            key("typed", 0, c, 300, "in");
            key("paper", 0, c + 150, 400);
            c += 600;
        }
        if (a.warm > b.warm) {
            key("warm", 0, c, 600);
            cueAt(c, "release");
            c += 600;
        }
        if (a.kb < b.kb) {
            key("kb", 1, c, 750, "back");
            cueAt(c + 560, "snap");
            pulse("bump", c + 600, 280);
            pulse("glow", c + 600, 600);
            screens(c + 750);
            c += 1200;
        } else if (a.kb > b.kb) {
            key("lift", 1, c, 320);
            key("kb", 0, c + 220, 600, "in");
            cueAt(c + 200, "release");
            key("lift", 0, c + 800, 450, "back");
            screens(c + 800);
            c += 1300;
        } else if (a.home !== b.home) {
            screens(c);
            c += 450;
        }
        if (a.mon < b.mon) {
            key("mon", 1, c, 650, "back");
            key("cable", 1, c + 450, 400);
            pulse("glow", c + 750, 500);
            key("monOn", 1, c + 850, 400);
            cueAt(c + 700, "connect");
            c += 1300;
        }
        if (a.paper < b.paper) {
            key("paper", 1, c, 500);
            key("typed", 1, c + 400, 1200, "linear");
            // key strikes while the lines appear, the bell at the end
            for (let at = c + 420; at < c + 1560; at += 75 + Math.random() * 60) {
                cueAt(at, "key");
            }
            cueAt(c + 1620, "bell");
            c += 1650;
        }
        if (a.warm < b.warm) {
            key("warm", 1, c, 800);
            cueAt(c, "warm");
            c += 900;
        }
        holdEnd = c + 700;
        key("zoom", 1, holdEnd, 850, "inout");
        key("scrim", 0, holdEnd + 700, 400);
        total = holdEnd + 1100;
        // nobody reports readiness for the typewriter and reading mode
        isReady = [from, to].some(m => m === "typewriter" || m === "reading");
        waiting = false;

        cs.sort((x, y) => x.at - y.at);
        cues = cs;
        cue = 0;
        sound = !!withSound;
        mode = to;
        caption = titleFor(to);
        subtitle = subtitleFor(from, to);
        clock.stop();
        for (const name of props) {
            win[name] = (tr[name] ? tr[name][0].from : now[name]);
        }
        tracks = tr;
        t = 0;
        visible = true;
        run(0, holdEnd);
    }

    function run(from, to) {
        clock.stop();
        clock.from = from;
        clock.to = to;
        clock.duration = to - from;
        clock.start();
    }
    function ready() {
        isReady = true;
        if (waiting) {
            finish();
        }
    }
    function finish() {
        waiting = false;
        safety.stop();
        sfx("whoosh");
        const target = mode === "dock" ? monScreen : screen;
        zoomRect = target.mapToItem(camera, 0, 0, target.width, target.height);
        run(t, total);
    }
    property string mode: ""

    // freeze on one frame (for checking the drawing: tabletshell modetest)
    function seek(ms) {
        clock.stop();
        sound = false;
        if (ms > holdEnd) {
            finish();
            clock.stop();
        }
        t = ms;
    }

    function titleFor(to) {
        return { tablet: Tr.t("Режим планшета"), pc: Tr.t("Режим ПК"), dock: Tr.t("Режим док-станции"),
                 typewriter: Tr.t("Печатная машинка"), reading: Tr.t("Режим чтения") }[to] || "";
    }
    function subtitleFor(from, to) {
        if (to === "dock") return Tr.t("Рабочий стол — на внешнем мониторе");
        if (to === "typewriter") return Tr.t("Только текст, без уведомлений");
        if (to === "reading") return Tr.t("Тёплый экран, без уведомлений");
        if (from === "typewriter") return Tr.t("Печатная машинка закрыта");
        if (from === "reading") return Tr.t("Режим чтения выключен");
        if (from === "dock" && to === "pc") return Tr.t("Внешний монитор отключён");
        return to === "tablet" ? Tr.t("Клавиатура отключена") : Tr.t("Клавиатура подключена");
    }

    NumberAnimation {
        id: clock
        target: win
        property: "t"
        from: 0
        easing.type: Easing.Linear
        onFinished: {
            if (win.t < win.total) {
                if (win.isReady) {
                    win.finish();
                } else {
                    win.waiting = true;
                    safety.start();
                }
                return;
            }
            win.visible = false;
            win.tracks = ({});
        }
    }
    // while waiting the scene stays alive: the device floats, dots pulse under the caption
    property real idle: 0
    NumberAnimation on idle {
        running: win.waiting
        from: 0
        to: 1
        duration: 1400
        loops: Animation.Infinite
    }
    readonly property real float: waiting ? Math.sin(idle * 2 * Math.PI) * 5 : 0

    // never cover the screen for long if nobody says the mode is ready
    Timer {
        id: safety
        interval: 5000
        onTriggered: win.ready()
    }

    // ---- drawing --------------------------------------------------------------------------------
    // opaque: whatever changes behind it (panels, windows) is never seen
    Rectangle {
        anchors.fill: parent
        opacity: win.scrim
        gradient: Gradient {
            GradientStop { position: 0; color: "#101018" }
            GradientStop { position: 1; color: "#1c1830" }
        }
    }

    // tablet screen wallpaper (also on the monitor)
    component Wallpaper: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0; color: "#2f6fd6" }
            GradientStop { position: 0.55; color: "#6a4fd8" }
            GradientStop { position: 1; color: "#c2569b" }
        }
    }
    // a desktop app window
    component AppWindow: Rectangle {
        radius: 4
        color: "#ececf0"
        Rectangle {
            width: parent.width; height: 12
            radius: 4
            color: "#d4d4da"
            Row {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater {
                    model: ["#ff5f57", "#febc2e", "#28c840"]
                    Rectangle { width: 5; height: 5; radius: 2.5; color: modelData }
                }
            }
        }
        Column {
            x: 10; y: 22
            spacing: 6
            Repeater {
                model: [0.8, 0.6, 0.72, 0.4]
                Rectangle { width: (parent.parent.width - 20) * modelData; height: 4; radius: 2; color: "#b8b8c2" }
            }
        }
    }

    // camera: at the end it flies into the screen of the drawn device (zoomRect) until that
    // screen covers the whole display
    Item {
        id: camera
        anchors.fill: parent
        transform: Matrix4x4 {
            matrix: {
                const r = win.zoomRect;
                const S = Math.max(win.width / r.width, win.height / r.height);
                const s = Math.pow(S, win.zoom);
                const k = S > 1 ? (s - 1) / (S - 1) : 0;
                const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
                return Qt.matrix4x4(s, 0, 0, cx * (1 - s) + (win.width / 2 - cx) * k,
                                    0, s, 0, cy * (1 - s) + (win.height / 2 - cy) * k,
                                    0, 0, 1, 0,
                                    0, 0, 0, 1);
            }
        }

        Item {
            id: stage
            width: 820
            height: 520
            anchors.centerIn: parent
            scale: Math.min(1, win.width / 900, win.height / 620) * (0.94 + 0.06 * win.scrim)
            opacity: win.scrim

            readonly property real cx: width / 2

            // ---- external monitor ----
            Item {
                id: monitor
                width: 340
                height: 262
                x: stage.cx + 40 + (1 - win.mon) * 90
                y: 40 - win.float
                opacity: Math.min(1, win.mon * 1.4)
                scale: 0.7 + 0.3 * win.mon
                transformOrigin: Item.Bottom

                Rectangle {
                    id: monBody
                    width: parent.width
                    height: 212
                    radius: 10
                    color: "#1c1c1e"
                    border.color: "#48484a"
                    Rectangle {
                        id: monScreen
                        anchors.fill: parent
                        anchors.margins: 8
                        radius: 4
                        color: "black"
                        clip: true
                        Wallpaper {
                            anchors.fill: parent
                            opacity: win.monOn
                            AppWindow { x: 30; y: 22; width: 170; height: 110 }
                            AppWindow { x: 140; y: 60; width: 140; height: 90 }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 14
                                color: "#cc000000"
                            }
                        }
                    }
                }
                Rectangle {   // neck
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: monBody.height
                    width: 36; height: 40
                    color: "#3a3a3c"
                }
                Rectangle {   // foot
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: monBody.height + 38
                    width: 130; height: 10
                    radius: 5
                    color: "#48484a"
                }
            }

            // ---- cable from the keyboard dock to the monitor ----
            Rectangle {
                readonly property real x0: device.x + device.width * device.scale - 20
                readonly property real x1: monitor.x + monitor.width / 2 - 65
                x: x0
                y: 292
                width: Math.max(0, (x1 - x0) * win.cable)
                height: 3
                radius: 1.5
                color: "#8e8e93"
                opacity: win.cable > 0 ? 1 : 0
                Rectangle {   // plug
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 7; radius: 2
                    color: "#aeaeb2"
                }
            }

            // ---- tablet + keyboard dock ----
            Item {
                id: device
                width: 320
                height: 330
                x: stage.cx - width / 2 - win.mon * 230
                y: 30 + win.mon * 40 + win.float
                scale: 1 - win.mon * 0.22
                transformOrigin: Item.TopLeft

                // keyboard deck, tilted into the screen
                Item {
                    id: keyboard
                    width: parent.width
                    height: 180
                    y: tablet.height - 4 + (1 - win.kb) * 240
                    opacity: Math.min(1, win.kb * 1.6)
                    transform: Rotation {
                        origin.x: keyboard.width / 2
                        origin.y: 0
                        axis { x: 1; y: 0; z: 0 }
                        angle: 58
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "#1d1d20"
                        border.color: "#3a3a3d"
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 14
                            spacing: 4
                            Repeater {
                                model: 5
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 4
                                    Repeater {
                                        model: 13
                                        Rectangle { width: 18; height: 16; radius: 3; color: "#38383c" }
                                    }
                                }
                            }
                            Rectangle {   // space bar row
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 120; height: 16; radius: 3
                                color: "#38383c"
                            }
                        }
                        Rectangle {   // touchpad
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            width: 96; height: 34; radius: 5
                            color: "#2a2a2e"
                            border.color: "#3a3a3d"
                        }
                    }
                }

                // the tablet itself (ThinkPad 10: 16:10, black)
                Rectangle {
                    id: tablet
                    width: parent.width
                    height: 206
                    y: -win.lift * 60 + win.bump * 6
                    radius: 14
                    color: "#111113"
                    border.color: "#4a4a4e"

                    Rectangle {
                        id: screen
                        anchors.fill: parent
                        anchors.margins: 10
                        radius: 5
                        color: "black"
                        clip: true

                        Wallpaper { anchors.fill: parent }

                        // home screen: app icons + dock
                        Item {
                            anchors.fill: parent
                            opacity: win.home
                            Grid {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 22
                                columns: 7
                                spacing: 13
                                Repeater {
                                    model: ["#ff9f0a", "#30d158", "#0a84ff", "#ff375f", "#ffd60a", "#64d2ff", "#bf5af2",
                                            "#ff453a", "#5e5ce6", "#32d74b", "#ac8e68", "#66d4cf", "#ff9f0a", "#0a84ff",
                                            "#e5e5ea", "#30d158", "#ff375f"]
                                    Rectangle { width: 24; height: 24; radius: 7; color: modelData }
                                }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 8
                                width: 150; height: 30; radius: 10
                                color: "#55ffffff"
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Repeater {
                                        model: ["#ff9f0a", "#0a84ff", "#30d158", "#8e8e93"]
                                        Rectangle { width: 20; height: 20; radius: 6; color: modelData }
                                    }
                                }
                            }
                        }

                        // PC: a window and a task bar
                        Item {
                            anchors.fill: parent
                            opacity: win.desk
                            AppWindow { x: 26; y: 18; width: 190; height: 120 }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 16
                                color: "#cc000000"
                                Row {
                                    x: 6; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Repeater {
                                        model: ["#ffffff", "#ff9f0a", "#0a84ff", "#30d158"]
                                        Rectangle { width: 10; height: 10; radius: 3; color: modelData }
                                    }
                                }
                            }
                        }

                        // typewriter: a sheet of paper being typed on
                        Rectangle {
                            anchors.fill: parent
                            color: "#f4f1ea"
                            opacity: win.paper
                            Column {
                                x: 40; y: 26
                                spacing: 9
                                Repeater {
                                    id: lines
                                    model: [0.5, 0.95, 0.9, 0.98, 0.6, 0.92, 0.75]
                                    Rectangle {
                                        required property real modelData
                                        required property int index
                                        width: 200 * modelData * Math.max(0, Math.min(1, win.typed * lines.count - index))
                                        height: 5
                                        radius: 1
                                        color: index === 0 ? "#1c1c1e" : "#55555a"
                                    }
                                }
                            }
                        }

                        // reading: warm light and a page of text
                        Rectangle {
                            anchors.fill: parent
                            color: "#f3e3c3"
                            opacity: win.warm * 0.92
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                Repeater {
                                    model: [1, 1, 0.95, 1, 0.7, 1, 0.9, 0.5]
                                    Rectangle { width: 170 * modelData; height: 4; radius: 2; color: "#7a6a52" }
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "#ff9500"
                            opacity: win.warm * 0.18
                        }
                    }

                    // pogo pins on the bottom edge
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.bottom
                        width: 150; height: 18; radius: 9
                        color: "#0a84ff"
                        opacity: win.glow * 0.35
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.bottom
                        width: 110; height: 4; radius: 2
                        color: "#64d2ff"
                        opacity: win.glow
                    }
                }
            }

            // ---- caption ----
            Column {
                opacity: 1 - Math.min(1, win.zoom * 3)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10 - (1 - win.scrim) * 16
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.caption
                    color: "white"
                    font.pixelSize: 32
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.subtitle
                    color: "white"
                    opacity: 0.7
                    font.pixelSize: 17
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        opacity: win.waiting ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 7; height: 7; radius: 3.5
                                color: "white"
                                opacity: 0.25 + 0.75 * Math.max(0, Math.sin((win.idle - index * 0.15) * 2 * Math.PI))
                            }
                        }
                    }
            }
        }
    }
}

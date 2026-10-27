// Typewriter pill in the top-right corner, above the fullscreen editor: words written today
// against the daily goal, battery and clock, and a × that leaves typewriter mode (closes the
// editor like its close button would, so ghostwriter saves; ~/.local/bin/typewriter then restores
// everything). Plays typewriter sounds on key presses.
// ≡ opens the typewriter panel (scenes, statistics, versions, export: TypewriterPanel.qml).
// Today's running word count is kept in $XDG_RUNTIME_DIR/typewriter-live for the statistics and
// the home screen widgets.
// Started by ~/.local/bin/typewriter, which passes TYPEWRITER_* variables; coding mode starts it
// with PILL_MODE=coding: battery and clock only, × closes the coding terminal.
import QtQuick
import QtQuick.Window
import QtMultimedia

import org.kde.layershell as LayerShell
import "Tr.js" as Tr

Window {
    id: win
    visible: true
    color: "transparent"
    width: label.implicitWidth + (menuButton.visible ? menuButton.width : 0) + exitButton.width + 36 * uiStyle.dp
    height: Math.max(label.implicitHeight + 10 * uiStyle.dp, 30 * uiStyle.dp)

    LayerShell.Window.scope: "tabletshell-pill"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 6 * uiStyle.dp
    LayerShell.Window.margins.right: 10 * uiStyle.dp
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    property string text: ""
    readonly property bool coding: shell.env("PILL_MODE") === "coding"
    readonly property string file: shell.env("TYPEWRITER_FILE")
    readonly property int baseline: parseInt(shell.env("TYPEWRITER_BASELINE")) || 0
    readonly property int earlierToday: parseInt(shell.env("TYPEWRITER_TODAY")) || 0
    readonly property int goal: parseInt(shell.env("TYPEWRITER_GOAL")) || 0
    readonly property bool sounds: shell.env("TYPEWRITER_SOUND") === "1"
    property int today: earlierToday
    readonly property bool goalReached: goal > 0 && today >= goal
    property bool celebrate: false
    onGoalReachedChanged: if (goalReached && today > earlierToday) {
        celebrate = true;
        celebrateTimer.restart();
    }
    Timer { id: celebrateTimer; interval: 4000; onTriggered: win.celebrate = false }

    // running time of the screenplay (page ~ minute), recounted once a minute
    property string runtime: ""
    property int refreshes: 0
    function minutes(secs) {
        return Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0");
    }

    function refresh() {
        if (file && refreshes++ % 12 === 0) {
            try {
                runtime = minutes(JSON.parse(shell.run([shell.env("HOME") + "/.local/bin/tablet-tools", "typewriter-runtime", file])).seconds);
            } catch (e) {
                runtime = "";
            }
        }
        if (file) {
            today = parseInt(shell.run(["sh", "-c",
                'w=$(wc -w < "$1"); t=$(( $2 + (w > $3 ? w - $3 : 0) )); printf %s "$t" > "${XDG_RUNTIME_DIR:-/tmp}/typewriter-live"; echo "$t"',
                "sh", file, String(earlierToday), String(baseline)])) || earlierToday;
        }
        const pct = shell.readFile(shell.batteryDir() + "/capacity");
        const charging = shell.readFile(shell.batteryDir() + "/status") === "Charging";
        const words = goal > 0 ? (goalReached ? "✓ " : "") + today + "/" + goal + Tr.t(" слов   ") : "";
        text = words + (runtime ? "⏱ " + runtime + "   " : "") + (charging ? "⚡" : "") + pct + "%   " + Qt.formatTime(new Date(), "HH:mm");
        if (celebrate) {
            text = Tr.t("🎉 Цель на сегодня!   ") + text;
        }
    }

    // Typewriter sounds: a strike per key, carriage return + bell on Enter
    SoundEffect { id: keySound; source: "file://" + shell.env("HOME") + "/.local/share/typewriter/sounds/key.wav"; volume: 0.5 }
    SoundEffect { id: returnSound; source: "file://" + shell.env("HOME") + "/.local/share/typewriter/sounds/return.wav"; volume: 0.5 }
    Connections {
        target: win.sounds ? shell : null
        function onKeyPressed(code) {
            if (code === 28 || code === 96) {   // KEY_ENTER, KEY_KPENTER
                returnSound.play();
            } else {
                keySound.stop();
                keySound.play();
            }
        }
    }

    Component.onCompleted: refresh()
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: win.refresh()
    }

    onCelebrateChanged: refresh()

    TypewriterPanel {
        id: typewriterPanel
        file: win.file
        dir: shell.env("TYPEWRITER_DIR") || (shell.env("HOME") + "/Сценарии")
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: uiStyle.pixel ? (win.celebrate ? "#81C995" : "#403949") : win.celebrate ? Qt.rgba(48 / 255, 209 / 255, 88 / 255, 0.85) : Qt.rgba(0, 0, 0, 0.55)
        Behavior on color { ColorAnimation { duration: 400 } }
        border.color: Qt.rgba(1, 1, 1, 0.25)
        border.width: 1

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12 * uiStyle.dp
            text: win.text
            color: win.goalReached ? "#ffffff" : "#d0d0d0"
            font.family: "FreeMono"
            font.pixelSize: 15 * uiStyle.dp
            font.bold: true
        }

        // ≡: the typewriter panel
        Rectangle {
            id: menuButton
            visible: !win.coding
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: exitButton.left
            anchors.rightMargin: 4 * uiStyle.dp
            width: parent.height - 8 * uiStyle.dp
            height: width
            radius: width / 2
            color: menuArea.pressed || typewriterPanel.visible ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.15)
            Text {
                anchors.centerIn: parent
                text: "≡"
                color: "#ffffff"
                font.pixelSize: parent.height * 0.7
                font.bold: true
            }
            MouseArea {
                id: menuArea
                anchors.fill: parent
                anchors.margins: -6 * uiStyle.dp
                onClicked: typewriterPanel.visible = !typewriterPanel.visible
            }
        }

        // ×: leave typewriter mode
        Rectangle {
            id: exitButton
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 4 * uiStyle.dp
            width: parent.height - 8 * uiStyle.dp
            height: width
            radius: width / 2
            color: exitArea.pressed ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.15)
            Text {
                anchors.centerIn: parent
                text: "×"
                color: "#ffffff"
                font.pixelSize: parent.height * 0.75
                font.bold: true
            }
            MouseArea {
                id: exitArea
                anchors.fill: parent
                anchors.margins: -6 * uiStyle.dp   // easier to hit with a finger
                onClicked: {
                    if (win.coding) {
                        // the coding terminal (LazyVim asks about unsaved files itself)
                        shell.start(["pkill", "-TERM", "-f", "profile TabletShellCoding"]);
                        return;
                    }
                    // close the editor window normally (it saves); if something else is in front,
                    // ask ghostwriter itself to quit
                    if (shell.run(["qdbus6", "org.ipad.TabletShell", "/", "org.ipad.TabletShell.CurrentApp"]).indexOf("ghostwriter") !== -1) {
                        shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Window Close"]);
                    } else {
                        shell.start(["pkill", "-TERM", "-x", "ghostwriter"]);
                    }
                }
            }
        }
    }
}

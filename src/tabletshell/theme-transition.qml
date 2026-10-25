// Style-change curtain (Apple ⇄ Material). shell-style starts it before touching any setting:
// the curtain grows from the centre until the screen is covered, writes
// $XDG_RUNTIME_DIR/tablet-style-covered, holds with a loading indicator while Plasma restyles
// itself and opens only after shell-style writes tablet-style-ready (plus a short settle time for
// the wallpaper cross-fade and icon reload). A 30 s timeout opens it in any case.
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import "Tr.js" as Tr

Window {
    id: win
    color: "transparent"
    visible: true
    title: Tr.t("Смена стиля")
    LayerShell.Window.scope: "tabletshell-theme-transition"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property bool pixel: shell.env("TABLET_SHELL_THEME_TARGET") === "pixel"
    readonly property string runtime: shell.env("XDG_RUNTIME_DIR")
    readonly property real reach: Math.sqrt(width * width + height * height) + 8
    // 0 → 1 while the curtain closes, back to 0 while it opens
    property real cover: 0
    property real content: 0
    property bool opening: false

    readonly property color c1: pixel ? "#4F378B" : "#0A84FF"
    readonly property color c2: pixel ? "#7D5260" : "#5E5CE6"
    readonly property color glow: pixel ? "#D0BCFF" : "#64D2FF"

    SequentialAnimation {
        id: closing
        running: win.width > 0
        NumberAnimation { target: win; property: "cover"; from: 0; to: 1; duration: 620; easing.type: Easing.InOutCubic }
        ScriptAction { script: shell.start(["sh", "-c", "echo 1 > \"$XDG_RUNTIME_DIR/tablet-style-covered\""]) }
        NumberAnimation { target: win; property: "content"; to: 1; duration: 320; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: open
        NumberAnimation { target: win; property: "content"; to: 0; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: win; property: "cover"; to: 0; duration: 560; easing.type: Easing.InOutCubic }
        ScriptAction { script: Qt.quit() }
    }
    function reveal() {
        if (opening) return;
        opening = true;
        poll.stop();
        closing.stop();
        settle.start();
    }
    Timer {
        id: poll
        interval: 150; repeat: true; running: true
        onTriggered: if (shell.readFile(win.runtime + "/tablet-style-ready") !== "") win.reveal()
    }
    // Wallpaper cross-fade and the icon cache reload continue briefly after shell-style is done.
    Timer { id: settle; interval: 1200; onTriggered: open.start() }
    Timer { interval: 30000; running: true; onTriggered: win.reveal() }

    // Curtain: a circle from the centre that covers the screen (Material) or a rounded sheet
    // with continuous corners (Apple). Both open by shrinking back into the centre.
    Rectangle {
        id: curtain
        anchors.centerIn: parent
        width: win.pixel ? win.reach * win.cover : win.width * (0.2 + 0.8 * win.cover) + 2
        height: win.pixel ? width : win.height * (0.2 + 0.8 * win.cover) + 2
        radius: win.pixel ? width / 2 : 48 * (1 - win.cover)
        opacity: win.pixel ? 1 : Math.min(1, win.cover * 1.6)
        visible: win.cover > 0.001
        antialiasing: true
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: win.c1 }
            GradientStop { position: 1; color: win.c2 }
        }
        // soft light spot so the curtain is not a flat colour (painted once)
        Canvas {
            anchors.centerIn: parent
            width: Math.min(win.width, win.height) * 1.3; height: width
            opacity: 0.3 * win.content
            onPaint: {
                const ctx = getContext("2d");
                const g = ctx.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, width / 2);
                g.addColorStop(0, win.glow);
                g.addColorStop(1, Qt.rgba(win.glow.r, win.glow.g, win.glow.b, 0));
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, width, height);
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 34
        opacity: win.content
        scale: 0.92 + 0.08 * win.content

        // Material 3 expressive loader: a shape that morphs between a square and a circle while
        // turning; Apple: the classic 12-spoke activity indicator.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96
            Rectangle {
                id: morph
                visible: win.pixel
                anchors.centerIn: parent
                width: 64; height: 64
                color: "#EADDFF"
                antialiasing: true
                property real phase: 0
                radius: 12 + 20 * (0.5 - 0.5 * Math.cos(phase * Math.PI * 2))
                rotation: phase * 270
                scale: 0.9 + 0.1 * Math.sin(phase * Math.PI * 2)
                NumberAnimation on phase { from: 0; to: 1; duration: 1300; loops: Animation.Infinite; running: win.pixel && win.visible }
                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22; radius: 11
                    color: "#4F378B"
                }
            }
            Item {
                id: spinner
                visible: !win.pixel
                anchors.fill: parent
                property int step: 0
                Repeater {
                    model: 12
                    Rectangle {
                        x: spinner.width / 2 - width / 2
                        y: 6
                        width: 7; height: 24; radius: 3.5
                        color: "white"
                        antialiasing: true
                        opacity: 1 - 0.8 * (((spinner.step - index) % 12 + 12) % 12) / 11
                        transform: Rotation { origin.x: 3.5; origin.y: spinner.height / 2 - 6; angle: index * 30 }
                    }
                }
                Timer { interval: 83; repeat: true; running: !win.pixel && win.visible; onTriggered: spinner.step = (spinner.step + 1) % 12 }
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.pixel ? "Material Design" : "iPadOS"
                color: "white"
                font.family: win.pixel ? "Roboto Flex" : "Inter"
                font.pixelSize: 40
                font.weight: win.pixel ? Font.Medium : Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Меняю оформление…")
                color: Qt.rgba(1, 1, 1, 0.75)
                font.family: win.pixel ? "Roboto Flex" : "Inter"
                font.pixelSize: 20
            }
        }
    }
    // Block taps while covered so nothing invisible is hit underneath.
    MouseArea { anchors.fill: parent; enabled: win.cover > 0.5 }
}

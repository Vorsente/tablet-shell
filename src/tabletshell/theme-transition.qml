// Style-change curtain (Apple ⇄ Material). shell-style starts it before touching any setting:
// the curtain grows from the centre until the screen is covered, writes
// $XDG_RUNTIME_DIR/tablet-style-covered, holds with a loading indicator while Plasma restyles
// itself and opens only after shell-style writes tablet-style-ready (plus a short settle time for
// the wallpaper cross-fade and icon reload). A 30 s timeout opens it in any case.
//
// Smoothness on the Atom: while Plasma restyles, plasmashell and plasma-apply-lookandfeel keep every
// core busy, and this process's GUI thread gets little time. Everything that moves therefore runs
// on the render thread (Scale/Opacity/Rotation animators), the shapes keep a fixed size (only a
// transform changes per frame, no geometry is rebuilt), and the animation starts only after the
// first frames are on screen: they compile shaders and build glyphs, which used to eat the start.
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
    property bool covered: false
    property bool opening: false

    readonly property color c1: pixel ? "#4F378B" : "#0A84FF"
    readonly property color c2: pixel ? "#7D5260" : "#5E5CE6"
    readonly property color glow: pixel ? "#D0BCFF" : "#64D2FF"

    // the first frames are slow (shaders, glyphs, textures): start once two are on screen
    property int warmFrames: 0
    onFrameSwapped: {
        if (warmFrames < 2 && width > 0 && ++warmFrames === 2) {
            begin();
        }
    }
    function begin() {
        if (closing.running || covered) return;
        if (!loader) loader = loaderComponent.createObject(null);
        closing.start();
    }
    Timer { interval: 400; running: true; onTriggered: win.begin() }

    SequentialAnimation {
        id: closing
        ParallelAnimation {
            ScaleAnimator { target: curtain; from: win.pixel ? 0.02 : 0.2; to: win.pixel ? 1 : 1.1; duration: 620; easing.type: Easing.InOutCubic }
            OpacityAnimator { target: curtain; from: win.pixel ? 1 : 0; to: 1; duration: win.pixel ? 1 : 380; easing.type: Easing.OutCubic }
        }
        ScriptAction {
            script: {
                win.covered = true;
                shell.start(["sh", "-c", "echo 1 > \"$XDG_RUNTIME_DIR/tablet-style-covered\""]);
            }
        }
        ScriptAction { script: if (win.loader) win.loader.show() }
        ParallelAnimation {
            OpacityAnimator { target: content; from: 0.01; to: 1; duration: 320; easing.type: Easing.OutCubic }
            ScaleAnimator { target: content; from: 0.92; to: 1; duration: 320; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: open
        ScriptAction { script: if (win.loader) win.loader.hide() }
        ParallelAnimation {
            OpacityAnimator { target: content; to: 0; duration: 220; easing.type: Easing.InCubic }
            ScaleAnimator { target: content; to: 1.06; duration: 220; easing.type: Easing.InCubic }
        }
        ParallelAnimation {
            ScaleAnimator { target: curtain; to: win.pixel ? 0.02 : 0.2; duration: 560; easing.type: Easing.InOutCubic }
            OpacityAnimator { target: curtain; to: win.pixel ? 1 : 0; duration: 560; easing.type: Easing.InCubic }
        }
        ScriptAction { script: Qt.quit() }
    }
    function reveal() {
        if (opening) return;
        opening = true;
        poll.stop();
        settle.start();
    }
    Timer {
        id: poll
        interval: 150; repeat: true; running: true
        onTriggered: if (shell.readFile(win.runtime + "/tablet-style-ready") !== "") win.reveal()
    }
    // shell-style reports ready once plasmashell is idle; the wallpaper cross-fade still ends
    // meanwhile. Never open in the middle of the closing animation.
    Timer {
        id: settle
        interval: 600
        onTriggered: {
            if (closing.running) {
                restart();
                return;
            }
            open.start();
        }
    }
    Timer { interval: 30000; running: true; onTriggered: win.reveal() }

    // Curtain: a circle from the centre that covers the screen (Material) or a rounded sheet
    // (Apple), drawn once at full size and only scaled.
    Rectangle {
        id: curtain
        anchors.centerIn: parent
        width: win.pixel ? win.reach : win.width
        height: win.pixel ? win.reach : win.height
        radius: win.pixel ? width / 2 : 48
        scale: win.pixel ? 0.02 : 0.2
        opacity: win.pixel ? 1 : 0
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0; color: win.c1 }
            GradientStop { position: 1; color: win.c2 }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0.01      // rendered (glyphs, shaders ready) but invisible until covered
        scale: 0.92

        // soft light spot: a small gradient painted once and scaled up (it is blurry anyway)
        Canvas {
            anchors.centerIn: parent
            width: 128; height: 128
            scale: Math.min(win.width, win.height) * 1.3 / 128
            opacity: 0.3
            renderStrategy: Canvas.Immediate
            onPaint: {
                const ctx = getContext("2d");
                const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
                g.addColorStop(0, win.glow);
                g.addColorStop(1, Qt.rgba(win.glow.r, win.glow.g, win.glow.b, 0));
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, 128, 128);
            }
        }

        // the captions under the loader (the loader itself is the small window below)
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 82
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

    // The loader lives in its own small window at the centre of the screen: while it turns, the
    // compositor redraws only this square. With the full-screen window changing every frame KWin
    // took a whole core for ten seconds, right when Plasma needs the CPU to restyle itself.
    // created once the curtain is on screen, so that it is stacked above it
    property var loader: null
    Component {
        id: loaderComponent
        Window {
            color: "transparent"
            visible: true
            flags: Qt.WindowTransparentForInput
            width: 120
            height: 120
            title: Tr.t("Смена стиля")
            LayerShell.Window.scope: "tabletshell-theme-loader"
            LayerShell.Window.layer: LayerShell.Window.LayerOverlay
            LayerShell.Window.anchors: LayerShell.Window.AnchorNone   // no edge: centred by the compositor
            LayerShell.Window.exclusionZone: -1
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
            function show() { loaderIn.start(); }
            function hide() { loaderOut.start(); }
            OpacityAnimator { id: loaderIn; target: spin; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
            OpacityAnimator { id: loaderOut; target: spin; to: 0; duration: 200; easing.type: Easing.InCubic }

            // Material 3 expressive loader: a rounded square turning and breathing next to a
            // circle that fades in and out (shapes morphing); Apple: the 12-spoke activity
            // indicator. Render-thread animators: smooth under load.
            Item {
                id: spin
                anchors.centerIn: parent
                width: 96; height: 96
                opacity: 0
                Item {
                    visible: win.pixel
                    anchors.fill: parent
                    Rectangle {
                        anchors.centerIn: parent
                        width: 60; height: 60; radius: 16
                        color: "#EADDFF"
                        antialiasing: true
                        RotationAnimator on rotation { from: 0; to: 360; duration: 2400; loops: Animation.Infinite; running: win.pixel }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 64; height: 64; radius: 32
                        color: "#EADDFF"
                        antialiasing: true
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite; running: win.pixel
                            OpacityAnimator { from: 0; to: 1; duration: 650; easing.type: Easing.InOutSine }
                            OpacityAnimator { from: 1; to: 0; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 22; radius: 11
                        color: "#4F378B"
                        SequentialAnimation on scale {
                            loops: Animation.Infinite; running: win.pixel
                            ScaleAnimator { from: 0.8; to: 1.15; duration: 650; easing.type: Easing.InOutSine }
                            ScaleAnimator { from: 1.15; to: 0.8; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }
                }
                Item {
                    id: spinner
                    visible: !win.pixel
                    anchors.fill: parent
                    Repeater {
                        model: 12
                        Rectangle {
                            required property int index
                            x: spinner.width / 2 - width / 2
                            y: 6
                            width: 7; height: 24; radius: 3.5
                            color: "white"
                            antialiasing: true
                            opacity: 1 - 0.8 * index / 11
                            transform: Rotation { origin.x: 3.5; origin.y: spinner.height / 2 - 6; angle: -index * 30 }
                        }
                    }
                    RotationAnimator on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: !win.pixel }
                }
            }
        }
    }
    // Block taps while covered so nothing invisible is hit underneath.
    MouseArea { anchors.fill: parent; enabled: win.covered && !win.opening }
}

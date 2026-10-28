// Charging animation: when the charger is plugged in, a green ring fills up to the battery level
// with a bolt and the percentage counting up, waves spread out from it and a chime plays. About two
// seconds, over a dimmed screen (not hidden: it is only a glance). Touches pass through.
// tabletshell: shell.chargingStarted (UPower OnBattery -> false, or D-Bus ShowCharging).
import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Shapes
import QtQuick.Window
import QtMultimedia

import org.kde.layershell as LayerShell
import "Tr.js" as Tr
import "MaterialYou.js" as MY

Window {
    id: win
    visible: false
    color: "transparent"
    flags: Qt.WindowTransparentForInput
    title: Tr.t("Зарядка")

    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property color green: uiStyle.pixel ? MY.you("#D0BCFF", uiStyle.pixel, Kirigami.Theme.highlightColor) : MY.you("#30D158", uiStyle.pixel, Kirigami.Theme.highlightColor)
    property int level: 0         // battery percent
    property bool full: false
    property real shown: 0        // fade in/out of everything
    property real fill: 0         // ring 0..1 of the level
    property real wave: 0         // 0..1, the waves spread out

    SoundEffect {
        id: chime
        source: "file://" + shell.env("HOME") + "/.local/share/tabletshell/sounds/charge.wav"
        volume: 0.5
    }

    function play() {
        level = parseInt(shell.readFile(shell.batteryDir() + "/capacity")) || 0;
        full = level >= 100 || shell.readFile(shell.batteryDir() + "/status").trim() === "Full";
        seq.stop();
        shown = 0;
        fill = 0;
        wave = 0;
        visible = true;
        seq.start();
        chime.stop();
        chime.play();
    }

    SequentialAnimation {
        id: seq
        ParallelAnimation {
            NumberAnimation { target: win; property: "shown"; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "fill"; to: 1; duration: 1100; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "wave"; to: 1; duration: 1400; easing.type: Easing.OutQuad }
        }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: win; property: "shown"; to: 0; duration: 380; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }

    // dim towards the edges, a little light in the middle
    Rectangle {
        anchors.fill: parent
        opacity: 0.6 * win.shown
        gradient: Gradient {
            GradientStop { position: 0; color: MY.you("#000000", uiStyle.pixel, Kirigami.Theme.highlightColor) }
            GradientStop { position: 0.5; color: uiStyle.pixel ? MY.you("#211B2D", uiStyle.pixel, Kirigami.Theme.highlightColor) : MY.you("#0b1a10", uiStyle.pixel, Kirigami.Theme.highlightColor) }
            GradientStop { position: 1; color: MY.you("#000000", uiStyle.pixel, Kirigami.Theme.highlightColor) }
        }
    }

    Item {
        id: center
        anchors.centerIn: parent
        width: 280
        height: 280
        opacity: win.shown
        scale: 0.85 + 0.15 * win.shown

        // waves spreading out from the ring
        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real p: Math.max(0, Math.min(1, win.wave * 1.3 - index * 0.15))
                anchors.centerIn: parent
                width: parent.width * (1 + p * 1.6)
                height: width
                radius: width / 2
                color: "transparent"
                border.color: win.green
                border.width: 3
                opacity: (1 - p) * 0.5 * (p > 0 ? 1 : 0)
            }
        }

        // dark disc under the ring, so the screen does not show through the numbers
        Rectangle {
            anchors.centerIn: parent
            width: 256
            height: 256
            radius: 128
            color: uiStyle.pixel ? MY.you("#2B2932", uiStyle.pixel, Kirigami.Theme.highlightColor) : Qt.rgba(0, 0, 0, 0.72)
        }

        // the ring: dim track, green arc up to the level
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.14)
                strokeWidth: 18
                fillColor: "transparent"
                PathAngleArc { centerX: 140; centerY: 140; radiusX: 128; radiusY: 128; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: win.green
                strokeWidth: 18
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 140; centerY: 140; radiusX: 128; radiusY: 128
                    startAngle: -90
                    sweepAngle: Math.max(0.5, 360 * win.level / 100 * win.fill)
                }
            }
        }

        // bolt
        Shape {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 46
            width: 48
            height: 80
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: win.green
                strokeColor: "transparent"
                startX: 30; startY: 0
                PathLine { x: 2; y: 46 }
                PathLine { x: 22; y: 46 }
                PathLine { x: 16; y: 80 }
                PathLine { x: 46; y: 32 }
                PathLine { x: 26; y: 32 }
                PathLine { x: 30; y: 0 }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 136
            text: Math.round(win.level * win.fill) + "%"
            color: "white"
            font.pixelSize: 54
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 204
            text: win.full ? Tr.t("Заряжено") : Tr.t("Заряжается")
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: 17
        }
    }
}

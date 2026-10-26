// The update in motion (Settings → Updates): a ring around the stage's symbol fills with the
// progress (or spins while the length is unknown), the symbol moves the way its stage does
// (the arrow drops while downloading, the package breathes while it is checked, the hammer
// swings while building), the four steps light up below, and at the end the ring closes in
// green with a tick and a small burst.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: anim

    required property string stage
    property real progress: 0          // 0..100, 0 = unknown
    property int step: 0               // installing: 1..4 (update.sh)

    readonly property bool done: stage === "done"
    readonly property bool failed: stage === "error"
    readonly property bool determinate: progress > 0 && (stage === "downloading" || stage === "installing")
    // the four steps shown under the ring
    readonly property int phase: done ? 4 : stage === "installing" ? 2 + (step >= 3 ? 1 : 0) : stage === "preparing" ? 1 : 0
    readonly property color accent: failed ? Kirigami.Theme.negativeTextColor
                                  : done ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.highlightColor
    readonly property real ring: Kirigami.Units.gridUnit * 6

    spacing: Kirigami.Units.largeSpacing

    Item {
        id: stageBox
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: anim.ring * 1.6
        Layout.preferredHeight: anim.ring * 1.25

        // the ring: a track and the progress arc
        Canvas {
            id: arc
            anchors.centerIn: parent
            width: anim.ring
            height: anim.ring
            property real value: anim.done ? 1 : anim.determinate ? anim.progress / 100 : 0.28
            property color tint: anim.accent
            Behavior on value { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            onValueChanged: requestPaint()
            onTintChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width * 0.07, r = width / 2 - w;
                ctx.lineWidth = w;
                ctx.lineCap = "round";
                ctx.strokeStyle = Qt.alpha(Kirigami.Theme.textColor, 0.1);
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2);
                ctx.stroke();
                ctx.strokeStyle = tint;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.01, Math.min(1, value)));
                ctx.stroke();
            }
            // unknown length: the short arc runs round
            RotationAnimation on rotation {
                running: !anim.determinate && !anim.done && !anim.failed
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1100
                onRunningChanged: if (!running) arc.rotation = 0
            }
        }

        // the soft glow of the accent behind the symbol
        Rectangle {
            anchors.centerIn: parent
            width: anim.ring * 0.62
            height: width
            radius: width / 2
            color: Qt.alpha(anim.accent, 0.14)
            SequentialAnimation on scale {
                running: !anim.done && !anim.failed
                loops: Animation.Infinite
                NumberAnimation { to: 1.08; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }

        // the stage's symbol and its motion
        Kirigami.Icon {
            id: symbol
            anchors.centerIn: parent
            width: anim.ring * 0.34
            height: width
            isMask: true
            color: anim.accent
            source: anim.failed ? "dialog-error-symbolic"
                  : anim.done ? "object-select-symbolic"
                  : anim.stage === "downloading" ? "download-symbolic"
                  : anim.stage === "preparing" ? "package-x-generic-symbolic"
                  : anim.stage === "installing" ? "run-build-symbolic"
                  : "view-refresh-symbolic"
            transform: Translate { id: drop }
            // downloading: the arrow drops into the tray again and again
            SequentialAnimation {
                running: anim.stage === "downloading"
                loops: Animation.Infinite
                NumberAnimation { target: drop; property: "y"; from: -anim.ring * 0.08; to: anim.ring * 0.05; duration: 650; easing.type: Easing.InQuad }
                NumberAnimation { target: drop; property: "y"; to: -anim.ring * 0.08; duration: 450; easing.type: Easing.OutQuad }
                onRunningChanged: if (!running) drop.y = 0
            }
            // building: the hammer swings
            SequentialAnimation {
                running: anim.stage === "installing"
                loops: Animation.Infinite
                NumberAnimation { target: symbol; property: "rotation"; to: -18; duration: 380; easing.type: Easing.OutQuad }
                NumberAnimation { target: symbol; property: "rotation"; to: 14; duration: 220; easing.type: Easing.InQuad }
                NumberAnimation { target: symbol; property: "rotation"; to: 0; duration: 300; easing.type: Easing.OutBack }
                PauseAnimation { duration: 250 }
                onRunningChanged: if (!running) symbol.rotation = 0
            }
            // checking: the arrows turn
            RotationAnimation {
                target: symbol
                running: anim.stage === "checking"
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1400
                onRunningChanged: if (!running) symbol.rotation = 0
            }
            // checking the package: it breathes
            SequentialAnimation on scale {
                running: anim.stage === "preparing"
                loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running && !anim.done) symbol.scale = 1
            }
        }

        // done: the tick pops in and a burst of dots flies out
        Connections {
            target: anim
            function onDoneChanged() {
                if (anim.done) {
                    pop.restart();
                    burst.restart();
                }
            }
        }
        SequentialAnimation {
            id: pop
            NumberAnimation { target: symbol; property: "scale"; from: 0.2; to: 1.25; duration: 260; easing.type: Easing.OutBack }
            NumberAnimation { target: symbol; property: "scale"; to: 1; duration: 180 }
        }
        Repeater {
            model: 10
            delegate: Rectangle {
                id: dot
                required property int index
                readonly property real angle: index / 10 * Math.PI * 2
                property real reach: 0
                x: stageBox.width / 2 - width / 2 + Math.cos(angle) * reach
                y: stageBox.height / 2 - height / 2 + Math.sin(angle) * reach
                width: anim.ring * 0.06
                height: width
                radius: width / 2
                color: index % 2 ? anim.accent : Kirigami.Theme.highlightColor
                opacity: 0
                ParallelAnimation {
                    id: fly
                    NumberAnimation { target: dot; property: "reach"; from: anim.ring * 0.42; to: anim.ring * 0.78; duration: 700; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        NumberAnimation { target: dot; property: "opacity"; to: 1; duration: 120 }
                        NumberAnimation { target: dot; property: "opacity"; to: 0; duration: 580 }
                    }
                }
                Connections {
                    target: burst
                    function onStarted() { fly.restart(); }
                }
            }
        }
        // a bare animation used as the burst's start signal
        PauseAnimation { id: burst; duration: 1 }

        // the percentage under the ring while it is known
        QQC2Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            visible: anim.determinate
            text: Math.round(anim.progress) + " %"
        }
    }

    // the four steps
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: [Tr.t("Скачивание"), Tr.t("Проверка"), Tr.t("Сборка"), Tr.t("Установка"), Tr.t("Готово")]
            delegate: RowLayout {
                required property string modelData
                required property int index
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    visible: index > 0
                    Layout.preferredWidth: Kirigami.Units.gridUnit
                    Layout.preferredHeight: 2
                    radius: 1
                    color: index <= anim.phase ? anim.accent : Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
                Rectangle {
                    Layout.preferredWidth: label.implicitWidth + Kirigami.Units.gridUnit
                    Layout.preferredHeight: label.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: height / 2
                    color: index < anim.phase || anim.done ? Qt.alpha(anim.accent, 0.18)
                         : index === anim.phase ? anim.accent : "transparent"
                    border.width: index > anim.phase && !anim.done ? 1 : 0
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    QQC2Label {
                        id: label
                        anchors.centerIn: parent
                        text: modelData
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: index === anim.phase && !anim.done ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        opacity: index > anim.phase && !anim.done ? 0.55 : 1
                    }
                }
            }
        }
    }

    // why the device stays awake
    QQC2Label {
        Layout.alignment: Qt.AlignHCenter
        visible: !anim.done && !anim.failed && anim.stage !== "checking"
        text: "☾ " + Tr.t("Сон отключён до конца обновления")
        opacity: 0.6
        font.pointSize: Kirigami.Theme.smallFont.pointSize
    }

    component QQC2Label: Text {
        color: Kirigami.Theme.textColor
        font.family: Kirigami.Theme.defaultFont.family
    }
}

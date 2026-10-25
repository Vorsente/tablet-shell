// Power menu (hold the power button, tabletd -> D-Bus PowerMenu), iPadOS style: "slide to power
// off" at the top, restart / sleep / log out below, cancel at the bottom; tapping elsewhere closes
// it. Power off and restart end with an old-TV "switch off": the picture closes into a glowing line,
// the line into a dot, the dot fades. Then Plasma ends the session properly (org.kde.Shutdown).
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Меню питания")

    LayerShell.Window.scope: "tabletshell-power"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand

    property real shown: 0
    property bool leaving: false     // the switch-off animation runs; nothing reacts any more
    property string action: ""
    property bool dryRun: false      // tests (tabletshell powertest): animate, but do nothing

    // one frame of the switch-off (tests)
    function preview(close, shrink, dot) {
        tv.visible = true;
        tv.close = close;
        tv.shrink = shrink;
        tv.dot = dot;
    }

    function open() {
        leaving = false;
        knob.x = 0;
        tv.close = 0;
        tv.shrink = 0;
        tv.dot = 1;
        tv.visible = false;
        visible = true;
        appear.restart();
        requestActivate();
    }
    function close() {
        if (!leaving) {
            disappear.restart();
        }
    }
    NumberAnimation { id: appear; target: win; property: "shown"; to: 1; duration: 280; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: disappear
        NumberAnimation { target: win; property: "shown"; to: 0; duration: 220; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }

    function shutdown(what) {
        leaving = true;
        action = what;
        if (what === "suspend") {
            sleepFade.restart();
        } else {
            tv.visible = true;
            switchOff.restart();
        }
    }
    function run() {
        if (dryRun) {
            return;
        }
        const methods = { poweroff: "logoutAndShutdown", reboot: "logoutAndReboot", logout: "logout" };
        if (action === "suspend") {
            shell.start(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                         "org.freedesktop.login1.Manager", "Suspend", "b", "true"]);
            // the menu goes away once the tablet is awake again
            hideAfterSleep.start();
            return;
        }
        shell.start(["qdbus6", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown." + methods[action]]);
    }
    Timer { id: hideAfterSleep; interval: 1500; onTriggered: { win.visible = false; win.shown = 0; win.leaving = false; } }

    // ---- the menu ----
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.78 * win.shown
        focus: true
        Keys.onEscapePressed: win.close()
        MouseArea {
            anchors.fill: parent
            onClicked: win.close()
        }
    }

    Item {
        anchors.fill: parent
        opacity: win.shown
        scale: 0.96 + 0.04 * win.shown

        visible: !uiStyle.pixel

        // slide to power off
        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.12
            width: 440
            height: 76
            radius: height / 2
            color: uiStyle.pixel ? "#49454F" : Qt.rgba(1, 1, 1, 0.16)
            border.color: Qt.rgba(1, 1, 1, 0.22)

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 30
                text: Tr.t("сдвиньте для выключения")
                color: "white"
                opacity: 0.85 * (1 - knob.x / (track.width - knob.width - 12))
                font.pixelSize: 20
                // shimmer
                SequentialAnimation on opacity {
                    running: win.visible && !uiStyle.pixel && knob.x === 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.9; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            Rectangle {
                id: knob
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 0
                width: 64
                height: 64
                radius: 32
                color: "white"
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    source: "system-shutdown-symbolic"
                    isMask: true
                    color: "#FF3B30"
                }
                Behavior on x { enabled: !drag.active; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                // knob sits 6 px inside the track
                transform: Translate { x: 6 }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                enabled: !win.leaving
                property real start: 0
                onPressed: mouse => start = mouse.x - knob.x
                onPositionChanged: mouse => knob.x = Math.max(0, Math.min(track.width - knob.width - 12, mouse.x - start))
                onReleased: {
                    if (knob.x > (track.width - knob.width - 12) * 0.9) {
                        knob.x = track.width - knob.width - 12;
                        win.shutdown("poweroff");
                    } else {
                        knob.x = 0;
                    }
                }
            }
        }

        // restart / sleep / log out
        Row {
            anchors.centerIn: parent
            spacing: 56
            Repeater {
                model: [
                    { what: "reboot", icon: "system-reboot-symbolic", label: Tr.t("Перезагрузить") },
                    { what: "suspend", icon: "system-suspend-symbolic", label: Tr.t("Сон") },
                    { what: "logout", icon: "system-log-out-symbolic", label: Tr.t("Выйти") },
                ]
                Column {
                    required property var modelData
                    spacing: 12
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 88
                        height: 88
                        radius: 44
                        color: press.pressed ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.18)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 38
                            height: 38
                            source: modelData.icon
                            isMask: true
                            color: "white"
                        }
                        MouseArea {
                            id: press
                            anchors.fill: parent
                            enabled: !win.leaving
                            onClicked: win.shutdown(modelData.what)
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        color: "white"
                        font.pixelSize: 16
                    }
                }
            }
        }

        // cancel
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.1
            spacing: 12
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72
                height: 72
                radius: 36
                color: cancel.pressed ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.18)
                Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 28 }
                MouseArea { id: cancel; anchors.fill: parent; enabled: !win.leaving; onClicked: win.close() }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Отмена"); color: "white"; font.pixelSize: 16 }
        }
    }

    Rectangle {
        visible: uiStyle.pixel
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 420)
        height: actions.implicitHeight + 64
        radius: 28
        color: "#2B2932"
        opacity: win.shown
        Column {
            id: actions
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 16
            Text { text: Tr.t("Меню питания"); color: "#E6E0E9"; font.pixelSize: 24; font.family: "Noto Sans" }
            Grid {
                width: parent.width
                columns: 2
                spacing: 12
                Repeater {
                    model: [
                        {what: "poweroff", icon: "system-shutdown-symbolic", label: Tr.t("Выключить")},
                        {what: "reboot", icon: "system-reboot-symbolic", label: Tr.t("Перезагрузить")},
                        {what: "suspend", icon: "system-suspend-symbolic", label: Tr.t("Сон")},
                        {what: "logout", icon: "system-log-out-symbolic", label: Tr.t("Выйти")}
                    ]
                    Rectangle {
                        required property var modelData
                        width: (actions.width - 12) / 2
                        height: 100
                        radius: 24
                        color: materialTap.pressed ? "#D0BCFF" : "#4A4458"
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            Kirigami.Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 28; height: 28
                                source: modelData.icon
                                isMask: true
                                color: materialTap.pressed ? "#381E72" : "#E8DEF8"
                            }
                            Text {
                                text: modelData.label
                                color: materialTap.pressed ? "#381E72" : "#E8DEF8"
                                font.pixelSize: 14
                            }
                        }
                        MouseArea {
                            id: materialTap
                            anchors.fill: parent
                            enabled: !win.leaving
                            onClicked: win.shutdown(modelData.what)
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 48; radius: 24; color: "#D0BCFF"
                Text { anchors.centerIn: parent; text: Tr.t("Отмена"); color: "#381E72"; font.pixelSize: 16 }
                MouseArea { anchors.fill: parent; enabled: !win.leaving; onClicked: win.close() }
            }
        }
    }

    // ---- sleep: a quick fade to black ----
    Rectangle {
        id: sleepCover
        anchors.fill: parent
        color: "black"
        opacity: 0
    }
    SequentialAnimation {
        id: sleepFade
        NumberAnimation { target: sleepCover; property: "opacity"; to: 1; duration: 450; easing.type: Easing.InCubic }
        ScriptAction { script: win.run() }
        PauseAnimation { duration: 1600 }
        PropertyAction { target: sleepCover; property: "opacity"; value: 0 }
    }

    // ---- old TV switching off ----
    Item {
        id: tv
        anchors.fill: parent
        visible: false
        property real close: 0     // black closes in from top and bottom
        property real shrink: 0    // the line shrinks to a dot
        property real dot: 1       // the dot fades
        // black from the top and the bottom
        Rectangle { width: parent.width; height: parent.height / 2 * tv.close; color: "black" }
        Rectangle { y: parent.height - height; width: parent.width; height: parent.height / 2 * tv.close; color: "black" }
        // the glowing line, then the dot
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(6, parent.width * (1 - tv.shrink))
            height: Math.max(4, parent.height * (1 - tv.close))
            radius: Math.min(width, height) / 2
            color: "white"
            opacity: tv.close < 0.6 ? tv.close / 0.6 * 0.9 : tv.dot
        }
        Rectangle {    // black behind the line once it is thin
            anchors.fill: parent
            color: "black"
            z: -1
            opacity: tv.close >= 0.98 ? 1 : 0
        }
    }
    SequentialAnimation {
        id: switchOff
        NumberAnimation { target: tv; property: "close"; to: 1; duration: 380; easing.type: Easing.InQuad }
        NumberAnimation { target: tv; property: "shrink"; to: 1; duration: 260; easing.type: Easing.InCubic }
        PauseAnimation { duration: 120 }
        NumberAnimation { target: tv; property: "dot"; to: 0; duration: 350; easing.type: Easing.OutQuad }
        ScriptAction { script: win.run() }
    }
}

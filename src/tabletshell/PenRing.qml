// Pen tool ring: hold a pen button in the air (tabletd -> D-Bus PenRing) and the tools fan out
// around the pen: quick note, screenshot of a region, magnifier (KWin zoom, follows the pen),
// colour picker (to the clipboard), screen recording of a region. A tap elsewhere closes it.
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Инструменты пера")

    LayerShell.Window.scope: "tabletshell-penring"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property string home: shell.env("HOME")
    readonly property real radius: 104
    // where the pen is, as fractions of the screen; the ring stays whole on the screen (the window
    // only knows its size once it is shown, so this is a binding)
    property real fx: 0.5
    property real fy: 0.5
    readonly property real margin: radius + 60
    readonly property point centre: Qt.point(Math.max(margin, Math.min(width - margin, fx * width)),
                                             Math.max(margin, Math.min(height - margin, fy * height)))
    property real open: 0
    property bool zoomed: false

    readonly property var tools: [
        { id: "note", icon: "document-edit", label: Tr.t("Заметка") },
        { id: "shot", icon: "spectacle", label: Tr.t("Скриншот") },
        { id: "zoom", icon: "zoom-in", label: Tr.t("Лупа") },
        { id: "color", icon: "color-picker", label: Tr.t("Пипетка") },
        { id: "record", icon: "media-record", label: Tr.t("Запись") },
    ]

    function show(x, y) {
        fx = x;
        fy = y;
        visible = true;
        opening.restart();
    }
    function close() {
        closing.restart();
    }
    function run(tool) {
        close();
        if (tool === "note") {
            shell.start([home + "/.local/bin/quick-note"]);
        } else if (tool === "shot") {
            shell.start(["spectacle", "-r"]);
        } else if (tool === "zoom") {
            zoomed = !zoomed;
            const name = zoomed ? "view_zoom_in" : "view_actual_size";
            shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", name]);
            if (zoomed) {   // twice: 2x is a useful magnifier
                shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", name]);
            }
        } else if (tool === "color") {
            showHint(Tr.t("Коснитесь цвета"), "");
            shell.pickColor();
        } else if (tool === "record") {
            shell.start(["spectacle", "-R", "r"]);
        }
    }

    NumberAnimation { id: opening; target: win; property: "open"; from: 0; to: 1; duration: 320; easing.type: Easing.OutBack }
    SequentialAnimation {
        id: closing
        NumberAnimation { target: win; property: "open"; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }

    // a tap anywhere else closes the ring
    MouseArea {
        anchors.fill: parent
        enabled: win.open > 0.5
        onClicked: win.close()
    }

    // the hub where the pen is
    Rectangle {
        x: win.centre.x - width / 2
        y: win.centre.y - height / 2
        width: 22
        height: 22
        radius: 11
        color: Qt.rgba(1, 1, 1, 0.85)
        border.color: Qt.rgba(0, 0, 0, 0.3)
        opacity: win.open
        scale: win.open
    }

    Repeater {
        model: win.tools
        Item {
            id: tool
            required property var modelData
            required property int index
            // fanned out evenly, starting at the top
            readonly property real angle: -Math.PI / 2 + index * 2 * Math.PI / win.tools.length
            readonly property real reach: win.radius * Math.min(1, Math.max(0, win.open * 1.15 - index * 0.04))
            x: win.centre.x + Math.cos(angle) * reach - width / 2
            y: win.centre.y + Math.sin(angle) * reach - 32
            width: 92
            height: 92
            opacity: Math.min(1, win.open * 1.4)

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
                radius: 32
                color: area.pressed ? Qt.rgba(0.25, 0.25, 0.28, 0.95) : Qt.rgba(0.11, 0.11, 0.12, 0.9)
                border.color: tool.modelData.id === "zoom" && win.zoomed ? "#0A84FF" : Qt.rgba(1, 1, 1, 0.18)
                border.width: tool.modelData.id === "zoom" && win.zoomed ? 2 : 1
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    source: tool.modelData.icon
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    onClicked: win.run(tool.modelData.id)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 68
                text: tool.modelData.label
                color: "white"
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.6)
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
    }

    // colour picker: a hint while waiting, then the picked colour. Its own small window at the top
    // that touches pass through (the next tap goes to KWin's picker).
    property var hint: null
    Component {
        id: hintComponent
        Window {
            id: hintWin
            visible: false
            color: "transparent"
            flags: Qt.WindowTransparentForInput
            width: row.implicitWidth + 32
            height: 48
            LayerShell.Window.scope: "tabletshell-penhint"
            LayerShell.Window.layer: LayerShell.Window.LayerOverlay
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop
            LayerShell.Window.margins.top: 56
            LayerShell.Window.exclusionZone: -1
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
            property string colour: ""
            function show(text, colour) {
                label.text = text;
                hintWin.colour = colour;
                visible = true;
                hide.restart();
            }
            Rectangle {
                anchors.fill: parent
                radius: 24
                color: Qt.rgba(0.11, 0.11, 0.12, 0.92)
                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 12
                    Rectangle {
                        visible: hintWin.colour !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: 13
                        color: hintWin.colour || "transparent"
                        border.color: "white"
                    }
                    Text { id: label; anchors.verticalCenter: parent.verticalCenter; color: "white"; font.pixelSize: 15 }
                }
            }
            Timer { id: hide; interval: 4000; onTriggered: hintWin.visible = false }
        }
    }
    function showHint(text, colour) {
        if (!hint) {
            hint = hintComponent.createObject(null);
        }
        hint.show(text, colour);
    }
    Connections {
        target: shell
        function onColorPicked(hex) {
            win.showHint(hex + Tr.t(" скопирован"), hex);
        }
    }
}

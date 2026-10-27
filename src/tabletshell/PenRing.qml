// Pen tool ring: hold a pen button in the air (tabletd -> D-Bus PenRing) and the tools fan out
// around the pen: quick note, screenshot of a region, Krita, colour picker (to the clipboard),
// screen recording of a region. A tap elsewhere closes it.
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
    readonly property real radius: Math.min(126, Math.max(62, Math.min(width, height) / 2 - 58))
    // where the pen is, as fractions of the screen; the ring stays whole on the screen (the window
    // only knows its size once it is shown, so this is a binding)
    property real fx: 0.5
    property real fy: 0.5
    readonly property real margin: radius + 54
    readonly property point centre: Qt.point(Math.max(margin, Math.min(width - margin, fx * width)),
                                             Math.max(margin, Math.min(height - margin, fy * height)))
    property real open: 0
    // Keep icon AND button colours under our control: Kirigami.Icon otherwise inherits
    // an unrelated palette from the active Qt/Plasma theme, making icons invisible.
    readonly property bool pixelLook: uiStyle.pixel
    readonly property color buttonSurface: pixelLook ? (Kirigami.Theme.backgroundColor) : Qt.rgba(0.14, 0.16, 0.20, 0.98)
    readonly property color buttonText: pixelLook ? Kirigami.Theme.textColor : "#ffffff"
    readonly property color buttonAccent: Kirigami.Theme.highlightColor
    readonly property color buttonPressedText: Kirigami.Theme.highlightedTextColor

    readonly property var tools: [
        { id: "note", icon: "document-edit", label: Tr.t("Заметка") },
        { id: "shot", icon: "image-x-generic", label: Tr.t("Скриншот") },
        { id: "krita", icon: "applications-graphics", label: "Krita" },
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
        } else if (tool === "krita") {
            shell.start([home + "/.local/bin/launch-krita"]);
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
        width: 22 * uiStyle.dp
        height: 22 * uiStyle.dp
        radius: 11 * uiStyle.dp
        color: win.buttonAccent
        border.color: win.buttonSurface
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
            y: win.centre.y + Math.sin(angle) * reach - height / 2
            width: 104 * uiStyle.dp
            height: 102 * uiStyle.dp
            opacity: Math.min(1, win.open * 1.4)

            Rectangle {
                id: tile
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72 * uiStyle.dp
                height: 72 * uiStyle.dp
                radius: win.pixelLook ? 27 * uiStyle.dp : 22 * uiStyle.dp
                color: area.pressed ? win.buttonAccent : win.buttonSurface
                border.color: area.pressed ? win.buttonAccent : Qt.rgba(win.buttonText.r, win.buttonText.g, win.buttonText.b, 0.32)
                border.width: 1.5
                Behavior on color { ColorAnimation { duration: 120 } }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 34 * uiStyle.dp
                    height: 34 * uiStyle.dp
                    source: tool.modelData.id === "krita" ? Qt.resolvedUrl("icons/krita.svg")
                          : tool.modelData.id === "shot" ? Qt.resolvedUrl("icons/shot.svg") : tool.modelData.icon
                    fallback: "applications-graphics"
                    color: area.pressed ? win.buttonPressedText : win.buttonText
                    isMask: true
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.run(tool.modelData.id)
                }
            }
            Rectangle {
                anchors.top: tile.bottom
                anchors.topMargin: 4 * uiStyle.dp
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(72 * uiStyle.dp, label.implicitWidth + 14 * uiStyle.dp)
                height: 24 * uiStyle.dp
                radius: 12 * uiStyle.dp
                color: win.buttonSurface
                border.color: Qt.rgba(win.buttonText.r, win.buttonText.g, win.buttonText.b, 0.24)
                border.width: 1
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: tool.modelData.label
                    color: win.buttonText
                    font.pixelSize: 13 * uiStyle.dp
                    font.weight: Font.DemiBold
                }
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
            width: row.implicitWidth + 32 * uiStyle.dp
            height: 48 * uiStyle.dp
            LayerShell.Window.scope: "tabletshell-penhint"
            LayerShell.Window.layer: LayerShell.Window.LayerOverlay
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop
            LayerShell.Window.margins.top: 56 * uiStyle.dp
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
                radius: 24 * uiStyle.dp
                color: Qt.rgba(0.11, 0.11, 0.12, 0.92)
                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 12 * uiStyle.dp
                    Rectangle {
                        visible: hintWin.colour !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26 * uiStyle.dp
                        height: 26 * uiStyle.dp
                        radius: 13 * uiStyle.dp
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

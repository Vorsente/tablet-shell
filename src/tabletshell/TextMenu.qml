// Text menu like on a phone: hold a finger on a text field (or select text with a held finger) and
// Cut / Copy / Paste / Select all appear above the finger. tabletshell watches the touch screen
// and decides when (Shell::watchTouch); the buttons press the app's own shortcuts through the
// virtual keyboard, the app keeps the keyboard focus (this surface never takes it). A touch
// anywhere else closes the menu and still reaches the app.
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Меню текста")
    width: bubble.width + 2 * pad
    height: bubble.height + arrow.height + 2 * pad

    LayerShell.Window.scope: "tabletshell-textmenu"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property bool pixelLook: uiStyle.pixel
    readonly property real pad: 10          // room for the shadow
    readonly property color surface: pixelLook ? Kirigami.Theme.backgroundColor : Qt.rgba(0.17, 0.17, 0.18, 0.97)
    readonly property color ink: pixelLook ? Kirigami.Theme.textColor : "#ffffff"
    readonly property color pressedInk: pixelLook ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.16)

    property string app: ""
    property bool editable: false
    property bool selected: false
    property bool canPaste: false
    property bool below: false              // no room above the finger: the menu hangs below it
    property real fingerX: 0                // the finger in this window's coordinates (the arrow)
    property real open: 0

    // terminals copy and paste with Shift as well, and have nothing to cut
    readonly property bool terminal: /konsole|yakuake|kitty|foot|alacritty|wezterm|ghostty|terminal/i.test(app)
    readonly property var actions: {
        const list = [];
        if (selected && editable && !terminal) {
            list.push({ id: "cut", label: Tr.t("Вырезать") });
        }
        if (selected) {
            list.push({ id: "copy", label: Tr.t("Копировать") });
        }
        if (editable && canPaste) {
            list.push({ id: "paste", label: Tr.t("Вставить") });
        }
        if (editable) {
            list.push({ id: "all", label: Tr.t("Выделить всё") });
        }
        if (selected && !editable) {
            list.push({ id: "search", label: Tr.t("Найти") });
        }
        return list;
    }

    // the built-in screen: touches are reported as fractions of it
    function builtIn() {
        const screens = Qt.application.screens;
        for (let i = 0; i < screens.length; ++i) {
            if (/^(eDP|LVDS|DSI)/.test(screens[i].name)) {
                return screens[i];
            }
        }
        return screens[0];
    }

    function show(fx, fy, isEditable, isSelected, paste, appId) {
        app = appId;
        editable = isEditable;
        selected = isSelected;
        canPaste = paste;
        if (actions.length === 0) {
            return;
        }
        row.forceLayout();                  // hidden windows are not polished: measure the buttons now
        const scr = builtIn();
        screen = scr;
        const px = fx * scr.width;
        const py = fy * scr.height;
        const gap = 34;                     // clear of the finger tip
        below = py - gap - height < 8;
        const x = Math.max(8, Math.min(scr.width - width - 8, px - width / 2));
        const y = below ? py + gap : py - gap - height;
        fingerX = px - x;
        visible = false;                    // margins of a layer surface apply on (re)mapping
        LayerShell.Window.margins.left = Math.round(x);
        LayerShell.Window.margins.top = Math.round(Math.max(8, Math.min(scr.height - height - 8, y)));
        visible = true;
        opening.restart();
        idle.restart();
    }

    function close() {
        idle.stop();
        if (visible) {
            closing.restart();
        }
    }

    function run(action) {
        if (action === "cut") {
            shell.Key("ctrl+x");
        } else if (action === "copy") {
            shell.Key(terminal ? "ctrl+shift+c" : "ctrl+c");
        } else if (action === "paste") {
            shell.Key(terminal ? "ctrl+shift+v" : "ctrl+v");
        } else if (action === "all") {
            shell.Key(terminal ? "ctrl+shift+a" : "ctrl+a");
            // like on a phone the menu stays, now for the selection
            selected = true;
            idle.restart();
            return;
        } else if (action === "search") {
            const text = shell.run(["wl-paste", "--primary", "--no-newline", "--type", "text"]).trim();
            if (text !== "") {
                shell.start(["firefox", "--search", text.slice(0, 300)]);
            }
        }
        close();
    }

    NumberAnimation { id: opening; target: win; property: "open"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: closing
        NumberAnimation { target: win; property: "open"; to: 0; duration: 100; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }
    Timer { id: idle; interval: 8000; onTriggered: win.close() }

    Connections {
        target: shell
        // a new touch outside the menu closes it (the touch itself goes on to the app)
        function onTouchStarted(fx, fy) {
            if (!win.visible) {
                return;
            }
            const scr = win.builtIn();
            const px = fx * scr.width - win.LayerShell.Window.margins.left;
            const py = fy * scr.height - win.LayerShell.Window.margins.top;
            if (px < 0 || py < 0 || px > win.width || py > win.height) {
                win.close();
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: win.open
        scale: 0.92 + 0.08 * win.open
        transformOrigin: win.below ? Item.Top : Item.Bottom

        // soft shadow
        Rectangle {
            x: bubble.x + 1
            y: bubble.y + 3
            width: bubble.width
            height: bubble.height
            radius: bubble.radius
            color: Qt.rgba(0, 0, 0, 0.22)
        }
        // the arrow pointing at the finger
        Rectangle {
            id: arrow
            width: 14
            height: 14
            rotation: 45
            color: win.surface
            x: Math.max(bubble.x + bubble.radius, Math.min(bubble.x + bubble.width - bubble.radius - width, win.fingerX - width / 2))
            y: win.below ? bubble.y - height / 2 : bubble.y + bubble.height - height / 2
        }
        Rectangle {
            id: bubble
            x: win.pad
            y: win.below ? win.pad + arrow.height / 2 : win.pad
            width: row.width
            height: win.pixelLook ? 48 : 42
            radius: win.pixelLook ? height / 2 : 11
            color: win.surface
            border.color: win.pixelLook ? Qt.rgba(win.ink.r, win.ink.g, win.ink.b, 0.12) : "transparent"

            Row {
                id: row
                height: parent.height
                Repeater {
                    model: win.actions
                    Item {
                        id: item
                        required property var modelData
                        required property int index
                        width: label.implicitWidth + (win.pixelLook ? 36 : 30)
                        height: row.height

                        // iOS: hairlines between the buttons
                        Rectangle {
                            visible: !win.pixelLook && item.index > 0
                            width: 1
                            height: parent.height - 16
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.18)
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: win.pixelLook ? 4 : 0
                            radius: win.pixelLook ? height / 2 : 0
                            color: area.pressed ? (win.pixelLook ? Qt.rgba(win.pressedInk.r, win.pressedInk.g, win.pressedInk.b, 0.18) : win.pressedInk)
                                                : "transparent"
                        }
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: item.modelData.label
                            color: win.ink
                            font.pixelSize: 15
                            font.weight: win.pixelLook ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            onClicked: win.run(item.modelData.id)
                        }
                    }
                }
            }
        }
    }
}

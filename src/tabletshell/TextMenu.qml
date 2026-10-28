// Text menu like on a phone: hold a finger on a word in a text field and it gets selected, with
// handles on its ends and Cut / Copy / Paste / Select all above it; select text with a held finger
// and the same appears. The handles move the ends of the selection (SelectionHandle.qml). tabletshell watches the touch screen
// and decides when (Shell::watchTouch); the buttons press the app's own shortcuts through the
// virtual keyboard, the app keeps the keyboard focus (this surface never takes it). A touch
// anywhere else closes the menu and still reaches the app.
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr
import "MaterialYou.js" as MY

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Меню текста")
    width: bubble.width + 2 * pad
    height: bubble.height + arrow.height + 2 * pad

    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property bool pixelLook: uiStyle.pixel
    readonly property real pad: 10 * uiStyle.dp   // room for the shadow
    readonly property color surface: pixelLook ? Kirigami.Theme.backgroundColor : Qt.rgba(0.17, 0.17, 0.18, 0.97)
    readonly property color ink: pixelLook ? Kirigami.Theme.textColor : MY.you("#ffffff", uiStyle.pixel, Kirigami.Theme.highlightColor)
    readonly property color pressedInk: pixelLook ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.16)

    property string app: ""
    property bool editable: false
    property bool selected: false
    property bool canPaste: false
    property bool below: false              // no room above the finger: the menu hangs below it
    // the selection's ends for the handles (fractions of the screen, middle of the line), or none
    property var sel: null
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

    function show(fx, fy, isEditable, isSelected, paste, appId, selection) {
        app = appId;
        editable = isEditable;
        selected = isSelected;
        canPaste = paste;
        sel = selection && selection.lh !== undefined ? selection : null;
        showHandles();
        if (actions.length === 0) {
            return;
        }
        row.forceLayout();                  // hidden windows are not polished: measure the buttons now
        const scr = builtIn();
        screen = scr;
        let px = fx * scr.width;
        // above the finger, or above the selected text and below its handles
        let top = fy * scr.height - 34;
        let bottom = fy * scr.height + 34;
        if (sel) {
            const lh = sel.lh * scr.height;
            px = (Math.min(sel.sx, sel.ex) + Math.max(sel.sx, sel.ex)) / 2 * scr.width;
            if (Math.abs(sel.sy - sel.ey) * scr.height > lh / 2) {
                px = fx * scr.width;        // several lines: over the finger
            }
            top = Math.min(sel.sy, sel.ey) * scr.height - lh / 2 - 10;
            bottom = Math.max(sel.sy, sel.ey) * scr.height + lh / 2 + startHandle.height + 6;
        }
        below = top - height < 8;
        const x = Math.max(8, Math.min(scr.width - width - 8, px - width / 2));
        const y = below ? bottom : top - height;
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

    // ---- selection handles --------------------------------------------------------------------
    property SelectionHandle startHandle: SelectionHandle { start: true }
    property SelectionHandle endHandle: SelectionHandle { start: false }
    // the handle under the finger while it is dragged: drawn here, the real ones step aside so the
    // app gets the touches
    property Window ghost: Window {
        visible: false
        color: "transparent"
        transientParent: null
        flags: Qt.WindowTransparentForInput
        LayerShell.Window.scope: "dock"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                                   | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
        property bool start: true
        property real tipX: 0
        property real tipY: 0
        Rectangle {
            readonly property real drop: 22
            x: ghost.start ? ghost.tipX - drop : ghost.tipX
            y: ghost.tipY
            width: drop
            height: drop
            color: Kirigami.Theme.highlightColor
            radius: drop / 2
            topLeftRadius: ghost.start ? drop / 2 : 0
            topRightRadius: ghost.start ? 0 : drop / 2
        }
    }

    function showHandles() {
        if (!sel) {
            hideHandles();
            return;
        }
        const scr = builtIn();
        startHandle.screen = scr;
        endHandle.screen = scr;
        const lh = sel.lh * scr.height;
        startHandle.place(sel.sx * scr.width, sel.sy * scr.height + lh / 2);
        endHandle.place(sel.ex * scr.width, sel.ey * scr.height + lh / 2);
        const frac = r => Qt.rect(r.x / scr.width, r.y / scr.height, r.width / scr.width, r.height / scr.height);
        shell.setHandles(true, sel.sx, sel.sy, sel.ex, sel.ey, frac(startHandle.hitRect()), frac(endHandle.hitRect()));
    }

    function hideHandles() {
        startHandle.visible = false;
        endHandle.visible = false;
        shell.setHandles(false, 0, 0, 0, 0, Qt.rect(0, 0, 0, 0), Qt.rect(0, 0, 0, 0));
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
            // like on a phone the menu stays, now for the selection (its ends are not known here)
            selected = true;
            sel = null;
            hideHandles();
            idle.restart();
            return;
        } else if (action === "search") {
            const text = shell.run(["wl-paste", "--primary", "--no-newline", "--type", "text"]).trim();
            if (text !== "") {
                shell.start(["firefox", "--search", text.slice(0, 300)]);
            }
        }
        sel = null;
        hideHandles();
        close();
    }

    NumberAnimation { id: opening; target: win; property: "open"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: closing
        NumberAnimation { target: win; property: "open"; to: 0; duration: 100; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }
    Timer { id: idle; interval: 20000; onTriggered: win.close() }

    Connections {
        target: shell
        // a new touch outside the menu closes it (the touch itself goes on to the app)
        function onTouchStarted(fx, fy) {
            if (!win.visible) {
                if (win.sel) {
                    win.sel = null;     // the menu timed out, the handles stay until a touch elsewhere
                    win.hideHandles();
                }
                return;
            }
            const scr = win.builtIn();
            const px = fx * scr.width - win.LayerShell.Window.margins.left;
            const py = fy * scr.height - win.LayerShell.Window.margins.top;
            if (px < 0 || py < 0 || px > win.width || py > win.height) {
                win.close();
                // a touch somewhere else ends the selection (a touch on a handle never comes here)
                win.sel = null;
                win.hideHandles();
            }
        }
        // a handle picked up: the menu and the handles step aside, the drop follows the finger
        function onHandleDragStarted() {
            idle.stop();
            closing.stop();
            win.visible = false;
            startHandle.visible = false;
            endHandle.visible = false;
        }
        function onHandleDragMoved(handle, fx, fy) {
            if (!win.sel) {
                return;
            }
            const scr = win.builtIn();
            ghost.screen = scr;
            ghost.start = handle === 1;
            ghost.tipX = fx * scr.width;
            ghost.tipY = fy * scr.height + win.sel.lh * scr.height / 2;
            ghost.visible = true;
        }
        function onHandleDragFinished(handle, fx, fy) {
            ghost.visible = false;
            if (!win.sel) {
                return;
            }
            const s = Object.assign({}, win.sel);
            if (handle === 1) {
                s.sx = fx;
                s.sy = fy;
            } else {
                s.ex = fx;
                s.ey = fy;
            }
            // dragged past the other end: they swap places, like the app's selection does
            const sameLine = Math.abs(s.sy - s.ey) < s.lh / 2;
            if ((sameLine && s.ex < s.sx) || (!sameLine && s.ey < s.sy)) {
                [s.sx, s.ex] = [s.ex, s.sx];
                [s.sy, s.ey] = [s.ey, s.sy];
            }
            win.show(fx, fy, win.editable, true, win.canPaste, win.app, s);
        }
    }

    Item {
        anchors.fill: parent
        opacity: win.open
        transformOrigin: win.below ? Item.Top : Item.Bottom

        // soft shadow
        Rectangle {
            x: bubble.x + 1
            y: bubble.y + 3 * uiStyle.dp
            width: bubble.width
            height: bubble.height
            radius: bubble.radius
            color: Qt.rgba(0, 0, 0, 0.22)
        }
        // the arrow pointing at the finger
        Rectangle {
            id: arrow
            width: 14 * uiStyle.dp
            height: 14 * uiStyle.dp
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
            height: win.pixelLook ? 48 * uiStyle.dp : 42 * uiStyle.dp
            radius: win.pixelLook ? height / 2 : 11 * uiStyle.dp
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
                        width: label.implicitWidth + (win.pixelLook ? 36 * uiStyle.dp : 30 * uiStyle.dp)
                        height: row.height

                        // iOS: hairlines between the buttons
                        Rectangle {
                            visible: !win.pixelLook && item.index > 0
                            width: 1
                            height: parent.height - 16 * uiStyle.dp
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.18)
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: win.pixelLook ? 4 * uiStyle.dp : 0
                            radius: win.pixelLook ? height / 2 : 0
                            color: area.pressed ? (win.pixelLook ? Qt.rgba(win.pressedInk.r, win.pressedInk.g, win.pressedInk.b, 0.18) : win.pressedInk)
                                                : "transparent"
                        }
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: item.modelData.label
                            color: win.ink
                            font.pixelSize: 15 * uiStyle.dp
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

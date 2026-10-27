// One end of a text selection, like on a phone: a drop under the line whose corner points at the
// end of the selected text. TextMenu.qml places it; Shell (main.cpp) watches the touch screen and
// moves the selection when a finger drags it (this surface only keeps the touch from the app).
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami

Window {
    id: handle
    visible: false
    color: "transparent"
    transientParent: null
    width: 44 * uiStyle.dp
    height: 50 * uiStyle.dp

    LayerShell.Window.scope: "tabletshell-texthandle"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    property bool start: true                // the start of the selection (the drop leans left)
    property color tint: Kirigami.Theme.highlightColor
    readonly property real drop: 22

    // the tip (screen pixels): the bottom of the line at that end of the selection
    function place(tipX, tipY) {
        visible = false;                    // margins of a layer surface apply on (re)mapping
        LayerShell.Window.margins.left = Math.round(start ? tipX - width : tipX);
        LayerShell.Window.margins.top = Math.round(tipY);
        visible = true;
    }

    // where a finger picks it up, in screen pixels
    function hitRect() {
        return Qt.rect(LayerShell.Window.margins.left, LayerShell.Window.margins.top, width, height);
    }

    Rectangle {
        x: handle.start ? handle.width - handle.drop : 0
        width: handle.drop
        height: handle.drop
        color: handle.tint
        radius: handle.drop / 2
        topLeftRadius: handle.start ? handle.drop / 2 : 0
        topRightRadius: handle.start ? 0 : handle.drop / 2
    }
}

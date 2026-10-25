// Back gesture (Android style), tablet mode only: a 10 px strip along the left edge takes the
// touch; while the finger pulls right the strip widens and a bubble with an arrow follows it,
// past the threshold it turns white, and letting go there sends Back (shell.Back: KEY_BACK
// through uinput, so the app in front gets it). Replaces KWin's left touch edge, which only
// reports a finished swipe. Off: Settings -> Жесты -> "Назад".
// The bubble is drawn in the strip itself: a separate transparent overlay got no frame
// callbacks from KWin and never repainted during the swipe.
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell

Window {
    id: strip

    readonly property real threshold: 90       // logical px to the right
    property real pull: 0                       // how far the finger is from where it started
    property real fingerY: 0
    property bool dragging: false
    readonly property bool armed: pull >= threshold

    visible: shell.tabletMode
    color: "transparent"
    width: dragging ? 160 : 10

    LayerShell.Window.scope: "tabletshell-back-edge"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
    // keep clear of the control center (top edge) and the home gesture (bottom edge)
    LayerShell.Window.margins.top: 60
    LayerShell.Window.margins.bottom: 90
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    MouseArea {
        anchors.fill: parent
        preventStealing: true
        property real startX: 0
        property real startY: 0
        onPressed: m => {
            if (!shell.backGestureEnabled()) {
                return;
            }
            startX = m.x;
            startY = m.y;
            strip.pull = 0;
            strip.fingerY = m.y;
            strip.dragging = true;
        }
        onPositionChanged: m => {
            if (!strip.dragging) {
                return;
            }
            // a mostly vertical move is not a back swipe
            if (Math.abs(m.y - startY) > 120 && Math.abs(m.y - startY) > (m.x - startX) * 1.5) {
                strip.dragging = false;
                return;
            }
            strip.pull = Math.max(0, m.x - startX);
            strip.fingerY = m.y;
        }
        onReleased: {
            if (strip.dragging && strip.armed) {
                shell.Back();
            }
            strip.dragging = false;
        }
        onCanceled: strip.dragging = false
    }

    // the bubble comes out of the edge; past the threshold it barely moves (rubber band)
    readonly property real reach: pull < threshold ? pull : threshold + (pull - threshold) * 0.2
    Rectangle {
        id: bubble
        visible: strip.dragging && strip.pull > 4
        width: 56
        height: 56
        radius: 28
        x: -width + Math.min(strip.reach * 0.8, width + 24)
        y: strip.fingerY - height / 2
        color: uiStyle.pixel ? (strip.armed ? "#D0BCFF" : "#49454F") : strip.armed ? "#ffffff" : Qt.rgba(0.1, 0.1, 0.11, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.3)
        border.width: strip.armed ? 0 : 1
        scale: strip.armed ? 1.08 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 6
            text: "‹"
            color: strip.armed ? "#000000" : "#ffffff"
            opacity: Math.min(1, strip.pull / strip.threshold)
            font.pixelSize: 40
            font.bold: true
        }
    }
}

// Privacy indicator: while an app records, a dot on the panel, orange for the microphone, green
// for the camera (steady, not animated). It sits in the bar just left of the tray icons
// (notifications, volume, battery...), centred on the bar's height, and only with the panel: on
// the Top layer like the panel itself, so a full-screen window covers it too. Touches pass through.
// Data: shell.micApps / shell.cameraApps; where the tray is: Plasma's scripting (on each show).
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import "Tr.js" as Tr

Window {
    id: win
    readonly property bool camera: shell.cameraApps.length > 0
    readonly property bool mic: shell.micApps.length > 0
    // the bar's height from morph-panels.js (tablet status bar / PC bar), in Plasma's logical px
    readonly property real bar: shell.tabletMode ? (uiStyle.pixel ? 32 : 28) : (uiStyle.pixel ? 48 : 44)
    readonly property real dot: Math.round(8 * uiStyle.dp)
    // from the screen's right edge to the tray's left edge (Plasma logical px)
    property real trayRight: 220 * uiStyle.dp

    function measure() {
        const out = shell.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
            "panels().forEach(function (p) { var t = p.widgets('org.kde.plasma.systemtray')[0];"
            + " if (t) print(JSON.stringify({ x: t.geometry.x, len: p.lengthMode === 'fill' ? 0 : p.length })); });"]);
        try {
            const g = JSON.parse(out.trim().split("\n")[0]);
            const panelWidth = g.len > 0 ? g.len : Screen.width;
            // a panel that does not fill the width is centred
            trayRight = Math.max(dot, (Screen.width + panelWidth) / 2 - g.x) + Math.round(5 * uiStyle.dp);
        } catch (e) {
        }
    }

    visible: camera || mic
    onVisibleChanged: if (visible) measure()
    Connections {
        target: shell
        function onTabletModeChanged() { if (win.visible) remeasure.restart(); }
    }
    // the panels are rebuilt after a mode switch
    Timer { id: remeasure; interval: 4000; onTriggered: win.measure() }
    color: "transparent"
    flags: Qt.WindowTransparentForInput
    title: Tr.t("Индикатор записи")
    width: dot
    height: dot

    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: (shell.tabletMode ? LayerShell.Window.AnchorTop : LayerShell.Window.AnchorBottom)
                               | LayerShell.Window.AnchorRight
    // in the bar, centred on its height, left of the tray
    LayerShell.Window.margins.top: Math.round((bar - dot) / 2)
    LayerShell.Window.margins.bottom: Math.round((bar - dot) / 2)
    LayerShell.Window.margins.right: Math.round(trayRight)
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        // the bright tint in both styles (a dark green vanished on dark bars)
        color: uiStyle.pixel ? (win.camera ? "#81C995" : "#FFB86C") : win.camera ? "#30D158" : "#FF9F0A"
    }
}

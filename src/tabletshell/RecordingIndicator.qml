// Privacy indicator: while an app records, a dot on the panel, orange for the microphone, green
// for the camera (steady, not animated). Only the dot, at the right end of the bar along its outer
// edge, above the tray icons like on iPadOS (tablet: the status bar on top; PC: the bottom bar),
// so it never covers notifications or icons. Touches pass through.
// Data: shell.micApps / shell.cameraApps.
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

    visible: camera || mic
    color: "transparent"
    flags: Qt.WindowTransparentForInput
    title: Tr.t("Индикатор записи")
    width: dot
    height: dot

    LayerShell.Window.scope: "tabletshell-recording"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: (shell.tabletMode ? LayerShell.Window.AnchorTop : LayerShell.Window.AnchorBottom)
                               | LayerShell.Window.AnchorRight
    // tablet: in the corner at the top of the status bar; PC: along the top edge of the bottom bar
    LayerShell.Window.margins.top: Math.round(2 * uiStyle.dp)
    LayerShell.Window.margins.bottom: Math.round(bar - dot - 2 * uiStyle.dp)
    LayerShell.Window.margins.right: Math.round(6 * uiStyle.dp)
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        // the bright tint in both styles (a dark green vanished on dark bars)
        color: uiStyle.pixel ? (win.camera ? "#81C995" : "#FFB86C") : win.camera ? "#30D158" : "#FF9F0A"
    }
}

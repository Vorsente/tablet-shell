// Privacy indicator (like iOS): while an app records, a dot at the top of the screen,
// orange for the microphone, green for the camera (steady, not animated). When recording starts the pill opens for a
// moment with the app's name. Touches pass through. Data: shell.micApps / shell.cameraApps.
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import "Tr.js" as Tr

Window {
    id: win
    readonly property bool camera: shell.cameraApps.length > 0
    readonly property bool mic: shell.micApps.length > 0
    readonly property var apps: shell.cameraApps.concat(shell.micApps.filter(a => shell.cameraApps.indexOf(a) < 0))
    property bool expanded: false

    visible: camera || mic || pill.width > pill.height + 1
    color: "transparent"
    flags: Qt.WindowTransparentForInput
    title: Tr.t("Индикатор записи")
    width: 340
    height: 34

    LayerShell.Window.scope: "tabletshell-recording"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.margins.top: 4
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    onAppsChanged: {
        if (apps.length > 0) {
            expanded = true;
            collapse.restart();
        }
    }
    Timer {
        id: collapse
        interval: 2500
        onTriggered: win.expanded = false
    }

    readonly property color tint: uiStyle.pixel ? (camera ? "#81C995" : "#FFB86C") : camera ? "#30D158" : "#FF9F0A"

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: win.expanded ? 28 : 12
        width: win.expanded ? label.implicitWidth + 44 : 12
        radius: height / 2
        // collapsed: the bright tint in both styles (Material used a dark green that vanished on dark bars)
        color: !win.expanded ? win.tint : uiStyle.pixel ? "#2B2B2B" : Qt.rgba(0, 0, 0, 0.82)
        opacity: win.camera || win.mic ? 1 : 0
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 250 } }
        Behavior on opacity { NumberAnimation { duration: 250 } }

        // steady dot: an endless "breathing" animation kept the overlay repainting at 60 fps for
        // as long as an app recorded (noticeable CPU on the Atom); iOS and Android do not animate it either

        Rectangle {
            visible: win.expanded
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: win.tint
        }
        Text {
            id: label
            visible: win.expanded
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            text: (win.camera ? Tr.t("Камера: ") : Tr.t("Микрофон: ")) + win.apps.join(", ")
            color: "white"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
    }
}

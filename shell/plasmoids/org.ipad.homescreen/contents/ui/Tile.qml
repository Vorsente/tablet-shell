// One cell of the home grid: tap launches (or opens a folder), long press enters edit mode and
// picks the icon up, so it can be dragged without lifting the finger (like iPadOS).
// Dropping onto another icon makes a folder; the target shows a folder outline while hovered.
import QtQuick

Item {
    id: tile

    required property var home
    required property var entry
    required property int layoutIndex

    readonly property bool dragging: home.dragFrom === layoutIndex
    readonly property bool dropTarget: home.dragging && !dragging
                                       && home.dropIndex === layoutIndex && home.dropOnto
                                       && typeof home.dragEntry === "string" && home.dragEntry !== entry

    width: home.cellWidth
    height: home.cellHeight
    opacity: dragging ? 0.25 : 1

    // Folder outline under a hovered drop target
    Rectangle {
        anchors.centerIn: face
        anchors.verticalCenterOffset: -face.height / 2 + tile.home.iconSize / 2
        width: tile.home.iconSize * 1.25
        height: width
        radius: tile.home.pixel ? width / 2 : width * 0.24
        color: Qt.rgba(1, 1, 1, 0.25)
        border.color: Qt.rgba(1, 1, 1, 0.5)
        visible: tile.dropTarget
    }

    TileFace {
        id: face
        anchors.centerIn: parent
        home: tile.home
        entry: tile.entry
        scale: tile.dropTarget ? 0.85 : (mouse.pressed && !tile.home.editing ? 0.88 : 1)
        Behavior on scale { NumberAnimation { duration: 100 } }

        SequentialAnimation {
            running: tile.home.editing && !tile.dragging
            loops: Animation.Infinite
            // offset the phase per tile so icons do not move in lockstep
            PauseAnimation { duration: (tile.layoutIndex * 37) % 120 }
            NumberAnimation { target: face; property: "rotation"; to: 2.2; duration: 110 }
            NumberAnimation { target: face; property: "rotation"; to: -2.2; duration: 220 }
            NumberAnimation { target: face; property: "rotation"; to: 0; duration: 110 }
            onRunningChanged: if (!running) face.rotation = 0
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        pressAndHoldInterval: 450
        // keep the swipe view from stealing the touch once an icon is picked up
        preventStealing: tile.home.dragging

        property point pressPos
        property bool picked: false

        function scenePoint(m) {
            return mapToItem(tile.home, m.x, m.y);
        }

        onPressed: m => {
            pressPos = Qt.point(m.x, m.y);
            picked = false;
        }
        onPressAndHold: m => {
            if (tile.home.pcMode) {
                return;
            }
            tile.home.editing = true;
            picked = true;
            tile.home.dragPos = scenePoint(m);
            tile.home.startDrag(tile.layoutIndex);
        }
        onPositionChanged: m => {
            // in edit mode (and with the mouse in PC mode) a plain drag also picks the icon up
            if (!picked && (tile.home.editing || tile.home.pcMode) && mouse.pressed
                    && Math.hypot(m.x - pressPos.x, m.y - pressPos.y) > 12) {
                picked = true;
                tile.home.startDrag(tile.layoutIndex);
            }
            if (picked) {
                tile.home.dragPos = scenePoint(m);
            }
        }
        onReleased: {
            if (picked) {
                picked = false;
                tile.home.finishDrag();
            }
        }
        onCanceled: {
            if (picked) {
                picked = false;
                tile.home.cancelDrag();
            }
        }
        onClicked: {
            if (face.isFolder) {
                tile.home.openFolder = tile.layoutIndex;
            } else if (!tile.home.editing) {
                tile.home.launch(tile.entry, face.iconItem);
            }
        }
    }

    // "×" on web apps in edit mode: delete the web app
    Rectangle {
        visible: tile.home.editing && tile.home.isWebApp(tile.entry)
        x: (tile.width - tile.home.iconSize) / 2 - width / 3
        y: face.y - height / 3
        width: Math.round(tile.home.iconSize * 0.3)
        height: width
        radius: width / 2
        color: Qt.rgba(0.35, 0.35, 0.38, 0.95)
        Text {
            anchors.centerIn: parent
            text: "×"
            color: "white"
            font.bold: true
            font.pixelSize: parent.height * 0.7
        }
        MouseArea {
            anchors.fill: parent
            onClicked: tile.home.removeWebApp(tile.entry)
        }
    }
}

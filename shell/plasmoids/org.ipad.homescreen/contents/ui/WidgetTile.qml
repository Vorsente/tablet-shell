// A widget on the home grid ({widget, size} in the layout): spans 2x2, 4x2 or 4x4 cells.
// Like an icon: long press enters edit mode and picks it up, drag moves it (it never makes a
// folder), "−" in edit mode removes it, the corner button changes its size, a tap does the
// widget's action.
import QtQuick

Item {
    id: tile

    required property var home
    required property var entry
    required property int layoutIndex

    readonly property bool dragging: home.dragFrom === layoutIndex

    opacity: dragging ? 0.25 : 1

    HomeWidget {
        id: face
        anchors.fill: parent
        anchors.margins: tile.home.cellWidth * 0.1
        home: tile.home
        kind: tile.entry.widget
        wide: tile.entry.size === "wide" || tile.entry.size === "large"
        scale: mouse.pressed && !tile.home.editing ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }

        SequentialAnimation {
            running: tile.home.editing && !tile.dragging
            loops: Animation.Infinite
            PauseAnimation { duration: (tile.layoutIndex * 37) % 120 }
            NumberAnimation { target: face; property: "rotation"; to: 0.8; duration: 130 }
            NumberAnimation { target: face; property: "rotation"; to: -0.8; duration: 260 }
            NumberAnimation { target: face; property: "rotation"; to: 0; duration: 130 }
            onRunningChanged: if (!running) face.rotation = 0
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        pressAndHoldInterval: 450
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
            tile.home.editing = true;
            picked = true;
            tile.home.dragPos = scenePoint(m);
            tile.home.startDrag(tile.layoutIndex);
        }
        onPositionChanged: m => {
            if (!picked && tile.home.editing && mouse.pressed && Math.hypot(m.x - pressPos.x, m.y - pressPos.y) > 12) {
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
            if (!tile.home.editing) {
                face.activate();
            }
        }
    }

    // "−" in edit mode: remove the widget
    Rectangle {
        visible: tile.home.editing
        x: face.x - width / 3
        y: face.y - height / 3
        width: Math.round(tile.home.iconSize * 0.3)
        height: width
        radius: width / 2
        color: tile.home.pal.control
        Text {
            anchors.centerIn: parent
            text: "−"
            color: tile.home.pal.text
            font.bold: true
            font.pixelSize: parent.height * 0.75
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onClicked: tile.home.removeEntry(tile.layoutIndex)
        }
    }

    // size button in edit mode (bottom right): small -> wide -> large -> small
    Rectangle {
        visible: tile.home.editing && !tile.dragging
        x: face.x + face.width - width * 2 / 3
        y: face.y + face.height - height * 2 / 3
        width: Math.round(tile.home.iconSize * 0.34)
        height: width
        radius: width / 2
        color: tile.home.pal.control
        Text {
            anchors.centerIn: parent
            text: "⤡"
            color: tile.home.pal.text
            font.bold: true
            font.pixelSize: parent.height * 0.6
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onClicked: tile.home.resizeEntry(tile.layoutIndex)
        }
    }
}

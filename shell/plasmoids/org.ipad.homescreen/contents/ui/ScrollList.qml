// A list inside a widget card that scrolls down (screen time: all of today's apps). The last row is
// cut by the bottom edge when there is more; a thin bar shows where you are while scrolling. On the PC
// desktop `swipe` is off (the card is dragged with the mouse there) and the wheel scrolls it.
import QtQuick

ListView {
    id: list

    property real rowHeight: 40
    property color barColor: "white"
    property bool swipe: true

    clip: true
    interactive: swipe && contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: 2500
    pressDelay: 0
    // a vertical drag on the list is the list's; sideways goes on to the home pages
    flickableDirection: Flickable.VerticalFlick
    reuseItems: true

    // a new day or another size: back to the top
    onCountChanged: if (count === 0) positionViewAtBeginning()

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: list.contentHeight > list.height
        onWheel: event => {
            list.contentY = Math.max(0, Math.min(list.contentHeight - list.height,
                                                 list.contentY - event.angleDelta.y / 120 * list.rowHeight));
        }
    }

    Rectangle {
        // scroll position: shown while moving, fades after
        parent: list
        anchors.right: parent.right
        width: Math.max(2, list.rowHeight * 0.08)
        radius: width / 2
        color: list.barColor
        visible: list.contentHeight > list.height
        height: Math.max(list.rowHeight * 0.6, list.height * list.height / Math.max(1, list.contentHeight))
        y: (list.height - height) * list.contentY / Math.max(1, list.contentHeight - list.height)
        opacity: list.moving ? 0.5 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
}

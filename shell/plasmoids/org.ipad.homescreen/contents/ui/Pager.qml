// Pages of a list inside a widget card (news, on this day): as many rows as fit on a page, swipe
// sideways or tap the dots for the next ones. `row` is the row delegate (gets modelData); on the
// PC desktop `swipe` is off (the widget is dragged with the mouse there) and the dots or the
// wheel turn the pages.
import QtQuick

Item {
    id: pager

    property var items: []
    property real rowHeight: 40
    property real spacing: 0
    property Component row
    property color dotColor: "white"
    property bool swipe: true
    signal held()

    readonly property real dotSize: Math.max(5, Math.round(rowHeight * 0.13))
    readonly property real dotsHeight: dotSize * 2.6
    readonly property int perPage: Math.max(1, Math.floor((height - dotsHeight + spacing) / (rowHeight + spacing)))
    readonly property int pages: Math.max(1, Math.ceil(items.length / perPage))
    readonly property int current: list.currentIndex

    // a new list (refresh) or another size: back to the first page
    onPerPageChanged: list.positionViewAtBeginning()
    onItemsChanged: list.currentIndex = Math.min(list.currentIndex, pages - 1)

    function go(i) {
        list.currentIndex = Math.max(0, Math.min(pages - 1, i));
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.bottomMargin: pager.pages > 1 ? pager.dotsHeight : 0
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 250
        boundsBehavior: Flickable.StopAtBounds
        interactive: pager.swipe && pager.pages > 1
        clip: true
        model: pager.pages
        delegate: Column {
            id: page
            required property int index
            width: list.width
            height: list.height
            spacing: pager.spacing
            Repeater {
                model: pager.items.slice(page.index * pager.perPage, (page.index + 1) * pager.perPage)
                delegate: pager.row
            }
        }
        WheelHandler {
            enabled: pager.pages > 1
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const d = event.angleDelta.x !== 0 ? -event.angleDelta.x : -event.angleDelta.y;
                if (Math.abs(d) >= 60 || event.device.type === PointerDevice.Mouse) {
                    pager.go(list.currentIndex + (d > 0 ? 1 : -1));
                }
            }
        }
    }

    // page dots: tap one to jump there
    Row {
        visible: pager.pages > 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (pager.dotsHeight - pager.dotSize) / 2 - pager.dotSize * 0.2
        spacing: pager.dotSize * 0.9
        Repeater {
            model: pager.pages
            delegate: Rectangle {
                required property int index
                width: index === pager.current ? pager.dotSize * 2.2 : pager.dotSize
                height: pager.dotSize
                radius: height / 2
                color: pager.dotColor
                opacity: index === pager.current ? 0.9 : 0.3
                Behavior on width { NumberAnimation { duration: 150 } }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -pager.dotSize * 0.6
                    onClicked: pager.go(parent.index)
                }
            }
        }
    }
}

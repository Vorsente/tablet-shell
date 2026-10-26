// Widgets on the PC mode desktop, like macOS Sonoma desktop widgets (Apple style) or Material
// cards on a ChromeOS desk (Pixel style): the same HomeWidget cards, which draw themselves in the
// shell's style. Containment config "pcWidgets" = [{kind, size: small|wide|large, x, y}] with x/y
// as shares of the free room, so they keep their corner on another screen size.
//   add:    "Добавить виджет…" in the desktop's right-click menu (the widget gallery)
//   move:   drag with the mouse, they snap to a grid
//   menu:   right click: size (small / medium / large), remove, add more
// A click goes through to the card (open the headline, turn the page with the dots, the
// widget's own action).
import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: widgets

    required property var home

    readonly property var entries: {
        try {
            const l = JSON.parse(Plasmoid.configuration.pcWidgets || "[]");
            return Array.isArray(l) ? l.filter(e => e && typeof e.kind === "string") : [];
        } catch (e) {
            return [];
        }
    }
    readonly property int count: entries.length

    // macOS sizes: small square, medium = two small side by side, large = four
    readonly property real cell: Kirigami.Units.gridUnit * 9
    readonly property real gap: Kirigami.Units.gridUnit
    readonly property real margin: Kirigami.Units.gridUnit * 1.5
    readonly property real snap: Kirigami.Units.gridUnit * 0.5
    function sizeOf(size) {
        return size === "large" ? Qt.size(cell * 2 + gap, cell * 2 + gap)
             : size === "wide" ? Qt.size(cell * 2 + gap, cell) : Qt.size(cell, cell);
    }
    function rectOf(e) {
        const s = sizeOf(e.size);
        const roomW = Math.max(0, width - s.width - margin * 2), roomH = Math.max(0, height - s.height - margin * 2);
        return Qt.rect(margin + Math.max(0, Math.min(1, Number(e.x) || 0)) * roomW,
                       margin + Math.max(0, Math.min(1, Number(e.y) || 0)) * roomH, s.width, s.height);
    }

    function save(list) {
        Plasmoid.configuration.pcWidgets = JSON.stringify(list);
    }
    function place(index, px, py) {
        const l = entries.slice();
        const s = sizeOf(l[index].size);
        const roomW = Math.max(1, width - s.width - margin * 2), roomH = Math.max(1, height - s.height - margin * 2);
        const x = Math.round((px - margin) / snap) * snap, y = Math.round((py - margin) / snap) * snap;
        l[index] = Object.assign({}, l[index], { x: Math.max(0, Math.min(1, x / roomW)), y: Math.max(0, Math.min(1, y / roomH)) });
        save(l);
    }
    function resize(index, size) {
        const l = entries.slice();
        const r = rectOf(l[index]);
        l[index] = Object.assign({}, l[index], { size: size });
        save(l);
        place(index, r.x, r.y);      // keep the top-left corner where it was
    }
    function remove(index) {
        save(entries.filter((e, i) => i !== index));
    }

    // a new widget: the first free place from the top-right corner down (the files fill the
    // desktop from the top-left), else on top of the others
    function add(kind, size) {
        const s = sizeOf(size);
        const taken = entries.map(rectOf);
        const free = r => !taken.some(t => r.x < t.x + t.width + gap / 2 && t.x < r.x + r.width + gap / 2
                                        && r.y < t.y + t.height + gap / 2 && t.y < r.y + r.height + gap / 2);
        let spot = Qt.point(width - margin - s.width, margin);
        search: for (let x = width - margin - s.width; x >= margin; x -= cell + gap) {
            for (let y = margin; y + s.height <= height - margin; y += snap * 2) {
                if (free(Qt.rect(x, y, s.width, s.height))) {
                    spot = Qt.point(x, y);
                    break search;
                }
            }
        }
        const l = entries.concat([{ kind: kind, size: size, x: 0, y: 0 }]);
        save(l);
        place(l.length - 1, spot.x, spot.y);
    }

    signal galleryRequested()

    Repeater {
        model: widgets.entries
        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property rect at: widgets.rectOf(modelData)
            x: at.x
            y: at.y
            // a drag moves the card by hand; afterwards it follows its saved place again
            function follow() {
                x = Qt.binding(() => slot.at.x);
                y = Qt.binding(() => slot.at.y);
            }
            width: at.width
            height: at.height
            z: mover.dragging ? 10 : 0

            HomeWidget {
                id: face
                anchors.fill: parent
                home: widgets.home
                kind: slot.modelData.kind
                wide: slot.modelData.size !== "small"
                swipe: false
                scale: mover.dragging ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                // a click that no row or dot took: the widget's own action
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: face.activate()
                }
            }

            // drag to move; clicks go on to the card below (propagateComposedEvents)
            MouseArea {
                id: mover
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                propagateComposedEvents: true
                hoverEnabled: true
                cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
                property point start
                property point origin
                property bool dragging: false
                onPressed: m => {
                    if (m.button === Qt.RightButton) {
                        widgetMenu.index = slot.index;
                        widgetMenu.size = slot.modelData.size;
                        widgetMenu.popup();
                        return;
                    }
                    start = mapToItem(widgets, m.x, m.y);
                    origin = Qt.point(slot.x, slot.y);
                    dragging = false;
                }
                onPositionChanged: m => {
                    if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                    const p = mapToItem(widgets, m.x, m.y);
                    if (!dragging && Math.hypot(p.x - start.x, p.y - start.y) < 6) return;
                    dragging = true;
                    slot.x = Math.max(0, Math.min(widgets.width - slot.width, origin.x + p.x - start.x));
                    slot.y = Math.max(0, Math.min(widgets.height - slot.height, origin.y + p.y - start.y));
                }
                onReleased: {
                    if (dragging) {
                        widgets.place(slot.index, slot.x, slot.y);
                        dragging = false;
                        slot.follow();
                    }
                }
                onCanceled: {
                    dragging = false;
                    slot.follow();
                }
                onClicked: m => {
                    // a real click (not the end of a drag) belongs to the card
                    m.accepted = m.button === Qt.RightButton || Math.hypot(mapToItem(widgets, m.x, m.y).x - start.x,
                                                                             mapToItem(widgets, m.x, m.y).y - start.y) >= 6;
                }
                onPressAndHold: m => { m.accepted = false; }
            }
        }
    }

    PC3.Menu {
        id: widgetMenu
        property int index: -1
        property string size: "small"
        Repeater {
            model: [["small", Tr.t("Маленький")], ["wide", Tr.t("Средний")], ["large", Tr.t("Большой")]]
            delegate: PC3.MenuItem {
                required property var modelData
                text: modelData[1]
                checkable: true
                checked: widgetMenu.size === modelData[0]
                onTriggered: widgets.resize(widgetMenu.index, modelData[0])
            }
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: Tr.t("Добавить виджет…")
            icon.name: "list-add"
            onTriggered: widgets.galleryRequested()
        }
        PC3.MenuItem {
            text: Tr.t("Удалить виджет")
            icon.name: "edit-delete-remove"
            onTriggered: widgets.remove(widgetMenu.index)
        }
    }
}

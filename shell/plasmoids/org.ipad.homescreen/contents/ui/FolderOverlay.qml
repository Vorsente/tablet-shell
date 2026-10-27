// Opened folder: dimmed backdrop with a frosted panel, editable name and the apps inside.
// In edit mode every app gets a "−" badge that moves it back to the home grid; an app can also be
// dragged out (long press, or a plain drag in edit/PC mode) and dropped anywhere on the home grid.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: overlay

    required property var home
    readonly property var folder: home.openFolder !== null ? home.layout[home.openFolder] : null

    // while an app is dragged out the folder is see-through but stays alive: it holds the touch
    visible: opacity > 0 || home.dragApp !== ""
    opacity: folder && typeof folder === "object" && home.dragApp === "" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea { anchors.fill: parent; onClicked: overlay.home.openFolder = null }
    }

    Rectangle {
        id: panel
        readonly property int cols: Math.min(4, Math.max(3, overlay.folder ? Math.ceil(Math.sqrt(overlay.folder.apps.length)) : 3))
        anchors.centerIn: parent
        width: cols * overlay.home.cellWidth + Kirigami.Units.gridUnit * 2
        height: content.implicitHeight + Kirigami.Units.gridUnit * 2
        radius: overlay.home.pixel ? Kirigami.Units.gridUnit * 2.2 : Kirigami.Units.gridUnit * 1.6
        color: overlay.home.pixel ? overlay.home.pal.sheet : Qt.alpha(overlay.home.pal.sheet, 0.78)
        border.color: overlay.home.pal.sheetBorder
        border.width: overlay.home.pixel ? 0 : 1
        scale: overlay.opacity > 0 ? 1 : 0.9
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        GlassSheen {
            home: overlay.home
        }
        MouseArea { anchors.fill: parent }  // swallow taps so the backdrop does not close the folder

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            PC3.TextField {
                id: nameField
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: overlay.home.cellWidth * 2.5
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                font.weight: Font.DemiBold
                readOnly: !overlay.home.editing
                background: null
                text: overlay.folder && overlay.folder.folder ? overlay.folder.folder : ""
                onEditingFinished: if (overlay.home.openFolder !== null) overlay.home.renameFolder(overlay.home.openFolder, text)
            }

            Grid {
                Layout.alignment: Qt.AlignHCenter
                columns: panel.cols

                Repeater {
                    model: overlay.folder && overlay.folder.apps ? overlay.folder.apps : []

                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: overlay.home.cellWidth
                        height: overlay.home.cellHeight

                        TileFace {
                            id: face
                            anchors.centerIn: parent
                            home: overlay.home
                            entry: cell.modelData
                            onSheet: true
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            pressAndHoldInterval: 450
                            preventStealing: picked
                            property point pressPos
                            property bool picked: false
                            property bool moved: false   // a swipe that ends on the icon is no tap

                            function pick(m) {
                                picked = true;
                                overlay.home.dragPos = mapToItem(overlay.home, m.x, m.y);
                                overlay.home.startFolderDrag(overlay.home.openFolder, cell.modelData);
                            }
                            onPressed: m => {
                                pressPos = Qt.point(m.x, m.y);
                                picked = false;
                                moved = false;
                            }
                            onPressAndHold: m => {
                                if (!overlay.home.pcMode) {
                                    overlay.home.editing = true;
                                }
                                pick(m);
                            }
                            onPositionChanged: m => {
                                if (Math.hypot(m.x - pressPos.x, m.y - pressPos.y) > overlay.home.tapSlop) {
                                    moved = true;
                                }
                                if (!picked && (overlay.home.editing || overlay.home.pcMode)
                                        && Math.hypot(m.x - pressPos.x, m.y - pressPos.y) > 12) {
                                    pick(m);
                                }
                                if (picked) {
                                    overlay.home.dragPos = mapToItem(overlay.home, m.x, m.y);
                                }
                            }
                            onReleased: {
                                if (picked) {
                                    picked = false;
                                    overlay.home.finishDrag();
                                }
                            }
                            onCanceled: {
                                if (picked) {
                                    picked = false;
                                    overlay.home.cancelDrag();
                                }
                            }
                            onClicked: if (!overlay.home.editing && !picked && !moved) overlay.home.launch(cell.modelData, face.iconItem)
                        }

                        // "−" badge: take the app out of the folder
                        Rectangle {
                            visible: overlay.home.editing
                            x: face.x + (face.width - overlay.home.iconSize) / 2 - width / 3
                            y: face.y - height / 3
                            width: Kirigami.Units.gridUnit * 1.4
                            height: width
                            radius: width / 2
                            color: overlay.home.pal.control
                            PC3.Label {
                                anchors.centerIn: parent
                                text: "−"
                                color: overlay.home.pal.text
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: overlay.home.takeOutOfFolder(overlay.home.openFolder, cell.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}

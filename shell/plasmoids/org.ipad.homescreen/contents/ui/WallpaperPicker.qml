// Wallpaper gallery: Plasma wallpaper packages (with light/dark variants) and photos from
// ~/Pictures; tap applies to the home and lock screen. "Выбрать фото…" opens a file dialog.
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: picker

    required property var home
    property bool open: false
    property var items: []   // [{ path, thumb }]

    function show() {
        open = true;
        home.runCommand([home.homeDir + "/.local/bin/wallpaper", "list"], out => {
            items = out.split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                const [path, thumb] = l.split("\t");
                return { path: path, thumb: thumb };
            });
        });
    }

    function apply(path) {
        home.runCommand([home.homeDir + "/.local/bin/wallpaper", "set", path]);
        open = false;
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: picker.open = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 46)
        height: Math.min(parent.height - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 32)
        radius: picker.home.pixel ? Kirigami.Units.gridUnit * 1.6 : Kirigami.Units.gridUnit * 1.2
        color: picker.home.pal.sheet
        border.color: picker.home.pal.sheetBorder
        border.width: picker.home.pixel ? 0 : 1

        GlassSheen { home: picker.home }
        MouseArea { anchors.fill: parent }  // keep taps inside

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    Layout.fillWidth: true
                    text: Tr.t("Обои")
                    color: picker.home.pal.text
                    font.weight: Font.DemiBold
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                }
                GlassButton {
                    home: picker.home
                    onSheet: true
                    text: Tr.t("Выбрать фото…")
                    iconName: "document-open-symbolic"
                    onClicked: fileDialog.open()
                }
                GlassButton {
                    home: picker.home
                    onSheet: true
                    iconName: "window-close-symbolic"
                    onClicked: picker.open = false
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                readonly property int cols: Math.max(2, Math.floor(width / (Kirigami.Units.gridUnit * 11)))
                cellWidth: Math.floor(width / cols)
                cellHeight: cellWidth * 0.68
                model: picker.items
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: frame
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        radius: Kirigami.Units.smallSpacing * 2
                        color: picker.home.pal.fillWeak
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: "file://" + modelData.thumb
                            sourceSize.width: 360
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        PC3.Label {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: modelData.path.split("/").pop().replace(/-iPad$/, "").replace(/\.[a-z]+$/i, "")
                            color: "white"
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.6)
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: picker.apply(modelData.path)
                    }
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: Tr.t("Выберите фото для обоев")
        nameFilters: [Tr.t("Изображения (*.jpg *.jpeg *.png *.webp *.jxl *.avif)")]
        onAccepted: picker.apply(decodeURIComponent(String(selectedFile).replace("file://", "")))
    }
}

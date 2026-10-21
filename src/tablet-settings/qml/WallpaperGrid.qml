// Wallpapers (home and lock screen): Plasma packages with light/dark variants and photos.
// Bigger tiles in tablet mode; arrow keys + Enter in PC mode.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: root
    property bool touch: false
    property var items: backend.wallpapers()

    function apply(path) {
        backend.start([backend.home() + "/.local/bin/wallpaper", "set", path]);
    }

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: Tr.t("Обои")
        }
        QQC2.Button {
            text: Tr.t("Выбрать фото…")
            icon.name: "document-open"
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            onClicked: fileDialog.open()
        }
    }

    GridView {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: Math.ceil(count / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
        interactive: false
        keyNavigationEnabled: true
        activeFocusOnTab: true
        cellWidth: Kirigami.Units.gridUnit * (root.touch ? 12 : 9)
        cellHeight: cellWidth * 0.7
        model: root.items
        Keys.onReturnPressed: root.apply(root.items[currentIndex].path)

        delegate: Item {
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.alternateBackgroundColor
                border.width: grid.activeFocus && grid.currentIndex === index ? 2 : 0
                border.color: Kirigami.Theme.highlightColor
                clip: true

                Image {
                    anchors.fill: parent
                    source: "file://" + modelData.thumb
                    sourceSize.width: 360
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                QQC2.Label {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Kirigami.Units.smallSpacing
                    text: modelData.name.replace(/\.[a-z]+$/i, "")
                    color: "white"
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.6)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        grid.currentIndex = index;
                        root.apply(modelData.path);
                    }
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: Tr.t("Выберите фото для обоев")
        nameFilters: [Tr.t("Изображения (*.jpg *.jpeg *.png *.webp *.jxl *.avif)")]
        onAccepted: root.apply(decodeURIComponent(String(selectedFile).replace("file://", "")))
    }
}

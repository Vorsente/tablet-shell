// Long press on empty home screen space: iOS-style menu with wallpaper, editing,
// web app and light/dark/auto appearance; in PC mode also a new folder / text file on the desktop.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: menu

    required property var home
    signal wallpaperRequested()
    signal webAppRequested()
    signal newFolderRequested()
    signal newFileRequested()

    property bool open: false
    property point at: Qt.point(0, 0)
    property string appearance: "auto"

    function popup(p) {
        at = p;
        open = true;
        home.runCommand([home.homeDir + "/.local/bin/appearance", "status"], out => appearance = out.trim() || "auto");
    }

    function setAppearance(mode) {
        appearance = mode;
        home.runCommand([home.homeDir + "/.local/bin/appearance", mode]);
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.open = false
    }

    Rectangle {
        id: panel
        // iOS-style context menu: rows inset from the rounded edge, hairline separators inside
        // the padding, symbolic icons at the right, the appearance switch as three tiles
        readonly property real pad: Math.round(Kirigami.Units.gridUnit * 0.55)
        width: Math.round(Kirigami.Units.gridUnit * 16)
        height: column.implicitHeight + pad * 2
        x: Math.max(Kirigami.Units.largeSpacing, Math.min(menu.at.x - width / 2, menu.width - width - Kirigami.Units.largeSpacing))
        y: Math.max(Kirigami.Units.largeSpacing, Math.min(menu.at.y, menu.height - height - Kirigami.Units.gridUnit * 5))
        radius: menu.home.pixel ? Kirigami.Units.gridUnit * 1.4 : Kirigami.Units.gridUnit
        color: menu.home.pal.sheet
        border.color: menu.home.pal.sheetBorder
        border.width: menu.home.pixel ? 0 : 1
        scale: menu.open ? 1 : 0.92
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        GlassSheen { home: menu.home }
        MouseArea { anchors.fill: parent }  // keep taps inside the menu

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: panel.pad
            spacing: 0

            // one row: label left, symbolic icon right, a rounded highlight while pressed
            component Entry: Item {
                id: entry
                property string text
                property string iconName
                signal clicked()
                Layout.fillWidth: true
                implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.5)
                Rectangle {
                    anchors.fill: parent
                    radius: menu.home.pixel ? height / 2 : Kirigami.Units.gridUnit * 0.55
                    color: menu.home.pal.fill
                    opacity: entryArea.pressed ? 1 : entryArea.containsMouse ? 0.55 : 0
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Math.round(Kirigami.Units.gridUnit * 0.75)
                    anchors.rightMargin: Math.round(Kirigami.Units.gridUnit * 0.75)
                    spacing: Kirigami.Units.largeSpacing
                    PC3.Label {
                        Layout.fillWidth: true
                        text: entry.text
                        color: menu.home.pal.text
                        elide: Text.ElideRight
                    }
                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignVCenter
                        source: entry.iconName
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                        color: menu.home.pal.text
                        isMask: true
                    }
                }
                MouseArea {
                    id: entryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: entry.clicked()
                }
            }
            component Separator: Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Math.round(Kirigami.Units.gridUnit * 0.75)
                Layout.rightMargin: Math.round(Kirigami.Units.gridUnit * 0.75)
                Layout.topMargin: panel.pad
                Layout.bottomMargin: panel.pad
                implicitHeight: 1
                color: menu.home.pal.fill
            }

            // PC desktop (DesktopFolder.qml): new folder / text file in ~/Desktop
            Entry {
                visible: menu.home.pcMode
                text: Tr.t("Новая папка")
                iconName: "folder-new-symbolic"
                onClicked: { menu.open = false; menu.newFolderRequested(); }
            }
            Entry {
                visible: menu.home.pcMode
                text: Tr.t("Новый текстовый файл")
                iconName: "document-new-symbolic"
                onClicked: { menu.open = false; menu.newFileRequested(); }
            }
            Separator { visible: menu.home.pcMode }
            Entry {
                text: Tr.t("Обои")
                iconName: "preferences-desktop-wallpaper"
                onClicked: { menu.open = false; menu.wallpaperRequested(); }
            }
            Entry {
                visible: !menu.home.pcMode
                text: Tr.t("Править экран «Домой»")
                iconName: "edit-entry-symbolic"
                onClicked: { menu.open = false; menu.home.editing = true; }
            }
            Entry {
                text: Tr.t("Веб-приложение")
                iconName: "list-add-symbolic"
                onClicked: { menu.open = false; menu.webAppRequested(); }
            }

            Separator {}

            // Appearance: segmented light / dark / auto
            RowLayout {
                Layout.fillWidth: true
                spacing: panel.pad

                Repeater {
                    model: [
                        { mode: "light", label: Tr.t("Светлая"), icon: "weather-clear-symbolic" },
                        { mode: "dark", label: Tr.t("Тёмная"), icon: "weather-clear-night-symbolic" },
                        { mode: "auto", label: Tr.t("Авто"), icon: "contrast-symbolic" },
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Math.round(Kirigami.Units.gridUnit * 3.4)
                        radius: menu.home.pixel ? Kirigami.Units.gridUnit * 1.1 : Kirigami.Units.gridUnit * 0.6
                        border.width: menu.appearance === modelData.mode ? 1 : 0
                        border.color: menu.home.pal.sheetBorder
                        color: menu.appearance === modelData.mode ? menu.home.pal.fillStrong : menu.home.pal.fillWeak

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                source: modelData.icon
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: implicitWidth
                                color: menu.home.pal.text
                                isMask: true
                            }
                            PC3.Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: menu.home.pal.text
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: menu.setAppearance(modelData.mode)
                        }
                    }
                }
            }
        }
    }
}

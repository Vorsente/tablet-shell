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
        width: Kirigami.Units.gridUnit * 15
        height: column.implicitHeight + Kirigami.Units.smallSpacing * 2
        x: Math.max(Kirigami.Units.largeSpacing, Math.min(menu.at.x - width / 2, menu.width - width - Kirigami.Units.largeSpacing))
        y: Math.max(Kirigami.Units.largeSpacing, Math.min(menu.at.y, menu.height - height - Kirigami.Units.gridUnit * 5))
        radius: menu.home.pixel ? Kirigami.Units.gridUnit * 1.6 : Kirigami.Units.gridUnit
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
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 0

            component Entry: PC3.ItemDelegate {
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit * 2.4
                palette.text: menu.home.pal.text
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    PC3.Label {
                        Layout.fillWidth: true
                        text: parent.parent.text
                        color: menu.home.pal.text
                    }
                    Kirigami.Icon {
                        source: parent.parent.icon.name
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                    }
                }
            }

            // PC desktop (DesktopFolder.qml): new folder / text file in ~/Desktop
            Entry {
                visible: menu.home.pcMode
                text: Tr.t("Новая папка")
                icon.name: "folder-new"
                onClicked: { menu.open = false; menu.newFolderRequested(); }
            }
            Entry {
                visible: menu.home.pcMode
                text: Tr.t("Новый текстовый файл")
                icon.name: "document-new"
                onClicked: { menu.open = false; menu.newFileRequested(); }
            }
            Rectangle {
                visible: menu.home.pcMode
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                implicitHeight: 1
                color: menu.home.pal.fill
            }
            Entry {
                text: Tr.t("Обои")
                icon.name: "preferences-desktop-wallpaper-symbolic"
                onClicked: { menu.open = false; menu.wallpaperRequested(); }
            }
            Entry {
                visible: !menu.home.pcMode
                text: Tr.t("Править экран «Домой»")
                icon.name: "edit-entry"
                onClicked: { menu.open = false; menu.home.editing = true; }
            }
            Entry {
                text: Tr.t("Веб-приложение")
                icon.name: "list-add"
                onClicked: { menu.open = false; menu.webAppRequested(); }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                implicitHeight: 1
                color: menu.home.pal.fill
            }

            // Appearance: segmented light / dark / auto
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: [
                        { mode: "light", label: Tr.t("Светлая"), icon: "weather-clear" },
                        { mode: "dark", label: Tr.t("Тёмная"), icon: "weather-clear-night" },
                        { mode: "auto", label: Tr.t("Авто"), icon: "chronometer" },
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 3.2
                        radius: Kirigami.Units.smallSpacing * 2
                        color: menu.appearance === modelData.mode ? menu.home.pal.fillStrong : menu.home.pal.fillWeak

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
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

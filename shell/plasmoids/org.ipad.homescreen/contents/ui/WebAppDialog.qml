// "Add web app" sheet: name + address; the launcher and icon are made by ~/.local/bin/webapp-create.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: dialog

    required property var home
    property bool open: false

    function show() {
        nameField.text = "";
        urlField.text = "";
        open = true;
        urlField.forceActiveFocus();
    }

    function accept() {
        const url = urlField.text.trim();
        if (!url) {
            return;
        }
        let name = nameField.text.trim();
        if (!name) {
            // "https://www.example.com/x" -> "Example"
            const host = url.replace(/^[a-z]+:\/\//i, "").replace(/^www\./, "").split(/[\/:]/)[0];
            name = host.split(".")[0];
            name = name.charAt(0).toUpperCase() + name.slice(1);
        }
        home.runCommand([home.homeDir + "/.local/bin/webapp-create", name, url]);
        open = false;
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea { anchors.fill: parent; onClicked: dialog.open = false }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 26)
        height: form.implicitHeight + Kirigami.Units.gridUnit * 2
        radius: dialog.home.pixel ? Kirigami.Units.gridUnit * 1.6 : Kirigami.Units.gridUnit * 1.2
        color: dialog.home.pal.sheet
        border.color: dialog.home.pal.sheetBorder
        border.width: dialog.home.pixel ? 0 : 1

        GlassSheen { home: dialog.home }
        MouseArea { anchors.fill: parent }  // keep taps inside the sheet

        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            PC3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: Tr.t("Новое веб-приложение")
                font.weight: Font.DemiBold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                color: dialog.home.pal.text
            }
            PC3.TextField {
                id: urlField
                Layout.fillWidth: true
                color: dialog.home.pal.text
                placeholderTextColor: dialog.home.pal.secondary
                background: Rectangle {
                    implicitHeight: Kirigami.Units.gridUnit * 2.2
                    radius: height * 0.3
                    color: dialog.home.pal.fill
                }
                placeholderText: Tr.t("Адрес, например music.yandex.ru")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                onAccepted: nameField.text ? dialog.accept() : nameField.forceActiveFocus()
            }
            PC3.TextField {
                id: nameField
                Layout.fillWidth: true
                color: dialog.home.pal.text
                placeholderTextColor: dialog.home.pal.secondary
                background: Rectangle {
                    implicitHeight: Kirigami.Units.gridUnit * 2.2
                    radius: height * 0.3
                    color: dialog.home.pal.fill
                }
                placeholderText: Tr.t("Название (необязательно)")
                onAccepted: dialog.accept()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                GlassButton {
                    home: dialog.home
                    onSheet: true
                    text: Tr.t("Отмена")
                    onClicked: dialog.open = false
                }
                GlassButton {
                    home: dialog.home
                    onSheet: true
                    prominent: true
                    text: Tr.t("Добавить")
                    enabled: urlField.text.trim().length > 0
                    onClicked: dialog.accept()
                }
            }
        }
    }
}

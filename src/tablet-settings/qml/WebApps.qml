// Web apps on the home screen: list with remove buttons and an "add" form.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: root
    property bool touch: false
    property var apps: backend.webApps()
    property bool busy: false

    Connections {
        target: backend
        function onWebAppsChanged() {
            root.apps = backend.webApps();
            root.busy = false;
        }
    }

    Kirigami.Heading {
        level: 3
        text: Tr.t("Веб-приложения")
    }

    QQC2.Label {
        visible: root.apps.length === 0
        text: Tr.t("Пока нет веб-приложений")
        opacity: 0.6
    }

    Repeater {
        model: root.apps
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: root.touch ? Kirigami.Units.gridUnit * 3.2 : Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: modelData.icon
                implicitWidth: root.touch ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label { text: modelData.name }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData.url
                    opacity: 0.6
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            QQC2.Button {
                icon.name: "edit-delete"
                text: root.touch ? Tr.t("Удалить") : ""
                // Qt 6.12: assigning undefined no longer restores the default
                Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
                QQC2.ToolTip.text: Tr.t("Удалить веб-приложение")
                QQC2.ToolTip.visible: hovered && !root.touch
                onClicked: backend.removeWebApp(modelData.id)
            }
        }
    }

    // add form
    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        columns: root.touch ? 1 : 3
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing

        QQC2.TextField {
            id: url
            Layout.fillWidth: true
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            placeholderText: Tr.t("Адрес, например music.yandex.ru")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            onAccepted: name.forceActiveFocus()
        }
        QQC2.TextField {
            id: name
            Layout.fillWidth: true
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            placeholderText: Tr.t("Название (необязательно)")
            onAccepted: addButton.clicked()
        }
        QQC2.Button {
            id: addButton
            text: root.busy ? Tr.t("Добавляю…") : Tr.t("Добавить")
            icon.name: "list-add"
            enabled: url.text.trim().length > 0 && !root.busy
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            onClicked: {
                let n = name.text.trim();
                if (!n) {
                    const host = url.text.trim().replace(/^[a-z]+:\/\//i, "").replace(/^www\./, "").split(/[\/:]/)[0];
                    n = host.split(".")[0];
                    n = n.charAt(0).toUpperCase() + n.slice(1);
                }
                root.busy = true;
                backend.addWebApp(n, url.text.trim());
                url.text = "";
                name.text = "";
            }
        }
    }
}

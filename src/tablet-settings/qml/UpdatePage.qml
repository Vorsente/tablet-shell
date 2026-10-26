// GitHub updater for tablet-shell. Uses asynchronous QProcess in Backend;
// builds and installs never block the settings window.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: root
    property bool touch: false
    readonly property var info: backend.updateInfo
    readonly property string stage: String(info.stage || "idle")
    readonly property bool busy: ["checking", "downloading", "preparing", "installing"].includes(stage)
    spacing: Kirigami.Units.largeSpacing

    Component.onCompleted: backend.checkForUpdates()

    Kirigami.Heading {
        level: 3
        text: Tr.t("Обновление tablet-shell")
    }
    QQC2.Label {
        Layout.fillWidth: true
        text: Tr.t("Источник: GitHub · Vorsente/tablet-shell")
        opacity: 0.68
        wrapMode: Text.WordWrap
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        // the release number (0.5.0) and the exact commit
        text: Tr.t("Установленная версия: ") + (info.installedRelease ? info.installedRelease + " · " : "")
              + (info.installed && info.installed !== "local" ? String(info.installed).slice(0, 10) : Tr.t("локальная сборка"))
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: !!info.label
        text: Tr.t("На GitHub: ") + (info.release ? info.release + " · " : "") + String(info.label || "")
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: {
            switch (root.stage) {
            case "checking": return Tr.t("Проверяю обновления на GitHub…");
            case "available": return root.info.older
                ? Tr.t("Версия на GitHub старее установленной (") + String(info.remoteDate || "") + Tr.t(" против ") + String(info.installedDate || "") + Tr.t("). Установка вернёт старый код.")
                : Tr.t("Найдена другая версия. Можно скачать и установить её.");
            case "up-to-date": return Tr.t("У вас установлена актуальная версия.");
            case "downloading": return Tr.t("Скачивание с GitHub…") + (info.progress ? " " + info.progress + " %" : "");
            case "preparing": return Tr.t("Проверка архива…");
            case "installing": return Tr.t("Шаг ") + (info.step || 1) + Tr.t(" из 4: ") + String(info.message || Tr.t("сборка и установка")) + Tr.t(". Не закрывайте приложение.");
            case "done": return Tr.t("Обновление установлено. Перезапустите оболочку, чтобы применить его.");
            case "error": return Tr.t("Ошибка обновления: ") + String(info.message || "");
            case "cancelled": return Tr.t("Загрузка отменена.");
            default: return Tr.t("Нажмите «Проверить обновления».");
            }
        }
        color: root.stage === "error" ? Kirigami.Theme.negativeTextColor
             : root.stage === "available" && root.info.older ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
    }
    QQC2.ProgressBar {
        Layout.fillWidth: true
        visible: root.busy
        indeterminate: !["downloading", "installing"].includes(root.stage) || !info.progress
        from: 0
        to: 100
        value: Number(info.progress || 0)
    }
    QQC2.Label {
        Layout.fillWidth: true
        visible: !!info.untracked && ["available", "downloading", "preparing"].includes(root.stage)
        wrapMode: Text.WordWrap
        text: Tr.t("Текущая версия установлена не из отслеживаемого Git-коммита. Версия с GitHub может быть старее и не содержать ваших локальных доработок, включая Pixel. Проверяйте перед установкой.")
        color: Kirigami.Theme.neutralTextColor
    }
    // what is new on GitHub (commit titles back to the installed version)
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.stage === "available" && (root.info.changes || []).length > 0
        spacing: Kirigami.Units.smallSpacing
        QQC2.Label {
            text: Tr.t("Что нового")
            font.weight: Font.DemiBold
        }
        Repeater {
            model: root.info.changes || []
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "vcs-commit"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Layout.alignment: Qt.AlignTop
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: modelData.title
                }
                QQC2.Label {
                    text: modelData.date
                    opacity: 0.6
                    Layout.alignment: Qt.AlignTop
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        QQC2.Button {
            icon.name: "system-reboot"
            text: Tr.t("Перезапустить оболочку")
            visible: root.stage === "done"
            highlighted: true
            onClicked: backend.start(["systemctl", "--user", "restart", "plasma-plasmashell.service", "tabletshell.service", "tabletd.service"])
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
        }
        QQC2.Button {
            icon.name: "view-refresh"
            text: Tr.t("Проверить обновления")
            enabled: !root.busy
            onClicked: backend.checkForUpdates()
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
        }
        QQC2.Button {
            icon.name: "system-software-update"
            text: Tr.t("Скачать и установить")
            visible: root.stage === "available"
            enabled: !root.busy && !!root.info.sha
            onClicked: confirmUpdate.open()
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
        }
        QQC2.Button {
            icon.name: "dialog-cancel"
            text: Tr.t("Отменить")
            visible: ["checking", "downloading", "preparing"].includes(root.stage)
            onClicked: backend.cancelUpdate()
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
        }
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.66
        text: Tr.t("Рабочий стол и пункт управления обновляются здесь. Клавиатура, экран блокировки и экран входа при обновлении не меняются; экран входа greetd обновляется отдельно: sudo ~/.local/share/tablet-shell/system/greeter.sh --refresh")
    }
    QQC2.Button {
        icon.name: "internet-web-browser"
        text: Tr.t("Открыть репозиторий на GitHub")
        onClicked: Qt.openUrlExternally("https://github.com/Vorsente/tablet-shell")
        flat: true
    }

    Kirigami.PromptDialog {
        id: confirmUpdate
        title: Tr.t("Установить версию с GitHub?")
        subtitle: (root.info.older ? Tr.t("Внимание: версия на GitHub старее установленной, новые функции пропадут. ") : "")
                  + Tr.t("Исходный код будет скачан с GitHub, затем собран и установлен. Он может отличаться от вашей локальной сборки. Обновление не сбрасывает конфигурацию, но может заменить локальные изменения в коде.")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: backend.installGitHubUpdate()
    }
}

// Recovery section: system snapshots of the btrfs root (/usr/local/lib/tablet/tablet-snapshot;
// one is taken automatically before every pacman update). Create, restore (after a reboot the
// system is the snapshot; the current one is kept for one undo) or delete, each through pkexec,
// which asks for the password. Home is never touched.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: root
    property bool touch: false
    property var snapshots: []
    property string busy: ""            // what is running ("" = nothing)
    property string message: ""
    property bool rebootNeeded: false

    readonly property string tool: "/usr/local/lib/tablet/tablet-snapshot"
    readonly property string outFile: backend.run(["sh", "-c", "printf %s \"$XDG_RUNTIME_DIR\""]) + "/tablet-snapshot.out"

    function load() {
        snapshots = backend.run(["sh", "-c", "ls -1 /.snapshots 2>/dev/null | sort -r"]).split("\n").filter(n => n.length > 0);
    }
    Component.onCompleted: load()

    // "2026-10-20_18-05-00_update" -> "20 октября, 18:05 · перед обновлением"
    function describe(name) {
        const m = name.match(/^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-\d{2}_(.*)$/);
        if (!m) {
            return [name, ""];
        }
        const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]));
        const why = { update: Tr.t("перед обновлением"), manual: Tr.t("создан вручную"), "before-restore": Tr.t("до восстановления") }[m[6]] || m[6];
        return [d.toLocaleDateString(Tr.locale(), "d MMMM") + ", " + m[4] + ":" + m[5], why];
    }

    // pkexec asks for the password, so the tool runs in the background and reports into a file
    function runTool(what, args) {
        busy = what;
        message = "";
        backend.run(["rm", "-f", outFile]);
        backend.start(["bash", "-c", 'pkexec "$1" "${@:3}" > "$2" 2>&1; echo "exit=$?" >> "$2"', "bash", tool, outFile].concat(args));
        poll.start();
    }
    Timer {
        id: poll
        interval: 1000
        repeat: true
        onTriggered: {
            const out = backend.run(["cat", root.outFile]);
            const m = out.match(/exit=(\d+)/);
            if (!m) {
                return;
            }
            stop();
            const ok = m[1] === "0";
            if (root.busy === "restore" && ok) {
                root.rebootNeeded = true;
                root.message = Tr.t("Готово. После перезагрузки система станет такой, какой была в момент снимка.");
            } else if (ok) {
                root.message = root.busy === "create" ? Tr.t("Снимок создан.") : Tr.t("Снимок удалён.");
            } else {
                root.message = m[1] === "126" || m[1] === "127" ? Tr.t("Отменено.") : Tr.t("Не получилось: ") + out.replace(/exit=\d+/, "").trim();
            }
            root.busy = "";
            root.load();
        }
    }

    Kirigami.Heading {
        level: 3
        text: Tr.t("Снимки системы")
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: Tr.t("Снимок сохраняет систему и программы (не ваши файлы). Перед каждым обновлением он делается сам. ")
              + Tr.t("Если после обновления что-то сломалось — восстановите снимок или выберите «до последнего обновления» в меню загрузки (пробел при включении).")
    }

    RowLayout {
        Layout.topMargin: Kirigami.Units.smallSpacing
        QQC2.Button {
            icon.name: "document-save"
            text: root.busy === "create" ? Tr.t("Создаю…") : Tr.t("Создать снимок")
            enabled: root.busy === ""
            onClicked: root.runTool("create", ["create", "manual"])
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
        }
        QQC2.Button {
            visible: root.rebootNeeded
            icon.name: "system-reboot"
            text: Tr.t("Перезагрузить")
            onClicked: backend.start(["systemctl", "reboot"])
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
        }
    }
    QQC2.Label {
        Layout.fillWidth: true
        visible: root.message.length > 0
        wrapMode: Text.WordWrap
        text: root.message
    }

    QQC2.Label {
        visible: root.snapshots.length === 0
        text: Tr.t("Снимков пока нет")
        opacity: 0.6
    }

    Repeater {
        model: root.snapshots
        delegate: RowLayout {
            required property string modelData
            readonly property var about: root.describe(modelData)
            Layout.fillWidth: true
            Layout.preferredHeight: root.touch ? Kirigami.Units.gridUnit * 3.2 : Kirigami.Units.gridUnit * 2.2
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: about[1] === Tr.t("перед обновлением") ? "system-software-update" : "document-save"
                implicitWidth: root.touch ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label { text: about[0] }
                QQC2.Label {
                    text: about[1]
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            QQC2.Button {
                icon.name: "edit-undo"
                text: Tr.t("Восстановить")
                enabled: root.busy === ""
                onClicked: {
                    restoreDialog.name = modelData;
                    restoreDialog.when = about[0];
                    restoreDialog.open();
                }
                Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            }
            QQC2.Button {
                icon.name: "edit-delete"
                enabled: root.busy === ""
                onClicked: {
                    deleteDialog.name = modelData;
                    deleteDialog.when = about[0];
                    deleteDialog.open();
                }
                QQC2.ToolTip.text: Tr.t("Удалить снимок")
                QQC2.ToolTip.visible: hovered
                Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            }
        }
    }

    Kirigami.PromptDialog {
        id: deleteDialog
        property string name
        property string when
        title: Tr.t("Удалить снимок?")
        subtitle: Tr.t("Снимок от ") + when + Tr.t(" будет удалён без возможности вернуть.")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.runTool("delete", ["delete", name])
    }

    Kirigami.PromptDialog {
        id: restoreDialog
        property string name
        property string when
        title: Tr.t("Восстановить систему?")
        subtitle: Tr.t("После перезагрузки система станет такой, какой была ") + when + Tr.t(". Ваши файлы не изменятся. ")
                  + Tr.t("Текущее состояние сохранится, и восстановление можно будет отменить.")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.runTool("restore", ["restore", name])
    }
}

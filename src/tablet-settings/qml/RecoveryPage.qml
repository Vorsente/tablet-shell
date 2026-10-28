// Recovery section: system snapshots of the btrfs root (/usr/local/lib/tablet/tablet-snapshot;
// one is taken automatically before every pacman update), plus the ones other tools made
// (Snapper on openSUSE, Timeshift, any btrfs snapshot). Create, restore (after a reboot the
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

    // /var/lib/tablet/snapshots.json (tablet-snapshot scan, kept fresh by systemd): every
    // snapshot on the root file system, whichever tool made it. Without it (recovery part not
    // installed yet): this tool's own in /.snapshots.
    property var index: null
    function load() {
        let data = null;
        try {
            data = JSON.parse(backend.run(["cat", "/var/lib/tablet/snapshots.json"]) || "null");
        } catch (e) {
            data = null;
        }
        index = data;
        if (data && data.snapshots) {
            snapshots = data.snapshots;
            return;
        }
        snapshots = backend.run(["sh", "-c", "ls -1 /.snapshots 2>/dev/null | sort -r"]).split("\n")
            .filter(n => /^\d{4}-\d{2}-\d{2}_/.test(n))
            .map(n => ({ id: "tablet:" + n, kind: "tablet", type: n.replace(/^.*_/, ""), description: "",
                         time: 0, name: n, restore: true }));
    }
    Component.onCompleted: load()

    // -> [when, why, source]
    function describe(s) {
        let when = "";
        if (s.time > 0) {
            const d = new Date(s.time * 1000);
            when = d.toLocaleDateString(Tr.locale(), d.getFullYear() === new Date().getFullYear() ? "d MMMM" : "d MMMM yyyy")
                   + ", " + d.toLocaleTimeString(Tr.locale(), "HH:mm");
        } else {
            const m = (s.name || "").match(/^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})/);
            when = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).toLocaleDateString(Tr.locale(), "d MMMM") + ", " + m[4] + ":" + m[5]
                     : s.id;
        }
        const types = {
            update: Tr.t("перед обновлением"), manual: Tr.t("создан вручную"), "before-restore": Tr.t("до восстановления"),
            pre: Tr.t("перед изменением"), post: Tr.t("после изменения"), single: Tr.t("отдельный снимок"),
            O: Tr.t("при загрузке"), B: Tr.t("при загрузке"), H: Tr.t("ежечасный"), D: Tr.t("ежедневный"),
            W: Tr.t("еженедельный"), M: Tr.t("ежемесячный"),
        };
        const why = [s.description, types[s.type] || (s.kind === "btrfs" ? s.path : s.type)]
            .filter(t => t && t.length).join(" · ");
        const source = { tablet: "", snapper: "Snapper", timeshift: "Timeshift", btrfs: "btrfs" }[s.kind] || "";
        return [when, why, source];
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
            visible: !root.index || root.index.layout === "at" || root.index.snapper
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
            required property var modelData
            readonly property var about: root.describe(modelData)
            Layout.fillWidth: true
            Layout.preferredHeight: root.touch ? Kirigami.Units.gridUnit * 3.2 : Kirigami.Units.gridUnit * 2.2
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: modelData.type === "update" || modelData.type === "pre" || modelData.type === "post"
                        ? "system-software-update" : modelData.important ? "starred-symbolic" : "document-save"
                implicitWidth: root.touch ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label { text: about[0] }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: [about[2], about[1]].filter(t => t.length).join(" · ")
                    elide: Text.ElideRight
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            QQC2.Button {
                icon.name: "edit-undo"
                text: Tr.t("Восстановить")
                visible: modelData.restore !== false
                enabled: root.busy === ""
                onClicked: {
                    restoreDialog.name = modelData.id;
                    restoreDialog.when = about[0];
                    restoreDialog.open();
                }
                Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.6 }
            }
            QQC2.Button {
                icon.name: "edit-delete"
                enabled: root.busy === ""
                onClicked: {
                    deleteDialog.name = modelData.id;
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

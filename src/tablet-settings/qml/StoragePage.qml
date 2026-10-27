// Storage section: how full the disk is and what can go (`tablet-tools cleanup`): the trash,
// Firefox's cache, app caches, old downloads (moved to the trash) and the package manager's cache
// (pkexec asks for the password). Automatic cleanup (tabletd, weekly): trash and thumbnails older
// than a month, crash reports.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: root
    property bool touch: false
    property var scan: null
    property string busy: ""
    property string message: ""

    readonly property string tools: backend.run(["sh", "-c", "printf %s \"$HOME\""]) + "/.local/bin/tablet-tools"
    readonly property string outFile: backend.run(["sh", "-c", "printf %s \"$XDG_RUNTIME_DIR\""]) + "/tablet-cleanup.out"

    // measuring the caches takes a while on the eMMC: in the background, the page shows at once
    readonly property string scanFile: outFile + ".scan"
    property bool scanning: false
    function load() {
        scanning = true;
        backend.run(["rm", "-f", scanFile]);
        backend.start(["sh", "-c", '"$1" cleanup scan > "$2.tmp" && mv "$2.tmp" "$2"', "sh", tools, scanFile]);
        scanPoll.start();
    }
    Timer {
        id: scanPoll
        interval: 700
        repeat: true
        onTriggered: {
            const out = backend.run(["cat", root.scanFile]);
            if (!out) {
                return;
            }
            stop();
            try {
                root.scan = JSON.parse(out);
            } catch (e) {
            }
            root.scanning = false;
        }
    }
    Component.onCompleted: load()

    function size(bytes) {
        if (bytes >= 1e9) return (bytes / 1e9).toLocaleString(Tr.locale(), "f", 1) + Tr.t(" ГБ");
        if (bytes >= 1e6) return Math.round(bytes / 1e6) + Tr.t(" МБ");
        if (bytes >= 1e3) return Math.round(bytes / 1e3) + Tr.t(" КБ");
        return bytes > 0 ? bytes + Tr.t(" Б") : Tr.t("пусто");
    }

    // runs in the background and reports into a file (pacman's goes through pkexec)
    function clean(ids) {
        busy = ids.join(" ");
        message = "";
        const before = scan ? scan.free : 0;
        backend.run(["rm", "-f", outFile]);
        const pac = ids.indexOf("pacman") >= 0;
        const rest = ids.filter(i => i !== "pacman");
        let script = "";
        if (rest.length > 0) {
            script += '"$1" cleanup run ' + rest.join(" ") + ' >/dev/null 2>&1; ';
        }
        if (pac) {
            // the package manager of this distribution ("pacman" is only the item's id)
            script += 'if command -v pacman >/dev/null; then c="pacman -Sc --noconfirm"; elif command -v apt-get >/dev/null; then c="apt-get clean"; '
                    + 'elif command -v dnf >/dev/null; then c="dnf clean packages"; elif command -v zypper >/dev/null; then c="zypper clean --all"; else c=true; fi; '
                    + 'pkexec $c >/dev/null 2>"$2.err"; p=$?; [ $p -ne 0 ] && echo "pacman=$p" >> "$2"; ';
        }
        script += 'echo done >> "$2"';
        backend.start(["bash", "-c", script, "bash", tools, outFile]);
        freedBefore = before;
        poll.start();
    }
    property real freedBefore: 0
    Timer {
        id: poll
        interval: 1000
        repeat: true
        onTriggered: {
            const out = backend.run(["cat", root.outFile]);
            if (out.indexOf("done") < 0) {
                return;
            }
            stop();
            root.busy = "";
            const free = Number(backend.run(["sh", "-c", "df -B1 --output=avail \"$HOME\" | tail -1"]).trim());
            const freed = free - root.freedBefore;
            const m = out.match(/pacman=(\d+)/);
            root.message = m ? (m[1] === "126" || m[1] === "127" ? Tr.t("Кэш пакетов: отменено.") : Tr.t("Кэш пакетов: не получилось."))
                             : freed > 1e6 ? Tr.t("Освобождено ") + root.size(freed) + "." : Tr.t("Готово.");
            root.load();
        }
    }

    // ---- disk ----
    Kirigami.Heading {
        level: 3
        text: Tr.t("Диск")
    }
    QQC2.Label {
        Layout.fillWidth: true
        text: root.scan ? Tr.t("Свободно ") + root.size(root.scan.free) + Tr.t(" из ") + root.size(root.scan.total) : Tr.t("Считаю…")
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 10
        radius: 5
        color: Qt.rgba(0.5, 0.5, 0.5, 0.25)
        Rectangle {
            readonly property real used: root.scan ? 1 - root.scan.free / root.scan.total : 0
            width: parent.width * used
            height: parent.height
            radius: 5
            color: used > 0.9 ? "#FF453A" : used > 0.75 ? "#FF9F0A" : Kirigami.Theme.highlightColor
        }
    }

    // ---- what can go ----
    Kirigami.Heading {
        level: 3
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: Tr.t("Можно освободить")
    }
    Repeater {
        model: root.scan ? root.scan.items : []
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label { text: modelData.label; font.weight: Font.DemiBold }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData.note
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            QQC2.Label { text: root.size(modelData.bytes) }
            QQC2.Button {
                text: modelData.id === "downloads" ? Tr.t("В корзину") : Tr.t("Очистить")
                enabled: root.busy === "" && modelData.bytes > 0
                         && !(modelData.id === "browser" && modelData.note.indexOf(Tr.t("Закройте")) === 0)
                onClicked: root.clean([modelData.id])
            }
        }
    }
    RowLayout {
        Layout.topMargin: Kirigami.Units.smallSpacing
        QQC2.Button {
            text: Tr.t("Очистить всё, кроме загрузок")
            icon.name: "edit-clear-all"
            enabled: root.busy === "" && root.scan !== null
            onClicked: root.clean(["trash", "browser", "apps", "pacman"])
        }
        QQC2.BusyIndicator {
            running: root.busy !== ""
            visible: running
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: root.message
            wrapMode: Text.WordWrap
        }
    }
}

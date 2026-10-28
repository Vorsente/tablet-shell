// Typewriter panel under the pill (opened with its ≡ button): scenes of the screenplay (tap jumps
// there in ghostwriter), writing statistics, versions (git history of ~/Сценарии kept by
// ~/.local/bin/typewriter; a version opens as a copy, the current text is never overwritten) and
// manuscript export (tablet-tools typewriter-export: PDF / DOCX / EPUB into ~/Сценарии/Экспорт).
// The panel takes no keyboard focus, so ghostwriter keeps the cursor.
import QtQuick
import QtQuick.Window

import org.kde.layershell as LayerShell
import "Tr.js" as Tr

Window {
    id: panel

    required property string file
    required property string dir
    property string tab: "scenes"

    visible: false
    color: "transparent"
    width: 440 * uiStyle.dp
    height: 600 * uiStyle.dp

    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 46 * uiStyle.dp
    LayerShell.Window.margins.right: 10 * uiStyle.dp
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property string tools: shell.env("HOME") + "/.local/bin/tablet-tools"
    readonly property string relFile: file.indexOf(dir + "/") === 0 ? file.slice(dir.length + 1) : file
    readonly property string baseName: relFile.replace(/\.md$/, "")

    function sh(script, args) {
        return shell.run(["sh", "-c", script, "sh"].concat(args || []));
    }

    // ---- data ----
    property var scenes: []
    property var runtime: null      // tablet-tools typewriter-runtime: pages, seconds, scenes
    property int totalWords: 0
    // a voice-over reads about 130 words a minute
    readonly property int speechSeconds: Math.round(totalWords / 130 * 60)
    function minutes(secs) {
        return Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0");
    }
    property var stats: null
    property var versions: []
    property string exportResult: ""

    function load() {
        if (tab === "scenes") {
            const text = shell.readFile(file);
            const out = [];
            let words = 0;
            for (const line of text.split("\n")) {
                if (/^##+\s/.test(line)) {
                    if (out.length > 0) {
                        out[out.length - 1].words = words;
                    }
                    out.push({ title: line.replace(/^##+\s*/, "").replace(/\*/g, ""), line: line, words: 0 });
                    words = 0;
                } else {
                    words += line.split(/\s+/).filter(w => w.length > 0).length;
                }
            }
            if (out.length > 0) {
                out[out.length - 1].words = words;
            }
            try {
                runtime = JSON.parse(shell.run([tools, "typewriter-runtime", file]));
            } catch (e) {
                runtime = null;
            }
            // the page time of each scene, when the screenplay parser found the same scenes
            const timed = runtime && runtime.scenes.length === out.length;
            out.forEach((sc, i) => sc.seconds = timed ? runtime.scenes[i].seconds : Math.round(sc.words / 130 * 60));
            totalWords = text.split(/\s+/).filter(w => w.length > 0).length;
            scenes = out;
        } else if (tab === "stats") {
            try {
                stats = JSON.parse(shell.run([tools, "typewriter-stats"]));
            } catch (e) {
                stats = null;
            }
        } else if (tab === "versions") {
            const log = sh('git -C "$1" log -n 40 --format="%h%x09%ad%x09%s" --date=format:"%d.%m %H:%M" -- "$2"', [dir, relFile]);
            versions = log.split("\n").filter(l => l.length > 0).map(l => {
                const p = l.split("\t");
                return { hash: p[0], date: p[1], subject: p[2] };
            });
        }
    }
    onVisibleChanged: if (visible) load()
    onTabChanged: load()

    // Jump to a scene: the cursor goes to its heading through the accessibility bus
    // (shell.jumpToText; ~/.local/bin/typewriter starts ghostwriter with accessibility on)
    function jumpTo(line) {
        panel.visible = false;
        shell.jumpToText("ghostwriter", line);
    }

    // A version opens as a copy next to the screenplay: "<name> (версия 21.10 14-05).md"
    function openVersion(v) {
        const target = dir + "/" + baseName + Tr.t(" (версия ") + v.date.replace(":", "-") + ").md";
        sh('git -C "$1" show "$2:$3" > "$4" && (ghostwriter "$4" >/dev/null 2>&1 &)', [dir, v.hash, relFile, target]);
        panel.visible = false;
    }

    function exportAs(format) {
        exportResult = Tr.t("Готовлю ") + format.toUpperCase() + "…";
        const out = shell.run([tools, "typewriter-export", file, format]).trim();
        exportResult = out ? out : Tr.t("Не получилось");
    }

    // ---- view ----
    Rectangle {
        anchors.fill: parent
        radius: uiStyle.pixel ? 28 * uiStyle.dp : 18 * uiStyle.dp
        color: uiStyle.pixel ? "#2B2932" : Qt.rgba(0.08, 0.08, 0.09, 0.94)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: uiStyle.pixel ? 0 : 1

        Row {
            id: tabs
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 12 * uiStyle.dp
            spacing: 6 * uiStyle.dp
            Repeater {
                model: [["scenes", Tr.t("Сцены")], ["stats", Tr.t("Статистика")], ["versions", Tr.t("Версии")], ["export", Tr.t("Экспорт")]]
                delegate: Rectangle {
                    required property var modelData
                    width: 98 * uiStyle.dp
                    height: 34 * uiStyle.dp
                    radius: 17 * uiStyle.dp
                    color: uiStyle.pixel ? (panel.tab === modelData[0] ? "#D0BCFF" : "#49454F") : panel.tab === modelData[0] ? "#ffffff" : Qt.rgba(1, 1, 1, 0.1)
                    Text {
                        anchors.centerIn: parent
                        text: modelData[1]
                        color: panel.tab === modelData[0] ? "#000000" : "#ffffff"
                        font.pixelSize: 14 * uiStyle.dp
                        font.bold: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: panel.tab = modelData[0] }
                }
            }
        }

        Item {
            anchors.top: tabs.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14 * uiStyle.dp

            // scenes
            ListView {
                anchors.fill: parent
                visible: panel.tab === "scenes"
                clip: true
                spacing: 4 * uiStyle.dp
                model: panel.scenes
                header: Text {
                    width: ListView.view.width
                    height: 34 * uiStyle.dp
                    visible: panel.runtime !== null
                    verticalAlignment: Text.AlignTop
                    text: panel.runtime ? "⏱ ≈ " + panel.minutes(panel.runtime.seconds) + Tr.t(" по страницам (") + panel.runtime.pages
                                          + Tr.t(" стр.)  ·  ≈ ") + panel.minutes(panel.speechSeconds) + Tr.t(" вслух") : ""
                    color: "#ffffff"
                    font.pixelSize: 14 * uiStyle.dp
                    font.weight: Font.DemiBold
                }
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 50 * uiStyle.dp
                    radius: 10 * uiStyle.dp
                    color: area.pressed ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        anchors.left: parent.left
                        anchors.right: count.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12 * uiStyle.dp
                        text: modelData.title
                        color: "#ffffff"
                        font.pixelSize: 15 * uiStyle.dp
                        elide: Text.ElideRight
                    }
                    Text {
                        id: count
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12 * uiStyle.dp
                        text: panel.minutes(modelData.seconds) + "  ·  " + modelData.words + Tr.t(" сл.")
                        color: "#9a9a9e"
                        font.pixelSize: 13 * uiStyle.dp
                    }
                    MouseArea { id: area; anchors.fill: parent; onClicked: panel.jumpTo(modelData.line) }
                }
                Text {
                    anchors.centerIn: parent
                    visible: panel.scenes.length === 0
                    text: Tr.t("Сцен пока нет.\nСцена начинается с «## ».")
                    horizontalAlignment: Text.AlignHCenter
                    color: "#9a9a9e"
                    font.pixelSize: 15 * uiStyle.dp
                }
            }

            // statistics
            Column {
                anchors.fill: parent
                visible: panel.tab === "stats" && panel.stats !== null
                spacing: 14 * uiStyle.dp
                readonly property var s: panel.stats || { words: 0, goal: 0, streak: 0, best: 0, total: 0, days: [] }

                Row {
                    spacing: 10 * uiStyle.dp
                    Repeater {
                        model: [
                            [String(parent.parent.s.words) + (parent.parent.s.goal > 0 ? " / " + parent.parent.s.goal : ""), Tr.t("слов сегодня")],
                            [(parent.parent.s.streak > 0 ? "🔥 " : "") + parent.parent.s.streak, Tr.t("дней подряд")],
                            [String(parent.parent.s.best), Tr.t("лучший день")],
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 128 * uiStyle.dp
                            height: 72 * uiStyle.dp
                            radius: 12 * uiStyle.dp
                            color: Qt.rgba(1, 1, 1, 0.06)
                            Column {
                                anchors.centerIn: parent
                                spacing: 2 * uiStyle.dp
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; color: "#ffffff"; font.pixelSize: 20; font.bold: true }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; color: "#9a9a9e"; font.pixelSize: 12 }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    readonly property int remaining: Math.max(0, parent.s.goal - parent.s.words)
                    text: parent.s.goal <= 0 ? "" : remaining > 0 ? Tr.t("До цели осталось ") + remaining + Tr.t(" слов") : Tr.t("Цель на сегодня выполнена ✓")
                    color: remaining > 0 ? "#d0d0d0" : "#30D158"
                    font.pixelSize: 15 * uiStyle.dp
                }

                Text { text: Tr.t("Последние две недели"); color: "#9a9a9e"; font.pixelSize: 13 }
                Item {
                    width: parent.width
                    height: 170 * uiStyle.dp
                    readonly property var days: parent.s.days
                    readonly property int peak: Math.max(parent.s.goal, ...days.map(d => d.words), 1)
                    // goal line
                    Rectangle {
                        visible: parent.parent.s.goal > 0
                        width: parent.width
                        height: 1
                        y: 150 * uiStyle.dp - 150 * uiStyle.dp * parent.parent.s.goal / parent.peak
                        color: Qt.rgba(48 / 255, 209 / 255, 88 / 255, 0.6)
                    }
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20 * uiStyle.dp
                        spacing: 6 * uiStyle.dp
                        Repeater {
                            model: parent.parent.days
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property var stat: parent.parent.parent.s
                                width: (parent.parent.width - 13 * uiStyle.dp * 6) / 14
                                height: Math.max(2 * uiStyle.dp, 150 * uiStyle.dp * modelData.words / parent.parent.peak)
                                anchors.bottom: parent.bottom
                                radius: 3 * uiStyle.dp
                                color: stat.goal > 0 && modelData.words >= stat.goal ? "#30D158" : index === 13 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.35)
                                Text {
                                    anchors.top: parent.bottom
                                    anchors.topMargin: 4 * uiStyle.dp
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.date.slice(8)
                                    color: "#7a7a7e"
                                    font.pixelSize: 10 * uiStyle.dp
                                }
                            }
                        }
                    }
                }
                Text { text: Tr.t("Всего написано: ") + parent.s.total + Tr.t(" слов"); color: "#9a9a9e"; font.pixelSize: 13 }
            }

            // versions
            ListView {
                anchors.fill: parent
                visible: panel.tab === "versions"
                clip: true
                spacing: 4 * uiStyle.dp
                model: panel.versions
                header: Text {
                    width: ListView.view.width
                    height: 34 * uiStyle.dp
                    text: Tr.t("Версия откроется копией рядом со сценарием")
                    color: "#9a9a9e"
                    font.pixelSize: 13 * uiStyle.dp
                }
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 50 * uiStyle.dp
                    radius: 10 * uiStyle.dp
                    color: varea.pressed ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12 * uiStyle.dp
                        text: modelData.date
                        color: "#ffffff"
                        font.pixelSize: 15 * uiStyle.dp
                        font.bold: true
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12 * uiStyle.dp
                        text: modelData.subject
                        color: "#9a9a9e"
                        font.pixelSize: 13 * uiStyle.dp
                    }
                    MouseArea { id: varea; anchors.fill: parent; onClicked: panel.openVersion(modelData) }
                }
                Text {
                    anchors.centerIn: parent
                    visible: panel.versions.length === 0
                    text: Tr.t("Версий пока нет.\nПервая сохранится через 5 минут.")
                    horizontalAlignment: Text.AlignHCenter
                    color: "#9a9a9e"
                    font.pixelSize: 15 * uiStyle.dp
                }
            }

            // export
            Column {
                anchors.fill: parent
                visible: panel.tab === "export"
                spacing: 10 * uiStyle.dp
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Tr.t("Рукопись в стандартном сценарном оформлении: Courier 12, A4, сцены, персонажи, ремарки и реплики с отступами. Файлы — в «Сценарии/Экспорт».")
                    color: "#9a9a9e"
                    font.pixelSize: 13 * uiStyle.dp
                }
                Repeater {
                    model: [["pdf", "PDF", Tr.t("для отправки и печати")], ["docx", "DOCX", Tr.t("для правок в Word")], ["epub", "EPUB", Tr.t("для чтения на читалке")]]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 56 * uiStyle.dp
                        radius: 12 * uiStyle.dp
                        color: earea.pressed ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14 * uiStyle.dp
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: "#ffffff"
                            font.pixelSize: 17 * uiStyle.dp
                            font.bold: true
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14 * uiStyle.dp
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[2]
                            color: "#9a9a9e"
                            font.pixelSize: 13 * uiStyle.dp
                        }
                        MouseArea { id: earea; anchors.fill: parent; onClicked: panel.exportAs(modelData[0]) }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: panel.exportResult
                    color: "#ffffff"
                    font.pixelSize: 13 * uiStyle.dp
                }
                Rectangle {
                    visible: panel.exportResult.indexOf("/") === 0
                    width: 180 * uiStyle.dp
                    height: 40 * uiStyle.dp
                    radius: 20 * uiStyle.dp
                    color: oarea.pressed ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.15)
                    Text { anchors.centerIn: parent; text: Tr.t("Открыть папку"); color: "#ffffff"; font.pixelSize: 14; font.bold: true }
                    MouseArea {
                        id: oarea
                        anchors.fill: parent
                        onClicked: {
                            shell.start(["xdg-open", panel.dir + (Tr.ru ? "/Экспорт" : "/Export")]);
                            panel.visible = false;
                        }
                    }
                }
            }
        }
    }
}

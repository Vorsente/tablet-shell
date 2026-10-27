// Screen time (iPadOS style): today's total, time per app, the last 7 days and words written
// in the typewriter. Data: ~/.local/share/screentime/YYYY-MM-DD.json (seconds per app, written by
// tabletshell from KWin's active window) and ~/.local/share/typewriter/words-YYYY-MM-DD.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Экранное время")

    LayerShell.Window.scope: "tabletshell-screentime"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    readonly property string home: shell.env("HOME")
    property var days: []        // [{ date, total, words }] oldest first, 7 entries
    property var apps: []        // today: [{ id, secs, name, icon }] longest first
    property int todayTotal: 0
    property int maxDay: 1

    function dayKey(offset) {
        const d = new Date();
        d.setDate(d.getDate() - offset);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function load(key) {
        try {
            return JSON.parse(shell.readFile(home + "/.local/share/screentime/" + key + ".json") || "{}");
        } catch (e) {
            return {};
        }
    }

    function formatTime(secs) {
        const h = Math.floor(secs / 3600), m = Math.round((secs % 3600) / 60);
        return h > 0 ? h + Tr.t(" ч ") + m + Tr.t(" мин") : m + Tr.t(" мин");
    }

    function refresh() {
        const list = [];
        for (let i = 6; i >= 0; --i) {
            const key = dayKey(i);
            const data = load(key);
            const total = Object.values(data).reduce((a, b) => a + b, 0);
            const words = parseInt(shell.readFile(home + "/.local/share/typewriter/words-" + key)) || 0;
            list.push({ date: key, total: total, words: words, weekday: new Date(key).toLocaleDateString(Tr.locale(), "ddd") });
        }
        days = list;
        maxDay = Math.max(60, ...list.map(d => d.total));
        const today = load(dayKey(0));
        todayTotal = list[6].total;
        const ids = Object.keys(today).sort((a, b) => today[b] - today[a]).slice(0, 8);
        let info = {};
        try {
            info = JSON.parse(shell.run([home + "/.local/bin/screentime-apps"].concat(ids)) || "{}");
        } catch (e) {}
        apps = ids.map(id => ({ id: id, secs: today[id], name: info[id] ? info[id].name : id,
                                icon: info[id] ? info[id].icon : id }));
    }

    function toggle() {
        if (visible) {
            dismiss();
            return;
        }
        refresh();
        visible = true;
    }
    // dims the whole screen and dissolves in / out (nothing grows or shrinks)
    property real shown: 0
    onVisibleChanged: if (visible) { fadeOut.stop(); fadeIn.restart(); }
    NumberAnimation { id: fadeIn; target: win; property: "shown"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: fadeOut
        NumberAnimation { target: win; property: "shown"; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }
    function dismiss() {
        if (visible && !fadeOut.running) {
            fadeOut.start();
        }
    }


    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea { anchors.fill: parent; onClicked: win.dismiss() }
        opacity: win.shown
    }

    Rectangle {
        opacity: win.shown
        anchors.centerIn: parent
        width: Math.min(parent.width - (Kirigami.Units.gridUnit * uiStyle.dp) * 2, (Kirigami.Units.gridUnit * uiStyle.dp) * 30)
        height: Math.min(parent.height - (Kirigami.Units.gridUnit * uiStyle.dp) * 2, content.implicitHeight + (Kirigami.Units.gridUnit * uiStyle.dp) * 2)
        radius: uiStyle.pixel ? (Kirigami.Units.gridUnit * uiStyle.dp) * 2.1 : (Kirigami.Units.gridUnit * uiStyle.dp) * 1.4
        color: uiStyle.pixel ? "#25232C" : Qt.rgba(0.12, 0.12, 0.15, 0.92)
        border.color: uiStyle.pixel ? "#625C69" : Qt.rgba(1, 1, 1, 0.16)
        border.width: uiStyle.pixel ? 0 : 1

        MouseArea { anchors.fill: parent }  // keep taps inside

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: (Kirigami.Units.gridUnit * uiStyle.dp)
            spacing: (Kirigami.Units.largeSpacing * uiStyle.dp)

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    spacing: 0
                    PC3.Label {
                        text: Tr.t("Экранное время · сегодня")
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                    PC3.Label {
                        text: win.formatTime(win.todayTotal)
                        color: "white"
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.2
                        font.weight: Font.DemiBold
                    }
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignTop
                    spacing: 0
                    PC3.Label {
                        Layout.alignment: Qt.AlignRight
                        text: Tr.t("Написано сегодня")
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                    PC3.Label {
                        Layout.alignment: Qt.AlignRight
                        text: (win.days.length ? win.days[6].words : 0) + Tr.t(" слов")
                        color: "white"
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Last 7 days: screen time bars with words under each day
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: (Kirigami.Units.gridUnit * uiStyle.dp) * 8
                spacing: (Kirigami.Units.smallSpacing * uiStyle.dp) * 2
                Repeater {
                    model: win.days
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        Item { Layout.fillHeight: true }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: (Kirigami.Units.gridUnit * uiStyle.dp) * 1.6
                            Layout.preferredHeight: Math.max(3, ((Kirigami.Units.gridUnit * uiStyle.dp) * 5) * modelData.total / win.maxDay)
                            radius: 4
                            color: index === 6 ? (uiStyle.pixel ? "#D0BCFF" : Kirigami.Theme.highlightColor) : Qt.rgba(1, 1, 1, 0.35)
                        }
                        PC3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.weekday
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                        PC3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.words > 0 ? modelData.words + Tr.t(" сл.") : " "
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(1, 1, 1, 0.12) }

            PC3.Label {
                text: Tr.t("Приложения сегодня")
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            PC3.Label {
                visible: win.apps.length === 0
                text: Tr.t("Пока нет данных")
                color: Qt.rgba(1, 1, 1, 0.5)
            }
            Repeater {
                model: win.apps
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: (Kirigami.Units.largeSpacing * uiStyle.dp)
                    Kirigami.Icon {
                        source: modelData.icon
                        implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
                        implicitHeight: implicitWidth
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            PC3.Label {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: "white"
                                elide: Text.ElideRight
                            }
                            PC3.Label {
                                text: win.formatTime(modelData.secs)
                                color: Qt.rgba(1, 1, 1, 0.7)
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: Math.max(4, parent.width * modelData.secs / Math.max(1, win.apps[0].secs))
                            implicitHeight: 4
                            radius: 2
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                }
            }
        }
    }
}

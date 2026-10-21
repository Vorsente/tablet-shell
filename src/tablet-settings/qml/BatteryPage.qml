// Battery section: charge level over the last day / week (UPower history), what the battery
// does right now (draw in W, time to empty / full), its wear (capacity left of the design
// capacity, charge cycles) and the apps the screen was on today (screen time; Linux cannot
// measure energy per app without root tools, so time on screen is the honest proxy).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

ColumnLayout {
    id: root
    property bool touch: false
    property int span: 86400          // seconds shown in the chart
    property var history: []          // [[time, percent, state], ...] oldest first
    property var info: ({})
    property var screentime: null

    readonly property string device: "/org/freedesktop/UPower/devices/battery_" + (backend.run(["sh", "-c", "for d in /sys/class/power_supply/*; do [ \"$(cat $d/type)\" = Battery ] && basename $d && break; done"]).trim() || "BAT0")

    function load() {
        try {
            const h = JSON.parse(backend.run(["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower", device,
                                              "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", String(span), "200"]));
            // state 0 = unknown: UPower's markers between sessions, not real readings
            history = h.data[0].filter(p => p[2] !== 0 && p[1] > 0).reverse();
        } catch (e) {
            history = [];
        }
        const props = {};
        backend.run(["upower", "-i", device]).split("\n").forEach(l => {
            const m = l.match(/^\s+([a-z -]+):\s+(.*)$/);
            if (m) {
                props[m[1].trim()] = m[2].trim();
            }
        });
        info = props;
        try {
            screentime = JSON.parse(backend.run([backend.home() + "/.local/bin/tablet-tools", "dashboard", "--local"])).screentime;
        } catch (e) {
            screentime = null;
        }
        chart.requestPaint();
    }
    Component.onCompleted: load()
    onSpanChanged: load()
    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.load()
    }

    Kirigami.Heading {
        level: 3
        text: Tr.t("Уровень заряда")
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC2.Button {
            text: Tr.t("24 часа")
            checkable: true
            checked: root.span === 86400
            onClicked: root.span = 86400
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.4 }
        }
        QQC2.Button {
            text: Tr.t("7 дней")
            checkable: true
            checked: root.span === 604800
            onClicked: root.span = 604800
            Binding on implicitHeight { when: root.touch; value: Kirigami.Units.gridUnit * 2.4 }
        }
    }

    Canvas {
        id: chart
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 10
        readonly property color line: Kirigami.Theme.highlightColor
        readonly property color text: Kirigami.Theme.textColor
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const left = Kirigami.Units.gridUnit * 2.2, bottom = height - Kirigami.Units.gridUnit * 1.4;
            const w = width - left, h = bottom;
            const now = Date.now() / 1000, start = now - root.span;
            ctx.font = Math.round(Kirigami.Units.gridUnit * 0.7) + "px sans-serif";
            ctx.fillStyle = Qt.rgba(text.r, text.g, text.b, 0.55);
            ctx.strokeStyle = Qt.rgba(text.r, text.g, text.b, 0.12);
            ctx.lineWidth = 1;
            for (const p of [0, 50, 100]) {
                const y = h - h * p / 100 + 0.5;
                ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width, y); ctx.stroke();
                ctx.fillText(p + "%", 0, Math.min(Math.max(y + 4, 10), h));
            }
            // time labels: hours for a day, weekdays for a week
            const days = [Tr.t("вс"), Tr.t("пн"), Tr.t("вт"), Tr.t("ср"), Tr.t("чт"), Tr.t("пт"), Tr.t("сб")];
            for (let i = 0; i <= 4; ++i) {
                const t = start + root.span * i / 4;
                const d = new Date(t * 1000);
                const label = root.span <= 86400 ? Qt.formatTime(d, "HH:mm") : days[d.getDay()] + " " + d.getDate();
                ctx.fillText(label, left + w * i / 4 - (i === 4 ? 40 : i === 0 ? 0 : 18), height - 4);
            }
            const pts = root.history.filter(p => p[0] >= start);
            if (pts.length < 2) {
                return;
            }
            const x = t => left + w * (t - start) / root.span;
            const y = v => h - h * v / 100;
            // filled area, green while charging
            for (let i = 1; i < pts.length; ++i) {
                const a = pts[i - 1], b = pts[i];
                if (b[0] - a[0] > Math.max(3600, root.span / 40)) {
                    continue;              // a gap (switched off / asleep): no line across it
                }
                const charging = b[2] === 1 || b[2] === 4;
                const c = charging ? Qt.rgba(0.19, 0.82, 0.35, 1) : line;
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.25);
                ctx.beginPath();
                ctx.moveTo(x(a[0]), h); ctx.lineTo(x(a[0]), y(a[1])); ctx.lineTo(x(b[0]), y(b[1])); ctx.lineTo(x(b[0]), h);
                ctx.closePath();
                ctx.fill();
                ctx.strokeStyle = c;
                ctx.lineWidth = 2;
                ctx.beginPath(); ctx.moveTo(x(a[0]), y(a[1])); ctx.lineTo(x(b[0]), y(b[1])); ctx.stroke();
            }
        }
    }

    // now
    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        columns: 2
        columnSpacing: Kirigami.Units.gridUnit
        rowSpacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: Tr.t("Сейчас"); opacity: 0.7 }
        QQC2.Label {
            Layout.fillWidth: true
            text: (root.info["percentage"] || "—") + ", "
                  + ({ "charging": Tr.t("заряжается"), "discharging": Tr.t("от батареи"), "fully-charged": Tr.t("заряжена"),
                       "pending-charge": Tr.t("ждёт зарядки") }[root.info["state"]] || root.info["state"] || "")
        }
        QQC2.Label { text: Tr.t("Расход"); opacity: 0.7 }
        QQC2.Label { text: root.info["energy-rate"] ? root.info["energy-rate"].replace(" W", Tr.t(" Вт")) : "—" }
        QQC2.Label {
            text: root.info["time to full"] ? Tr.t("До полной") : Tr.t("Хватит ещё")
            opacity: 0.7
        }
        QQC2.Label {
            readonly property string raw: root.info["time to full"] || root.info["time to empty"] || "—"
            // upower answers in English
            text: Tr.ru ? raw.replace("hours", "ч").replace("hour", "ч").replace("minutes", "мин").replace("minute", "мин") : raw
        }
        QQC2.Label { text: Tr.t("Ёмкость"); opacity: 0.7 }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            readonly property real remaining: parseFloat(root.info["capacity"] || "0")
            text: root.info["energy-full"]
                  ? Math.round(remaining) + Tr.t("% от новой (") + root.info["energy-full"].replace(" Wh", "") + Tr.t(" из ")
                    + root.info["energy-full-design"].replace(" Wh", "") + Tr.t(" Вт·ч)") + (remaining < 60 ? Tr.t(" — пора менять") : "")
                  : "—"
            color: remaining > 0 && remaining < 60 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
        }
        QQC2.Label { text: Tr.t("Циклы зарядки"); opacity: 0.7 }
        QQC2.Label { text: root.info["charge-cycles"] || "—" }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.WordWrap
        opacity: 0.6
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        // charge_control_end_threshold: KDE's own power settings can set it
        readonly property bool threshold: /"chargeThreshold":true/.test(backend.run([backend.home() + "/.local/bin/tablet-tools", "hardware"]))
        text: threshold ? Tr.t("Ограничение зарядки (например, до 80%) задаётся в Настройках KDE → Управление питанием.")
                        : Tr.t("Ограничить зарядку до 80% на этом планшете нельзя: контроллер батареи не даёт такой настройки.")
    }

    Kirigami.Heading {
        level: 3
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: Tr.t("Экран сегодня")
        visible: !!root.screentime && root.screentime.top.length > 0
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.6
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        visible: !!root.screentime && root.screentime.top.length > 0
        text: Tr.t("Больше всего батареи уходит на экран: вот где он был включён дольше всего.")
    }
    Repeater {
        model: root.screentime ? root.screentime.top.slice(0, 5) : []
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: modelData.icon
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }
            QQC2.Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
            QQC2.Label {
                readonly property int s: modelData.seconds
                text: s >= 3600 ? Math.floor(s / 3600) + Tr.t(" ч ") + Math.floor(s % 3600 / 60) + Tr.t(" мин") : Math.max(1, Math.floor(s / 60)) + Tr.t(" мин")
                opacity: 0.7
            }
        }
    }
}

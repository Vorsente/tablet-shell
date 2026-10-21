// One iPadOS-like widget card: clock, weather, calendar, battery, typewriter, screen time,
// YouTube, Linux news, Russia news, exchange rates, Claude limits, on this day, sky, week report.
// "small" fills 2x2 home grid cells, "wide" 4x2. Data comes from home.homeData (HomeData.qml).
// Tapping does what the widget is about (typewriter opens the typewriter, screen time its
// window); the home grid's WidgetTile handles editing.
import QtQuick
import QtQuick.Layouts
import "Tr.js" as Tr

Rectangle {
    id: card

    required property var home
    required property string kind
    property bool wide: false
    readonly property var d: home.homeData
    readonly property real u: Math.min(width / (wide ? 2 : 1), height) / 12   // text unit

    radius: Math.min(width, height) * 0.13
    color: home.pal.card
    border.color: home.pal.cardBorder
    border.width: 1
    clip: true

    readonly property color text: home.pal.text
    readonly property color secondary: home.pal.secondary
    readonly property color green: home.pal.green
    readonly property color red: home.pal.red
    readonly property color orange: home.pal.orange
    readonly property color blue: home.pal.blue
    readonly property var ru: Tr.locale()

    function activate() {
        if (kind === "typewriter") {
            home.runCommand([home.homeDir + "/.local/bin/typewriter"]);
        } else if (kind === "screentime" || kind === "weekly") {
            home.runCommand(["qdbus6", "org.ipad.TabletShell", "/", "org.ipad.TabletShell.ToggleScreenTime"]);
        } else if (kind === "weather") {
            Qt.openUrlExternally("https://yandex.ru/pogoda/");
        } else if (kind === "battery") {
            home.runCommand([home.homeDir + "/.local/bin/tablet-settings", "section:Батарея"]);
        } else if (kind === "youtube") {
            Qt.openUrlExternally("https://studio.youtube.com/");
        } else if (kind === "claude") {
            Qt.openUrlExternally("https://claude.ai/settings/usage");
        } else if (kind === "linux" || kind === "russia") {
            const list = kind === "linux" ? d.linuxNews : d.russiaNews;
            if (list.length > 0) {
                Qt.openUrlExternally(list[0].link);
            }
        } else if (kind === "onthisday" && d.onThisDay.length > 0) {
            Qt.openUrlExternally(d.onThisDay[0].link);
        }
    }

    // ---- shared pieces ----
    component Caption: Text {
        color: card.secondary
        font.pixelSize: card.u * 1.05
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    component Big: Text {
        color: card.text
        font.pixelSize: card.u * 3.4
        font.weight: Font.Light
    }
    component Ring: Canvas {
        property real value: 0
        property color tint: card.green
        property real thickness: width * 0.11
        onValueChanged: requestPaint()
        onTintChanged: requestPaint()
        readonly property color track: card.home.pal.fill
        onTrackChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = width / 2 - thickness / 2;
            ctx.lineWidth = thickness;
            ctx.lineCap = "round";
            ctx.strokeStyle = track;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2);
            ctx.stroke();
            ctx.strokeStyle = tint;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.001, Math.min(1, value)));
            ctx.stroke();
        }
    }

    Loader {
        anchors.fill: parent
        anchors.margins: card.u * 1.3
        sourceComponent: ({
            clock: clockView, weather: weatherView, calendar: calendarView,
            battery: batteryView, typewriter: typewriterView, screentime: screentimeView,
            youtube: youtubeView, linux: newsView, russia: newsView, rates: ratesView,
            claude: claudeView, onthisday: onThisDayView, sky: skyView, weekly: weeklyView,
        })[card.kind] || null
    }

    // ---- clock ----
    Component {
        id: clockView
        ColumnLayout {
            spacing: 0
            Caption { text: card.d.now.toLocaleDateString(card.ru, "dddd"); color: card.red; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
            Text {
                text: Qt.formatTime(card.d.now, "HH:mm")
                color: card.text
                font.pixelSize: card.u * (card.wide ? 5.6 : 3.5)
                font.weight: Font.Light
            }
            Caption { text: card.d.now.toLocaleDateString(card.ru, "d MMMM yyyy") }
        }
    }

    // ---- weather ----
    Component {
        id: weatherView
        Item {
            readonly property var w: card.d.weather
            readonly property var info: w && w.code !== undefined ? card.d.weatherInfo(w.code, w.day) : ["…", ""]
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Caption { text: w ? (w.place || w.city) + " ➤" : Tr.t("Погода"); color: card.text; Layout.fillWidth: true }
                Big { text: w && w.temp !== undefined ? Math.round(w.temp) + "°" : "—" }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: card.u * 0.4
                    Text { text: info[0]; font.pixelSize: card.u * 1.5 }
                    Caption { text: w && w.error ? w.error : info[1]; color: card.text; Layout.fillWidth: true }
                }
                Caption {
                    visible: !!w && w.max !== undefined
                    text: w ? "↑" + Math.round(w.max) + "°  ↓" + Math.round(w.min) + "°" : ""
                    Layout.fillWidth: true
                }
            }
            ColumnLayout {
                visible: card.wide && !!w && w.feels !== undefined
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: card.u * 0.4
                Caption { Layout.alignment: Qt.AlignRight; text: w ? Tr.t("Ощущается как ") + Math.round(w.feels) + "°" : "" }
                Caption { Layout.alignment: Qt.AlignRight; text: w ? Tr.t("Ветер ") + Math.round(w.wind) + Tr.t(" км/ч") : "" }
            }
        }
    }

    // ---- calendar ----
    Component {
        id: calendarView
        RowLayout {
            spacing: card.u * 1.5
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: card.wide ? card.u * 8 : -1
                Layout.fillWidth: !card.wide
                spacing: 0
                Caption { text: card.d.now.toLocaleDateString(card.ru, "dddd").toUpperCase(); color: card.red }
                Text {
                    text: card.d.now.getDate()
                    color: card.text
                    font.pixelSize: card.u * 5
                    font.weight: Font.Light
                }
                Item { Layout.fillHeight: true }
                Caption { text: card.ru.standaloneMonthName(card.d.now.getMonth()) + " " + card.d.now.getFullYear() }
            }
            // month grid
            Grid {
                visible: card.wide
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                columns: 7
                columnSpacing: 0
                // 7 day columns in what is left of the card next to the big date
                readonly property real cell: (card.width - card.u * 2.6 - card.u * 8 - card.u * 1.5) / 7
                rowSpacing: card.u * 0.1
                readonly property date first: new Date(card.d.now.getFullYear(), card.d.now.getMonth(), 1)
                readonly property int lead: (first.getDay() + 6) % 7       // Monday first
                readonly property int days: new Date(card.d.now.getFullYear(), card.d.now.getMonth() + 1, 0).getDate()
                Repeater {
                    model: Tr.ru ? ["П", "В", "С", "Ч", "П", "С", "В"] : ["M", "T", "W", "T", "F", "S", "S"]
                    delegate: Text {
                        required property string modelData
                        required property int index
                        width: parent.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: index >= 5 ? card.secondary : card.text
                        font.pixelSize: card.u * 0.95
                        font.weight: Font.DemiBold
                    }
                }
                Repeater {
                    model: parent.lead + parent.days
                    delegate: Item {
                        required property int index
                        readonly property int day: index - parent.lead + 1
                        width: parent.cell
                        height: card.u * 1.75
                        Rectangle {
                            anchors.centerIn: parent
                            width: card.u * 1.7
                            height: width
                            radius: width / 2
                            color: card.red
                            visible: parent.day === card.d.now.getDate()
                        }
                        Text {
                            anchors.centerIn: parent
                            text: parent.day > 0 ? parent.day : ""
                            color: parent.day === card.d.now.getDate() ? "white" : card.text
                            font.pixelSize: card.u * 0.95
                        }
                    }
                }
            }
        }
    }

    // ---- battery ----
    Component {
        id: batteryView
        RowLayout {
            spacing: card.u * 1.5
            Item {
                Layout.preferredWidth: card.wide ? parent.height : parent.width
                Layout.fillHeight: true
                Ring {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.9
                    height: width
                    value: card.d.battery / 100
                    tint: card.d.battery <= 20 ? card.red : card.green
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (card.d.charging ? "⚡" : "") + (card.d.battery >= 0 ? card.d.battery + "%" : "—")
                        color: card.text
                        font.pixelSize: card.u * 2.2
                        font.weight: Font.DemiBold
                    }
                    Caption { anchors.horizontalCenter: parent.horizontalCenter; text: card.d.model }
                }
            }
            ColumnLayout {
                visible: card.wide
                Layout.fillWidth: true
                spacing: card.u * 0.6
                Caption { text: card.d.charging ? Tr.t("Заряжается") : Tr.t("От батареи"); color: card.text }
                Caption {
                    visible: !!card.d.disk
                    text: card.d.disk ? Tr.t("Свободно на диске: ") + Math.round(card.d.disk.free / 1e9) + Tr.t(" ГБ") : ""
                    Layout.fillWidth: true
                }
            }
        }
    }

    // ---- typewriter ----
    Component {
        id: typewriterView
        RowLayout {
            readonly property var t: card.d.typewriter || { words: 0, goal: 0, streak: 0, days: [] }
            spacing: card.u * 1.5
            Item {
                Layout.preferredWidth: card.wide ? parent.height : parent.width
                Layout.fillHeight: true
                Ring {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.9
                    height: width
                    value: t.goal > 0 ? t.words / t.goal : 0
                    tint: t.goal > 0 && t.words >= t.goal ? card.green : card.orange
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: t.words
                        color: card.text
                        font.pixelSize: card.u * 2.4
                        font.weight: Font.DemiBold
                    }
                    Caption { anchors.horizontalCenter: parent.horizontalCenter; text: t.goal > 0 ? Tr.t("из ") + t.goal : Tr.t("слов") }
                    Caption {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: t.streak > 0
                        text: "🔥 " + t.streak
                        color: card.text
                    }
                }
            }
            // the last 14 days
            ColumnLayout {
                visible: card.wide
                Layout.fillWidth: true
                Layout.fillHeight: true
                Caption { text: Tr.t("Печатная машинка"); color: card.text }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property int peak: Math.max(t.goal, ...(t.days || []).map(x => x.words), 1)
                    Row {
                        anchors.bottom: parent.bottom
                        spacing: card.u * 0.25
                        Repeater {
                            model: t.days || []
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: (parent.parent.width - 13 * card.u * 0.25) / 14
                                height: Math.max(card.u * 0.2, parent.parent.height * modelData.words / parent.parent.peak)
                                anchors.bottom: parent.bottom
                                radius: card.u * 0.2
                                color: t.goal > 0 && modelData.words >= t.goal ? card.green : index === 13 ? card.text : card.home.pal.tertiary
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- screen time ----
    Component {
        id: screentimeView
        ColumnLayout {
            readonly property var s: card.d.screentime || { total: 0, top: [] }
            spacing: card.u * 0.4
            Caption { text: Tr.t("Экранное время"); color: card.text; Layout.fillWidth: true }
            Text {
                text: card.d.duration(s.total || 0)
                color: card.text
                font.pixelSize: card.u * 2.6
                font.weight: Font.Light
            }
            Item { Layout.fillHeight: true }
            Repeater {
                model: (s.top || []).slice(0, card.wide ? 3 : 2)
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: card.u * 0.15
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: modelData.name; Layout.fillWidth: true }
                        Caption { text: card.d.duration(modelData.seconds) }
                    }
                    Rectangle {
                        Layout.preferredWidth: Math.max(card.u * 0.4, parent.width * modelData.seconds / Math.max(1, s.top[0].seconds))
                        Layout.preferredHeight: card.u * 0.45
                        radius: height / 2
                        color: [card.blue, card.home.pal.cyan, card.orange][index]
                    }
                }
            }
        }
    }

    // ---- week report: this week against the one before ----
    Component {
        id: weeklyView
        ColumnLayout {
            id: week
            readonly property var w: card.d.weekly
            spacing: card.u * 0.5

            // "+12%" / "−5%" against the week before (nothing when there was nothing before)
            function delta(now, before) {
                if (!before) {
                    return "";
                }
                const p = Math.round((now - before) / before * 100);
                return (p > 0 ? "+" : p < 0 ? "−" : "±") + Math.abs(p) + "%";
            }
            function range() {
                if (!w) {
                    return "";
                }
                const a = new Date(w.from + "T12:00"), b = new Date(w.to + "T12:00");
                return a.getMonth() === b.getMonth()
                    ? a.getDate() + "–" + b.toLocaleDateString(card.ru, "d MMMM")
                    : a.toLocaleDateString(card.ru, "d MMM") + " – " + b.toLocaleDateString(card.ru, "d MMM");
            }

            component Row7: RowLayout {
                id: row
                property string title
                property string value
                property string change
                property bool goodWhenUp: true
                property bool up: change.startsWith("+")
                property var days: []
                property color tint
                Layout.fillWidth: true
                spacing: card.u * 0.8
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    Caption { text: row.title; font.pixelSize: card.u * 0.85; Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: card.u * 0.5
                        Text {
                            text: row.value
                            color: card.text
                            font.pixelSize: card.u * 1.45
                            font.weight: Font.Light
                            elide: Text.ElideRight
                            Layout.maximumWidth: row.width - bars.width - card.u * 3.5
                        }
                        Text {
                            visible: row.change !== ""
                            text: row.change
                            color: row.change.startsWith("±") ? card.secondary
                                 : row.up === row.goodWhenUp ? card.green : card.orange
                            font.pixelSize: card.u * 0.8
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
                // the 7 days, today last
                Row {
                    id: bars
                    Layout.alignment: Qt.AlignBottom
                    Layout.preferredWidth: card.u * 6.8
                    Layout.preferredHeight: card.u * 2.2
                    spacing: card.u * 0.3
                    Repeater {
                        model: row.days
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property real peak: Math.max(1, Math.max.apply(null, row.days))
                            anchors.bottom: parent.bottom
                            width: card.u * 0.7
                            height: Math.max(card.u * 0.3, card.u * 2.2 * modelData / peak)
                            radius: card.u * 0.2
                            color: row.tint
                            opacity: index === 6 ? 1 : 0.55
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Caption { text: Tr.t("Итоги недели"); color: card.text; Layout.fillWidth: true }
                Caption { text: week.range(); font.pixelSize: card.u * 0.85 }
            }
            Item { Layout.fillHeight: true }
            Row7 {
                title: Tr.t("Экранное время")
                value: week.w ? card.d.duration(week.w.screen.total) : "—"
                change: week.w ? week.delta(week.w.screen.total, week.w.screen.before) : ""
                goodWhenUp: false
                days: week.w ? week.w.screen.days : []
                tint: card.blue
            }
            Row7 {
                title: Tr.t("Печатная машинка")
                value: week.w ? week.w.words.total.toLocaleString(card.ru, "f", 0) + Tr.t(" слов") : "—"
                change: week.w ? week.delta(week.w.words.total, week.w.words.before) : ""
                days: week.w ? week.w.words.days : []
                tint: card.orange
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                readonly property var b: week.w ? week.w.battery : null
                Caption { text: Tr.t("Батарея · ёмкость"); font.pixelSize: card.u * 0.85; Layout.fillWidth: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: card.u * 0.5
                    Text {
                        text: parent.parent.b ? parent.parent.b.health.toLocaleString(card.ru, "f", 1) + "%" : "—"
                        color: card.text
                        font.pixelSize: card.u * 1.45
                        font.weight: Font.Light
                    }
                    Caption {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBaseline
                        font.pixelSize: card.u * 0.8
                        readonly property var b: parent.parent.b
                        text: !b ? "" : b.healthBefore === undefined ? b.cycles + Tr.t(" циклов · сравнение через неделю")
                            : (b.health - b.healthBefore >= 0 ? "+" : "−") + Math.abs(b.health - b.healthBefore).toLocaleString(card.ru, "f", 1)
                              + Tr.t("% за неделю · +") + (b.cycles - b.cyclesBefore) + Tr.t(" циклов")
                    }
                }
            }
            Item { Layout.fillHeight: true }
            Caption {
                font.pixelSize: card.u * 0.8
                Layout.fillWidth: true
                text: week.w && week.w.screen.top.length > 0
                      ? Tr.t("Больше всего: ") + week.w.screen.top.map(a => a.name + " " + card.d.duration(a.seconds)).join(" · ")
                      : ""
            }
        }
    }

    // ---- YouTube ----
    Component {
        id: youtubeView
        ColumnLayout {
            readonly property var yt: card.d.youtube
            spacing: card.u * 0.3
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    Layout.preferredWidth: card.u * 2.2
                    Layout.preferredHeight: card.u * 1.55
                    radius: card.u * 0.4
                    color: "#FF0033"
                    Text { anchors.centerIn: parent; text: "▶"; color: "white"; font.pixelSize: card.u * 0.9 }
                }
                Caption { text: yt && yt.title ? yt.title : "YouTube"; color: card.text; Layout.fillWidth: true }
            }
            Item { Layout.fillHeight: true }
            Text {
                text: yt && yt.subscribers !== undefined ? card.d.bigNumber(yt.subscribers) : "—"
                color: card.text
                font.pixelSize: card.u * (card.wide ? 3.6 : 2.9)
                font.weight: Font.DemiBold
            }
            Caption { text: yt && yt.error && yt.subscribers === undefined ? Tr.t("нужно подключить в «Сводке»") : Tr.t("подписчиков") }
            RowLayout {
                visible: !!yt && yt.last28 !== undefined
                spacing: card.u
                Caption {
                    text: yt ? (yt.last28 >= 0 ? "+" : "") + card.d.bigNumber(yt.last28) + Tr.t(" за 28 дней") : ""
                    color: yt && yt.last28 >= 0 ? card.green : card.red
                }
                Caption {
                    visible: card.wide && !!yt && yt.views !== undefined
                    text: yt ? card.d.bigNumber(yt.views) + Tr.t(" просмотров") : ""
                }
            }
        }
    }

    // ---- news (Linux or Russia): newest headlines, tap one to read it ----
    Component {
        id: newsView
        ColumnLayout {
            readonly property var items: card.kind === "linux" ? card.d.linuxNews : card.d.russiaNews
            readonly property real lineHeight: card.u * (card.wide ? 3.0 : 3.6)
            spacing: card.u * 0.3
            RowLayout {
                Layout.fillWidth: true
                Text { text: card.kind === "linux" ? "🐧" : "🇷🇺"; font.pixelSize: card.u * 1.3 }
                Caption {
                    text: card.kind === "linux" ? Tr.t("Новости Linux") : Tr.t("Новости России")
                    color: card.kind === "linux" ? card.home.pal.yellow : card.home.pal.cyan
                    Layout.fillWidth: true
                }
            }
            Repeater {
                model: items.slice(0, Math.max(1, Math.floor((card.height - card.u * 5) / lineHeight)))
                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: lineHeight
                    Column {
                        anchors.fill: parent
                        spacing: card.u * 0.1
                        Text {
                            width: parent.width
                            text: modelData.title
                            color: card.text
                            font.pixelSize: card.u * 0.95
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.source + " · " + card.d.ago(modelData.time)
                            color: card.secondary
                            font.pixelSize: card.u * 0.75
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally(modelData.link) }
                }
            }
            Item { Layout.fillHeight: true }
            Caption { visible: items.length === 0; text: Tr.t("Загружаю…") }
        }
    }

    // ---- exchange rates (Bank of Russia) ----
    Component {
        id: ratesView
        ColumnLayout {
            readonly property var r: card.d.rates
            spacing: card.u * 0.4
            Caption { text: Tr.t("Курс ЦБ"); color: card.text }
            Item { Layout.fillHeight: true }
            Repeater {
                model: [["USD", "$"], ["EUR", "€"], ["CNY", "¥"]]
                delegate: RowLayout {
                    required property var modelData
                    readonly property var v: r ? r[modelData[0]] : null
                    readonly property real change: v ? v.value - v.previous : 0
                    Layout.fillWidth: true
                    Text { text: modelData[1]; color: card.secondary; font.pixelSize: card.u * 1.5; Layout.preferredWidth: card.u * 1.6 }
                    Text {
                        text: v ? v.value.toFixed(2) + " ₽" : "—"
                        color: card.text
                        font.pixelSize: card.u * 1.6
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: !!v
                        text: (change >= 0 ? "▲ " : "▼ ") + Math.abs(change).toFixed(2)
                        color: change >= 0 ? card.green : card.red
                        font.pixelSize: card.u * 0.9
                    }
                }
            }
        }
    }

    // ---- Claude limits ----
    Component {
        id: claudeView
        ColumnLayout {
            readonly property var c: card.d.claude
            spacing: card.u * 0.5
            RowLayout {
                Text { text: "✳"; color: "#D97757"; font.pixelSize: card.u * 1.4 }
                Caption { text: "Claude" + (c && c.plan ? " · " + c.plan : ""); color: card.text; Layout.fillWidth: true }
            }
            Item { Layout.fillHeight: true }
            Repeater {
                model: [["session", Tr.t("5 часов")], ["weekly", Tr.t("Неделя")]]
                delegate: ColumnLayout {
                    required property var modelData
                    readonly property var l: c ? c[modelData[0]] : null
                    readonly property int pct: l ? Math.round(l.percent) : 0
                    Layout.fillWidth: true
                    spacing: card.u * 0.2
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: modelData[1]; Layout.fillWidth: true }
                        Caption {
                            text: l ? pct + "%" + (l.resetsAt ? Tr.t(" · до ") + Qt.formatTime(new Date(l.resetsAt), "HH:mm") : "") : "—"
                            color: card.text
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: card.u * 0.5
                        radius: height / 2
                        color: card.home.pal.fill
                        Rectangle {
                            width: parent.width * Math.min(1, pct / 100)
                            height: parent.height
                            radius: height / 2
                            color: pct >= 90 ? card.red : pct >= 70 ? card.orange : "#D97757"
                        }
                    }
                }
            }
        }
    }

    // ---- on this day (Russian Wikipedia) ----
    Component {
        id: onThisDayView
        ColumnLayout {
            spacing: card.u * 0.4
            Caption { text: Tr.t("В этот день · ") + card.d.now.toLocaleDateString(card.ru, "d MMMM"); color: card.home.pal.purple; Layout.fillWidth: true }
            Repeater {
                model: card.d.onThisDay.slice(0, card.wide && card.height > card.width * 0.6 ? 4 : card.wide ? 2 : 1)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: card.u * 0.6
                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: modelData.year
                        color: card.text
                        font.pixelSize: card.u * 1.1
                        font.weight: Font.Bold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.text
                        color: card.text
                        font.pixelSize: card.u * 0.9
                        wrapMode: Text.WordWrap
                        maximumLineCount: card.wide ? 3 : 5
                        elide: Text.ElideRight
                        MouseArea { anchors.fill: parent; onClicked: if (modelData.link) Qt.openUrlExternally(modelData.link) }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- sky: sunrise, sunset, day length, the moon ----
    Component {
        id: skyView
        RowLayout {
            spacing: card.u * 1.2
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: card.u * 0.3
                Caption { text: Tr.t("Небо"); color: card.text }
                Item { Layout.fillHeight: true }
                Text {
                    text: "🌅 " + (card.d.sun.rise ? Qt.formatTime(card.d.sun.rise, "HH:mm") : "—")
                    color: card.text
                    font.pixelSize: card.u * 1.5
                }
                Text {
                    text: "🌇 " + (card.d.sun.set ? Qt.formatTime(card.d.sun.set, "HH:mm") : "—")
                    color: card.text
                    font.pixelSize: card.u * 1.5
                }
                Caption { text: Tr.t("День ") + card.d.duration(card.d.sun.length) }
            }
            ColumnLayout {
                visible: card.wide
                Layout.fillHeight: true
                spacing: 0
                Text { Layout.alignment: Qt.AlignHCenter; text: card.d.moon.icon; font.pixelSize: card.u * 4.2 }
                Caption { Layout.alignment: Qt.AlignHCenter; text: card.d.moon.name; color: card.text }
                Caption { Layout.alignment: Qt.AlignHCenter; text: Tr.t("освещена на ") + card.d.moon.light + "%" }
            }
        }
    }
}

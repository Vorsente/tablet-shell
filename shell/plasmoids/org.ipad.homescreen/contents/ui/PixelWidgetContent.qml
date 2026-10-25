// Material You widgets (Pixel): each kind in its own tonal container (home.tone(kind), drawn by
// HomeWidget), a themed icon in a filled circle and a title on top, then content laid out the
// Material way: big Roboto numbers, pill chips, thick rounded progress bars, list rows.
// Not the iPad cards recoloured: the layouts are different, the data the same (HomeData).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: material
    required property var home
    required property var d
    required property string kind
    property bool wide: false

    readonly property var tone: home.tone(kind)
    readonly property color on: tone.on
    readonly property color accent: tone.accent
    readonly property color muted: Qt.rgba(on.r, on.g, on.b, 0.72)
    readonly property color track: Qt.rgba(on.r, on.g, on.b, 0.16)
    readonly property string family: home.fontFamily
    // text unit: the card's height decides, a narrow card limits it
    readonly property real u: Math.max(8, Math.min(height / 11, width / (wide ? 19 : 12)))
    readonly property var ru: Tr.locale()

    readonly property var titles: ({
        clock: Tr.t("Часы"), weather: Tr.t("Погода"), calendar: Tr.t("Календарь"), battery: Tr.t("Батарея"),
        typewriter: Tr.t("Печатная машинка"), screentime: Tr.t("Экранное время"), youtube: "YouTube",
        linux: Tr.t("Новости Linux"), russia: Tr.t("Новости России"), rates: Tr.t("Курс ЦБ"),
        claude: "Claude", onthisday: Tr.t("В этот день"), sky: Tr.t("Небо"), weekly: Tr.t("Итоги недели"),
    })
    readonly property var icons: ({
        clock: "clock-symbolic", calendar: "view-calendar-day-symbolic", typewriter: "document-edit-symbolic",
        screentime: "chronometer-symbolic", youtube: "media-playback-start-symbolic", linux: "news-subscribe-symbolic",
        russia: "globe-symbolic", rates: "wallet-open-symbolic", claude: "dialog-messages-symbolic",
        onthisday: "view-history-symbolic", sky: "weather-clear-night-symbolic", weekly: "office-chart-bar-symbolic",
    })
    function headerIcon() {
        if (kind === "weather") {
            const w = d.weather;
            return w && w.code !== undefined ? d.weatherIcon(w.code, w.day) : "weather-few-clouds-symbolic";
        }
        if (kind === "battery") {
            const b = d.battery;
            return d.charging ? "battery-full-charging-symbolic"
                 : b < 0 ? "battery-missing-symbolic" : b <= 20 ? "battery-low-symbolic" : b <= 60 ? "battery-good-symbolic" : "battery-full-symbolic";
        }
        return icons[kind] || "view-list-details-symbolic";
    }

    // ---- shared pieces ----
    component Label: Text {
        color: material.on
        font.family: material.family
        font.pixelSize: material.u * 1.0
        elide: Text.ElideRight
    }
    component Muted: Label {
        color: material.muted
        font.pixelSize: material.u * 0.9
    }
    component Display: Label {
        font.pixelSize: material.u * 3.6
        font.weight: Font.Normal
        elide: Text.ElideNone
    }
    // thick rounded bar (Material 3 linear progress)
    component Progress: Rectangle {
        property real value: 0
        property color tint: material.accent
        implicitHeight: material.u * 0.7
        radius: height / 2
        color: material.track
        Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, parent.value)))
            height: parent.height
            radius: height / 2
            color: parent.tint
            visible: parent.value > 0
        }
    }
    component Chip: Rectangle {
        property string label: ""
        property string icon: ""
        implicitHeight: material.u * 2.1
        implicitWidth: chipRow.implicitWidth + material.u * 1.6
        radius: height / 2
        color: material.track
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: material.u * 0.3
            Kirigami.Icon {
                visible: parent.parent.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: material.u * 1.1
                height: width
                source: parent.parent.icon
                isMask: true
                color: material.on
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.label
                font.pixelSize: material.u * 0.85
                font.weight: Font.Medium
            }
        }
    }

    // header: icon in a filled accent circle + title (+ trailing text)
    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: material.u * 0.7
        Rectangle {
            Layout.preferredWidth: material.u * 2.4
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: material.accent
            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.56
                height: width
                source: material.headerIcon()
                isMask: true
                color: material.tone.container
            }
        }
        Label {
            Layout.fillWidth: true
            text: material.kind === "weather" && material.d.weather ? (material.d.weather.place || material.d.weather.city || material.titles.weather)
                : material.kind === "calendar" ? material.ru.standaloneMonthName(material.d.now.getMonth()) + " " + material.d.now.getFullYear()
                : material.kind === "youtube" && material.d.youtube && material.d.youtube.title ? material.d.youtube.title
                : material.titles[material.kind] || material.kind
            font.pixelSize: material.u * 1.05
            font.weight: Font.Medium
        }
        Muted {
            id: trailing
            visible: text !== ""
            text: material.kind === "clock" ? material.d.now.toLocaleDateString(material.ru, "ddd")
                : material.kind === "onthisday" ? material.d.now.toLocaleDateString(material.ru, "d MMMM")
                : material.kind === "claude" && material.d.claude && material.d.claude.plan ? material.d.claude.plan
                : ""
        }
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: material.u * 0.6
        sourceComponent: ({ clock: clockView, weather: weatherView, calendar: calendarView,
            battery: batteryView, screentime: screentimeView, typewriter: writingView,
            youtube: youtubeView, linux: newsView, russia: newsView, rates: ratesView,
            claude: claudeView, onthisday: onThisDayView, sky: skyView, weekly: weeklyView })[material.kind] || null
    }

    // ---- clock ----
    Component {
        id: clockView
        ColumnLayout {
            spacing: 0
            Item { Layout.fillHeight: true }
            Display {
                text: Qt.formatTime(material.d.now, "HH:mm")
                font.pixelSize: material.u * (material.wide ? 5.4 : 4.4)
            }
            Muted { text: material.d.now.toLocaleDateString(material.ru, "d MMMM, dddd"); Layout.fillWidth: true }
        }
    }

    // ---- weather ----
    Component {
        id: weatherView
        ColumnLayout {
            readonly property var w: material.d.weather
            readonly property var info: w && w.code !== undefined ? material.d.weatherInfo(w.code, w.day) : ["", ""]
            spacing: material.u * 0.3
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: material.u
                Display { text: w && w.temp !== undefined ? Math.round(w.temp) + "°" : "—" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: w && w.error ? w.error : info[1]; font.weight: Font.Medium; Layout.fillWidth: true }
                    Muted {
                        visible: !!w && w.feels !== undefined
                        text: w ? Tr.t("Ощущается как ") + Math.round(w.feels) + "°" : ""
                        Layout.fillWidth: true
                    }
                }
                Kirigami.Icon {
                    visible: material.wide && !!w && w.code !== undefined
                    Layout.preferredWidth: material.u * 4
                    Layout.preferredHeight: Layout.preferredWidth
                    source: w ? material.d.weatherIcon(w.code, w.day) : ""
                    isMask: true
                    color: material.accent
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: material.u * 0.4
                visible: !!w && w.max !== undefined
                Chip { icon: "go-up-symbolic"; label: w ? Math.round(w.max) + "°" : "" }
                Chip { icon: "go-down-symbolic"; label: w ? Math.round(w.min) + "°" : "" }
                Chip {
                    visible: material.wide && !!w && w.wind !== undefined
                    icon: "speedometer-symbolic"
                    label: w ? Math.round(w.wind) + Tr.t(" км/ч") : ""
                }
            }
        }
    }

    // ---- calendar ----
    Component {
        id: calendarView
        RowLayout {
            spacing: material.u * 1.2
            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: !material.wide
                spacing: material.u * 0.3
                Item { Layout.fillHeight: true }
                Rectangle {
                    Layout.preferredWidth: material.u * 5.2
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: width / 2
                    color: material.accent
                    Label {
                        anchors.centerIn: parent
                        text: material.d.now.getDate()
                        color: material.tone.container
                        font.pixelSize: material.u * 2.8
                        font.weight: Font.Medium
                    }
                }
                Label { text: material.d.now.toLocaleDateString(material.ru, "dddd"); font.weight: Font.Medium }
            }
            Grid {
                visible: material.wide
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                columns: 7
                readonly property real cell: (material.width - material.u * 6.4) / 7
                readonly property date first: new Date(material.d.now.getFullYear(), material.d.now.getMonth(), 1)
                readonly property int lead: (first.getDay() + 6) % 7
                readonly property int days: new Date(material.d.now.getFullYear(), material.d.now.getMonth() + 1, 0).getDate()
                Repeater {
                    model: Tr.ru ? ["П", "В", "С", "Ч", "П", "С", "В"] : ["M", "T", "W", "T", "F", "S", "S"]
                    delegate: Muted {
                        required property string modelData
                        width: parent.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: material.u * 0.8
                        font.weight: Font.Medium
                    }
                }
                Repeater {
                    model: parent.lead + parent.days
                    delegate: Item {
                        required property int index
                        readonly property int day: index - parent.lead + 1
                        readonly property bool today: day === material.d.now.getDate()
                        width: parent.cell
                        height: material.u * 1.6
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, material.u * 1.6)
                            height: width
                            radius: width / 2
                            color: material.accent
                            visible: parent.today
                        }
                        Label {
                            anchors.centerIn: parent
                            text: parent.day > 0 ? parent.day : ""
                            color: parent.today ? material.tone.container : material.on
                            font.pixelSize: material.u * 0.85
                        }
                    }
                }
            }
        }
    }

    // ---- battery ----
    Component {
        id: batteryView
        ColumnLayout {
            spacing: material.u * 0.5
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Display { text: material.d.battery >= 0 ? material.d.battery + "%" : "—" }
                Item { Layout.fillWidth: true }
                Chip { label: material.d.charging ? Tr.t("Заряжается") : Tr.t("От батареи"); icon: material.d.charging ? "battery-full-charging-symbolic" : "" }
            }
            Progress {
                Layout.fillWidth: true
                value: Math.max(0, material.d.battery) / 100
                tint: material.d.battery >= 0 && material.d.battery <= 20 && !material.d.charging ? material.home.tone("red").accent : material.accent
            }
            Muted {
                visible: material.wide && !!material.d.disk
                text: material.d.disk ? Tr.t("Свободно на диске: ") + Math.round(material.d.disk.free / 1e9) + Tr.t(" ГБ") : ""
                Layout.fillWidth: true
            }
        }
    }

    // ---- typewriter ----
    Component {
        id: writingView
        RowLayout {
            readonly property var t: material.d.typewriter || { words: 0, goal: 0, streak: 0, days: [] }
            spacing: material.u
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: material.u * 0.4
                Item { Layout.fillHeight: true }
                RowLayout {
                    spacing: material.u * 0.5
                    Display { text: t.words }
                    Muted { Layout.alignment: Qt.AlignBaseline; text: t.goal > 0 ? Tr.t("из ") + t.goal : Tr.t("слов") }
                }
                Progress { Layout.fillWidth: true; visible: t.goal > 0; value: t.goal > 0 ? t.words / t.goal : 0 }
                Chip { visible: t.streak > 0; icon: "flag-symbolic"; label: t.streak + Tr.t(" дн. подряд") }
            }
            // the last 14 days
            Item {
                visible: material.wide
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property int peak: Math.max(t.goal, ...(t.days || []).map(x => x.words), 1)
                Row {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    spacing: material.u * 0.25
                    Repeater {
                        model: t.days || []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: (parent.parent.width - 13 * material.u * 0.25) / 14
                            height: Math.max(width, parent.parent.height * 0.9 * modelData.words / parent.parent.peak)
                            anchors.bottom: parent.bottom
                            radius: width / 2
                            color: index === 13 || (t.goal > 0 && modelData.words >= t.goal) ? material.accent : material.track
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
            readonly property var s: material.d.screentime || { total: 0, top: [] }
            spacing: material.u * 0.35
            Display { text: material.d.duration(s.total || 0); font.pixelSize: material.u * 2.8 }
            Item { Layout.fillHeight: true }
            Repeater {
                model: (s.top || []).slice(0, material.wide || material.height > material.u * 13 ? 3 : 2)
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: material.u * 0.15
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: modelData.name; font.pixelSize: material.u * 0.9; Layout.fillWidth: true }
                        Muted { text: material.d.duration(modelData.seconds) }
                    }
                    Progress {
                        Layout.fillWidth: true
                        implicitHeight: material.u * 0.5
                        value: modelData.seconds / Math.max(1, s.top[0].seconds)
                    }
                }
            }
        }
    }

    // ---- YouTube ----
    Component {
        id: youtubeView
        ColumnLayout {
            readonly property var yt: material.d.youtube
            spacing: material.u * 0.3
            Item { Layout.fillHeight: true }
            Display { text: yt && yt.subscribers !== undefined ? material.d.bigNumber(yt.subscribers) : "—" }
            Muted { text: yt && yt.error && yt.subscribers === undefined ? Tr.t("нужно подключить в «Сводке»") : Tr.t("подписчиков"); Layout.fillWidth: true }
            Flow {
                Layout.fillWidth: true
                spacing: material.u * 0.4
                Chip {
                    visible: !!yt && yt.last28 !== undefined
                    icon: yt && yt.last28 < 0 ? "go-down-symbolic" : "go-up-symbolic"
                    label: yt ? material.d.bigNumber(Math.abs(yt.last28 || 0)) + Tr.t(" за 28 дней") : ""
                }
                Chip {
                    visible: material.wide && !!yt && yt.views !== undefined
                    icon: "view-visible-symbolic"
                    label: yt ? material.d.bigNumber(yt.views) : ""
                }
            }
        }
    }

    // ---- news: a list, tap a headline to read it ----
    Component {
        id: newsView
        ColumnLayout {
            readonly property var items: material.kind === "linux" ? material.d.linuxNews : material.d.russiaNews
            readonly property real rowHeight: material.u * 3.4
            spacing: 0
            Repeater {
                model: items.slice(0, Math.max(1, Math.floor(parent.height / rowHeight)))
                delegate: Item {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: rowHeight
                    Rectangle {
                        visible: index > 0
                        width: parent.width
                        height: 1
                        color: material.track
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: material.u * 0.1
                        Label {
                            width: parent.width
                            text: modelData.title
                            font.pixelSize: material.u * 0.92
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                        }
                        Muted {
                            width: parent.width
                            text: modelData.source + " · " + material.d.ago(modelData.time)
                            font.pixelSize: material.u * 0.75
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally(modelData.link) }
                }
            }
            Item { Layout.fillHeight: true }
            Muted { visible: items.length === 0; text: Tr.t("Загружаю…") }
        }
    }

    // ---- exchange rates ----
    Component {
        id: ratesView
        ColumnLayout {
            readonly property var r: material.d.rates
            spacing: material.u * 0.25
            Item { Layout.fillHeight: true }
            Repeater {
                model: [["USD", "$"], ["EUR", "€"], ["CNY", "¥"]]
                delegate: RowLayout {
                    required property var modelData
                    readonly property var v: r ? r[modelData[0]] : null
                    readonly property real change: v ? v.value - v.previous : 0
                    Layout.fillWidth: true
                    spacing: material.u * 0.6
                    Rectangle {
                        Layout.preferredWidth: material.u * 2
                        Layout.preferredHeight: Layout.preferredWidth
                        radius: width / 2
                        color: material.track
                        Label { anchors.centerIn: parent; text: modelData[1]; font.weight: Font.Medium }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: v ? v.value.toFixed(2) + " ₽" : "—"
                        font.pixelSize: material.u * 1.35
                        font.weight: Font.Medium
                    }
                    Kirigami.Icon {
                        visible: !!v
                        Layout.preferredWidth: material.u
                        Layout.preferredHeight: Layout.preferredWidth
                        source: change >= 0 ? "go-up-symbolic" : "go-down-symbolic"
                        isMask: true
                        color: change >= 0 ? material.home.tone("green").accent : material.home.tone("red").accent
                    }
                    Muted { visible: !!v; text: Math.abs(change).toFixed(2) }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- Claude limits ----
    Component {
        id: claudeView
        ColumnLayout {
            readonly property var c: material.d.claude
            spacing: material.u * 0.5
            Item { Layout.fillHeight: true }
            Repeater {
                model: [["session", Tr.t("5 часов")], ["weekly", Tr.t("Неделя")]]
                delegate: ColumnLayout {
                    required property var modelData
                    readonly property var l: c ? c[modelData[0]] : null
                    readonly property int pct: l ? Math.round(l.percent) : 0
                    Layout.fillWidth: true
                    spacing: material.u * 0.25
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: modelData[1]; Layout.fillWidth: true }
                        Muted { text: l ? pct + "%" + (l.resetsAt ? Tr.t(" · до ") + Qt.formatTime(new Date(l.resetsAt), "HH:mm") : "") : "—" }
                    }
                    Progress {
                        Layout.fillWidth: true
                        value: pct / 100
                        tint: pct >= 90 ? material.home.tone("red").accent : material.accent
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- on this day ----
    Component {
        id: onThisDayView
        ColumnLayout {
            spacing: material.u * 0.5
            Repeater {
                model: material.d.onThisDay.slice(0, Math.max(1, Math.floor(parent.height / (material.u * (material.wide ? 3.2 : 4.4)))))
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: material.u * 0.6
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: yearText.implicitWidth + material.u
                        Layout.preferredHeight: material.u * 1.6
                        radius: height / 2
                        color: material.accent
                        Label {
                            id: yearText
                            anchors.centerIn: parent
                            text: modelData.year
                            color: material.tone.container
                            font.pixelSize: material.u * 0.85
                            font.weight: Font.Bold
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.text
                        font.pixelSize: material.u * 0.88
                        wrapMode: Text.WordWrap
                        maximumLineCount: material.wide ? 2 : 3
                        MouseArea { anchors.fill: parent; onClicked: if (modelData.link) Qt.openUrlExternally(modelData.link) }
                    }
                }
            }
            Item { Layout.fillHeight: true }
            Muted { visible: material.d.onThisDay.length === 0; text: Tr.t("Загружаю…") }
        }
    }

    // ---- sky ----
    Component {
        id: skyView
        RowLayout {
            spacing: material.u
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: material.u * 0.3
                Item { Layout.fillHeight: true }
                Repeater {
                    model: [["weather-clear-symbolic", material.d.sun.rise, Tr.t("Восход")],
                            ["weather-clear-night-symbolic", material.d.sun.set, Tr.t("Закат")]]
                    delegate: RowLayout {
                        required property var modelData
                        spacing: material.u * 0.6
                        Kirigami.Icon {
                            Layout.preferredWidth: material.u * 1.5
                            Layout.preferredHeight: Layout.preferredWidth
                            source: modelData[0]
                            isMask: true
                            color: material.accent
                        }
                        Label {
                            text: modelData[1] ? Qt.formatTime(modelData[1], "HH:mm") : "—"
                            font.pixelSize: material.u * 1.6
                        }
                        Muted { text: modelData[2] }
                    }
                }
                Muted { text: Tr.t("День ") + material.d.duration(material.d.sun.length) }
            }
            ColumnLayout {
                visible: material.wide
                spacing: 0
                Text { Layout.alignment: Qt.AlignHCenter; text: material.d.moon.icon; font.pixelSize: material.u * 3.6 }
                Label { Layout.alignment: Qt.AlignHCenter; text: material.d.moon.name; font.weight: Font.Medium }
                Muted { Layout.alignment: Qt.AlignHCenter; text: Tr.t("освещена на ") + material.d.moon.light + "%" }
            }
        }
    }

    // ---- week report ----
    Component {
        id: weeklyView
        ColumnLayout {
            id: week
            readonly property var w: material.d.weekly
            spacing: material.u * 0.45
            function delta(now, before) {
                if (!before) return "";
                const p = Math.round((now - before) / before * 100);
                return (p > 0 ? "+" : p < 0 ? "−" : "±") + Math.abs(p) + "%";
            }
            component WeekRow: RowLayout {
                id: row
                property string title
                property string value
                property string change
                property var days: []
                Layout.fillWidth: true
                spacing: material.u * 0.6
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Muted { text: row.title; font.pixelSize: material.u * 0.8; Layout.fillWidth: true }
                    RowLayout {
                        spacing: material.u * 0.4
                        Label { text: row.value; font.pixelSize: material.u * 1.3; font.weight: Font.Medium }
                        Muted { visible: row.change !== ""; text: row.change; font.pixelSize: material.u * 0.8 }
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignBottom
                    spacing: material.u * 0.25
                    Repeater {
                        model: row.days
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property real peak: Math.max(1, Math.max.apply(null, row.days))
                            anchors.bottom: parent.bottom
                            width: material.u * 0.6
                            height: Math.max(width, material.u * 2 * modelData / peak)
                            radius: width / 2
                            color: index === 6 ? material.accent : material.track
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
            WeekRow {
                title: Tr.t("Экранное время")
                value: week.w ? material.d.duration(week.w.screen.total) : "—"
                change: week.w ? week.delta(week.w.screen.total, week.w.screen.before) : ""
                days: week.w ? week.w.screen.days : []
            }
            WeekRow {
                title: Tr.t("Печатная машинка")
                value: week.w ? week.w.words.total.toLocaleString(material.ru, "f", 0) + Tr.t(" слов") : "—"
                change: week.w ? week.delta(week.w.words.total, week.w.words.before) : ""
                days: week.w ? week.w.words.days : []
            }
            Item { Layout.fillHeight: true }
        }
    }
}

// Dock dashboard: the built-in screen while the tablet sits in the dock (the external monitor is
// the main screen). Apple style: StandBy clock on the left, macOS-like widgets on the right.
// System numbers come from ksystemstats, online ones from `tablet-tools dashboard` (cached for
// 5 minutes). Nothing animates; numbers change every couple of seconds, the clock once a minute.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import org.kde.kirigami as Kirigami

import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.private.mpris as Mpris
import "Tr.js" as Tr

ContainmentItem {
    id: root

    readonly property bool pixel: Plasmoid.configuration.shellStyle === "pixel"
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light

    // only sample while the dashboard is on a screen
    readonly property bool active: Window.window !== null && Window.window.visible
    readonly property string homeDir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace("file://", "")
    readonly property int interval: Math.max(1, Plasmoid.configuration.sampleInterval) * 1000

    // Apple system colours (dark appearance)
    QtObject {
        id: pal
        readonly property bool pixel: root.pixel
        readonly property bool dark: root.dark
        // Material type: Roboto Flex when installed (install-material-icons.sh)
        readonly property string fontFamily: root.pixel && Qt.fontFamilies().indexOf("Roboto Flex") >= 0
                                             ? "Roboto Flex" : Kirigami.Theme.defaultFont.family
        readonly property color background: root.pixel ? (root.dark ? "#141218" : "#FEF7FF") : "#000000"
        readonly property color plate: root.pixel ? (root.dark ? "#2B2932" : "#F3EDF7") : "#1C1C1E"
        readonly property color label: root.pixel ? (root.dark ? "#E6E0E9" : "#1D1B20") : "#FFFFFF"
        readonly property color secondary: root.pixel ? (root.dark ? "#CAC4D0" : "#49454F") : Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6)
        readonly property color tertiary: root.pixel ? (root.dark ? "#938F99" : "#79747E") : Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.3)
        readonly property color blue: root.pixel ? (root.dark ? "#D0BCFF" : "#6750A4") : "#0A84FF"
        readonly property color green: root.pixel ? (root.dark ? "#81C995" : "#146C2E") : "#30D158"
        readonly property color yellow: root.pixel ? (root.dark ? "#F9DE81" : "#755B00") : "#FFD60A"
        readonly property color orange: root.pixel ? (root.dark ? "#FFB86C" : "#825500") : "#FF9F0A"
        readonly property color red: root.pixel ? (root.dark ? "#F2B8B5" : "#B3261E") : "#FF453A"
        readonly property color purple: root.pixel ? (root.dark ? "#D0BCFF" : "#6750A4") : "#BF5AF2"
        readonly property color teal: root.pixel ? (root.dark ? "#80D5D0" : "#006A66") : "#64D2FF"
        readonly property color claude: "#D97757"
        readonly property color pink: root.pixel ? (root.dark ? "#EFB8C8" : "#7D5260") : "#FF375F"
        readonly property color indigo: root.pixel ? (root.dark ? "#B69DF8" : "#625B71") : "#5E5CE6"
    }

    // ---- sensors --------------------------------------------------------------------------

    component S: Sensors.Sensor {
        enabled: root.active
        updateRateLimit: root.interval
    }
    S { id: cpu; sensorId: "cpu/all/usage" }
    S { id: freq; sensorId: "cpu/all/averageFrequency" }
    S { id: memUsed; sensorId: "memory/physical/used" }
    S { id: memTotal; sensorId: "memory/physical/total" }
    S { id: swapUsed; sensorId: "memory/swap/used" }
    S { id: swapTotal; sensorId: "memory/swap/total" }
    S { id: temp; sensorId: "cpu/all/maximumTemperature" }
    S { id: gpu; sensorId: "gpu/all/usage" }
    S { id: down; sensorId: "network/all/download" }
    S { id: up; sensorId: "network/all/upload" }
    S { id: battery; sensorId: "power/1313/chargePercentage" }
    S { id: chargeRate; sensorId: "power/1313/chargeRate" }
    S { id: health; sensorId: "power/1313/health"; enabled: root.active && Plasmoid.configuration.w_battery }
    S { id: uptime; sensorId: "os/system/uptime"; enabled: root.active && Plasmoid.configuration.w_system }
    S { id: load1; sensorId: "cpu/loadaverages/loadaverage1"; enabled: root.active && Plasmoid.configuration.w_system }
    S { id: load5; sensorId: "cpu/loadaverages/loadaverage5"; enabled: root.active && Plasmoid.configuration.w_system }
    S { id: load15; sensorId: "cpu/loadaverages/loadaverage15"; enabled: root.active && Plasmoid.configuration.w_system }
    S { id: kernel; sensorId: "os/kernel/version"; enabled: root.active && Plasmoid.configuration.w_system }
    S { id: plasmaVersion; sensorId: "os/plasma/plasmaVersion"; enabled: root.active && Plasmoid.configuration.w_system }

    readonly property var widgetIds: ["cpu", "memory", "temperature", "claude", "youtube", "network", "weather", "media",
                                      "battery", "calendar", "screentime", "typewriter", "system"]
    readonly property int widgetCount: widgetIds.filter(w => Plasmoid.configuration["w_" + w]).length
    // many widgets: the big clock column folds into a header row and the widgets get the width
    readonly property bool compact: widgetCount > 6

    // WMO weather codes (Open-Meteo)
    function weatherInfo(code, day) {
        const c = Number(code);
        if (c === 0) return [day ? "☀️" : "🌙", Tr.t("Ясно")];
        if (c <= 2) return [day ? "🌤️" : "☁️", Tr.t("Малооблачно")];
        if (c === 3) return ["☁️", Tr.t("Пасмурно")];
        if (c <= 48) return ["🌫️", Tr.t("Туман")];
        if (c <= 57) return ["🌦️", Tr.t("Морось")];
        if (c <= 67) return ["🌧️", Tr.t("Дождь")];
        if (c <= 77) return ["🌨️", Tr.t("Снег")];
        if (c <= 82) return ["🌧️", Tr.t("Ливень")];
        if (c <= 86) return ["🌨️", Tr.t("Снегопад")];
        return ["⛈️", Tr.t("Гроза")];
    }
    function weatherIconName(code, day) {
        const c = Number(code);
        if (code === undefined || isNaN(c)) return "weather-clear-symbolic";
        if (c === 0) return day ? "weather-clear-symbolic" : "weather-clear-night-symbolic";
        if (c <= 2) return day ? "weather-few-clouds-symbolic" : "weather-few-clouds-night-symbolic";
        if (c === 3) return "weather-overcast-symbolic";
        if (c <= 48) return "weather-fog-symbolic";
        if (c <= 57) return "weather-showers-scattered-symbolic";
        if (c <= 67 || (c >= 80 && c <= 82)) return "weather-showers-symbolic";
        if (c <= 86) return "weather-snow-symbolic";
        return "weather-storm-symbolic";
    }
    function duration(secs) {
        const h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60);
        return h > 0 ? h + Tr.t(" ч ") + m + Tr.t(" мин") : m + Tr.t(" мин");
    }

    Mpris.Mpris2Model { id: mpris }

    // notification history, as in the tray (count + the newest two)
    NotificationManager.Notifications {
        id: notifications
        showExpired: true
        showDismissed: true
        showJobs: false
        showAddedDuringInhibition: true
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
    }
    // Do Not Disturb, the same switch as the tray's
    NotificationManager.Settings { id: notificationSettings }
    readonly property bool dnd: notificationSettings.notificationsInhibitedByApplication
                                || (notificationSettings.notificationsInhibitedUntil !== undefined
                                    && new Date(notificationSettings.notificationsInhibitedUntil) > root.now)
    function toggleDnd() {
        if (dnd) {
            notificationSettings.notificationsInhibitedUntil = undefined;
            notificationSettings.revokeApplicationInhibitions();
        } else {
            const until = new Date();
            until.setFullYear(until.getFullYear() + 1);      // until turned off
            notificationSettings.notificationsInhibitedUntil = until;
        }
        notificationSettings.save();
        root.now = new Date();
    }
    // the newest two for the cards (a limited model, so no delegates for the rest)
    NotificationManager.Notifications {
        id: newestNotifications
        showExpired: true
        showDismissed: true
        showJobs: false
        showAddedDuringInhibition: true
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
        limit: 2
    }

    property var cpuHistory: []
    property var memHistory: []

    function pushed(list, v) {
        const l = list.slice(Math.max(0, list.length - 39));
        l.push(Number(v) || 0);
        return l;
    }

    Timer {
        interval: root.interval
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            root.cpuHistory = root.pushed(root.cpuHistory, cpu.value);
            root.memHistory = root.pushed(root.memHistory, memTotal.value > 0 ? 100 * memUsed.value / memTotal.value : 0);
        }
    }

    // ---- online data ------------------------------------------------------------------------

    property var online: ({})
    readonly property var claude: online.claude || {}
    readonly property var youtube: online.youtube || {}
    readonly property var disk: online.disk || {}

    P5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf(" dashboard") !== -1) {
                try {
                    root.online = JSON.parse(data["stdout"]);
                } catch (e) {
                }
            }
        }
    }
    function refreshOnline() {
        const city = Plasmoid.configuration.w_weather ? String(Plasmoid.configuration.weatherCity).replace(/'/g, "") : "";
        executable.connectSource("'" + root.homeDir + "/.local/bin/tablet-tools' dashboard" + (city ? " --weather '" + city + "'" : ""));
    }
    // one call gives the online numbers (cached by tablet-tools: 5 min, failures retried after
    // one) and fresh local ones (zram, Android, disk)
    readonly property var zram: online.zram || {}
    readonly property var android: online.android || {}
    function stopAndroid() {
        executable.connectSource("waydroid session stop");
        androidRefresh.start();
    }
    Timer {
        id: androidRefresh
        interval: 4000
        onTriggered: root.refreshOnline()
    }
    Timer {
        interval: 30 * 1000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.refreshOnline()
    }

    // ---- formatting -------------------------------------------------------------------------

    readonly property var ru: Tr.locale()
    function gib(bytes) {
        return (bytes / 1073741824).toLocaleString(ru, "f", 1);
    }
    function rate(bytesPerSec) {
        const v = Number(bytesPerSec) || 0;
        if (v >= 1048576) return [(v / 1048576).toLocaleString(ru, "f", 1), Tr.t("МБ/с")];
        if (v >= 1024) return [String(Math.round(v / 1024)), Tr.t("КБ/с")];
        return [String(Math.round(v)), Tr.t("Б/с")];
    }
    function number(n) {
        return Number(n).toLocaleString(ru, "f", 0);
    }
    function untilText(iso) {
        if (!iso) return "";
        const ms = new Date(iso).getTime() - root.now.getTime();
        if (ms <= 0) return Tr.t("сейчас");
        const h = Math.floor(ms / 3600000);
        const m = Math.floor(ms % 3600000 / 60000);
        if (h >= 24) return new Date(iso).toLocaleString(ru, "ddd, HH:mm");
        return Tr.t("через ") + (h > 0 ? h + Tr.t(" ч ") : "") + m + Tr.t(" мин");
    }
    // usage of a Claude limit; past its reset time it is 0 again, also when offline
    function limitNow(l) {
        if (!l) return 0;
        return l.resetsAt && new Date(l.resetsAt).getTime() <= root.now.getTime() ? 0 : l.percent;
    }
    function timeOf(iso) {
        return iso ? Qt.formatTime(new Date(iso), "HH:mm") : "";
    }

    // Atom Z3795: throttles near 90 °C
    readonly property int tempLevel: temp.value >= 88 ? 3 : temp.value >= 82 ? 2 : temp.value >= 75 ? 1 : 0
    function limitColor(p, normal) {
        return p >= 90 ? pal.red : p >= 75 ? pal.orange : normal;
    }

    // the clock shows minutes only: wake up once a minute, on the minute (fewer repaints)
    property date now: new Date()
    Timer {
        interval: 1000
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            interval = 60000 - root.now.getSeconds() * 1000 - root.now.getMilliseconds() + 50;
            restart();
        }
    }

    // ---- view -------------------------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: pal.background
    }

    readonly property real u: Math.min(width / 64, height / 40)

    // big value + small unit on one baseline
    component Value: Row {
        property string prefix
        property color prefixColor: pal.label
        property string value
        property string unit
        property real size: root.u * 2.4
        property color color: pal.label
        spacing: root.u * 0.25
        Text {
            visible: text.length > 0
            anchors.baseline: big.baseline
            text: parent.prefix
            color: parent.prefixColor
            font.pixelSize: parent.size * 0.8
            font.family: pal.fontFamily
            font.weight: root.pixel ? Font.Medium : Font.Bold
        }
        Text {
            id: big
            text: parent.value
            color: parent.color
            font.pixelSize: parent.size
            font.family: pal.fontFamily
            font.weight: root.pixel ? Font.Medium : Font.Bold
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.baseline: big.baseline
            text: parent.unit
            color: pal.secondary
            font.pixelSize: parent.size * 0.45
            font.family: pal.fontFamily
            font.weight: Font.DemiBold
        }
    }
    component Caption: Text {
        color: pal.secondary
        font.pixelSize: root.u * 0.72
        font.family: pal.fontFamily
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.u * 1.6
        spacing: root.u * 1.1

    // compact header: time, date, battery, notifications with Do Not Disturb / clear
    RowLayout {
        visible: root.compact
        Layout.fillWidth: true
        spacing: root.u * 1.0
        Text {
            text: Qt.formatTime(root.now, Plasmoid.configuration.clock24 ? "HH:mm" : "h:mm")
            color: pal.label
            font.pixelSize: root.u * 3
            font.family: pal.fontFamily
            font.weight: root.pixel ? Font.Medium : Font.Bold
            font.features: { "tnum": 1 }
        }
        Column {
            Layout.alignment: Qt.AlignVCenter
            Text {
                text: root.now.toLocaleDateString(root.ru, "dddd").toUpperCase()
                color: pal.red
                font.pixelSize: root.u * 0.8
                font.family: pal.fontFamily
                font.weight: root.pixel ? Font.Medium : Font.Bold
            }
            Text {
                text: root.now.toLocaleDateString(root.ru, "d MMMM") + (Plasmoid.configuration.showBattery && battery.value > 0
                      ? " · " + Math.round(battery.value) + "%" + (chargeRate.value > 0.05 ? " ⚡" : "") : "")
                color: pal.secondary
                font.pixelSize: root.u * 0.8
                font.family: pal.fontFamily
            }
        }
        Item { Layout.fillWidth: true }
        RowLayout {
            visible: Plasmoid.configuration.showNotifications
            spacing: root.u * 0.5
            Text {
                text: root.dnd ? Tr.t("Не беспокоить") : notifications.count === 0 ? Tr.t("Нет уведомлений")
                      : notifications.count + Tr.t(" уведомл.") + (notifications.unreadNotificationsCount > 0 ? " · " + notifications.unreadNotificationsCount + Tr.t(" новых") : "")
                color: root.dnd ? pal.indigo : pal.secondary
                font.pixelSize: root.u * 0.8
                font.family: pal.fontFamily
                font.weight: Font.DemiBold
            }
            Pill { glyph: "☾"; icon: "notifications-disabled-symbolic"; on: root.dnd; onActivated: root.toggleDnd() }
            Pill {
                visible: notifications.count > 0
                glyph: Tr.t("Очистить")
                onActivated: notifications.clear(NotificationManager.Notifications.ClearExpired)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: root.u * 1.6

        // ---- StandBy clock ----
        ColumnLayout {
            visible: !root.compact
            // fixed width: long notification texts must elide, not push the widgets off screen
            Layout.preferredWidth: root.u * 21
            Layout.maximumWidth: root.u * 21
            Layout.minimumWidth: root.u * 21
            Layout.fillHeight: true
            spacing: 0

            Item { Layout.fillHeight: true }
            Text {
                text: root.pixel ? root.now.toLocaleDateString(root.ru, "dddd, d MMMM") : root.now.toLocaleDateString(root.ru, "dddd").toUpperCase()
                color: root.pixel ? pal.label : pal.red
                font.pixelSize: root.u * 1.25
                font.family: pal.fontFamily
                font.weight: root.pixel ? Font.Medium : Font.Bold
                font.letterSpacing: root.u * 0.05
            }
            Text {
                visible: !root.pixel
                text: root.now.toLocaleDateString(root.ru, "d MMMM")
                color: pal.label
                font.pixelSize: root.u * 1.25
                font.family: pal.fontFamily
                font.weight: Font.DemiBold
            }
            // Material: the Pixel lock screen clock, hours over minutes, hours in the accent
            Column {
                visible: root.pixel
                Layout.topMargin: root.u * 0.4
                spacing: -root.u * 1.6
                Repeater {
                    model: [Qt.formatTime(root.now, Plasmoid.configuration.clock24 ? "HH" : "hh"), Qt.formatTime(root.now, "mm")]
                    delegate: Text {
                        required property string modelData
                        required property int index
                        text: modelData
                        color: index === 0 ? pal.blue : pal.label
                        font.family: pal.fontFamily
                        font.pixelSize: root.u * 7.4
                        font.weight: Font.Normal
                        font.features: { "tnum": 1 }
                    }
                }
            }
            Text {
                visible: !root.pixel
                Layout.topMargin: -root.u * 0.6
                text: Qt.formatTime(root.now, Plasmoid.configuration.clock24 ? "HH:mm" : "h:mm")
                color: pal.label
                font.pixelSize: root.u * 6.6
                font.family: pal.fontFamily
                font.weight: root.pixel ? Font.Medium : Font.Bold
                font.letterSpacing: -root.u * 0.12
                font.features: { "tnum": 1 }
            }

            // notifications: count badge and the newest two, like StandBy
            ColumnLayout {
                visible: Plasmoid.configuration.showNotifications
                Layout.topMargin: root.u * 1.2
                Layout.fillWidth: true
                spacing: root.u * 0.45
                RowLayout {
                    spacing: root.u * 0.4
                    Rectangle {
                        implicitWidth: Math.max(implicitHeight, countText.implicitWidth + root.u * 0.7)
                        implicitHeight: root.u * 1.3
                        radius: height / 2
                        color: notifications.count > 0 ? pal.red : pal.plate
                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: notifications.count
                            color: pal.label
                            font.pixelSize: root.u * 0.8
                            font.family: pal.fontFamily
                            font.weight: root.pixel ? Font.Medium : Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.dnd ? Tr.t("Не беспокоить")
                              : notifications.count === 0 ? Tr.t("Нет уведомлений")
                              : notifications.unreadNotificationsCount > 0
                                ? notifications.unreadNotificationsCount + Tr.t(" новых") : Tr.t("уведомлений")
                        color: root.dnd ? pal.indigo : pal.secondary
                        elide: Text.ElideRight
                        font.pixelSize: root.u * 0.85
                        font.family: pal.fontFamily
                        font.weight: Font.DemiBold
                    }
                    // pill buttons: Do Not Disturb (moon, like iOS Focus) and clear
                    component Pill: Rectangle {
                        property string glyph
                        property string icon        // Material: a themed symbol instead of the glyph
                        property bool on: false
                        signal activated()
                        readonly property bool showIcon: root.pixel && icon !== ""
                        implicitWidth: (showIcon ? root.u * 1.0 : pillText.implicitWidth) + root.u * 1.2
                        implicitHeight: root.u * 1.4
                        radius: height / 2
                        color: on ? pal.indigo : pal.plate
                        Kirigami.Icon {
                            visible: parent.showIcon
                            anchors.centerIn: parent
                            width: root.u * 0.95
                            height: width
                            source: parent.icon
                            isMask: true
                            color: parent.on ? pal.background : pal.label
                        }
                        Text {
                            id: pillText
                            visible: !parent.showIcon
                            anchors.centerIn: parent
                            text: parent.glyph
                            color: pal.label
                            font.pixelSize: root.u * 0.75
                            font.family: pal.fontFamily
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -root.u * 0.3
                            onClicked: parent.activated()
                        }
                    }
                    Pill {
                        glyph: "☾"
                        icon: "notifications-disabled-symbolic"
                        on: root.dnd
                        onActivated: root.toggleDnd()
                    }
                    Pill {
                        visible: notifications.count > 0
                        glyph: Tr.t("Очистить")
                        onActivated: notifications.clear(NotificationManager.Notifications.ClearExpired)
                    }
                }
                Repeater {
                    model: newestNotifications
                    delegate: Rectangle {
                        required property var model
                        Layout.preferredWidth: root.u * 21
                        Layout.maximumWidth: root.u * 21
                        implicitHeight: note.implicitHeight + root.u * 0.8
                        radius: root.u * 0.7
                        color: pal.plate
                        ColumnLayout {
                            id: note
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: root.u * 0.6
                            spacing: 0
                            Caption {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                text: (model.applicationName || "") + " · " + Qt.formatTime(model.updated || model.created, "HH:mm")
                                font.pixelSize: root.u * 0.62
                                font.family: pal.fontFamily
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                maximumLineCount: 1
                                text: model.summary || ""
                                color: pal.label
                                elide: Text.ElideRight
                                font.pixelSize: root.u * 0.75
                                font.family: pal.fontFamily
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }

            // battery, like the iOS batteries widget
            RowLayout {
                visible: battery.value > 0 && Plasmoid.configuration.showBattery
                spacing: root.u * 0.8
                Item {
                    implicitWidth: root.u * 3.6
                    implicitHeight: implicitWidth
                    Ring {
                        anchors.fill: parent
                        value: battery.value / 100
                        color: battery.value <= 20 ? pal.red : chargeRate.value > 0.05 ? pal.green : pal.label
                    }
                    Text {
                        anchors.centerIn: parent
                        text: chargeRate.value > 0.05 ? "⚡" : ""
                        color: pal.green
                        font.pixelSize: root.u * 1.2
                        font.family: pal.fontFamily
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Text {
                        text: Math.round(battery.value) + "%"
                        color: pal.label
                        font.pixelSize: root.u * 1.5
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                        font.features: { "tnum": 1 }
                    }
                    Caption {
                        text: chargeRate.value > 0.05 ? Tr.t("Заряжается") : chargeRate.value < -0.05 ? Tr.t("От аккумулятора") : Tr.t("Подключено")
                    }
                }
            }
        }

        // ---- widgets ----
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // 2 columns for up to six widgets, then 3, then 4 (hidden widgets take no cell)
            columns: root.widgetCount > 9 ? 4 : root.widgetCount > 6 ? 3 : 2
            rowSpacing: root.u * 1.1
            columnSpacing: root.u * 1.1

            // CPU: ring + bars of the last minute
            Widget {
                visible: Plasmoid.configuration.w_cpu
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: Tr.t("Процессор")
                icon: "speedometer-symbolic"
                accent: pal.blue
                Ring {
                    id: cpuRing
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.height, parent.width * 0.45, root.u * 6.2)
                    height: width
                    value: cpu.value / 100
                    color: pal.blue
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(cpu.value) + "%"
                        color: pal.label
                        font.pixelSize: parent.width * 0.24
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }
                ColumnLayout {
                    anchors.left: cpuRing.right
                    anchors.leftMargin: root.u
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    spacing: root.u * 0.2
                    Caption { text: (freq.value / 1000).toLocaleString(root.ru, "f", 2) + Tr.t(" ГГц · GPU ") + Math.round(gpu.value) + "%"; Layout.fillWidth: true }
                    Bars {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        values: root.cpuHistory
                        color: pal.blue
                    }
                    Caption { text: Tr.t("последние 2 минуты"); color: pal.tertiary; font.pixelSize: root.u * 0.6 }
                }
            }

            // Memory
            Widget {
                visible: Plasmoid.configuration.w_memory
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: Tr.t("Память")
                icon: "media-flash-memory-stick-symbolic"
                accent: pal.green
                Ring {
                    id: memRing
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.height, parent.width * 0.45, root.u * 6.2)
                    height: width
                    value: memTotal.value > 0 ? memUsed.value / memTotal.value : 0
                    color: pal.green
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(100 * memRing.value) + "%"
                        color: pal.label
                        font.pixelSize: parent.width * 0.24
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }
                ColumnLayout {
                    anchors.left: memRing.right
                    anchors.leftMargin: root.u
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.u * 0.35
                    Value { value: root.gib(memUsed.value); unit: Tr.t("из ") + root.gib(memTotal.value) + Tr.t(" ГБ"); size: root.u * 2 }
                    // zram: how much swapped data it holds and what that costs in RAM
                    Caption {
                        Layout.fillWidth: true
                        text: root.zram.size
                              ? "zram " + root.gib(root.zram.data) + " → " + root.gib(root.zram.used) + Tr.t(" ГБ")
                                + (root.zram.used > 0 ? " · ×" + (root.zram.data / root.zram.used).toLocaleString(root.ru, "f", 1) : "")
                              : Tr.t("Подкачка ") + root.gib(swapUsed.value) + Tr.t(" из ") + root.gib(swapTotal.value) + Tr.t(" ГБ")
                    }
                    Capsule {
                        Layout.fillWidth: true
                        implicitHeight: root.u * 0.4
                        value: root.zram.size ? root.zram.data / root.zram.size : (swapTotal.value > 0 ? swapUsed.value / swapTotal.value : 0)
                        tint: pal.green
                    }
                    // Android (Waydroid) holds ~1 GB even when idle: show it with a stop button
                    RowLayout {
                        visible: !!root.android.running
                        Layout.fillWidth: true
                        Layout.topMargin: root.u * 0.2
                        Caption { Layout.fillWidth: true; text: "Android " + root.gib(root.android.rss) + Tr.t(" ГБ") }
                        Rectangle {
                            implicitWidth: stopText.implicitWidth + root.u * 1.2
                            implicitHeight: stopText.implicitHeight + root.u * 0.5
                            radius: height / 2
                            color: Qt.rgba(pal.red.r, pal.red.g, pal.red.b, 0.22)
                            Text {
                                id: stopText
                                anchors.centerIn: parent
                                text: Tr.t("Остановить")
                                color: pal.red
                                font.pixelSize: root.u * 0.7
                                font.family: pal.fontFamily
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -root.u * 0.4
                                onClicked: root.stopAndroid()
                            }
                        }
                    }
                }
            }

            // Temperature, Weather style
            Widget {
                visible: Plasmoid.configuration.w_temperature
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: Tr.t("Температура")
                icon: "temperature-warm-symbolic"
                accent: pal.orange
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.u * 0.3
                    RowLayout {
                        Text {
                            text: Math.round(temp.value) + "°"
                            color: pal.label
                            font.pixelSize: root.u * 3.4
                            font.family: pal.fontFamily
                            font.weight: root.pixel ? Font.Medium : Font.Bold
                            font.features: { "tnum": 1 }
                        }
                        ColumnLayout {
                            Layout.leftMargin: root.u * 0.6
                            spacing: 0
                            Text {
                                text: [Tr.t("Норма"), Tr.t("Тепло"), Tr.t("Горячо"), Tr.t("Перегрев")][root.tempLevel]
                                color: [pal.green, pal.yellow, pal.orange, pal.red][root.tempLevel]
                                font.pixelSize: root.u * 0.95
                                font.family: pal.fontFamily
                                font.weight: root.pixel ? Font.Medium : Font.Bold
                            }
                            Caption { text: Tr.t("процессор, максимум ядер") }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Capsule {
                        Layout.fillWidth: true
                        implicitHeight: root.u * 0.4
                        weather: true
                        material: root.pixel
                        ring: pal.plate
                        value: (temp.value - 40) / 55
                    }
                    RowLayout {
                        Caption { text: "40°"; color: pal.tertiary }
                        Item { Layout.fillWidth: true }
                        Caption { text: Tr.t("троттлинг ~90°"); color: pal.tertiary }
                    }
                }
            }

            // Claude limits: two Activity rings (outer 5 h, inner week)
            Widget {
                visible: Plasmoid.configuration.w_claude
                id: claudeWidget
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                readonly property real session: root.limitNow(root.claude.session)
                readonly property real week: root.limitNow(root.claude.weekly)
                readonly property color sessionColor: root.limitColor(session, pal.claude)
                readonly property color weekColor: root.limitColor(week, pal.purple)
                title: "Claude" + (root.claude.plan ? " " + root.claude.plan.charAt(0).toUpperCase() + root.claude.plan.slice(1) : "")
                icon: "dialog-messages-symbolic"
                accent: pal.claude
                Caption {
                    visible: !!root.claude.error && !root.claude.session
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap
                    text: root.claude.error || ""
                }
                Item {
                    id: claudeRings
                    visible: !!root.claude.session
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.height, parent.width * 0.45, root.u * 6.2)
                    height: width
                    Ring {
                        anchors.fill: parent
                        thickness: claudeRings.width * 0.13
                        value: claudeWidget.session / 100
                        color: claudeWidget.sessionColor
                    }
                    Ring {
                        anchors.fill: parent
                        anchors.margins: claudeRings.width * 0.155
                        thickness: claudeRings.width * 0.13
                        value: claudeWidget.week / 100
                        color: claudeWidget.weekColor
                    }
                }
                ColumnLayout {
                    visible: !!root.claude.session
                    anchors.left: claudeRings.right
                    anchors.leftMargin: root.u
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.u * 0.5
                    Caption {
                        visible: !!root.claude.stale
                        Layout.fillWidth: true
                        text: Tr.t("нет связи · данные ") + root.timeOf(root.claude.since)
                        color: pal.orange
                    }
                    Repeater {
                        model: [
                            { name: Tr.t("5 часов"), p: claudeWidget.session, c: claudeWidget.sessionColor,
                              at: root.claude.session ? root.claude.session.resetsAt : "" },
                            { name: Tr.t("Неделя"), p: claudeWidget.week, c: claudeWidget.weekColor,
                              at: root.claude.weekly ? root.claude.weekly.resetsAt : "" },
                        ]
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                spacing: root.u * 0.3
                                Rectangle { implicitWidth: root.u * 0.5; implicitHeight: implicitWidth; radius: width / 2; color: modelData.c }
                                Text {
                                    text: modelData.name
                                    color: pal.label
                                    font.pixelSize: root.u * 0.8
                                    font.family: pal.fontFamily
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: Math.round(modelData.p) + "%"
                                    color: modelData.c
                                    font.pixelSize: root.u * 0.8
                                    font.family: pal.fontFamily
                                    font.weight: root.pixel ? Font.Medium : Font.Bold
                                    font.features: { "tnum": 1 }
                                }
                            }
                            Caption {
                                Layout.fillWidth: true
                                text: modelData.at && new Date(modelData.at).getTime() <= root.now.getTime()
                                      ? Tr.t("лимит сброшен") : Tr.t("сброс ") + root.untilText(modelData.at)
                            }
                        }
                    }
                }
            }

            // YouTube subscribers (YouTube Analytics, exact)
            Widget {
                visible: Plasmoid.configuration.w_youtube
                id: ytWidget
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                readonly property bool has: root.youtube.subscribers !== undefined
                title: root.youtube.title || "YouTube"
                icon: "media-playback-start-symbolic"
                accent: pal.red
                onTapped: {
                    if (!has || root.youtube.error) {
                        executable.connectSource("konsole --hide-menubar -e '" + root.homeDir + "/.local/bin/youtube-setup'");
                    } else {
                        root.refreshOnline();
                    }
                }
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.u * 0.3
                    Value {
                        visible: ytWidget.has
                        value: ytWidget.has ? root.number(root.youtube.subscribers) : ""
                        unit: Tr.t("подписчиков")
                        size: root.u * 2.6
                    }
                    Text {
                        visible: ytWidget.has && root.youtube.last28 !== undefined && root.youtube.last28 !== null
                        text: (root.youtube.last28 >= 0 ? "▲ +" : "▼ ") + root.number(root.youtube.last28) + Tr.t(" за 28 дней")
                        color: root.youtube.last28 >= 0 ? pal.green : pal.red
                        font.pixelSize: root.u * 0.85
                        font.family: pal.fontFamily
                        font.weight: Font.DemiBold
                    }
                    Caption {
                        visible: ytWidget.has
                        Layout.fillWidth: true
                        text: root.youtube.stale ? Tr.t("нет связи · данные ") + root.timeOf(root.youtube.since) : Tr.t("YouTube Аналитика, без последних 2 дней")
                        color: pal.tertiary
                    }
                    Text {
                        visible: !ytWidget.has
                        text: Tr.t("Подключить канал")
                        color: pal.label
                        font.pixelSize: root.u * 1.3
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                    }
                    Caption {
                        visible: !ytWidget.has
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Tr.t("Коснитесь, чтобы войти в Google — подписчики как в Творческой студии")
                    }
                }
            }

            // Network and disk
            Widget {
                visible: Plasmoid.configuration.w_network
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: Tr.t("Сеть и диск")
                icon: "network-wireless-symbolic"
                accent: pal.teal
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.u * 0.2
                    RowLayout {
                        spacing: root.u * 1.4
                        Repeater {
                            model: [{ arrow: "↓", r: root.rate(down.value) }, { arrow: "↑", r: root.rate(up.value) }]
                            delegate: Value {
                                required property var modelData
                                prefix: modelData.arrow
                                prefixColor: pal.teal
                                value: modelData.r[0]
                                unit: modelData.r[1]
                                size: root.u * 2
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Caption { text: Tr.t("Диск") }
                        Item { Layout.fillWidth: true }
                        Caption { text: root.disk.total ? Tr.t("свободно ") + root.gib(root.disk.free) + Tr.t(" из ") + root.gib(root.disk.total) + Tr.t(" ГБ") : "" }
                    }
                    Capsule {
                        Layout.fillWidth: true
                        implicitHeight: root.u * 0.4
                        value: root.disk.total ? 1 - root.disk.free / root.disk.total : 0
                        tint: pal.teal
                    }
                }
            }

            // Weather (Open-Meteo), Weather app style
            Widget {
                id: weatherW
                visible: Plasmoid.configuration.w_weather
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                readonly property var w: root.online.weather || {}
                readonly property var info: root.weatherInfo(w.code, w.day)
                title: w.place || (Plasmoid.configuration.weatherCity || Tr.t("Погода"))
                icon: root.weatherIconName(w.code, w.day)
                accent: pal.teal
                Caption {
                    anchors.centerIn: parent
                    visible: !Plasmoid.configuration.weatherCity || (!!weatherW.w.error && weatherW.w.temp === undefined)
                    text: Plasmoid.configuration.weatherCity ? (weatherW.w.error || "") : Tr.t("Укажите город в Настройках → Сводка")
                }
                RowLayout {
                    anchors.fill: parent
                    visible: weatherW.w.temp !== undefined
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: Math.round(weatherW.w.temp) + "°"
                            color: pal.label
                            font.pixelSize: root.u * 3.2
                            font.family: pal.fontFamily
                            font.weight: root.pixel ? Font.Medium : Font.Bold
                            font.features: { "tnum": 1 }
                        }
                        Caption { text: weatherW.info[1] + Tr.t(" · ощущается ") + Math.round(weatherW.w.feels) + "°" }
                        Caption { text: "↑" + Math.round(weatherW.w.max) + "°  ↓" + Math.round(weatherW.w.min) + Tr.t("°  · ветер ") + Math.round(weatherW.w.wind) + Tr.t(" км/ч") }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: !root.pixel
                        text: weatherW.info[0]
                        font.pixelSize: root.u * 3.4
                        font.family: pal.fontFamily
                    }
                    // Material: the theme's weather icon on a tonal circle instead of an emoji
                    Rectangle {
                        visible: root.pixel
                        implicitWidth: root.u * 4.4; implicitHeight: implicitWidth
                        radius: width / 2
                        color: Qt.alpha(pal.teal, 0.22)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: parent.width * 0.6; height: width
                            source: root.weatherIconName(weatherW.w.code, weatherW.w.day)
                            color: pal.teal
                            isMask: true
                        }
                    }
                }
            }

            // Now playing (MPRIS)
            Widget {
                id: mediaWidget
                visible: Plasmoid.configuration.w_media
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                readonly property var player: mpris.currentPlayer
                title: player ? player.identity : Tr.t("Сейчас играет")
                icon: "media-playback-start-symbolic"
                accent: pal.pink
                Caption {
                    anchors.centerIn: parent
                    visible: !mediaWidget.player || !mediaWidget.player.track
                    text: Tr.t("Ничего не играет")
                }
                RowLayout {
                    anchors.fill: parent
                    visible: !!mediaWidget.player && !!mediaWidget.player.track
                    spacing: root.u * 0.8
                    Rectangle {
                        Layout.preferredWidth: Math.min(parent.height, root.u * 5)
                        Layout.preferredHeight: Layout.preferredWidth
                        radius: root.u * 0.6
                        color: pal.track
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: mediaWidget.player ? mediaWidget.player.artUrl : ""
                            sourceSize: Qt.size(width, height)
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.u * 0.2
                        Text {
                            Layout.fillWidth: true
                            text: mediaWidget.player ? mediaWidget.player.track : ""
                            color: pal.label
                            elide: Text.ElideRight
                            font.pixelSize: root.u * 1.0
                            font.family: pal.fontFamily
                            font.weight: root.pixel ? Font.Medium : Font.Bold
                        }
                        Caption { Layout.fillWidth: true; text: mediaWidget.player ? mediaWidget.player.artist : "" }
                        RowLayout {
                            spacing: root.u * 1.2
                            Repeater {
                                model: [["⏮", () => mediaWidget.player.Previous()],
                                        [mediaWidget.player && mediaWidget.player.playbackStatus === Mpris.PlaybackStatus.Playing ? "⏸" : "▶", () => mediaWidget.player.PlayPause()],
                                        ["⏭", () => mediaWidget.player.Next()]]
                                delegate: Text {
                                    required property var modelData
                                    text: modelData[0]
                                    color: pal.label
                                    font.pixelSize: root.u * 1.5
                                    font.family: pal.fontFamily
                                    MouseArea { anchors.fill: parent; anchors.margins: -root.u * 0.4; onClicked: parent.modelData[1]() }
                                }
                            }
                        }
                    }
                }
            }

            // Battery
            Widget {
                visible: Plasmoid.configuration.w_battery
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: Tr.t("Аккумулятор")
                icon: "battery-full-symbolic"
                accent: pal.green
                Ring {
                    id: batRing
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.height, parent.width * 0.45, root.u * 6.2)
                    height: width
                    value: battery.value / 100
                    color: battery.value <= 20 ? pal.red : pal.green
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(battery.value) + "%"
                        color: pal.label
                        font.pixelSize: parent.width * 0.24
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                    }
                }
                ColumnLayout {
                    anchors.left: batRing.right
                    anchors.leftMargin: root.u
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.u * 0.3
                    Text {
                        text: chargeRate.value > 0.05 ? Tr.t("Заряжается") : chargeRate.value < -0.05 ? Tr.t("От аккумулятора") : Tr.t("Подключено")
                        color: pal.label
                        font.pixelSize: root.u * 1.0
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                    }
                    Caption { text: Math.abs(chargeRate.value).toLocaleString(root.ru, "f", 1) + Tr.t(" Вт") }
                    Caption { visible: health.value > 0; text: Tr.t("Состояние ") + Math.round(health.value) + "%" }
                }
            }

            // Calendar: this month, today in red (Apple Calendar widget)
            Widget {
                id: calWidget
                visible: Plasmoid.configuration.w_calendar
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: [Tr.t("Январь"), Tr.t("Февраль"), Tr.t("Март"), Tr.t("Апрель"), Tr.t("Май"), Tr.t("Июнь"), Tr.t("Июль"), Tr.t("Август"), Tr.t("Сентябрь"), Tr.t("Октябрь"),
                        Tr.t("Ноябрь"), Tr.t("Декабрь")][root.now.getMonth()] + " " + root.now.getFullYear()
                icon: "view-calendar-symbolic"
                accent: pal.red
                readonly property var days: {
                    const y = root.now.getFullYear(), m = root.now.getMonth();
                    const first = (new Date(y, m, 1).getDay() + 6) % 7;     // Monday first
                    const count = new Date(y, m + 1, 0).getDate();
                    const out = [];
                    for (let i = 0; i < first; ++i) out.push("");
                    for (let d = 1; d <= count; ++d) out.push(String(d));
                    return out;
                }
                Grid {
                    anchors.centerIn: parent
                    columns: 7
                    // weekday row + the weeks of this month
                    readonly property int rows: 1 + Math.ceil(calWidget.days.length / 7)
                    readonly property real cell: Math.min(calWidget.width * 0.9 / 7, (calWidget.height - root.u * 2.6) / rows)
                    Repeater {
                        model: [Tr.t("пн"), Tr.t("вт"), Tr.t("ср"), Tr.t("чт"), Tr.t("пт"), Tr.t("сб"), Tr.t("вс")].concat(calWidget.days)
                        delegate: Item {
                            required property string modelData
                            required property int index
                            width: parent.cell * 1.12
                            height: parent.cell
                            readonly property bool today: index >= 7 && modelData === String(root.now.getDate())
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.height * 0.95
                                height: width
                                radius: width / 2
                                color: pal.red
                                visible: parent.today
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: index < 7 ? pal.secondary : (index % 7 >= 5 ? pal.secondary : pal.label)
                                font.pixelSize: parent.height * (index < 7 ? 0.5 : 0.62)
                                font.family: pal.fontFamily
                                font.weight: parent.today ? Font.Bold : Font.Normal
                            }
                        }
                    }
                }
            }

            // Screen time today
            Widget {
                id: stWidget
                visible: Plasmoid.configuration.w_screentime
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                readonly property var st: root.online.screentime || {}
                title: Tr.t("Экранное время")
                icon: "chronometer-symbolic"
                accent: pal.indigo
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.u * 0.25
                    Text {
                        text: root.duration(stWidget.st.total || 0)
                        color: pal.label
                        font.pixelSize: root.u * 1.8
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                    }
                    Repeater {
                        model: (stWidget.st.top || []).slice(0, 3)
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: root.u * 0.1
                            RowLayout {
                                Caption { Layout.fillWidth: true; text: modelData.name }
                                Caption { text: root.duration(modelData.seconds) }
                            }
                            Capsule {
                                Layout.fillWidth: true
                                implicitHeight: root.u * 0.3
                                value: stWidget.st.total ? modelData.seconds / stWidget.st.total : 0
                                tint: pal.indigo
                            }
                        }
                    }
                }
            }

            // Typewriter: today's words against the daily goal
            Widget {
                id: twWidget
                visible: Plasmoid.configuration.w_typewriter
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                readonly property var tw: root.online.typewriter || {}
                title: Tr.t("Печатная машинка")
                icon: "document-edit-symbolic"
                accent: pal.yellow
                Ring {
                    id: twRing
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.height, parent.width * 0.45, root.u * 6.2)
                    height: width
                    value: twWidget.tw.goal ? twWidget.tw.words / twWidget.tw.goal : 0
                    color: pal.yellow
                    Text {
                        anchors.centerIn: parent
                        text: twWidget.tw.goal ? Math.round(100 * Math.min(1, twWidget.tw.words / twWidget.tw.goal)) + "%" : ""
                        color: pal.label
                        font.pixelSize: parent.width * 0.24
                        font.family: pal.fontFamily
                        font.weight: root.pixel ? Font.Medium : Font.Bold
                    }
                }
                ColumnLayout {
                    anchors.left: twRing.right
                    anchors.leftMargin: root.u
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Value { value: root.number(twWidget.tw.words || 0); unit: Tr.t("слов"); size: root.u * 2 }
                    Caption { text: Tr.t("цель на сегодня ") + root.number(twWidget.tw.goal || 0) }
                }
            }

            // System
            Widget {
                visible: Plasmoid.configuration.w_system
                Layout.fillWidth: true
                Layout.fillHeight: true
                pal: pal
                u: root.u
                title: Tr.t("Система")
                icon: "computer-symbolic"
                accent: pal.secondary
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.u * 0.3
                    Value { value: root.duration(uptime.value || 0); unit: Tr.t("работает"); size: root.u * 1.5 }
                    Caption { text: Tr.t("Нагрузка ") + [load1, load5, load15].map(l => Number(l.value).toLocaleString(root.ru, "f", 2)).join(" · ") }
                    Caption { Layout.fillWidth: true; text: "Linux " + (kernel.value || "") + " · Plasma " + (plasmaVersion.value || "") }
                }
            }
        }
    }
    }
}

// Data of the home screen widgets and the Today page: `tablet-tools dashboard` (weather, screen
// time, typewriter statistics, YouTube, Claude limits; its online part is cached for 5 minutes),
// `tablet-tools today` (Linux and Russia news, exchange rates, on this day; cached 30 minutes)
// and the battery from sysfs. Refreshed only while the home screen is on top, and whenever it comes back.
import QtQuick
import "Tr.js" as Tr

QtObject {
    id: data

    required property var home
    property bool active: true

    property var online: ({})
    property int battery: -1
    property bool charging: false
    property date now: new Date()

    readonly property var weather: online.weather || null
    readonly property var screentime: online.screentime || null
    readonly property var typewriter: online.typewriter || null
    readonly property var disk: online.disk || null
    readonly property var youtube: online.youtube || null
    readonly property var claude: online.claude || null

    property var today: ({})
    readonly property var linuxNews: today.linux || []
    readonly property var russiaNews: today.russia || []
    readonly property var rates: today.rates || null
    readonly property var onThisDay: today.onthisday || []
    // week report (`tablet-tools weekly`, local and quick): refreshed with the Today data
    property var weekly: null
    // the device's name for the battery widget (tablet-tools hardware: DMI product)
    property string model: ""
    function refreshToday() {
        home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "weekly"], out => {
            try {
                data.weekly = JSON.parse(out);
            } catch (e) {
            }
        });
        home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "today"], out => {
            try {
                data.today = JSON.parse(out);
            } catch (e) {
            }
        });
    }

    function refresh() {
        home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "dashboard", "--weather", home.weatherCity], out => {
            try {
                data.online = JSON.parse(out);
            } catch (e) {
            }
        });
        refreshBattery();
        refreshToday();
    }
    function refreshBattery() {
        home.runCommand(["sh", "-c", "for d in /sys/class/power_supply/*; do [ \"$(cat $d/type)\" = Battery ] && cat $d/capacity $d/status && break; done"], out => {
            const lines = out.trim().split("\n");
            data.battery = parseInt(lines[0]);
            data.charging = lines[1] === "Charging" || lines[1] === "Full";
        });
    }

    onActiveChanged: if (active) refresh()
    Component.onCompleted: {
        refresh();
        home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "hardware"], out => {
            try {
                data.model = JSON.parse(out).model || "";
            } catch (e) {
            }
        });
    }

    property Timer todayTimer: Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: data.active
        onTriggered: data.refreshToday()
    }
    property Timer onlineTimer: Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: data.active
        onTriggered: data.refresh()
    }
    property Timer minuteTimer: Timer {
        interval: 30 * 1000
        repeat: true
        running: data.active
        onTriggered: {
            data.now = new Date();
            data.refreshBattery();
        }
    }

    // "5 мин назад", "3 ч назад", or the date
    function ago(secs) {
        if (!secs) {
            return "";
        }
        const d = Math.max(0, now.getTime() / 1000 - secs);
        if (d < 3600) return Math.max(1, Math.round(d / 60)) + Tr.t(" мин");
        if (d < 86400) return Math.round(d / 3600) + Tr.t(" ч");
        return new Date(secs * 1000).toLocaleDateString(Tr.locale(), "d MMM");
    }
    function bigNumber(n) {
        return Number(n || 0).toLocaleString(Tr.locale(), "f", 0);
    }

    // ---- sky: sunrise / sunset and the moon (computed here, no network) ----
    function sunElevation(date, lat, lon) {
        const rad = Math.PI / 180;
        const day = (Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) - Date.UTC(date.getUTCFullYear(), 0, 0)) / 86400000;
        const hours = date.getUTCHours() + date.getUTCMinutes() / 60;
        const g = 2 * Math.PI / 365 * (day - 1 + (hours - 12) / 24);
        const eqTime = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
                     + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        const ha = ((hours * 60 + eqTime + 4 * lon) / 4 - 180) * rad;
        const cz = Math.sin(lat * rad) * Math.sin(decl) + Math.cos(lat * rad) * Math.cos(decl) * Math.cos(ha);
        return 90 - Math.acos(Math.max(-1, Math.min(1, cz))) / rad;
    }
    // today's sunrise and sunset (sun at -0.833°), found by stepping through the day
    readonly property var sun: {
        const lat = weather && weather.lat ? weather.lat : 55.75, lon = weather && weather.lon ? weather.lon : 37.62;
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        let rise = null, set = null, prev = sunElevation(start, lat, lon);
        for (let m = 5; m <= 1440; m += 5) {
            const t = new Date(start.getTime() + m * 60000);
            const e = sunElevation(t, lat, lon);
            if (prev < -0.833 && e >= -0.833 && !rise) rise = t;
            if (prev >= -0.833 && e < -0.833) set = t;
            prev = e;
        }
        return { rise: rise, set: set, length: rise && set ? (set - rise) / 1000 : 0 };
    }
    readonly property var moon: {
        const synodic = 29.530588853;
        const age = ((now.getTime() - Date.UTC(2000, 0, 6, 18, 14)) / 86400000) % synodic;
        const i = Math.floor((age / synodic) * 8 + 0.5) % 8;
        return {
            age: age,
            light: Math.round((1 - Math.cos(2 * Math.PI * age / synodic)) / 2 * 100),
            icon: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"][i],
            name: [Tr.t("Новолуние"), Tr.t("Растущий серп"), Tr.t("Первая четверть"), Tr.t("Растущая луна"), Tr.t("Полнолуние"), Tr.t("Убывающая луна"), Tr.t("Последняя четверть"), Tr.t("Убывающий серп")][i],
        };
    }

    // WMO weather codes (Open-Meteo), same as the dock dashboard
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
    function duration(secs) {
        const h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60);
        return h > 0 ? h + Tr.t(" ч ") + m + Tr.t(" мин") : m + Tr.t(" мин");
    }
}

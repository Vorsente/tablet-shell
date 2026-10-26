// Main window: sections on the left (or as the first page), settings of the chosen section on the
// right. Tablet mode: maximized, big rows and controls, tap to open, swipe/back button to return.
// PC mode: normal window, compact rows; keyboard: ↑/↓ + Enter in the list, Ctrl+1…9 jump to a
// section, Esc back to the list, Ctrl+Q quit.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Kirigami.ApplicationWindow {
    id: app

    readonly property bool touch: backend.tabletMode
    readonly property bool pixel: uiStyle.pixel
    readonly property string home: backend.home()
    property int currentSection: -1

    title: Tr.t("Настройки планшета")
    width: Kirigami.Units.gridUnit * 56
    height: Kirigami.Units.gridUnit * 38
    minimumWidth: Kirigami.Units.gridUnit * 24
    minimumHeight: Kirigami.Units.gridUnit * 20

    Component.onCompleted: {
        if (touch) {
            showMaximized();
        }
        const start = backend.startModule();
        if (start && openModuleById(start)) {
            return;
        }
        openSection(0);
    }
    onTouchChanged: touch ? showMaximized() : showNormal()

    pageStack.defaultColumnWidth: Kirigami.Units.gridUnit * (touch ? 20 : 14)
    pageStack.initialPage: sectionsPage
    pageStack.columnView.columnResizeMode: pageStack.wideMode ? Kirigami.ColumnView.FixedColumns : Kirigami.ColumnView.SingleColumn

    // ---- storage of the individual settings ---------------------------------------------------

    function value(item) {
        switch (item.store) {
        case "kconfig": return backend.read(item.file, item.group, item.key, item.def);
        case "device": return backend.deviceMode();
        case "home": return backend.homeScreen(item.key, item.def);
        case "dashboard": return backend.containmentConfig("org.ipad.dashboard", item.key, item.def);
        case "appearance": return backend.run([home + "/.local/bin/appearance", "status"]).trim() || "auto";
        case "shellStyle": return uiStyle.name;
        case "info": return item.get();
        case "im": {
            const im = String(backend.read("kwinrc", "Wayland", "InputMethod", ""));
            return im.indexOf("tablet-keyboard") !== -1 ? "own" : im.indexOf("plasma.keyboard") !== -1 ? "plasma" : "off";
        }
        }
        return undefined;
    }

    function setValue(item, v) {
        switch (item.store) {
        case "kconfig": backend.write(item.file, item.group, item.key, v, !!item.notify); break;
        case "device": backend.setDeviceMode(v); break;
        case "home": backend.setHomeScreen(item.key, v); break;
        case "dashboard": backend.setContainmentConfig("org.ipad.dashboard", item.key, v); break;
        case "appearance": backend.start([home + "/.local/bin/appearance", v]); break;
        case "shellStyle": backend.start([home + "/.local/bin/shell-style", v]); break;
        case "im":
            backend.write("kwinrc", "Wayland", "InputMethod",
                          v === "own" ? home + "/.local/share/applications/tablet-keyboard.desktop"
                          : v === "plasma" ? "/usr/share/applications/org.kde.plasma.keyboard.desktop" : "", true);
            break;
        }
        if (item.apply === "modes") {
            backend.reapplyModes();
        } else if (item.apply === "gestures") {
            backend.reloadKWinScript("tablet-gestures");
        } else if (item.apply === "weatherAnimation") {
            backend.setHomeScreen("weatherAnimation", v);
        } else if (item.apply === "livewallpaper") {
            backend.start([home + "/.local/bin/wallpaper", "live", v ? "on" : "off"]);
            backend.setHomeScreen("liveWallpaper", v);   // weather on the wallpaper moves only then
        } else if (item.apply === "tabletshell") {
            backend.start(["systemctl", "--user", "restart", "tabletshell.service"]);
        } else if (item.apply === "homeData") {
            // the home screen fetches the weather and the news again (HomeData.reload)
            backend.setHomeScreen("dataStamp", String(Date.now()));
        } else if (item.apply === "screenlocker") {
            qdbus("org.freedesktop.ScreenSaver", "/ScreenSaver", "configure");
        }
    }

    function tabletrc(group, key, def) { return { store: "kconfig", file: "tabletrc", group: group, key: key, def: def }; }
    function typewriterrc(key, def) { return { store: "kconfig", file: "typewriterrc", group: "General", key: key, def: def }; }
    function make(base, extra) { return Object.assign({}, base, extra); }
    function dash(key, def, extra) { return Object.assign({ store: "dashboard", key: key, def: def }, extra); }
    function kbrc(key, def) { return { store: "kconfig", file: "tablet-keyboardrc", group: "General", key: key, def: def }; }
    function lockrc(group, key, def) { return { store: "kconfig", file: "tablet-lockrc", group: group, key: key, def: def }; }
    function lockerrc(key, def) { return { store: "kconfig", file: "kscreenlockerrc", group: "Daemon", key: key, def: def, apply: "screenlocker" }; }

    // the look shared by the lock and the login screen, stored per screen ([Lock] / [Login])
    function lookItems(g) {
        return [
            make(lockrc(g, "clockWeight", "bold"), { type: "choice", label: Tr.t("Часы"),
                 options: [{ value: "bold", label: Tr.t("Жирные, как на iPad") }, { value: "light", label: Tr.t("Тонкие") }] }),
            make(lockrc(g, "clock24", true), { type: "switch", label: Tr.t("24-часовой формат") }),
            make(lockrc(g, "clockScale", 100), { type: "number", min: 60, max: 140, step: 10, suffix: " %", label: Tr.t("Размер часов") }),
            make(lockrc(g, "showDate", true), { type: "switch", label: Tr.t("Дата над часами") }),
            make(lockrc(g, "dim", 25), { type: "number", min: 0, max: 60, step: 5, suffix: " %", label: Tr.t("Затемнение обоев"),
                 note: Tr.t("Чтобы часы читались на светлых обоях") }),
            make(lockrc(g, "blur", true), { type: "switch", label: Tr.t("Размытие при вводе пароля") }),
            make(lockrc(g, "blurAmount", 100), { type: "number", min: 10, max: 100, step: 10, suffix: " %", label: Tr.t("Сила размытия") }),
            make(lockrc(g, "showUser", true), { type: "switch", label: Tr.t("Имя и аватар над паролем") }),
            make(lockrc(g, "showHint", true), { type: "switch", label: Tr.t("Подсказка «Проведите вверх»"), note: Tr.t("Полоска внизу остаётся") }),
            make(lockrc(g, "osk", "auto"), { type: "choice", label: Tr.t("Экранная клавиатура"),
                 options: [{ value: "auto", label: Tr.t("При касании экрана") }, { value: "always", label: Tr.t("Всегда") }, { value: "button", label: Tr.t("Только по кнопке") }] }),
        ];
    }
    function sessionOptions() {
        return backend.run(["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do printf '%s|%s\\n' \"$f\" \"$(sed -n 's/^Name=//p' \"$f\" | head -1)\"; done"])
            .trim().split("\n").filter(l => l).map(l => ({ value: l.split("|")[0], label: l.split("|")[1] }));
    }
    function qdbus(service, path, method) { backend.start(["qdbus6", service, path, method]); }

    // news of the Today page (tablet-tools today): countries and the English Linux feeds, the same
    // ids and defaults as in tablet-tools.cpp
    readonly property var newsCountries: [
        ["ru", "🇷🇺 " + Tr.t("Россия")], ["ua", "🇺🇦 " + Tr.t("Украина")], ["kz", "🇰🇿 " + Tr.t("Казахстан")],
        ["us", "🇺🇸 " + Tr.t("США")], ["gb", "🇬🇧 " + Tr.t("Великобритания")], ["ca", "🇨🇦 " + Tr.t("Канада")],
        ["au", "🇦🇺 " + Tr.t("Австралия")], ["in", "🇮🇳 " + Tr.t("Индия")], ["de", "🇩🇪 " + Tr.t("Германия")],
        ["at", "🇦🇹 " + Tr.t("Австрия")], ["ch", "🇨🇭 " + Tr.t("Швейцария")], ["fr", "🇫🇷 " + Tr.t("Франция")],
        ["it", "🇮🇹 " + Tr.t("Италия")], ["es", "🇪🇸 " + Tr.t("Испания")], ["pt", "🇵🇹 " + Tr.t("Португалия")],
        ["br", "🇧🇷 " + Tr.t("Бразилия")], ["nl", "🇳🇱 " + Tr.t("Нидерланды")], ["pl", "🇵🇱 " + Tr.t("Польша")],
        ["cz", "🇨🇿 " + Tr.t("Чехия")], ["se", "🇸🇪 " + Tr.t("Швеция")], ["no", "🇳🇴 " + Tr.t("Норвегия")],
        ["tr", "🇹🇷 " + Tr.t("Турция")], ["il", "🇮🇱 " + Tr.t("Израиль")], ["jp", "🇯🇵 " + Tr.t("Япония")],
        ["kr", "🇰🇷 " + Tr.t("Южная Корея")],
    ].map(c => ({ value: c[0], label: c[1] }))
    readonly property var linuxEnglishFeeds: [
        ["phoronix", "Phoronix", true], ["9to5linux", "9to5Linux", true], ["lwn", "LWN.net", true],
        ["omgubuntu", "OMG! Ubuntu", false], ["itsfoss", "It's FOSS", false], ["gamingonlinux", "GamingOnLinux", false],
        ["linuxiac", "Linuxiac", false], ["planetkde", "Planet KDE", false], ["archlinux", "Arch Linux News", false],
    ]

    // ---- what can be set ------------------------------------------------------------------------

    readonly property var sections: [
        { title: Tr.t("Режимы"), icon: "tablet-symbolic", items: [
            { type: "choice", store: "device", label: Tr.t("Режим устройства"),
              note: Tr.t("«Авто» — планшет без клавиатуры, ПК с клавиатурой или док-станцией"),
              options: [{ value: "auto", label: Tr.t("Авто") }, { value: "on", label: Tr.t("Всегда планшет") }, { value: "off", label: Tr.t("Всегда ПК") }] },
            make(tabletrc("Modes", "hideTitleBars", true), { type: "switch", apply: "modes",
              label: Tr.t("Скрывать заголовки окон"), note: Tr.t("В режиме планшета окна без рамок, как приложения iPad") }),
            make(tabletrc("Modes", "maximizeWindows", true), { type: "switch", apply: "modes",
              label: Tr.t("Окна на весь экран"), note: Tr.t("В режиме планшета новые и открытые окна разворачиваются") }),
            make(tabletrc("Modes", "iphoneGestures", true), { type: "switch", apply: "modes",
              label: Tr.t("Жесты iPhone снизу"), note: Tr.t("Свайп вверх — домой, с задержкой — запущенные приложения") }),
            make(tabletrc("Modes", "singleClick", true), { type: "switch", apply: "modes",
              label: Tr.t("Открывать файлы одним касанием"), note: Tr.t("В режиме планшета; в ПК-режиме двойной щелчок") }),
            make(tabletrc("Modes", "askTypewriter", true), { type: "switch",
              label: Tr.t("Предлагать печатную машинку"), note: Tr.t("Уведомление при подключении клавиатуры") }),
            make(tabletrc("Modes", "askCoding", true), { type: "switch",
              label: Tr.t("Предлагать LazyVim"), note: Tr.t("В уведомлении при подключении клавиатуры") }),
            make(tabletrc("Modes", "changeDisplayScale", false), { type: "switch", apply: "modes",
              label: Tr.t("Менять масштаб при смене режима"), note: Tr.t("На медленных устройствах лучше оставить выключенным") }),
            make(tabletrc("Modes", "transitionAnimation", true), { type: "switch",
              label: Tr.t("Анимация смены режима"), note: Tr.t("Клавиатура, монитор, печатная машинка и чтение — с заставкой на весь экран") }),
            make(tabletrc("Modes", "transitionSound", true), { type: "switch",
              label: Tr.t("Звук смены режима"), note: Tr.t("Щелчок клавиатуры, перезвон монитора, удары клавиш печатной машинки") }),
            make(tabletrc("Effects", "chargeAnimation", true), { type: "switch",
              label: Tr.t("Анимация зарядки"), note: Tr.t("Зелёное кольцо с процентом и звук при подключении зарядки") }),
            make(tabletrc("Effects", "osd", true), { type: "switch", apply: "tabletshell",
              label: Tr.t("Индикатор громкости и яркости"), note: Tr.t("Полосы уровня вверху экрана при нажатии клавиш; по полосам можно провести пальцем") }),
            make(tabletrc("Effects", "osdPercent", true), { type: "switch",
              label: Tr.t("Проценты на индикаторе"), note: Tr.t("Число рядом с полосами громкости и яркости") }),
            make(tabletrc("Effects", "unlockSound", true), { type: "switch",
              label: Tr.t("Звук разблокировки"), note: Tr.t("Мягкий щелчок, когда экран разблокирован") }),
            make(tabletrc("Effects", "lockSound", true), { type: "switch",
              label: Tr.t("Звук блокировки"), note: Tr.t("Короткий щелчок, когда экран заблокирован") }),
        ] },
        { title: Tr.t("Внешний вид"), icon: "preferences-desktop-theme-global-symbolic", wallpapers: true, items: [
            { type: "choice", store: "shellStyle", label: Tr.t("Стиль всей оболочки"),
              note: Tr.t("Apple — исходный интерфейс. Pixel — Material Design: рабочий стол, панели, иконки, настройки, клавиатура, блокировка и вход."),
              options: [{ value: "apple", label: "Apple / iPadOS" }, { value: "pixel", label: "Google Pixel / Material Design" }] },
            { type: "choice", store: "appearance", label: Tr.t("Оформление"),
              options: [{ value: "light", label: Tr.t("Светлое") }, { value: "dark", label: Tr.t("Тёмное") }, { value: "auto", label: Tr.t("Авто (по времени)") }] },
            make(tabletrc("Appearance", "liveWallpaper", true), { type: "switch", apply: "livewallpaper",
              label: Tr.t("Живые обои"), note: Tr.t("Светлый вариант со светлой темой, тёмный — с тёмной; плавный переход") }),
            make({store:"kconfig", file:"tabletrc", group:"Appearance", key:"weatherAnimation", def:false},
                 { type: "switch", apply: "weatherAnimation", label: Tr.t("Анимированная погода на обоях"),
                   note: Tr.t("Дополнительная нагрузка на графику; выключено по умолчанию") }),
            make(tabletrc("Tray", "hideApps", true), { type: "switch", label: Tr.t("Значки приложений под стрелкой в трее"),
              note: Tr.t("Новые значки (Telegram, Claude и т.п.) сразу прячутся; закреплённые вручную остаются на виду") }),
        ] },
        { title: Tr.t("Жесты"), icon: "input-touchscreen-symbolic", items: [
            make({ store: "kconfig", file: "kwinrc", group: "Script-tablet-gestures", key: "topEdge", def: true },
                 { type: "switch", apply: "gestures", label: Tr.t("Пункт управления"), note: Tr.t("Свайп вниз от верхнего края") }),
            make({ store: "kconfig", file: "kwinrc", group: "Script-tablet-gestures", key: "leftEdge", def: true },
                 { type: "switch", apply: "gestures", label: Tr.t("Назад"), note: Tr.t("Свайп от левого края") }),
            make({ store: "kconfig", file: "kwinrc", group: "Script-tablet-gestures", key: "rightEdge", def: true },
                 { type: "switch", apply: "gestures", label: Tr.t("Центр уведомлений"), note: Tr.t("Свайп от правого края") }),
            { type: "info", store: "info", label: "Slide Over", note: Tr.t("Плавающее окно поверх остальных"), get: () => "Meta+O" },
            { type: "info", store: "info", label: "Split View", note: Tr.t("Два окна рядом"), get: () => "Meta+S" },
        ] },
        { title: Tr.t("Домашний экран"), icon: "go-home-symbolic", webApps: true, items: [
            { type: "switch", store: "home", key: "showBadges", def: true,
              label: Tr.t("Значки уведомлений"), note: Tr.t("Красный счётчик непрочитанного на иконках") },
            { type: "switch", store: "home", key: "weatherOnWallpaper", def: true, label: Tr.t("Погода на обоях"),
              note: Tr.t("Обои становятся зимними, дождливыми или туманными; с живыми обоями капли бегут по стеклу и падает снег") },
            { type: "button", label: Tr.t("Расположение иконок"), note: Tr.t("Вернуть порядок «избранное, затем по алфавиту»"),
              button: Tr.t("Сбросить"), icon: "edit-reset", action: () => resetLayoutDialog.open() },
        ] },
        { title: Tr.t("Сегодня и виджеты"), icon: "view-calendar-day-symbolic", items: [
            make(tabletrc("Weather", "source", "openmeteo"), { type: "choice", apply: "homeData", label: Tr.t("Источник погоды"),
                 note: Tr.t("Для виджетов, страницы «Сегодня», сводки и погоды на обоях. Все без ключа"),
                 options: [{ value: "openmeteo", label: "Open-Meteo" }, { value: "metno", label: "MET Norway (yr.no)" }, { value: "wttr", label: "wttr.in" }] }),
            { type: "text", store: "home", key: "weatherCity", def: "", apply: "homeData", label: Tr.t("Город для погоды"), placeholder: Tr.t("Например, Москва") },
            make(tabletrc("Today", "newsCountry", "ru"), { type: "choice", apply: "homeData", label: Tr.t("Новости страны"),
                 note: Tr.t("Россия — Лента и ТАСС, другие страны — главное из Google Новостей на языке страны"),
                 options: app.newsCountries }),
            make(tabletrc("Today", "currency", "auto"), { type: "choice", apply: "homeData", label: Tr.t("Валюта курсов"),
                 note: Tr.t("Рубль — курс ЦБ РФ, другие — ExchangeRate-API"),
                 options: [{ value: "auto", label: Tr.t("По стране новостей") }].concat(
                     ["RUB", "UAH", "KZT", "USD", "EUR", "GBP", "CHF", "PLN", "CZK", "SEK", "NOK", "TRY", "ILS", "JPY", "KRW", "CAD", "AUD", "INR", "BRL"]
                         .map(c => ({ value: c, label: c }))) }),
            make(tabletrc("Today", "customFeeds", ""), { type: "text", apply: "homeData", label: Tr.t("Свои RSS-ленты"),
                 note: Tr.t("Адреса через пробел или запятую; карточка «Моя лента»"), placeholder: "https://example.com/feed" }),
            make(tabletrc("Today", "customTitle", ""), { type: "text", apply: "homeData", label: Tr.t("Название своей ленты"),
                 placeholder: Tr.t("Моя лента") }),
            make(tabletrc("Today", "linuxLanguage", "ru"), { type: "choice", apply: "homeData", label: Tr.t("Новости Linux"),
                 options: [{ value: "ru", label: Tr.t("На русском: OpenNET, LOR") }, { value: "en", label: Tr.t("На английском") },
                           { value: "both", label: Tr.t("На обоих языках") }] }),
        ].concat(app.linuxEnglishFeeds.map(f => make(tabletrc("Today", "en_" + f[0], f[2]),
                 { type: "switch", apply: "homeData", label: f[1], note: Tr.t("Лента на английском: когда выбраны английские новости Linux") }))) },
        { title: Tr.t("Сводка"), icon: "office-chart-pie-symbolic", items: [
            { type: "info", store: "info", label: Tr.t("Где"), note: Tr.t("Встроенный экран, когда планшет в доке с внешним монитором"), get: () => "" },
            dash("w_cpu", true, { type: "switch", label: Tr.t("Процессор"), note: Tr.t("Загрузка, частота, история") }),
            dash("w_memory", true, { type: "switch", label: Tr.t("Память"), note: Tr.t("ОЗУ, zram, кнопка остановки Android") }),
            dash("w_temperature", true, { type: "switch", label: Tr.t("Температура") }),
            dash("w_claude", true, { type: "switch", label: Tr.t("Лимиты Claude") }),
            dash("w_youtube", true, { type: "switch", label: Tr.t("Подписчики YouTube") }),
            dash("w_network", true, { type: "switch", label: Tr.t("Сеть и диск") }),
            dash("w_weather", false, { type: "switch", label: Tr.t("Погода"), note: Tr.t("Источник — в разделе «Сегодня и виджеты»") }),
            dash("weatherCity", "", { type: "text", label: Tr.t("Город для погоды"), placeholder: Tr.t("Например, Москва") }),
            dash("w_media", false, { type: "switch", label: Tr.t("Сейчас играет"), note: Tr.t("Музыка и видео с управлением") }),
            dash("w_battery", false, { type: "switch", label: Tr.t("Аккумулятор"), note: Tr.t("Мощность и состояние батареи") }),
            dash("w_calendar", false, { type: "switch", label: Tr.t("Календарь") }),
            dash("w_screentime", false, { type: "switch", label: Tr.t("Экранное время за сегодня") }),
            dash("w_typewriter", false, { type: "switch", label: Tr.t("Печатная машинка"), note: Tr.t("Слова за сегодня и цель") }),
            dash("w_system", false, { type: "switch", label: Tr.t("Система"), note: Tr.t("Время работы, нагрузка, версии") }),
            dash("clock24", true, { type: "switch", label: Tr.t("24-часовой формат") }),
            dash("showNotifications", true, { type: "switch", label: Tr.t("Уведомления под часами") }),
            dash("showBattery", true, { type: "switch", label: Tr.t("Заряд под часами") }),
            dash("sampleInterval", 3, { type: "number", min: 1, max: 10, step: 1, suffix: Tr.t(" с"), label: Tr.t("Обновление показателей"),
                 note: Tr.t("Реже — меньше нагрузка на процессор") }),
            { type: "button", label: Tr.t("Подписчики YouTube"), note: Tr.t("Вход в Google для YouTube Аналитики"), button: Tr.t("Настроить"), icon: "media-playback-start",
              action: () => backend.start(["konsole", "-e", home + "/.local/bin/youtube-setup"]) },
        ] },
        { title: Tr.t("Клавиатура"), icon: "input-keyboard-virtual-symbolic", items: [
            { type: "choice", store: "im", label: Tr.t("Экранная клавиатура"),
              options: [{ value: "own", label: Tr.t("Своя (iPad)") }, { value: "plasma", label: "Plasma" }, { value: "off", label: Tr.t("Выключена") }] },
            make(kbrc("theme", "auto"), { type: "choice", label: Tr.t("Тема"),
                 options: [{ value: "auto", label: Tr.t("Как в системе") }, { value: "light", label: Tr.t("Светлая") }, { value: "dark", label: Tr.t("Тёмная") }] }),
            make(kbrc("hideWithKeyboard", true), { type: "switch", label: Tr.t("Скрывать при физической клавиатуре"),
              note: Tr.t("Док, USB или Bluetooth-клавиатура: поля ввода не открывают экранную") }),
            make(kbrc("layoutEn", true), { type: "switch", label: "English" }),
            make(kbrc("layoutRu", true), { type: "switch", label: Tr.t("Русский"), note: Tr.t("С буквами ё и ъ; глобус переключает раскладки") }),
            make(kbrc("height", 40), { type: "number", min: 25, max: 55, step: 1, suffix: " %", label: Tr.t("Высота в альбомной"), note: Tr.t("Доля высоты экрана, ширина — во весь экран") }),
            make(kbrc("heightPortrait", 26), { type: "number", min: 18, max: 45, step: 1, suffix: " %", label: Tr.t("Высота в портретной"), note: Tr.t("Подстраивается сама при повороте") }),
            make(kbrc("keyShape", "thinkpad"), { type: "choice", label: Tr.t("Форма клавиш"),
                 options: [{ value: "thinkpad", label: Tr.t("ThinkPad, с изгибом") }, { value: "rounded", label: Tr.t("Скруглённые") }] }),
            make(kbrc("split", false), { type: "switch", label: Tr.t("Разделённая клавиатура"), note: Tr.t("Или разведите и сведите двумя пальцами") }),
            make(kbrc("splitWidth", 36), { type: "number", min: 25, max: 48, step: 1, suffix: " %", label: Tr.t("Ширина половинок") }),
            make(kbrc("flicks", true), { type: "switch", label: Tr.t("Символы смахиванием вниз"), note: Tr.t("Серые символы над буквами") }),
            make(kbrc("autoCap", true), { type: "switch", label: Tr.t("Заглавная в начале предложения") }),
            make(kbrc("doubleSpace", true), { type: "switch", label: Tr.t("Точка двойным пробелом") }),
            make(kbrc("spaceTrackpad", true), { type: "switch", label: Tr.t("Пробел как тачпад"), note: Tr.t("Удерживайте пробел и ведите пальцем") }),
            make(kbrc("spaceSwipe", true), { type: "switch", label: Tr.t("Смена языка свайпом по пробелу") }),
            make(kbrc("spaceLabel", true), { type: "switch", label: Tr.t("Название языка на пробеле") }),
            make(kbrc("sound", false), { type: "switch", label: Tr.t("Звук нажатий"), note: Tr.t("Щелчок клавиш, как на iPad: буквы, удаление и пробел звучат по-разному") }),
            make(kbrc("soundVolume", 50), { type: "number", min: 10, max: 100, step: 10, suffix: " %", label: Tr.t("Громкость щелчков") }),
            { type: "button", label: Tr.t("Недавние эмодзи"), button: Tr.t("Очистить"), icon: "edit-clear-history",
              action: () => backend.write("tablet-keyboardrc", "General", "recentEmoji", "") },
            { type: "button", label: Tr.t("Предпросмотр"), note: Tr.t("Клавиатура в окне, текст никуда не вводится"), button: Tr.t("Показать"), icon: "input-keyboard-virtual",
              action: () => backend.start(["env", "TABLET_KEYBOARD_DEMO=1", home + "/.local/bin/tablet-keyboard"]) },
        ] },
        { title: Tr.t("Экран блокировки"), icon: "system-lock-screen-symbolic", items: [
            make(lockerrc("Autolock", true), { type: "switch", label: Tr.t("Блокировать автоматически") }),
            make(lockerrc("Timeout", 5), { type: "number", min: 1, max: 60, step: 1, suffix: Tr.t(" мин"), label: Tr.t("Через") }),
            make(lockerrc("LockOnResume", true), { type: "switch", label: Tr.t("Блокировать после сна") }),
            make(lockerrc("LockGrace", 5), { type: "number", min: 0, max: 300, step: 5, suffix: Tr.t(" с"), label: Tr.t("Без пароля в течение"),
                 note: Tr.t("Сразу после блокировки откроется свайпом") }),
        ].concat(lookItems("Lock")).concat([
            make(lockrc("Lock", "showNotifications", true), { type: "switch", label: Tr.t("Уведомления на экране блокировки") }),
            make(lockrc("Lock", "showMedia", true), { type: "switch", label: Tr.t("Сейчас играет"),
              note: Tr.t("Обложка, название и кнопки ⏮ ⏯ ⏭ под часами, пока играет музыка или видео") }),
            make(lockrc("Lock", "notificationText", true), { type: "switch", label: Tr.t("Показывать текст уведомлений"),
                 note: Tr.t("Иначе только приложение и «Новое уведомление»") }),
            { type: "info", store: "info", label: Tr.t("Обои"), note: Tr.t("Как на рабочем столе (Внешний вид)"), get: () => "" },
            { type: "button", label: Tr.t("Применить оформление блокировки"),
              note: Tr.t("Обновить Apple / Pixel и виджеты блокировки без изменения пароля"),
              button: Tr.t("Применить"), icon: "view-refresh",
              action: () => backend.start(["bash", home + "/.local/bin/lockscreen-sync"]) },
            { type: "button", label: Tr.t("Проверить"), note: Tr.t("Экран блокировки в тестовом режиме, закроется паролем"), button: Tr.t("Показать"), icon: "system-lock-screen",
              action: () => backend.start(["/usr/lib/kscreenlocker_greet", "--testing"]) },
        ]) },
        { title: Tr.t("Экран входа"), icon: "system-users-symbolic", items: [
            { type: "info", store: "info", label: Tr.t("Состояние"),
              get: () => backend.run(["systemctl", "is-enabled", "greetd"]).trim() === "enabled"
                         ? (backend.run(["sh", "-c", "test -w /var/lib/tablet-greeter/lock.conf && echo ok"]).trim() === "ok"
                            ? Tr.t("Свой экран входа") : Tr.t("Нужно обновить: sudo ~/.local/share/tablet-shell/system/greeter.sh"))
                         : Tr.t("Не установлен: sudo ~/.local/share/tablet-shell/system/greeter.sh") },
        ].concat(lookItems("Login")).concat([
            make(lockrc("Login", "powerButtons", true), { type: "switch", label: Tr.t("Кнопки «Сон», «Перезагрузка», «Выключить»") }),
            make(lockrc("Login", "session", "/usr/share/wayland-sessions/plasma.desktop"), { type: "choice", label: Tr.t("Сеанс"),
                 options: sessionOptions() }),
            { type: "info", store: "info", label: Tr.t("Обои"), note: Tr.t("Как на экране блокировки"), get: () => "" },
            { type: "button", label: Tr.t("Обновить системный экран входа"),
              note: Tr.t("Только для greetd tablet-shell; запросит пароль администратора"),
              button: Tr.t("Обновить"), icon: "view-refresh",
              action: () => backend.start(["konsole", "--hold", "-e", "sudo", "bash", home + "/.local/share/tablet-shell/system/greeter.sh", "--refresh"]) },
            { type: "button", label: Tr.t("Предпросмотр"), note: Tr.t("Экран входа в окне; пароль для проверки — test"), button: Tr.t("Показать"), icon: "system-users",
              action: () => backend.start(["env", "TABLET_GREETER_QML=" + home + "/.local/share/tablet-greeter",
                                           "TABLET_GREETER_LOOK=" + home + "/.config/tablet-lockrc",
                                           home + "/.local/share/tablet-greeter/tablet-greeter"]) },
        ]) },
        { title: Tr.t("Кнопки"), icon: "system-shutdown-symbolic", items: [
            make(tabletrc("PowerButton", "tapAction", "lock"), { type: "choice", label: Tr.t("Короткое нажатие"),
              options: [{ value: "lock", label: Tr.t("Заблокировать") }, { value: "suspend", label: Tr.t("Сон") }, { value: "nothing", label: Tr.t("Ничего") }] }),
            make(tabletrc("PowerButton", "holdMenu", true), { type: "switch",
              label: Tr.t("Меню питания при удержании"), note: Tr.t("Выключение, перезагрузка, сон") }),
            make(tabletrc("Buttons", "windowsClaude", true), { type: "switch", needs: "windowsButton",
              label: Tr.t("Кнопка Windows открывает Claude"), note: Tr.t("Кнопка под экраном; клавиша Win на клавиатуре по-прежнему открывает меню приложений") }),
        ] },
        { title: Tr.t("Перо"), icon: "draw-freehand-symbolic", needs: "pen", items: [
            make(tabletrc("Pen", "palmRejection", true), { type: "switch",
              label: Tr.t("Игнорировать ладонь"), note: Tr.t("Касания пальцами отключаются, пока перо у экрана") }),
            make(tabletrc("Pen", "quickNote", true), { type: "switch",
              label: Tr.t("Быстрая заметка из угла"), note: Tr.t("Провести пером от правого нижнего угла") }),
            make(tabletrc("Pen", "toolRing", true), { type: "switch",
              label: Tr.t("Кольцо инструментов"), note: Tr.t("Удерживать кнопку пера над экраном: заметка, скриншот, Krita, пипетка, запись") }),
            make(tabletrc("Pen", "button1", "quicknote"), { type: "choice", label: Tr.t("Нижняя кнопка пера"),
              note: Tr.t("Нажать, держа перо над экраном (не касаясь)"), options: [{ value: "quicknote", label: Tr.t("Быстрая заметка") }, { value: "screenshot", label: Tr.t("Снимок экрана с рисованием") }, { value: "nothing", label: Tr.t("Ничего") }] }),
            make(tabletrc("Pen", "button2", "screenshot"), { type: "choice", label: Tr.t("Верхняя кнопка пера"),
              options: [{ value: "quicknote", label: Tr.t("Быстрая заметка") }, { value: "screenshot", label: Tr.t("Снимок экрана с рисованием") }, { value: "nothing", label: Tr.t("Ничего") }] }),
            { type: "button", label: Tr.t("Заметка"), button: Tr.t("Открыть"), icon: "draw-freehand",
              action: () => backend.start([home + "/.local/bin/quick-note"]) },
        ] },
        { title: Tr.t("Печатная машинка"), icon: "document-edit-symbolic", items: [
            make(typewriterrc("dailyGoal", 500), { type: "number", min: 0, max: 5000, step: 50, suffix: Tr.t(" слов"),
              label: Tr.t("Цель на день") }),
            make(typewriterrc("sounds", true), { type: "switch", label: Tr.t("Звук клавиш") }),
            make(typewriterrc("blackWhite", true), { type: "switch", label: Tr.t("Чёрно-белая тема") }),
            make(typewriterrc("focus", true), { type: "switch", label: Tr.t("Не беспокоить во время письма") }),
            make(typewriterrc("powerSaver", true), { type: "switch", label: Tr.t("Энергосбережение во время письма") }),
            make(typewriterrc("brightness", 45), { type: "number", min: 10, max: 100, step: 5, suffix: " %",
              label: Tr.t("Яркость не выше") }),
            { type: "button", label: Tr.t("Печатная машинка"), button: Tr.t("Открыть"), icon: "document-edit",
              action: () => backend.start([home + "/.local/bin/typewriter"]) },
            { type: "button", label: Tr.t("Сценарии"), button: Tr.t("Показать папку"), icon: "folder-documents",
              action: () => backend.start(["dolphin", String(backend.read("typewriterrc", "General", "folder", home + (Tr.ru ? "/Сценарии" : "/Screenplays")))]) },
        ] },
        { title: Tr.t("Режим кодинга"), icon: "code-context-symbolic", items: [
            { type: "info", store: "info", label: "LazyVim (Neovim)", note: Tr.t("Запускается в полноэкранном терминале Konsole; установка выполняется автоматически"), get: () => "" },
            make({ store: "kconfig", file: "codingrc", group: "General", key: "focus", def: true },
                 { type: "switch", label: Tr.t("Не беспокоить во время кодинга") }),
            make({ store: "kconfig", file: "codingrc", group: "General", key: "powerSaver", def: true },
                 { type: "switch", label: Tr.t("Энергосбережение во время кодинга") }),
            make({ store: "kconfig", file: "codingrc", group: "General", key: "reduceEffects", def: true },
                 { type: "switch", label: Tr.t("Отключать эффекты рабочего стола") }),
            make({ store: "kconfig", file: "codingrc", group: "General", key: "brightness", def: 55 },
                 { type: "number", min: 10, max: 100, step: 5, suffix: " %", label: Tr.t("Яркость не выше") }),
            { type: "button", label: "LazyVim", button: Tr.t("Открыть"), icon: "applications-development",
              action: () => backend.start([home + "/.local/bin/coding-mode"]) },
            { type: "button", label: Tr.t("Проекты"), button: Tr.t("Показать папку"), icon: "folder-documents",
              action: () => backend.start(["dolphin", String(backend.read("codingrc", "General", "folder", home + (Tr.ru ? "/Проекты" : "/Projects")))]) },
        ] },
        { title: Tr.t("Режим чтения"), icon: "view-readermode-symbolic", items: [
            make(tabletrc("Reading", "temperature", 3400), { type: "number", min: 2700, max: 6500, step: 100, suffix: " K",
              label: Tr.t("Тёплый цвет экрана"), note: Tr.t("Меньше — теплее") }),
            make(tabletrc("Reading", "brightness", 50), { type: "number", min: 10, max: 100, step: 5, suffix: " %",
              label: Tr.t("Яркость не выше") }),
        ] },
        { title: Tr.t("Экранное время"), icon: "chronometer-symbolic", items: [
            { type: "button", label: Tr.t("Статистика за неделю"), button: Tr.t("Показать"), icon: "view-statistics",
              action: () => qdbus("org.ipad.TabletShell", "/", "org.ipad.TabletShell.ToggleScreenTime") },
            { type: "button", label: Tr.t("Очистить статистику"), note: Tr.t("Удалить всю историю экранного времени"),
              button: Tr.t("Очистить"), icon: "edit-clear-history", action: () => clearStatsDialog.open() },
        ] },
        { title: "Android", icon: "smartphone-symbolic", needs: "waydroid", items: [
            { type: "info", store: "info", label: Tr.t("Состояние"),
              get: () => /Session:\s*RUNNING/.test(backend.run(["waydroid", "status"])) ? Tr.t("Запущен") : Tr.t("Остановлен") },
            { type: "button", label: Tr.t("Android целиком"), button: Tr.t("Открыть"), icon: "waydroid",
              action: () => backend.start(["waydroid", "show-full-ui"]) },
            make(tabletrc("Android", "autoStopMinutes", 10), { type: "number", min: 0, max: 120, step: 5, suffix: Tr.t(" мин"),
              label: Tr.t("Останавливать без окон через"), note: Tr.t("Android сам выключится, если его окна закрыты; 0 — не останавливать") }),
            { type: "button", label: Tr.t("Остановить Android"), note: Tr.t("Освобождает память; запустится сам при открытии приложения"),
              button: Tr.t("Остановить"), icon: "media-playback-stop", action: () => backend.start(["waydroid", "session", "stop"]) },
        ] },
        { title: Tr.t("Батарея"), icon: "battery-good-symbolic", battery: true, items: [] },
        { title: Tr.t("Восстановление"), icon: "edit-undo-history-symbolic", recovery: true, items: [] },
        { title: Tr.t("Хранилище"), icon: "drive-harddisk-symbolic", storage: true, items: [
            make(tabletrc("Cleanup", "auto", true), { type: "switch", label: Tr.t("Автоочистка раз в неделю"),
              note: Tr.t("Корзина и миниатюры старше месяца, отчёты о сбоях. Загрузки не трогаются") }),
        ] },
        { title: Tr.t("Обновление"), icon: "system-software-update-symbolic", updates: true, items: [] },
        { title: Tr.t("О системе"), icon: "help-about-symbolic", items: [
            { type: "info", store: "info", label: Tr.t("Устройство"), get: () => sysinfo.model },
            { type: "info", store: "info", label: Tr.t("Процессор"), get: () => sysinfo.cpu },
            { type: "info", store: "info", label: Tr.t("Память"), get: () => sysinfo.memory },
            { type: "info", store: "info", label: Tr.t("Батарея"), get: () => sysinfo.battery },
            { type: "info", store: "info", label: Tr.t("Износ батареи"), get: () => sysinfo.batteryHealth },
            { type: "info", store: "info", label: Tr.t("Диск"), get: () => sysinfo.disk },
            { type: "info", store: "info", label: Tr.t("Система"), get: () => sysinfo.system },
            { type: "info", store: "info", label: Tr.t("Ядро"), get: () => sysinfo.kernel },
            { type: "info", store: "info", label: "Plasma", get: () => sysinfo.plasma },
            { type: "info", store: "info", label: "tablet-shell", get: () => backend.run(["cat", home + "/.local/share/tablet-shell/release"]).trim() || "—" },
        ] },
    ]
    property var sysinfo: ({})

    // the standard KDE settings modules, grouped like System Settings
    readonly property var groupIcons: ({
        "input-devices": "preferences-desktop-peripherals", "network": "preferences-system-network",
        "appearance": "preferences-desktop-theme-global", "workspace": "preferences-desktop",
        "applications": "preferences-desktop-default-applications", "personalization": "preferences-desktop-user",
        "security-privacy": "preferences-system-privacy", "regionalsettings": "preferences-desktop-locale",
        "system-administration": "preferences-system", "hardware": "preferences-devices-tree",
    })
    // Material draws the list icons as one-colour masks: KDE's coloured category icons would turn
    // into solid blobs there, so it gets symbolic ones (scripts/pixel-symbolic-icons.py copies
    // every "*-symbolic" name used here into the Pixel icon themes)
    readonly property var groupSymbolic: ({
        "input-devices": "input-keyboard-symbolic", "hardware": "computer-symbolic", "network": "network-wireless-symbolic",
        "appearance": "preferences-desktop-theme-global-symbolic", "workspace": "plasma-symbolic",
        "applications": "applications-all-symbolic", "personalization": "user-symbolic",
        "security-privacy": "security-high-symbolic", "regionalsettings": "preferences-desktop-locale-symbolic",
        "system-administration": "preferences-system-symbolic",
    })
    readonly property var kdeGroups: {
        const groups = [];
        backend.modules().forEach(m => {
            let g = groups.find(x => x.title === m.groupName);
            if (!g) {
                g = { title: m.groupName, icon: (app.pixel ? groupSymbolic[m.group] : groupIcons[m.group]) || (app.pixel ? "preferences-other-symbolic" : m.icon),
                      kde: true, modules: [] };
                groups.push(g);
            }
            g.modules.push(m);
        });
        return groups;
    }
    // what this device has (tablet-tools hardware): sections and rows with `needs` are hidden without it
    readonly property var hw: {
        try {
            return JSON.parse(backend.run([home + "/.local/bin/tablet-tools", "hardware"]));
        } catch (e) {
            return {};
        }
    }
    function present(x) {
        return !x.needs || hw[x.needs] !== false;
    }
    readonly property var allSections: sections.filter(present)
        .map(s => Object.assign({ kde: false }, s, { items: (s.items || []).filter(present) }))
        .concat(kdeGroups)

    property var currentModule: null
    property string currentModuleId: ""

    // another launch (e.g. "open display settings" from Plasma) asked for a module
    Connections {
        target: backend
        function onModuleRequested(id) {
            if (id) {
                app.openModuleById(id);
            }
            app.raise();
            app.requestActivate();
            backend.activateWindow();
        }
    }
    // started from the control center / a settings link: make sure the window is the active one
    Timer {
        running: true
        interval: 400
        onTriggered: backend.activateWindow()
    }

    function saveCurrentModule() {
        if (currentModule && currentModule.needsSave) {
            currentModule.save();
        }
        currentModule = null;
        currentModuleId = "";
    }

    function openSection(i) {
        if (i < 0 || i >= allSections.length) {
            return;
        }
        saveCurrentModule();
        if (allSections[i].title === Tr.t("О системе")) {
            sysinfo = backend.systemInfo();
        }
        currentSection = i;
        sectionList.currentIndex = i;
        // a section opened from outside ("section:…", a module id) may be far down the list
        if (sectionList.reveal) sectionList.reveal();
        while (pageStack.depth > 1) {
            pageStack.pop();
        }
        if (allSections[i].kde) {
            pageStack.push(moduleListPage, { group: allSections[i] });
        } else {
            pageStack.push(sectionPage, { section: allSections[i] });
        }
        if (!pageStack.wideMode) {
            pageStack.currentIndex = 1;
        }
    }

    // open a standard module: inside the window (QML modules) or in its own window (old ones)
    function openModule(m) {
        if (!m.qml) {
            backend.openModuleWindow(m.id);
            return;
        }
        saveCurrentModule();
        const module = backend.loadModule(m.id);
        if (!module || !module.mainUi) {
            backend.openModuleWindow(m.id);
            return;
        }
        while (pageStack.depth > 2) {
            pageStack.pop();
        }
        currentModule = module;
        currentModuleId = m.id;
        pageStack.push(module.mainUi);
        pageStack.currentIndex = pageStack.depth - 1;
    }

    // "section:Сводка" opens one of our own sections by its (Russian) title
    function openModuleById(id) {
        if (String(id).indexOf("section:") === 0) {
            const i = allSections.findIndex(x => x.title === Tr.t(String(id).slice(8)));
            if (i >= 0) {
                openSection(i);
                return true;
            }
            return false;
        }
        for (let i = 0; i < allSections.length; ++i) {
            const s = allSections[i];
            const m = s.kde ? s.modules.find(x => x.id === id) : null;
            if (m) {
                openSection(i);
                openModule(m);
                return true;
            }
        }
        return false;
    }

    // sub-pages of the open module (e.g. a Wi-Fi network's details)
    Connections {
        target: app.currentModule
        ignoreUnknownSignals: true
        function onPagePushed(page) {
            app.pageStack.push(page);
            app.pageStack.currentIndex = app.pageStack.depth - 1;
        }
        function onPageRemoved() {
            app.pageStack.pop();
        }
    }

    // Apply / Reset for modules that do not apply instantly
    footer: QQC2.ToolBar {
        visible: !!app.currentModule && app.currentModule.needsSave
        height: visible ? implicitHeight : 0
        contentItem: RowLayout {
            Item { Layout.fillWidth: true }
            QQC2.Button {
                text: Tr.t("Сбросить")
                icon.name: "edit-undo"
                // Qt 6.12: assigning undefined no longer restores the default
                Binding on implicitHeight { when: app.touch; value: Kirigami.Units.gridUnit * 2.6 }
                onClicked: app.currentModule.load()
            }
            QQC2.Button {
                text: Tr.t("Применить")
                icon.name: "dialog-ok-apply"
                // Qt 6.12: assigning undefined no longer restores the default
                Binding on implicitHeight { when: app.touch; value: Kirigami.Units.gridUnit * 2.6 }
                onClicked: app.currentModule.save()
            }
        }
    }

    // ---- keyboard (PC mode) ---------------------------------------------------------------------

    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (!pageStack.wideMode && pageStack.currentIndex > 0) {
                pageStack.currentIndex = 0;
            }
            sectionList.forceActiveFocus();
        }
    }
    Repeater {
        model: 9
        delegate: Item {
            required property int index
            Shortcut { sequence: "Ctrl+" + (index + 1); onActivated: app.openSection(index) }
        }
    }

    // ---- pages ------------------------------------------------------------------------------------

    Component {
        id: sectionsPage
        Kirigami.ScrollablePage {
            title: Tr.t("Настройки")
            ListView {
                id: list
                model: app.allSections
                currentIndex: app.currentSection
                keyNavigationEnabled: true
                focus: !app.touch
                Component.onCompleted: {
                    app.sectionListRef = list;
                    revealCurrent.start();
                }
                // once the rows are laid out: scroll the open section into view (it may have been
                // opened from outside, far down the list)
                Timer {
                    id: revealCurrent
                    interval: 250
                    onTriggered: list.positionViewAtIndex(Math.max(0, app.currentSection), ListView.Center)
                }
                function reveal() {
                    revealCurrent.restart();
                }
                Keys.onReturnPressed: app.openSection(currentIndex)
                Keys.onEnterPressed: app.openSection(currentIndex)
                // group headings drawn by the rows themselves (ListView sections duplicated the
                // heading above the current row)
                delegate: Column {
                    id: sectionRow
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    readonly property bool current: ListView.isCurrentItem
                    Kirigami.ListSectionHeader {
                        width: parent.width
                        visible: sectionRow.index === 0 || app.allSections[sectionRow.index - 1].kde !== sectionRow.modelData.kde
                        text: sectionRow.modelData.kde ? Tr.t("Система") : Tr.t("Планшет")
                    }
                    QQC2.ItemDelegate {
                    id: sectionButton
                    background: Rectangle {
                        radius: app.pixel ? Kirigami.Units.gridUnit * 1.6 : Kirigami.Units.gridUnit * 0.65
                        color: sectionRow.current
                               ? (app.pixel ? Qt.alpha(Kirigami.Theme.highlightColor, 0.26) : Kirigami.Theme.highlightColor)
                               : (sectionButton.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.08) : "transparent")
                        border.color: app.pixel && sectionRow.current ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25) : "transparent"
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    readonly property var modelData: sectionRow.modelData
                    readonly property int index: sectionRow.index
                    width: parent.width
                    implicitHeight: app.touch ? Kirigami.Units.gridUnit * (app.pixel ? 4.0 : 3.4)
                                                      : Kirigami.Units.gridUnit * (app.pixel ? 2.75 : 2)
                    highlighted: sectionRow.current
                    onClicked: app.openSection(index)
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Rectangle {
                            implicitWidth: app.touch ? Kirigami.Units.gridUnit * 2.35 : Kirigami.Units.gridUnit * 1.8
                            implicitHeight: implicitWidth
                            radius: app.pixel ? implicitHeight / 2 : implicitHeight * 0.28
                            color: app.pixel ? Qt.alpha(Kirigami.Theme.highlightColor, sectionRow.current ? 0.25 : 0.13) : "transparent"
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: parent.width * 0.57
                                height: width
                                source: modelData.icon
                                color: app.pixel ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                                isMask: app.pixel
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: modelData.title
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * (app.touch ? 1.2 : app.pixel ? 1.07 : 1)
                            font.weight: app.pixel && sectionRow.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            visible: !app.touch && index < 9
                            text: "Ctrl+" + (index + 1)
                            opacity: 0.45
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                        Kirigami.Icon {
                            visible: app.touch && !app.pageStack.wideMode
                            source: "go-next-symbolic"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth
                        }
                    }
                    }
                }
            }
        }
    }
    property var sectionListRef: null
    readonly property var sectionList: sectionListRef || { currentIndex: 0, forceActiveFocus: function () {} }

    Component {
        id: moduleListPage
        Kirigami.ScrollablePage {
            id: groupPage
            required property var group
            title: group.title
            ListView {
                model: groupPage.group.modules
                keyNavigationEnabled: true
                Keys.onReturnPressed: app.openModule(groupPage.group.modules[currentIndex])
                Keys.onEnterPressed: app.openModule(groupPage.group.modules[currentIndex])
                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    implicitHeight: app.touch ? Kirigami.Units.gridUnit * 3.4 : Kirigami.Units.gridUnit * 2
                    highlighted: modelData.id === app.currentModuleId
                    onClicked: {
                        ListView.view.currentIndex = index;
                        app.openModule(modelData);
                    }
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon {
                            source: modelData.icon
                            implicitWidth: app.touch ? Kirigami.Units.iconSizes.medium : Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: implicitWidth
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * (app.touch ? 1.15 : 1)
                            elide: Text.ElideRight
                        }
                        Kirigami.Icon {
                            visible: !modelData.qml
                            source: "window-new"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth
                            opacity: 0.6
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionPage
        Kirigami.ScrollablePage {
            id: page
            required property var section
            title: section.title

            ColumnLayout {
                spacing: app.touch ? Kirigami.Units.largeSpacing : 0

                Repeater {
                    model: page.section.items
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0
                        SettingRow {
                            item: modelData
                            settings: app
                            touch: app.touch
                        }
                        Kirigami.Separator {
                            Layout.fillWidth: true
                            visible: !app.touch && index < page.section.items.length - 1
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    active: !!page.section.wallpapers
                    visible: active
                    sourceComponent: WallpaperGrid { touch: app.touch }
                }
                Loader {
                    Layout.fillWidth: true
                    active: !!page.section.battery
                    visible: active
                    sourceComponent: BatteryPage { touch: app.touch }
                }
                Loader {
                    Layout.fillWidth: true
                    active: !!page.section.recovery
                    visible: active
                    sourceComponent: RecoveryPage { touch: app.touch }
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    active: !!page.section.updates
                    visible: active
                    sourceComponent: UpdatePage { touch: app.touch }
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    active: !!page.section.storage
                    visible: active
                    sourceComponent: StoragePage { touch: app.touch }
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    active: !!page.section.webApps
                    visible: active
                    sourceComponent: WebApps { touch: app.touch }
                }
            }
        }
    }

    // ---- confirmations ----------------------------------------------------------------------------

    Kirigami.PromptDialog {
        id: resetLayoutDialog
        title: Tr.t("Сбросить расположение иконок?")
        subtitle: Tr.t("Папки будут удалены, иконки встанут как сначала. Домашний экран перезапустится.")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: {
            backend.setHomeScreen("layout", "");
            backend.start(["systemctl", "--user", "restart", "plasma-plasmashell.service"]);
        }
    }
    Kirigami.PromptDialog {
        id: clearStatsDialog
        title: Tr.t("Очистить экранное время?")
        subtitle: Tr.t("История по дням будет удалена.")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: backend.start(["sh", "-c", "rm -f \"$HOME\"/.local/share/screentime/*.json"])
    }
}

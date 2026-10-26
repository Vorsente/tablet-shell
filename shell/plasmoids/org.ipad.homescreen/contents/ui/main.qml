// iPadOS-style home screen for the desktop: every app lives on paged grids in the user's order,
// with widgets (2x2 / 4x2 cells, WidgetTile.qml) between the icons and a Today page on the left.
// Long press enters edit mode (icons jiggle): drag to move, drop onto another icon to make a folder,
// drag an app out of an open folder to take it out. In PC mode icons are dragged with the mouse
// (widgets are not shown there).
// PC mode desktop: the files and folders of ~/Desktop (DesktopFolder.qml) instead of the apps.
import QtQuick
import QtQml
import QtQml.Models
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.plasma5support as P5Support
import org.kde.milou as Milou
import "Tr.js" as Tr

ContainmentItem {
    id: root

    // PC mode (keyboard/dock attached): Samsung DeX-like desktop with small icons in columns
    readonly property bool pcMode: Plasmoid.configuration.pcMode
    // Legacy releases reserved 88 px regardless of dock height, leaving a big gap.
    // Keep explicit custom values; the old shipped default tracks the actual dock.
    readonly property real dockReserve: [64, 72, 88].indexOf(Number(Plasmoid.configuration.dockSpace)) !== -1
                                        ? (pixel ? 80 : 72)
                                        : Math.max(0, Number(Plasmoid.configuration.dockSpace) || 0)
    // Floating Plasma dock overlaps its nominal height by a few pixels (shadow/touch area).
    // The dots must sit visibly ABOVE it, without changing a user's explicitly chosen reserve.
    readonly property real pageDotsClearance: Kirigami.Units.smallSpacing * 3
    readonly property bool pixel: Plasmoid.configuration.shellStyle === "pixel"
    readonly property bool showBadges: Plasmoid.configuration.showBadges
    readonly property string weatherCity: Plasmoid.configuration.weatherCity

    // Light/dark like iPadOS: follows the Plasma colour scheme (org.ipad.light / org.ipad.dark,
    // switched by `appearance` or by time of day). Cards, menus and sheets take their colours
    // from here; labels drawn straight on the wallpaper stay white.
    // (by the text colour: glass themes like WhiteSurLiquid give a translucent black background in
    // their light variant too)
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
    readonly property QtObject pal: QtObject {
        readonly property color card: root.pixel ? (root.dark ? "#292831" : "#F3F1FA") : root.dark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.74) : Qt.rgba(1, 1, 1, 0.72)
        // Liquid Glass: a light rim around cards in both looks
        readonly property color cardBorder: root.pixel ? (root.dark ? "#58555F" : "#D9D3E1") : root.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.65)
        readonly property color sheet: root.pixel ? (root.dark ? "#2B2932" : "#F6F2FA") : root.dark ? Qt.rgba(0.16, 0.16, 0.19, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.94)
        readonly property color sheetBorder: root.pixel ? (root.dark ? "#53505B" : "#D6D0DD") : root.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.1)
        readonly property color text: root.pixel ? (root.dark ? "#E7E1EC" : "#1D1B20") : root.dark ? "white" : "black"
        readonly property color secondary: root.pixel ? (root.dark ? "#CAC4D0" : "#625B71") : root.dark ? Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6) : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.6)
        readonly property color tertiary: root.dark ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(0, 0, 0, 0.3)
        readonly property color fill: root.pixel ? (root.dark ? "#49454F" : "#E8DEF8") : root.dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color fillStrong: root.pixel ? (root.dark ? "#605D67" : "#D0C9D9") : root.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
        readonly property color fillWeak: root.pixel ? (root.dark ? "#33313B" : "#F3EDF7") : root.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
        readonly property color control: root.pixel ? (root.dark ? "#49454F" : "#E6E0E9") : root.dark ? Qt.rgba(0.35, 0.35, 0.38, 0.95) : Qt.rgba(0.82, 0.82, 0.84, 0.95)
        readonly property color green: root.pixel ? (root.dark ? "#81C995" : "#146C2E") : root.dark ? "#30D158" : "#34C759"
        readonly property color red: root.pixel ? (root.dark ? "#F2B8B5" : "#B3261E") : root.dark ? "#FF453A" : "#FF3B30"
        readonly property color orange: root.pixel ? "#FFB86C" : root.dark ? "#FF9F0A" : "#FF9500"
        readonly property color blue: root.pixel ? (root.dark ? "#D0BCFF" : "#6750A4") : root.dark ? "#0A84FF" : "#007AFF"
        readonly property color yellow: root.pixel ? "#F9DE81" : root.dark ? "#FFD60A" : "#FFCC00"
        readonly property color purple: root.pixel ? "#B69DF8" : root.dark ? "#BF5AF2" : "#AF52DE"
        readonly property color cyan: root.pixel ? "#7EC9D9" : root.dark ? "#64D2FF" : "#32ADE6"
    }

    // ---- Material (Pixel) look -----------------------------------------------------------------
    // Roboto Flex when installed (install-material-icons.sh), else the Plasma font
    readonly property bool materialFont: Qt.fontFamilies().indexOf("Roboto Flex") >= 0
    readonly property string fontFamily: pixel && materialFont ? "Roboto Flex" : Kirigami.Theme.defaultFont.family
    // Material 3 tonal colour roles per widget kind: Pixel widgets are colourful containers, each
    // kind in its own hue, with "on" content and an accent for icons and progress.
    function tone(kind) {
        const d = dark;
        const sets = {
            primary:   d ? ["#4F378B", "#EADDFF", "#D0BCFF"] : ["#EADDFF", "#21005D", "#6750A4"],
            secondary: d ? ["#4A4458", "#E8DEF8", "#CCC2DC"] : ["#E8DEF8", "#1D192B", "#625B71"],
            tertiary:  d ? ["#633B48", "#FFD8E4", "#EFB8C8"] : ["#FFD8E4", "#31111D", "#7D5260"],
            blue:      d ? ["#0F4A73", "#D1E4FF", "#9ECAFF"] : ["#D1E4FF", "#001D36", "#1A63A0"],
            green:     d ? ["#1D4E2C", "#C2EFCB", "#8FD6A1"] : ["#C4EED0", "#072711", "#1E6C3B"],
            teal:      d ? ["#0B4F4E", "#BCEDEA", "#80D5D2"] : ["#C5ECE9", "#00201F", "#006A67"],
            orange:    d ? ["#6A3A0F", "#FFDCC2", "#FFB77C"] : ["#FFDCC2", "#2E1500", "#8B4F1C"],
            red:       d ? ["#7A2921", "#FFDAD5", "#FFB4A9"] : ["#FFDAD5", "#410001", "#A63A2E"],
            indigo:    d ? ["#2F3778", "#DFE0FF", "#BAC3FF"] : ["#DFE0FF", "#000F5C", "#4A55A2"],
            neutral:   d ? ["#2B2930", "#E6E0E9", "#D0BCFF"] : ["#ECE6F0", "#1D1B20", "#6750A4"],
        };
        const byKind = {
            weather: "blue", calendar: "primary", clock: "tertiary", battery: "green",
            typewriter: "secondary", screentime: "teal", youtube: "red", linux: "neutral",
            russia: "neutral", rates: "green", claude: "orange", onthisday: "tertiary",
            sky: "indigo", weekly: "secondary", note: "orange",
        };
        const t = sets[byKind[kind] || kind] || sets.neutral;
        return { container: t[0], on: t[1], accent: t[2] };
    }
    readonly property real glanceHeight: pixel && !pcMode ? Kirigami.Units.gridUnit * 4.4 : 0
    readonly property real searchHeight: pixel && !pcMode ? Kirigami.Units.gridUnit * 2.8 : 0

    // Grid geometry: 7 columns in landscape, 5 in portrait, as many rows as fit
    readonly property bool portrait: pages.height > pages.width
    readonly property int columns: portrait ? 5 : 7
    readonly property real cellWidth: pcMode ? Kirigami.Units.gridUnit * 5.5
                                             : Math.floor((pages.width - Kirigami.Units.gridUnit * 4) / columns)
    readonly property real cellHeight: pcMode ? Kirigami.Units.gridUnit * 5.2 : Math.min(cellWidth, Kirigami.Units.gridUnit * 9)
    readonly property int rows: Math.max(1, Math.floor((pages.height - Kirigami.Units.gridUnit) / cellHeight))
    readonly property int pageSize: columns * rows
    // DeX desktop: icons in columns, top to bottom
    readonly property int pcRows: Math.max(1, Math.floor((area.height - Kirigami.Units.largeSpacing * 2) / cellHeight))
    readonly property real iconSize: pcMode ? Kirigami.Units.gridUnit * 2.6 : Math.round(Math.min(cellWidth, cellHeight) * 0.56)

    property bool editing: false

    // ---- icon shapes (AppIcon.qml) ----------------------------------------------------------
    // Each icon is measured once from its pixels: { shape: "native" (the theme's rounded square),
    // "square" (full-bleed, gets rounded corners), "round" (a disc) or "free" (a logo, goes on a plate),
    // scale / dx / dy: how to blow the visible square up to the whole icon box }.
    property var iconShapes: ({})
    property var iconQueue: []
    // O(1) duplicate detection while hundreds of icons are being classified.
    property var iconPending: ({})
    readonly property var nativeIcon: ({ shape: "native", scale: 1, dx: 0, dy: 0 })
    // Another style means another icon theme: the old measurements put every MacTahoe icon on a
    // plate after a live Material -> Apple switch. Measure again once the new theme is loaded.
    onPixelChanged: reshapeTimer.restart()
    Timer {
        id: reshapeTimer
        interval: 1500
        onTriggered: {
            probeTimer.stop();
            iconProbe.current = "";
            iconProbe.grab = null;
            shot.source = "";
            root.iconQueue = [];
            root.iconPending = ({});
            root.iconShapes = ({});
        }
    }
    function iconShape(name) {
        if (!name) return nativeIcon;
        const known = iconShapes[name];
        if (known === undefined && !iconPending[name]) {
            iconPending[name] = true;
            iconQueue.push(name);
            Qt.callLater(iconProbe.next);
        }
        return known || nativeIcon;
    }
    function classifyIcon(d, n) {
        let minX = n, minY = n, maxX = -1, maxY = -1, opaque = 0;
        for (let y = 0; y < n; ++y) {
            for (let x = 0; x < n; ++x) {
                if (d[(y * n + x) * 4 + 3] > 128) {
                    ++opaque;
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        if (opaque === 0) return nativeIcon;
        const w = maxX - minX + 1, h = maxY - minY + 1;
        const fill = opaque / (w * h);                 // squircle ~0.95, circle 0.79, square 1
        const squareBox = Math.abs(w - h) <= n * 0.08;
        // a disc covers pi/4 = 0.785 of its box: "round" (Material icons; on a plate in the Apple look)
        const shape = squareBox && fill >= 0.975 ? "square" : squareBox && fill > 0.86 ? "native"
                    : squareBox && fill > 0.74 ? "round" : "free";
        const side = Math.max(w, h);
        return { shape: shape, scale: n / side, dx: 0.5 - (minX + maxX + 1) / 2 / n, dy: 0.5 - (minY + maxY + 1) / 2 / n };
    }
    // top of the icon grid: lower in edit mode, under the "+ Виджет" / "Готово" buttons
    readonly property real gridTop: Kirigami.Units.gridUnit * (editing ? 2.6 : 1)
    onPcModeChanged: {
        editing = false;
        openFolder = null;
    }
    property var layout: []          // see main.xml
    property var catalog: ({})       // id -> { name, icon, row }
    property var openFolder: null    // index into layout of the folder shown in the overlay

    // ---- grid placement --------------------------------------------------------------------
    // Entries fill the pages in layout order; a widget takes the first free block of its size on
    // the current page (icons after it fill the holes beside it, as on iPadOS), or starts a page.
    function isWidget(e) {
        return e !== null && typeof e === "object" && e.widget !== undefined;
    }
    function spanOf(e) {
        if (!isWidget(e)) {
            return [1, 1];
        }
        return [Math.min(columns, e.size === "wide" ? 4 : 2), Math.min(rows, 2)];
    }
    // First-fit packing with one bit mask per row. Each collision check is a
    // single integer AND, instead of walking every occupied cell of each tile.
    // Preserve the exact existing row-major first-fit layout and widget spans.
    readonly property var placement: {
        const pos = [];
        const byPage = [[]];
        let page = 0;
        let occupied = new Array(rows).fill(0);
        const fit = (w, h) => {
            const bits = (1 << w) - 1;
            for (let r = 0; r <= rows - h; ++r) {
                for (let c = 0; c <= columns - w; ++c) {
                    const mask = bits << c;
                    let free = true;
                    for (let y = r; y < r + h; ++y) {
                        if (occupied[y] & mask) { free = false; break; }
                    }
                    if (free) return [c, r];
                }
            }
            return null;
        };
        for (let i = 0; i < layout.length; ++i) {
            const [w, h] = spanOf(layout[i]);
            let at = fit(w, h);
            if (!at) {
                ++page;
                occupied.fill(0);
                byPage.push([]);
                at = [0, 0];
            }
            const mask = ((1 << w) - 1) << at[0];
            for (let y = at[1]; y < at[1] + h; ++y) occupied[y] |= mask;
            pos.push({ page: page, col: at[0], row: at[1], w: w, h: h });
            byPage[page].push(i);
        }
        return { pos: pos, byPage: byPage, pages: Math.max(1, page + 1) };
    }
    // Reuse the precomputed per-page index instead of rescanning every icon
    // on each drag movement or page render.
    function pageEntries(p) {
        return placement.byPage[p] || [];
    }
    // swipe view page of the first app page (the Today page is left of it)
    readonly property int firstAppPage: 1

    readonly property int pageCount: Math.max(1, placement.pages + (editing ? 1 : 0))

    // Pages live in a ListModel that only grows/shrinks at the end: an integer model would
    // recreate every page (and the icon under the finger) when edit mode adds the empty page,
    // which cut the drag off right after the long press.
    ListModel { id: pageModel }
    function syncPages() {
        while (pageModel.count < pageCount) {
            pageModel.append({ page: pageModel.count });
        }
        while (pageModel.count > pageCount) {
            pageModel.remove(pageModel.count - 1);
        }
    }
    onPageCountChanged: syncPages()
    Component.onCompleted: {
        syncPages();
        Qt.callLater(() => pages.setCurrentIndex(root.firstAppPage));
    }

    // widgets and the Today page: refreshed while the home screen is shown in tablet mode
    readonly property alias homeData: homeDataObject
    // weather on the wallpaper, behind everything else (tablet mode)
    WeatherEffects {
        anchors.fill: parent
        z: -1
        shown: !root.pcMode
        // Day/night wallpaper remains live; expensive moving weather is independent.
        style: !Plasmoid.configuration.weatherOnWallpaper ? "off"
             : Plasmoid.configuration.weatherAnimation ? "animated" : "static"
        wallpaper: Plasmoid.wallpaperGraphicsObject
        code: homeDataObject.weather && homeDataObject.weather.code !== undefined
              ? Number(homeDataObject.weather.code) : -1
    }

    HomeData {
        id: homeDataObject
        home: root
        active: !root.pcMode
    }
    readonly property string homeDir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace("file://", "")

    // ---- commands (web apps) ----------------------------------------------------------------

    P5Support.DataSource {
        id: executable
        engine: "executable"
        property var callbacks: ({})
        onNewData: (source, data) => {
            disconnectSource(source);
            const cb = callbacks[source];
            delete callbacks[source];
            if (cb) {
                cb(data["stdout"] || "");
            }
        }
    }

    // Run a command (argument list, shell-quoted here); `done` gets its stdout
    function runCommand(args, done) {
        const cmd = args.map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ");
        if (done) {
            executable.callbacks[cmd] = done;
        }
        executable.connectSource(cmd);
    }

    function isWebApp(id) {
        return typeof id === "string" && id.indexOf("webapp-") === 0;
    }

    function removeEntry(index) {
        const l = layout.slice();
        l.splice(index, 1);
        setLayout(l);
    }

    // a new widget goes to the start of the current home page
    function addWidget(kind, size) {
        const l = layout.slice();
        const onPage = pageEntries(Math.max(0, pages.currentIndex - firstAppPage));
        l.splice(onPage.length > 0 ? onPage[0] : l.length, 0, { widget: kind, size: size });
        setLayout(l);
    }

    function removeWebApp(id) {
        runCommand([homeDir + "/.local/bin/webapp-create", "--remove", id.replace(/\.desktop$/, "")]);
    }

    // ---- data -------------------------------------------------------------------------------

    Kicker.RootModel {
        id: rootModel
        appletInterface: root
        flat: true
        sorted: true
        showSeparators: false
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        Component.onCompleted: {
            favoritesModel.initForClient("org.ipad.homescreen.favorites");
            refresh();
        }
        onRefreshed: root.pickApps()
        onCountChanged: root.pickApps()
    }

    property var apps: null

    // The flat "All Applications" list is the root row with the most entries.
    function pickApps() {
        let best = null;
        for (let i = 0; i < rootModel.count; ++i) {
            const m = rootModel.modelForRow(i);
            if (m && (!best || m.count > best.count)) {
                best = m;
            }
        }
        apps = best;
    }

    function normalizeId(id) {
        return String(id || "").replace(/^applications:/, "");
    }

    Instantiator {
        id: appEntries
        model: root.apps
        delegate: QtObject {
            required property int index
            required property var model
            readonly property string appId: root.normalizeId(model.favoriteId)
            readonly property string name: model.display || ""
            readonly property var icon: model.decoration
        }
        onObjectAdded: Qt.callLater(root.rebuildCatalog)
        onObjectRemoved: Qt.callLater(root.rebuildCatalog)
    }

    Instantiator {
        id: favoriteEntries
        model: rootModel.favoritesModel
        delegate: QtObject {
            required property var model
            readonly property string appId: root.normalizeId(model.favoriteId)
        }
    }

    function rebuildCatalog() {
        const c = {};
        for (let i = 0; i < appEntries.count; ++i) {
            const o = appEntries.objectAt(i);
            if (o && o.appId) {
                c[o.appId] = { name: o.name, icon: o.icon, row: i };
            }
        }
        catalog = c;
        if (apps && appEntries.count === apps.count && apps.count > 0) {
            reconcile();
        }
    }

    // Drop uninstalled apps, append new ones; first run starts with the favorites, then A-Z.
    function reconcile() {
        let l = [];
        try {
            l = JSON.parse(Plasmoid.configuration.layout || "[]");
        } catch (e) {
            l = [];
        }
        const firstRun = l.length === 0;
        const seen = {};
        const out = [];
        for (const e of l) {
            if (typeof e === "string") {
                if (catalog[e] && !seen[e]) {
                    seen[e] = true;
                    out.push(e);
                }
            } else if (isWidget(e)) {
                out.push({ widget: e.widget, size: e.size === "wide" ? "wide" : "small" });
            } else if (e && e.apps) {
                const inner = e.apps.filter(a => catalog[a] && !seen[a] && (seen[a] = true));
                if (inner.length > 1) {
                    out.push({ folder: e.folder || Tr.t("Папка"), apps: inner });
                } else if (inner.length === 1) {
                    out.push(inner[0]);
                }
            }
        }
        if (firstRun) {
            for (let i = 0; i < favoriteEntries.count; ++i) {
                const id = favoriteEntries.objectAt(i)?.appId;
                if (id && catalog[id] && !seen[id]) {
                    seen[id] = true;
                    out.push(id);
                }
            }
        }
        const rest = Object.keys(catalog).filter(id => !seen[id])
            .sort((a, b) => catalog[a].name.localeCompare(catalog[b].name));
        // New Android (Waydroid) apps go into the "Android" folder instead of the pages
        const android = rest.filter(id => id.indexOf("waydroid.") === 0);
        const others = rest.filter(id => id.indexOf("waydroid.") !== 0);
        if (android.length > 0) {
            const folder = out.find(e => typeof e === "object" && e.folder === "Android");
            if (folder) {
                folder.apps = folder.apps.concat(android);
            } else if (android.length === 1) {
                others.push(android[0]);
            } else {
                out.push({ folder: "Android", apps: android });
            }
        }
        let result = out.concat(others);
        // first time with widgets: weather and the calendar at the top of the first page
        if (!Plasmoid.configuration.widgetsSeeded) {
            Plasmoid.configuration.widgetsSeeded = true;
            if (!result.some(e => isWidget(e))) {
                result = [{ widget: "weather", size: "small" }, { widget: "calendar", size: "small" }].concat(result);
            }
        }
        setLayout(result);
    }

    // the layout was changed from outside (a script, the settings app): show it
    Connections {
        target: Plasmoid.configuration
        function onLayoutChanged() {
            if (Plasmoid.configuration.layout !== JSON.stringify(root.layout) && Object.keys(root.catalog).length > 0) {
                root.reconcile();
            }
        }
    }

    function setLayout(l) {
        layout = l;
        const json = JSON.stringify(l);
        if (json !== Plasmoid.configuration.layout) {
            Plasmoid.configuration.layout = json;
        }
    }

    function launch(id, from) {
        const e = catalog[id];
        if (e && apps) {
            if (from) {
                launchZoom.start(from, e.icon);
            }
            apps.trigger(e.row, "", null);
        }
        openFolder = null;
    }

    // ---- editing ----------------------------------------------------------------------------

    property int dragFrom: -1        // layout index being dragged
    property string dragApp: ""      // or: app being dragged out of the folder at dragSrcFolder
    property int dragSrcFolder: -1
    property point dragPos: Qt.point(0, 0)
    readonly property bool dragging: dragFrom >= 0 || dragApp !== ""
    readonly property var dragEntry: dragApp !== "" ? dragApp : (dragFrom >= 0 ? layout[dragFrom] : null)

    // What is under the finger right now (drives the folder highlight)
    readonly property var dropSlot: dragging ? slotAt(dragPos) : null
    readonly property int dropIndex: dropSlot ? dropSlot.index : -1
    readonly property bool dropOnto: dropSlot ? dropSlot.onto : false

    function startDrag(index) {
        dragFrom = index;
    }

    // From an open folder: the folder fades out (it stays alive, it holds the touch) and the
    // app follows the finger over the home grid
    function startFolderDrag(folderIndex, appId) {
        dragSrcFolder = folderIndex;
        dragApp = appId;
    }

    function cancelDrag() {
        dragFrom = -1;
        dragApp = "";
        dragSrcFolder = -1;
    }

    // Layout index and "onto the icon" flag for a point in root coordinates
    function slotAt(p) {
        if (pcMode) {
            const d = deskGrid.mapToItem(root, 0, 0);
            const c = Math.max(0, Math.floor((p.x - d.x) / cellWidth));
            const r = Math.max(0, Math.min(pcRows - 1, Math.floor((p.y - d.y) / cellHeight)));
            const ddx = (p.x - d.x) - (c + 0.5) * cellWidth;
            const ddy = (p.y - d.y) - (r + 0.5) * cellHeight;
            const n = c * pcRows + r;            // position among the shown (non-widget) entries
            return {
                index: n < pcEntries.length ? pcEntries[n] : layout.length,
                onto: Math.abs(ddx) < cellWidth * 0.32 && Math.abs(ddy) < cellHeight * 0.32,
            };
        }
        const page = Math.max(0, pages.currentIndex - firstAppPage);
        const g = pages.mapToItem(root, 0, 0);
        const gridX = g.x + (pages.width - columns * cellWidth) / 2;
        const gridY = g.y + gridTop;
        const col = Math.max(0, Math.min(columns - 1, Math.floor((p.x - gridX) / cellWidth)));
        const row = Math.max(0, Math.min(rows - 1, Math.floor((p.y - gridY) / cellHeight)));
        const dx = (p.x - gridX) - (col + 0.5) * cellWidth;
        const dy = (p.y - gridY) - (row + 0.5) * cellHeight;
        const onPage = pageEntries(page);
        // the entry covering this cell
        for (const i of onPage) {
            const q = placement.pos[i];
            if (col >= q.col && col < q.col + q.w && row >= q.row && row < q.row + q.h) {
                return {
                    index: i,
                    onto: !isWidget(layout[i]) && Math.abs(dx) < cellWidth * 0.32 && Math.abs(dy) < cellHeight * 0.32,
                };
            }
        }
        // an empty cell: before the first entry placed after it, else after the page's last one
        for (const i of onPage) {
            const q = placement.pos[i];
            if (q.row > row || (q.row === row && q.col > col)) {
                return { index: i, onto: false, gap: true };
            }
        }
        if (onPage.length > 0) {
            return { index: onPage[onPage.length - 1] + 1, onto: false, gap: true };
        }
        const later = placement.pos.findIndex(q => q.page > page);
        return { index: later >= 0 ? later : layout.length, onto: false, gap: true };
    }
    // PC mode shows only icons and folders: their layout indices in order
    readonly property var pcEntries: layout.map((e, i) => i).filter(i => !isWidget(layout[i]))

    function finishDrag() {
        if (!dragging) {
            return;
        }
        let from = dragFrom;
        const app = dragApp;
        const srcFolder = dragSrcFolder;
        const s = slotAt(dragPos);
        cancelDrag();
        const l = layout.slice();
        let item;
        if (app !== "") {
            // out of a folder: the folder keeps its place (or becomes the last app left in it)
            const f = l[srcFolder];
            const inner = f.apps.filter(a => a !== app);
            l[srcFolder] = inner.length > 1 ? { folder: f.folder, apps: inner } : inner[0];
            item = app;
            from = -1;
            openFolder = null;
        } else {
            item = l[from];
        }
        if (s.onto && s.index < l.length && s.index !== from && typeof item === "string" && l[s.index] !== item
                && !isWidget(l[s.index])) {
            const target = l[s.index];
            if (typeof target === "string") {
                l[s.index] = { folder: Tr.t("Папка"), apps: [target, item] };
            } else {
                l[s.index] = { folder: target.folder, apps: target.apps.concat([item]) };
            }
            if (from >= 0) {
                l.splice(from, 1);
            }
        } else {
            let to = s.index;
            if (from >= 0) {
                l.splice(from, 1);
                // an empty cell means "before this entry": it moved down by one
                if (s.gap && from < to) {
                    to -= 1;
                }
            }
            l.splice(Math.min(to, l.length), 0, item);
        }
        setLayout(l);
    }

    // Flip pages while dragging near the left/right edge
    Timer {
        id: edgeFlip
        interval: 650
        repeat: true
        running: root.dragging && !root.pcMode
        onTriggered: {
            const edge = Kirigami.Units.gridUnit * 2;
            if (root.dragPos.x < edge && pages.currentIndex > root.firstAppPage) {
                pages.currentIndex -= 1;
            } else if (root.dragPos.x > root.width - edge && pages.currentIndex < root.pageCount - 1) {
                pages.currentIndex += 1;
            }
        }
    }

    function takeOutOfFolder(folderIndex, appId) {
        const l = layout.slice();
        const f = l[folderIndex];
        const inner = f.apps.filter(a => a !== appId);
        if (inner.length > 1) {
            l[folderIndex] = { folder: f.folder, apps: inner };
            l.splice(folderIndex + 1, 0, appId);
        } else {
            l.splice(folderIndex, 1, inner[0], appId);
            openFolder = null;
        }
        setLayout(l);
    }

    function renameFolder(folderIndex, name) {
        const l = layout.slice();
        l[folderIndex] = { folder: name || Tr.t("Папка"), apps: l[folderIndex].apps };
        setLayout(l);
    }

    // ---- view -------------------------------------------------------------------------------

    Item {
        id: area
        anchors.fill: parent
        anchors.leftMargin: root.availableScreenRect ? root.availableScreenRect.x : 0
        anchors.topMargin: root.availableScreenRect ? root.availableScreenRect.y : 0
        anchors.rightMargin: root.availableScreenRect ? parent.width - root.availableScreenRect.x - root.availableScreenRect.width : 0

        // Empty space: tap leaves edit mode; long press (or right click) opens the home menu
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            pressAndHoldInterval: 500
            onClicked: m => {
                if (m.button === Qt.RightButton) {
                    homeMenu.popup(mapToItem(root, m.x, m.y));
                } else {
                    root.editing = false;
                }
            }
            onPressAndHold: m => {
                if (!root.editing) {
                    homeMenu.popup(mapToItem(root, m.x, m.y));
                }
            }
        }

        // PC desktop: the Desktop folder's files and folders (DesktopFolder.qml), not the apps
        DesktopFolder {
            id: deskGrid
            visible: root.pcMode
            enabled: root.pcMode
            anchors.fill: parent
            home: root
            onWallpaperRequested: wallpaperPicker.show()
        }

        QQC2.SwipeView {
            id: pages
            visible: !root.pcMode
            anchors.fill: parent
            anchors.topMargin: root.glanceHeight
            anchors.bottomMargin: root.dockReserve + dots.height + root.pageDotsClearance
                                  + (root.pixel ? root.searchHeight + root.pageDotsClearance : 0)
            clip: true
            interactive: !root.editing

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                    if (d < 0) pages.incrementCurrentIndex(); else if (d > 0) pages.decrementCurrentIndex();
                }
            }

            TodayPage {
                home: root
            }

            Repeater {
                model: pageModel

                delegate: Item {
                    id: page
                    required property int index

                    // empty space of the page (under the icons); swipe down = search (Spotlight)
                    MouseArea {
                        anchors.fill: parent
                        pressAndHoldInterval: 500
                        property point start
                        onPressed: m => {
                            start = Qt.point(m.x, m.y);
                            searchField.focus = false;   // a tap beside the search bar lets it go
                        }
                        onReleased: m => {
                            if (!root.editing && m.y - start.y > Kirigami.Units.gridUnit * 4
                                    && Math.abs(m.x - start.x) < Kirigami.Units.gridUnit * 3) {
                                // Material: into the search bar at the bottom; Apple: Spotlight (KRunner)
                                if (searchBar.visible) {
                                    searchField.forceActiveFocus();
                                } else {
                                    root.runCommand(["qdbus6", "org.kde.krunner", "/App", "org.kde.krunner.App.display"]);
                                }
                            }
                        }
                        onClicked: root.editing = false
                        onPressAndHold: m => {
                            if (!root.editing) {
                                homeMenu.popup(mapToItem(root, m.x, m.y));
                            }
                        }
                    }

                    // icons and widgets at their cells (see placement)
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: root.gridTop
                        Behavior on anchors.topMargin { NumberAnimation { duration: 150 } }
                        width: root.columns * root.cellWidth
                        height: root.rows * root.cellHeight

                        Repeater {
                            model: root.pageEntries(page.index)

                            delegate: Loader {
                                id: slot
                                required property int modelData
                                readonly property var entry: root.layout[modelData]
                                readonly property var at: root.placement.pos[modelData]
                                x: at ? at.col * root.cellWidth : 0
                                y: at ? at.row * root.cellHeight : 0
                                width: at ? at.w * root.cellWidth : root.cellWidth
                                height: at ? at.h * root.cellHeight : root.cellHeight
                                sourceComponent: root.isWidget(entry) ? widgetTile : iconTile

                                Component {
                                    id: iconTile
                                    Tile {
                                        home: root
                                        entry: slot.entry
                                        layoutIndex: slot.modelData
                                    }
                                }
                                Component {
                                    id: widgetTile
                                    WidgetTile {
                                        home: root
                                        entry: slot.entry
                                        layoutIndex: slot.modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }

        // Page dots like iOS: the dot of the page under the finger stretches into a pill and slides
        // along with the swipe; a glass capsule shows behind them while swiping and in edit mode.
        // Tap or drag along the dots to jump between pages.
        Item {
            id: dots
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.dockReserve + root.pageDotsClearance
                                  + (root.pixel ? root.searchHeight + root.pageDotsClearance : 0)
            visible: pages.count > 1 && !root.pcMode
            readonly property real dot: Kirigami.Units.smallSpacing * 2
            readonly property real gap: dot * 0.9
            // page position, continuous while swiping (2.5 = halfway between pages 2 and 3)
            readonly property real pos: {
                const list = pages.contentItem;
                const step = pages.width + pages.spacing;
                return list && step > 0 ? (list.contentX - list.originX) / step : pages.currentIndex;
            }
            readonly property bool active: (pages.contentItem && pages.contentItem.moving) || scrub.pressed || root.editing
            width: row.width + dot * 2.4
            height: dot * 3

            Glass {
                anchors.fill: parent
                home: root
                visible: !root.pixel        // Material: bare dashes, no capsule
                opacity: dots.active ? 1 : 0
                scale: dots.active ? 1 : 0.85
                Behavior on opacity { NumberAnimation { duration: dots.active ? 150 : 600; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: dots.gap
                Repeater {
                    model: pages.count
                    delegate: Item {
                        required property int index
                        // the Today page gets its own glyph instead of a dot, like Spotlight on iOS
                        readonly property bool today: index < root.firstAppPage
                        // 1 on the page, falling to 0 one page away
                        readonly property real near: Math.max(0, 1 - Math.abs(dots.pos - index))
                        // Material: thin dashes, the current one long (Pixel launcher)
                        width: today ? Kirigami.Units.iconSizes.small
                             : root.pixel ? dots.dot * (1.2 + 2.4 * near) : dots.dot * (1 + 1.6 * near)
                        height: today ? width : root.pixel ? dots.dot * 0.55 : dots.dot
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.4 + 0.55 * near
                        Rectangle {
                            anchors.fill: parent
                            visible: !parent.today
                            radius: height / 2
                            color: "white"
                        }
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: parent.today
                            source: root.pixel ? "view-list-details-symbolic" : "view-calendar-day-symbolic"
                            isMask: true
                            color: "white"
                            scale: 0.9 + 0.15 * parent.near
                        }
                    }
                }
            }

            MouseArea {
                id: scrub
                anchors.fill: parent
                anchors.margins: -Kirigami.Units.smallSpacing
                function go(x) {
                    const p = mapToItem(row, x, 0).x;
                    let best = 0, dist = Infinity;
                    for (let i = 0; i < row.children.length; ++i) {
                        const c = row.children[i];
                        if (c.width === undefined || c.index === undefined) continue;
                        const d = Math.abs(c.x + c.width / 2 - p);
                        if (d < dist) { dist = d; best = c.index; }
                    }
                    if (best !== pages.currentIndex) pages.currentIndex = best;
                }
                onPressed: m => go(m.x)
                onPositionChanged: m => { if (pressed) go(m.x); }
            }
        }

        // Material: "At a glance" over the pages (date, weather, battery when it matters), like the
        // Pixel launcher
        Item {
            id: glance
            visible: root.pixel && !root.pcMode && !root.editing
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: (pages.width - root.columns * root.cellWidth) / 2 + root.cellWidth * 0.18
            height: root.glanceHeight
            // stays on the Today page too: there it is the page's date line (TodayPage has no own)
            readonly property var w: homeDataObject.weather
            readonly property var d: homeDataObject
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Kirigami.Units.smallSpacing
                Text {
                    text: {
                        const t = glance.d.now.toLocaleDateString(Tr.locale(), "ddd, d MMMM");
                        return t.charAt(0).toUpperCase() + t.slice(1);
                    }
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: Kirigami.Units.gridUnit * 1.9
                    font.weight: Font.Normal
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.25)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: pages.setCurrentIndex(0)
                    }
                }
                Row {
                    spacing: Kirigami.Units.smallSpacing * 1.5
                    Kirigami.Icon {
                        visible: !!glance.w && glance.w.code !== undefined
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: glance.w ? glance.d.weatherIcon(glance.w.code, glance.w.day) : ""
                        isMask: true
                        color: "white"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const w = glance.w;
                            let parts = [];
                            if (w && w.temp !== undefined) parts.push(Math.round(w.temp) + "°  " + glance.d.weatherInfo(w.code, w.day)[1]);
                            if (glance.d.charging && glance.d.battery >= 0) parts.push(Tr.t("Заряжается · ") + glance.d.battery + "%");
                            else if (glance.d.battery >= 0 && glance.d.battery <= 20) parts.push(Tr.t("Батарея ") + glance.d.battery + "%");
                            return parts.join("   ·   ");
                        }
                        color: "white"
                        font.family: root.fontFamily
                        font.pixelSize: Kirigami.Units.gridUnit * 0.95
                        font.weight: Font.Medium
                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.25)
                    }
                }
            }
        }

        // Material: the search bar above the dock, like the Pixel launcher's. Typing searches right
        // here (KRunner's runners through Milou): the results open upwards from the bar, the bar
        // rises above the on-screen keyboard while it is up. Enter runs the first result.
        Rectangle {
            id: searchBar
            visible: root.pixel && !root.pcMode && !root.editing
            readonly property bool searching: searchField.activeFocus || searchField.text.length > 0
            // only active while used: another window in front lets it go (the text stays, its
            // results come back with the focus)
            readonly property bool windowActive: Window.active
            onWindowActiveChanged: if (!windowActive) searchField.focus = false
            // the on-screen keyboard: KWin says whether it is up, its height is the share of the
            // screen set in tablet-keyboardrc (height = landscape, heightPortrait = portrait)
            property bool keyboardUp: false
            property real keyboardShare: 0.4
            readonly property real keyboardLift: keyboardUp && searchField.activeFocus
                                                 ? Screen.height * keyboardShare + Kirigami.Units.largeSpacing : 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(root.dockReserve + root.pageDotsClearance, keyboardLift)
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 34)
            height: root.searchHeight
            radius: height / 2
            color: root.dark ? Qt.rgba(0x2B / 255, 0x29 / 255, 0x30 / 255, 0.94) : Qt.rgba(0xEC / 255, 0xE6 / 255, 0xF0 / 255, 0.96)
            border.width: searchField.activeFocus ? 2 : 0
            border.color: root.pal.blue
            scale: searchArea.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }

            function clear() {
                searchField.text = "";
                searchField.focus = false;
            }

            // recent queries: the ones that ran a result, newest first
            readonly property var recent: {
                try {
                    const list = JSON.parse(Plasmoid.configuration.recentSearches || "[]");
                    return Array.isArray(list) ? list : [];
                } catch (e) {
                    return [];
                }
            }
            function remember(query) {
                if (query) {
                    Plasmoid.configuration.recentSearches = JSON.stringify([query].concat(recent.filter(q => q !== query)).slice(0, 8));
                }
            }

            onSearchingChanged: {
                if (searching) {
                    const portrait = Screen.height > Screen.width;
                    root.runCommand(["kreadconfig6", "--file", "tablet-keyboardrc", "--group", "General",
                                     "--key", portrait ? "heightPortrait" : "height", "--default", portrait ? "26" : "40"],
                                    out => keyboardShare = Math.max(0.15, Math.min(0.6, (parseFloat(out) || 40) / 100)));
                }
            }
            Timer {
                interval: 350
                repeat: true
                running: searchField.activeFocus
                triggeredOnStart: true
                onTriggered: root.runCommand(["qdbus6", "org.kde.KWin", "/VirtualKeyboard", "org.kde.kwin.VirtualKeyboard.visible"],
                                             out => searchBar.keyboardUp = out.trim() === "true")
                onRunningChanged: if (!running) searchBar.keyboardUp = false
            }

            MouseArea {
                id: searchArea
                anchors.fill: parent
                onClicked: searchField.forceActiveFocus()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: parent.height * 0.42
                anchors.rightMargin: parent.height * 0.42
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Layout.preferredWidth
                    source: "search-symbolic"
                    isMask: true
                    color: root.pal.blue
                }
                QQC2.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    leftPadding: 0
                    rightPadding: 0
                    placeholderText: Tr.t("Поиск приложений, файлов и в интернете")
                    placeholderTextColor: root.pal.secondary
                    color: root.pal.text
                    selectionColor: root.pal.blue
                    selectedTextColor: root.dark ? "#211A2E" : "white"
                    font.family: root.fontFamily
                    font.pixelSize: Kirigami.Units.gridUnit * 0.95
                    inputMethodHints: Qt.ImhNoPredictiveText
                    // focus only from a tap (or the swipe down), never by itself
                    focus: false
                    activeFocusOnTab: false
                    onAccepted: searchResults.runFirst()
                    Keys.onEscapePressed: searchBar.clear()
                    Keys.onUpPressed: searchResults.forceFocus()
                }
                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Layout.preferredWidth
                    source: searchBar.searching ? "edit-clear-symbolic" : "view-app-grid-symbolic"
                    isMask: true
                    color: root.pal.secondary
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Kirigami.Units.smallSpacing
                        onClicked: {
                            if (searchBar.searching) {
                                searchBar.clear();
                            } else {
                                root.runCommand(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.activateLauncherMenu"]);
                            }
                        }
                    }
                }
            }
        }

        // the search results, a sheet growing upwards from the search bar. The runners are only
        // loaded while searching (they hold memory and threads of their own).
        Loader {
            id: searchResults
            active: searchBar.visible && searchField.activeFocus && searchField.text.length > 0
            anchors.horizontalCenter: searchBar.horizontalCenter
            anchors.bottom: searchBar.top
            anchors.bottomMargin: Kirigami.Units.smallSpacing * 2
            width: searchBar.width
            height: Math.max(0, searchBar.y - Kirigami.Units.gridUnit * 2)
            function runFirst() {
                if (item) {
                    item.run(0);
                }
            }
            function forceFocus() {
                if (item) {
                    item.list.currentIndex = 0;
                    item.list.forceActiveFocus();
                }
            }
            sourceComponent: Item {
                id: resultsBox
                property alias list: results
                function run(row) {
                    if (row >= 0 && row < results.count) {
                        searchBar.remember(searchField.text.trim());
                        milou.run(milou.index(row, 0));
                        searchBar.clear();
                    }
                }
                Milou.ResultsModel {
                    id: milou
                    queryString: searchField.text
                    limit: 24
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(parent.height, results.contentHeight + Kirigami.Units.largeSpacing * 2)
                    visible: results.count > 0
                    radius: Kirigami.Units.gridUnit * 1.4
                    color: root.pal.sheet
                    border.width: 1
                    border.color: root.pal.sheetBorder
                    clip: true
                    ListView {
                        id: results
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        model: milou
                        // best match next to the bar, like the launcher
                        verticalLayoutDirection: ListView.BottomToTop
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: true
                        currentIndex: -1
                        Keys.onReturnPressed: resultsBox.run(currentIndex)
                        Keys.onEnterPressed: resultsBox.run(currentIndex)
                        Keys.onEscapePressed: searchBar.clear()
                        // bottom to top: Up goes on to the next result, Down back towards the bar
                        Keys.onDownPressed: event => {
                            if (currentIndex <= 0) {
                                searchField.forceActiveFocus();
                            } else {
                                event.accepted = false;
                            }
                        }
                        delegate: Rectangle {
                            id: result
                            required property int index
                            required property var model
                            width: ListView.view.width
                            height: Kirigami.Units.gridUnit * 2.8
                            radius: height / 2
                            color: hit.pressed || ListView.isCurrentItem ? root.pal.fill : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.largeSpacing
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing
                                Kirigami.Icon {
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                    Layout.preferredHeight: Layout.preferredWidth
                                    source: result.model.decoration || "application-x-executable"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: result.model.display || ""
                                        color: root.pal.text
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        font.family: root.fontFamily
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.9
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text.length > 0
                                        text: String(result.model.subtext || "")
                                        color: root.pal.secondary
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        font.family: root.fontFamily
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.72
                                    }
                                }
                                Text {
                                    text: String(result.model.category || "")
                                    color: root.pal.secondary
                                    font.family: root.fontFamily
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                }
                            }
                            MouseArea {
                                id: hit
                                anchors.fill: parent
                                onClicked: resultsBox.run(result.index)
                            }
                        }
                    }
                }
            }
        }

        // the empty search bar in focus: apps used most and the recent queries above it
        Loader {
            id: searchSuggestions
            active: searchBar.visible && searchField.activeFocus && searchField.text.length === 0
            anchors.horizontalCenter: searchBar.horizontalCenter
            anchors.bottom: searchBar.top
            anchors.bottomMargin: Kirigami.Units.smallSpacing * 2
            width: searchBar.width
            sourceComponent: Rectangle {
                readonly property real pad: Kirigami.Units.largeSpacing * 1.5
                height: suggestions.implicitHeight + pad * 2
                radius: Kirigami.Units.gridUnit * 1.4
                color: root.pal.sheet
                border.width: 1
                border.color: root.pal.sheetBorder
                visible: popular.count > 0 || searchBar.recent.length > 0

                Kicker.RecentUsageModel {
                    id: usage
                    shownItems: Kicker.RecentUsageModel.OnlyApps
                    ordering: Kicker.RecentUsageModel.Popular
                }
                // the most used apps that are on the home screen (they launch like their icons)
                DelegateModel {
                    id: popular
                    model: usage
                    filterOnGroup: "shown"
                    groups: DelegateModelGroup { id: shownGroup; name: "shown" }
                    items.onChanged: {
                        let shown = 0;
                        for (let i = 0; i < items.count; ++i) {
                            const id = root.normalizeId(items.get(i).model.favoriteId);
                            const keep = !!root.catalog[id] && shown < 6;
                            items.setGroups(i, 1, keep ? ["items", "shown"] : ["items"]);
                            if (keep) {
                                ++shown;
                            }
                        }
                    }
                    delegate: Item {
                        id: suggested
                        required property var model
                        readonly property string appId: root.normalizeId(model.favoriteId)
                        width: (suggestions.width - apps.spacing * 5) / 6
                        height: icon.height + label.implicitHeight + Kirigami.Units.smallSpacing
                        AppIcon {
                            id: icon
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, Kirigami.Units.gridUnit * 3.2)
                            height: width
                            home: root
                            source: root.catalog[suggested.appId] ? root.catalog[suggested.appId].icon : ""
                        }
                        Text {
                            id: label
                            anchors.top: icon.bottom
                            anchors.topMargin: Kirigami.Units.smallSpacing
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: root.catalog[suggested.appId] ? root.catalog[suggested.appId].name : ""
                            color: root.pal.text
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: Kirigami.Units.gridUnit * 0.72
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.launch(suggested.appId, icon);
                                searchBar.clear();
                            }
                        }
                    }
                }

                Column {
                    id: suggestions
                    anchors.fill: parent
                    anchors.margins: parent.pad
                    spacing: Kirigami.Units.largeSpacing

                    Text {
                        visible: popular.count > 0
                        text: Tr.t("Часто используемые")
                        color: root.pal.secondary
                        font.family: root.fontFamily
                        font.pixelSize: Kirigami.Units.gridUnit * 0.72
                        font.weight: Font.Medium
                    }
                    Row {
                        id: apps
                        visible: popular.count > 0
                        spacing: Kirigami.Units.largeSpacing
                        Repeater { model: popular }
                    }

                    Item {
                        visible: searchBar.recent.length > 0
                        width: parent.width
                        height: recentTitle.implicitHeight
                        Text {
                            id: recentTitle
                            text: Tr.t("Недавние запросы")
                            color: root.pal.secondary
                            font.family: root.fontFamily
                            font.pixelSize: Kirigami.Units.gridUnit * 0.72
                            font.weight: Font.Medium
                        }
                        Text {
                            anchors.right: parent.right
                            text: Tr.t("Очистить")
                            color: root.pal.blue
                            font.family: root.fontFamily
                            font.pixelSize: Kirigami.Units.gridUnit * 0.72
                            font.weight: Font.Medium
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Kirigami.Units.smallSpacing * 2
                                onClicked: Plasmoid.configuration.recentSearches = "[]"
                            }
                        }
                    }
                    // chips: tap = search it again
                    Flow {
                        visible: searchBar.recent.length > 0
                        width: parent.width
                        spacing: Kirigami.Units.smallSpacing * 2
                        Repeater {
                            model: searchBar.recent
                            Rectangle {
                                required property string modelData
                                width: Math.min(suggestions.width, chip.implicitWidth + Kirigami.Units.gridUnit * 2.4)
                                height: Kirigami.Units.gridUnit * 2
                                radius: height / 2
                                color: chipTap.pressed ? root.pal.fillStrong : root.pal.fill
                                Kirigami.Icon {
                                    id: clock
                                    anchors.left: parent.left
                                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    source: "document-open-recent-symbolic"
                                    isMask: true
                                    color: root.pal.secondary
                                }
                                Text {
                                    id: chip
                                    anchors.left: clock.right
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    anchors.right: parent.right
                                    anchors.rightMargin: Kirigami.Units.smallSpacing * 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData
                                    color: root.pal.text
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.8
                                }
                                MouseArea {
                                    id: chipTap
                                    anchors.fill: parent
                                    onClicked: {
                                        searchField.text = parent.modelData;
                                        searchField.forceActiveFocus();
                                        searchField.cursorPosition = searchField.text.length;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // "+" adds a widget or a web app ("Add to Home Screen")
        Row {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            visible: root.editing
            GlassButton {
                home: root
                visible: !root.pcMode
                iconName: "list-add-symbolic"
                text: Tr.t("Виджет")
                onClicked: widgetPicker.show()
            }
            GlassButton {
                home: root
                iconName: "list-add-symbolic"
                text: Tr.t("Веб-приложение")
                onClicked: webAppDialog.show()
            }
        }

        // "Done" button in edit mode, like iPadOS
        GlassButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing
            home: root
            visible: root.editing
            prominent: true
            text: Tr.t("Готово")
            onClicked: root.editing = false
        }
    }

    // measures icon shapes off screen: renders the icon, reads its pixels through a Canvas
    Item {
        id: iconProbe
        x: -200
        y: -200
        width: 64
        height: 64
        property string current: ""
        property var grab: null
        function next() {
            if (current !== "" || root.iconQueue.length === 0) return;
            current = root.iconQueue[0];
            probeTimer.restart();
        }
        function finish(shape) {
            if (current === "") return;
            const m = Object.assign({}, root.iconShapes);
            m[current] = shape;
            delete root.iconPending[current];
            root.iconQueue.shift();
            current = "";
            grab = null;
            shot.source = "";
            root.iconShapes = m;
            next();
        }
        Kirigami.Icon {
            id: probeIcon
            anchors.fill: parent
            animated: false
            roundToIconSize: false
            source: iconProbe.current
        }
        // let the icon load, then take its picture
        Timer {
            id: probeTimer
            interval: 120
            onTriggered: {
                if (!probeIcon.valid) {
                    iconProbe.finish(root.nativeIcon);
                    return;
                }
                const started = probeIcon.grabToImage(r => {
                    iconProbe.grab = r;
                    shot.source = r.url;
                }, Qt.size(64, 64));
                if (!started) {
                    // window not shown yet (login): try again in a moment
                    interval = 2000;
                    restart();
                } else {
                    interval = 120;
                }
            }
        }
        Image {
            id: shot
            x: 70
            width: 64
            height: 64
            cache: false
            onStatusChanged: {
                if (status === Image.Ready) probeCanvas.requestPaint();
                else if (status === Image.Error) iconProbe.finish(root.nativeIcon);
            }
        }
        Canvas {
            id: probeCanvas
            x: 140
            width: 64
            height: 64
            onPaint: {
                if (shot.status !== Image.Ready || iconProbe.current === "") return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, 64, 64);
                ctx.drawImage(shot, 0, 0, 64, 64);
                iconProbe.finish(root.classifyIcon(ctx.getImageData(0, 0, 64, 64).data, 64));
            }
        }
    }

    // Icon following the finger while dragging
    Item {
        id: ghost
        visible: root.dragging
        readonly property var span: root.spanOf(root.dragEntry)
        width: root.cellWidth * span[0]
        height: root.cellHeight * span[1]
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        z: 10
        scale: 1.12
        opacity: 0.9

        TileFace {
            anchors.centerIn: parent
            visible: !root.isWidget(root.dragEntry)
            home: root
            entry: visible ? root.dragEntry : null
        }
        HomeWidget {
            anchors.fill: parent
            anchors.margins: root.cellWidth * 0.1
            visible: root.isWidget(root.dragEntry)
            home: root
            kind: visible ? root.dragEntry.widget : ""
            wide: visible && root.dragEntry.size === "wide"
        }
    }

    FolderOverlay {
        anchors.fill: parent
        z: 20
        home: root
    }

    HomeMenu {
        id: homeMenu
        anchors.fill: parent
        z: 25
        home: root
        onWallpaperRequested: wallpaperPicker.show()
        onWebAppRequested: webAppDialog.show()
        onNewFolderRequested: deskGrid.create(true)
        onNewFileRequested: deskGrid.create(false)
    }

    WallpaperPicker {
        id: wallpaperPicker
        anchors.fill: parent
        z: 30
        home: root
    }

    WidgetPicker {
        id: widgetPicker
        anchors.fill: parent
        anchors.bottomMargin: root.dockReserve
        z: 30
        home: root
    }

    WebAppDialog {
        id: webAppDialog
        anchors.fill: parent
        z: 30
        home: root
    }

    // App launch, like iPadOS: a card with the app's icon grows from the tapped icon to the whole
    // screen; the app's window then opens over it. If no window covers it in time, it fades away.
    Item {
        id: launchZoom
        anchors.fill: parent
        z: 40
        visible: card.opacity > 0
        property rect from: Qt.rect(0, 0, 1, 1)
        property real p: 0           // 0 = the icon, 1 = full screen
        property var icon: ""

        function start(item, icon) {
            const r = item.mapToItem(launchZoom, 0, 0, item.width, item.height);
            from = Qt.rect(r.x, r.y, r.width, r.height);
            launchZoom.icon = icon;
            grow.stop();
            fade.stop();
            p = 0;
            card.opacity = 1;
            grow.start();
            giveUp.restart();
        }

        Rectangle {
            id: card
            opacity: 0
            // Animate a fixed-size card using the scenegraph transform, rather than
            // resizing an image/item tree on each frame (CPU layout + GPU uploads).
            x: (launchZoom.width - width) / 2
            y: (launchZoom.height - height) / 2
            width: launchZoom.width
            height: launchZoom.height
            transform: [
                Translate {
                    x: (launchZoom.from.x + launchZoom.from.width / 2 - launchZoom.width / 2) * (1 - launchZoom.p)
                    y: (launchZoom.from.y + launchZoom.from.height / 2 - launchZoom.height / 2) * (1 - launchZoom.p)
                },
                Scale {
                    origin.x: card.width / 2
                    origin.y: card.height / 2
                    xScale: Math.max(0.01, launchZoom.from.width / Math.max(1, launchZoom.width)) * (1 - launchZoom.p) + launchZoom.p
                    yScale: Math.max(0.01, launchZoom.from.height / Math.max(1, launchZoom.height)) * (1 - launchZoom.p) + launchZoom.p
                }
            ]
            radius: root.pixel ? 32 * (1 - launchZoom.p) : 22 * (1 - launchZoom.p)
            color: root.pixel ? root.pal.card : "#1c1c1e"
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.min(136, launchZoom.width * 0.22)
                height: width
                source: launchZoom.icon
            }
            // the app takes a while: a quiet spinner under the icon
            PC3.BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: launchZoom.from.width
                running: launchZoom.p === 1 && card.opacity === 1
                visible: running && slow.ready
                Timer { id: slow; property bool ready: false; interval: 1200; running: launchZoom.p === 1; onRunningChanged: ready = false; onTriggered: ready = true }
            }
        }
        NumberAnimation { id: grow; target: launchZoom; property: "p"; to: 1; duration: 280; easing.type: Easing.OutCubic }
        // back home (the desktop is active again) or a tap: away with it
        Connections {
            target: launchZoom.Window.window
            function onActiveChanged() {
                if (launchZoom.Window.window.active && launchZoom.p === 1 && card.opacity === 1) {
                    fade.start();
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: card.opacity > 0
            onClicked: fade.start()
        }
        // the app window is over it by now; if not (slow start, other screen) fade it out
        Timer { id: giveUp; interval: 1800; onTriggered: fade.start() }
        NumberAnimation { id: fade; target: card; property: "opacity"; to: 0; duration: 300 }
    }
}

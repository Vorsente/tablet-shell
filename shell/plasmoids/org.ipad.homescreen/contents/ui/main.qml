// iPadOS-style home screen for the desktop: every app lives on paged grids in the user's order,
// with widgets (2x2 / 4x2 cells, WidgetTile.qml) between the icons and a Today page on the left.
// Long press enters edit mode (icons jiggle): drag to move, drop onto another icon to make a folder,
// drag an app out of an open folder to take it out. In PC mode icons are dragged with the mouse
// (widgets are not shown there).
import QtQuick
import QtQml
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.plasma5support as P5Support
import "Tr.js" as Tr

ContainmentItem {
    id: root

    // PC mode (keyboard/dock attached): Samsung DeX-like desktop with small icons in columns
    readonly property bool pcMode: Plasmoid.configuration.pcMode
    readonly property bool showBadges: Plasmoid.configuration.showBadges
    readonly property string weatherCity: Plasmoid.configuration.weatherCity

    // Light/dark like iPadOS: follows the Plasma colour scheme (org.ipad.light / org.ipad.dark,
    // switched by `appearance` or by time of day). Cards, menus and sheets take their colours
    // from here; labels drawn straight on the wallpaper stay white.
    // (by the text colour: glass themes like WhiteSurLiquid give a translucent black background in
    // their light variant too)
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
    readonly property QtObject pal: QtObject {
        readonly property color card: root.dark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.74) : Qt.rgba(1, 1, 1, 0.72)
        readonly property color cardBorder: root.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color sheet: root.dark ? Qt.rgba(0.16, 0.16, 0.19, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.94)
        readonly property color sheetBorder: root.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.1)
        readonly property color text: root.dark ? "white" : "black"
        readonly property color secondary: root.dark ? Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6) : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.6)
        readonly property color tertiary: root.dark ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(0, 0, 0, 0.3)
        readonly property color fill: root.dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color fillStrong: root.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
        readonly property color fillWeak: root.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
        readonly property color control: root.dark ? Qt.rgba(0.35, 0.35, 0.38, 0.95) : Qt.rgba(0.82, 0.82, 0.84, 0.95)
        readonly property color green: root.dark ? "#30D158" : "#34C759"
        readonly property color red: root.dark ? "#FF453A" : "#FF3B30"
        readonly property color orange: root.dark ? "#FF9F0A" : "#FF9500"
        readonly property color blue: root.dark ? "#0A84FF" : "#007AFF"
        readonly property color yellow: root.dark ? "#FFD60A" : "#FFCC00"
        readonly property color purple: root.dark ? "#BF5AF2" : "#AF52DE"
        readonly property color cyan: root.dark ? "#64D2FF" : "#32ADE6"
    }

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
    readonly property var placement: {
        const pos = [];
        let page = 0;
        let occ = [];
        const free = (c, r, w, h) => {
            if (c + w > columns || r + h > rows) return false;
            for (let y = r; y < r + h; ++y)
                for (let x = c; x < c + w; ++x)
                    if (occ[y * columns + x]) return false;
            return true;
        };
        const fit = (w, h) => {
            for (let r = 0; r < rows; ++r)
                for (let c = 0; c < columns; ++c)
                    if (free(c, r, w, h)) return [c, r];
            return null;
        };
        for (let i = 0; i < layout.length; ++i) {
            const [w, h] = spanOf(layout[i]);
            let at = fit(w, h);
            if (!at) {
                ++page;
                occ = [];
                at = [0, 0];
            }
            for (let y = at[1]; y < at[1] + h; ++y)
                for (let x = at[0]; x < at[0] + w; ++x)
                    occ[y * columns + x] = true;
            pos.push({ page: page, col: at[0], row: at[1], w: w, h: h });
        }
        return { pos: pos, pages: layout.length > 0 ? page + 1 : 1 };
    }
    function pageEntries(p) {
        const out = [];
        for (let i = 0; i < placement.pos.length; ++i) {
            if (placement.pos[i].page === p) {
                out.push(i);
            }
        }
        return out;
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
        style: !Plasmoid.configuration.weatherOnWallpaper ? "off"
             : Plasmoid.configuration.liveWallpaper ? "animated" : "static"
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

        // DeX desktop: every icon in columns from the top-left corner
        Grid {
            id: deskGrid
            visible: root.pcMode
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: Kirigami.Units.largeSpacing
            flow: Grid.TopToBottom
            rows: root.pcRows

            Repeater {
                model: root.pcMode ? root.pcEntries : []
                delegate: Tile {
                    required property int modelData
                    home: root
                    entry: root.layout[modelData]
                    layoutIndex: modelData
                }
            }
        }

        QQC2.SwipeView {
            id: pages
            visible: !root.pcMode
            anchors.fill: parent
            anchors.bottomMargin: Plasmoid.configuration.dockSpace + dots.height
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
                        onPressed: m => start = Qt.point(m.x, m.y)
                        onReleased: m => {
                            if (!root.editing && m.y - start.y > Kirigami.Units.gridUnit * 4
                                    && Math.abs(m.x - start.x) < Kirigami.Units.gridUnit * 3) {
                                root.runCommand(["qdbus6", "org.kde.krunner", "/App", "org.kde.krunner.App.display"]);
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

        QQC2.PageIndicator {
            id: dots
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Plasmoid.configuration.dockSpace
            count: pages.count
            currentIndex: pages.currentIndex
            interactive: root.editing
            visible: count > 1 && !root.pcMode
            onCurrentIndexChanged: if (interactive) pages.currentIndex = currentIndex
            delegate: Item {
                required property int index
                // the Today page gets its own glyph instead of a dot, like Spotlight on iOS
                readonly property bool today: index < root.firstAppPage
                implicitWidth: today ? Kirigami.Units.iconSizes.small : Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                opacity: index === pages.currentIndex ? 0.95 : 0.4
                Rectangle {
                    anchors.fill: parent
                    visible: !parent.today
                    radius: width / 2
                    color: "white"
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: parent.today
                    source: "view-calendar-day-symbolic"
                    isMask: true
                    color: "white"
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
            PC3.Button {
                visible: !root.pcMode
                icon.name: "list-add"
                text: Tr.t("Виджет")
                onClicked: widgetPicker.show()
            }
            PC3.Button {
                icon.name: "list-add"
                text: Tr.t("Веб-приложение")
                onClicked: webAppDialog.show()
            }
        }

        // "Done" button in edit mode, like iPadOS
        PC3.Button {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing
            visible: root.editing
            text: Tr.t("Готово")
            onClicked: root.editing = false
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
        anchors.bottomMargin: Plasmoid.configuration.dockSpace
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
            x: launchZoom.from.x * (1 - launchZoom.p)
            y: launchZoom.from.y * (1 - launchZoom.p)
            width: launchZoom.from.width + (launchZoom.width - launchZoom.from.width) * launchZoom.p
            height: launchZoom.from.height + (launchZoom.height - launchZoom.from.height) * launchZoom.p
            radius: launchZoom.from.width * 0.22 * (1 - launchZoom.p)
            color: "#1c1c1e"
            Kirigami.Icon {
                anchors.centerIn: parent
                width: launchZoom.from.width * (1 + launchZoom.p * 0.6)
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
        NumberAnimation { id: grow; target: launchZoom; property: "p"; to: 1; duration: 380; easing.type: Easing.OutCubic }
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
        Timer { id: giveUp; interval: 4500; onTriggered: fade.start() }
        NumberAnimation { id: fade; target: card; property: "opacity"; to: 0; duration: 300 }
    }
}

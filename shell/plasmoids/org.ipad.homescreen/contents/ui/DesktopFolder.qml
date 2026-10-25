// PC mode desktop: the files and folders of the Desktop folder (XDG, ~/Desktop), in columns from
// the top-left corner like a classic desktop. Apps do not appear here by themselves; a .desktop
// file put into the folder shows as its app.
//   selection: click, Ctrl+click (add/remove), Shift+click (range), a rubber band dragged over
//              empty space, Ctrl+A; Esc clears it
//   open:      double click or Enter
//   keys:      F2 rename, Delete to the trash, Ctrl+C / Ctrl+X / Ctrl+V through the clipboard
//              (text/uri-list, so files copied in Dolphin paste here and the other way round)
//   menus:     right click on files (open, open in Dolphin / terminal, cut / copy, copy path,
//              duplicate, rename, compress, trash, properties) and on empty space (new folder /
//              text file, paste, select all, sort, open the folder in Dolphin / terminal,
//              wallpaper, display settings, system settings)
// New items are named "Новая папка", "Новая папка 2"… and renamed in place.
import QtQuick
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: desk

    required property var home
    signal wallpaperRequested()

    readonly property string dir: String(StandardPaths.writableLocation(StandardPaths.DesktopLocation)).replace("file://", "")
    property var selection: ({})      // file name -> true
    property string anchorName: ""    // where Shift+click ranges start
    property string renaming: ""      // file name being renamed in place
    property string pendingRename: "" // created a moment ago: rename once the model shows it
    property string sortBy: "name"    // name | time | size | type
    readonly property int selectedCount: Object.keys(selection).length

    focus: true

    // ---- selection --------------------------------------------------------------------------
    function isSelected(name) {
        return selection[name] === true;
    }
    function selectOnly(name) {
        const s = {};
        if (name) s[name] = true;
        selection = s;
        anchorName = name;
    }
    function toggle(name) {
        const s = Object.assign({}, selection);
        if (s[name]) delete s[name]; else s[name] = true;
        selection = s;
        anchorName = name;
    }
    function selectRange(name) {
        const all = names();
        const a = all.indexOf(anchorName), b = all.indexOf(name);
        if (a === -1 || b === -1) {
            selectOnly(name);
            return;
        }
        const s = {};
        for (let i = Math.min(a, b); i <= Math.max(a, b); ++i) s[all[i]] = true;
        selection = s;
    }
    function selectAll() {
        const s = {};
        for (const n of names()) s[n] = true;
        selection = s;
    }
    function clearSelection() {
        selection = {};
        anchorName = "";
    }
    function selectedNames() {
        return names().filter(n => selection[n]);
    }
    // the cell of the index-th item, in desk coordinates (the grid fills columns top to bottom)
    function cellRect(i) {
        const rows = home.pcRows;
        return Qt.rect(grid.x + Math.floor(i / rows) * home.cellWidth, grid.y + (i % rows) * home.cellHeight,
                       home.cellWidth, home.cellHeight);
    }
    function selectInBand(r, add) {
        const s = add ? Object.assign({}, bandBase) : {};
        const all = names();
        for (let i = 0; i < all.length; ++i) {
            const c = cellRect(i);
            // the icon and label part of the cell, not its empty margins
            const ix = c.x + c.width * 0.12, iw = c.width * 0.76;
            if (ix < r.x + r.width && ix + iw > r.x && c.y < r.y + r.height && c.y + c.height * 0.9 > r.y) {
                s[all[i]] = true;
            }
        }
        selection = s;
    }
    property var bandBase: ({})

    // ---- files --------------------------------------------------------------------------------
    function path(name) {
        return dir + "/" + name;
    }
    function names() {
        const out = [];
        for (let i = 0; i < folder.count; ++i) {
            out.push(folder.get(i, "fileName"));
        }
        return out;
    }
    function freeName(base, ext) {
        const taken = names();
        let n = 1, name = base + ext;
        while (taken.indexOf(name) !== -1) {
            name = base + " " + (++n) + ext;
        }
        return name;
    }
    function create(isFolder) {
        const name = isFolder ? freeName(Tr.t("Новая папка"), "") : freeName(Tr.t("Новый файл"), ".txt");
        pendingRename = name;
        selectOnly(name);
        home.runCommand(["mkdir", "-p", dir]);
        home.runCommand(isFolder ? ["mkdir", path(name)] : ["touch", path(name)]);
    }
    function open(list) {
        // kioclient: the default app for a file, the app itself for a .desktop file
        for (const n of list) home.runCommand(["kioclient", "exec", path(n)]);
    }
    function rename(from, to) {
        renaming = "";
        to = to.trim();
        if (!to || to === from || to.indexOf("/") !== -1 || to === "." || to === ".." || names().indexOf(to) !== -1) {
            return;
        }
        selectOnly(to);
        home.runCommand(["mv", "-n", path(from), path(to)]);
    }
    function trash(list) {
        for (const n of list) home.runCommand(["kioclient", "move", path(n), "trash:/"]);
        clearSelection();
    }
    function duplicate(list) {
        for (const n of list) {
            const dot = n.lastIndexOf(".");
            const base = dot > 0 ? n.slice(0, dot) : n, ext = dot > 0 ? n.slice(dot) : "";
            home.runCommand(["cp", "-a", "-n", path(n), path(freeName(base + " " + Tr.t("копия"), ext))]);
        }
    }
    function compress(list) {
        if (list.length > 0) {
            // ark: one archive next to the files, named after the first one
            home.runCommand(["ark", "--batch", "--add", "--autofilename", "zip", "--changetofirstpath"].concat(list.map(path)));
        }
    }
    // clipboard: text/uri-list (what Dolphin reads and writes); a cut is marked the KDE way
    function copy(list, cut) {
        if (list.length === 0) return;
        const uris = list.map(n => "file://" + encodeURI(path(n))).join("\r\n");
        home.runCommand(["sh", "-c", 'printf "%s" "$1" | wl-copy -t text/uri-list', "sh", uris]);
        cutNames = cut ? list.slice() : [];
    }
    property var cutNames: []
    function paste() {
        home.runCommand(["wl-paste", "-n", "-t", "text/uri-list"], out => {
            const srcs = out.split(/\r?\n/).filter(u => u.indexOf("file://") === 0).map(u => decodeURI(u.slice(7)));
            if (srcs.length === 0) return;
            const move = cutNames.length > 0;
            for (const src of srcs) {
                if (src.replace(/\/[^/]*$/, "") === dir && !move) {
                    duplicate([src.split("/").pop()]);   // pasted onto itself: a copy beside it
                } else if (src.replace(/\/[^/]*$/, "") !== dir) {
                    home.runCommand(move ? ["mv", "-n", src, dir + "/"] : ["cp", "-a", "-n", src, dir + "/"]);
                }
            }
            if (move) {
                cutNames = [];
                home.runCommand(["wl-copy", "--clear"]);
            }
        });
    }
    function copyPaths(list) {
        home.runCommand(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", list.map(path).join("\n")]);
    }
    function showInDolphin(list) {
        home.runCommand(list.length > 0 ? ["dolphin", "--select"].concat(list.map(path)) : ["dolphin", dir]);
    }
    function terminalAt(where) {
        home.runCommand(["konsole", "--workdir", where]);
    }
    function properties(list) {
        for (const n of (list.length > 0 ? list : [""])) {
            home.runCommand(["kioclient", "openProperties", n ? path(n) : dir]);
        }
    }

    Keys.onPressed: e => {
        if (renaming) {
            return;
        }
        const ctrl = e.modifiers & Qt.ControlModifier;
        const sel = selectedNames();
        if (ctrl && e.key === Qt.Key_A) {
            selectAll();
        } else if (ctrl && e.key === Qt.Key_C) {
            copy(sel, false);
        } else if (ctrl && e.key === Qt.Key_X) {
            copy(sel, true);
        } else if (ctrl && e.key === Qt.Key_V) {
            paste();
        } else if (e.key === Qt.Key_Escape) {
            clearSelection();
        } else if (e.key === Qt.Key_F2 && sel.length === 1) {
            renaming = sel[0];
        } else if (e.key === Qt.Key_Delete && sel.length > 0) {
            trash(sel);
        } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && sel.length > 0) {
            open(sel);
        } else {
            return;
        }
        e.accepted = true;
    }

    FolderListModel {
        id: folder
        folder: "file://" + desk.dir
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: desk.sortBy === "time" ? FolderListModel.Time : desk.sortBy === "size" ? FolderListModel.Size
                 : desk.sortBy === "type" ? FolderListModel.Type : FolderListModel.Name
        sortReversed: desk.sortBy === "time" || desk.sortBy === "size"   // newest / biggest first
        onCountChanged: {
            if (desk.pendingRename && desk.names().indexOf(desk.pendingRename) !== -1) {
                desk.renaming = desk.pendingRename;
                desk.pendingRename = "";
            }
            // forget what is gone
            const all = desk.names();
            const s = {};
            for (const n in desk.selection) if (all.indexOf(n) !== -1) s[n] = true;
            desk.selection = s;
        }
    }

    // icon by kind: folders, pictures (their own thumbnail), the app of a .desktop file, mime icons
    function iconFor(name, isDir) {
        if (isDir) {
            return "folder";
        }
        const ext = name.indexOf(".") > 0 ? name.split(".").pop().toLowerCase() : "";
        const icons = {
            txt: "text-plain", md: "text-markdown", pdf: "application-pdf", odt: "application-vnd.oasis.opendocument.text",
            doc: "application-msword", docx: "application-vnd.openxmlformats-officedocument.wordprocessingml.document",
            ods: "application-vnd.oasis.opendocument.spreadsheet", xls: "application-vnd.ms-excel",
            xlsx: "application-vnd.openxmlformats-officedocument.spreadsheetml.sheet", csv: "text-csv",
            epub: "application-epub+zip", zip: "application-zip", gz: "application-x-compressed-tar",
            xz: "application-x-xz-compressed-tar", "7z": "application-x-7z-compressed", rar: "application-x-rar",
            mp3: "audio-x-generic", ogg: "audio-x-generic", flac: "audio-x-generic", wav: "audio-x-generic",
            mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic", avi: "video-x-generic",
            sh: "application-x-shellscript", py: "text-x-python", html: "text-html", json: "application-json",
            iso: "application-x-cd-image", apk: "application-vnd.android.package-archive",
        };
        return icons[ext] || "text-x-generic";
    }

    // ---- empty space: click clears, drag draws the rubber band, right click opens the menu ----
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point start
        property bool banding: false
        onPressed: m => {
            desk.forceActiveFocus();
            if (m.button === Qt.RightButton) {
                if (!(m.modifiers & Qt.ControlModifier)) desk.clearSelection();
                deskMenu.popup();
                return;
            }
            start = Qt.point(m.x, m.y);
            banding = false;
            desk.bandBase = (m.modifiers & Qt.ControlModifier) ? Object.assign({}, desk.selection) : {};
            if (!(m.modifiers & Qt.ControlModifier)) desk.clearSelection();
        }
        onPositionChanged: m => {
            if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
            if (!banding && Math.hypot(m.x - start.x, m.y - start.y) < 6) return;
            banding = true;
            band.x = Math.min(start.x, m.x);
            band.y = Math.min(start.y, m.y);
            band.width = Math.abs(m.x - start.x);
            band.height = Math.abs(m.y - start.y);
            desk.selectInBand(Qt.rect(band.x, band.y, band.width, band.height), true);
        }
        onReleased: banding = false
        onCanceled: banding = false

        Rectangle {
            id: band
            visible: parent.banding
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            radius: 3
            z: 10
        }
    }

    Grid {
        id: grid
        x: Kirigami.Units.largeSpacing
        y: Kirigami.Units.largeSpacing
        flow: Grid.TopToBottom
        rows: desk.home.pcRows

        Repeater {
            model: folder
            delegate: Item {
                id: item
                required property string fileName
                required property bool fileIsDir
                required property url fileUrl

                readonly property string suffix: fileName.indexOf(".") > 0 ? fileName.split(".").pop().toLowerCase() : ""
                readonly property bool picture: ["png", "jpg", "jpeg", "webp", "gif", "svg", "bmp"].indexOf(suffix) !== -1
                readonly property bool selected: desk.isSelected(fileName)
                readonly property bool cut: desk.cutNames.indexOf(fileName) !== -1
                property string appName: ""
                property string appIcon: ""

                width: desk.home.cellWidth
                height: desk.home.cellHeight
                opacity: cut ? 0.5 : 1

                // a .desktop file shows as its app (Name= and Icon=)
                Component.onCompleted: {
                    if (suffix === "desktop") {
                        desk.home.runCommand(["grep", "-m2", "-E", "^(Name|Icon)=", desk.path(fileName)], out => {
                            for (const line of out.split("\n")) {
                                if (line.indexOf("Name=") === 0) appName = line.slice(5);
                                if (line.indexOf("Icon=") === 0) appIcon = line.slice(5);
                            }
                        });
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Kirigami.Units.smallSpacing * 2
                    color: item.selected ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35)
                                         : Qt.rgba(1, 1, 1, hover.hovered ? 0.1 : 0)
                    border.width: item.selected ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                }

                ColumnLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Kirigami.Units.smallSpacing
                    width: parent.width - Kirigami.Units.smallSpacing * 2
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: desk.home.iconSize
                        implicitHeight: desk.home.iconSize
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !item.picture
                            source: item.suffix === "desktop" ? (item.appIcon || "application-x-executable")
                                                              : desk.iconFor(item.fileName, item.fileIsDir)
                        }
                        Image {
                            anchors.fill: parent
                            visible: item.picture
                            source: item.picture ? item.fileUrl : ""
                            sourceSize.width: desk.home.iconSize * 2
                            sourceSize.height: desk.home.iconSize * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        visible: desk.renaming !== item.fileName
                        text: item.suffix === "desktop" && item.appName ? item.appName : item.fileName
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: item.selected && desk.selectedCount === 1 ? 4 : 2
                        elide: Text.ElideRight
                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.45)
                    }
                    PC3.TextField {
                        Layout.fillWidth: true
                        visible: desk.renaming === item.fileName
                        horizontalAlignment: Text.AlignHCenter
                        onVisibleChanged: {
                            if (visible) {
                                text = item.fileName;
                                forceActiveFocus();
                                // the name without its extension is selected, like in a file manager
                                const dot = item.fileIsDir ? -1 : text.lastIndexOf(".");
                                select(0, dot > 0 ? dot : text.length);
                            }
                        }
                        onAccepted: desk.rename(item.fileName, text)
                        onActiveFocusChanged: if (!activeFocus && visible) desk.rename(item.fileName, text)
                        Keys.onEscapePressed: { desk.renaming = ""; desk.forceActiveFocus(); }
                    }
                }

                HoverHandler { id: hover }

                MouseArea {
                    anchors.fill: parent
                    enabled: desk.renaming !== item.fileName
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: m => {
                        desk.forceActiveFocus();
                        if (m.modifiers & Qt.ControlModifier) {
                            desk.toggle(item.fileName);
                        } else if (m.modifiers & Qt.ShiftModifier) {
                            desk.selectRange(item.fileName);
                        } else if (!item.selected) {
                            desk.selectOnly(item.fileName);
                        }
                        if (m.button === Qt.RightButton) {
                            itemMenu.target = item.fileName;
                            itemMenu.isDir = item.fileIsDir;
                            itemMenu.popup();
                        }
                    }
                    onClicked: m => {
                        // a plain click on one of several selected items keeps only it
                        if (m.button === Qt.LeftButton && !(m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                                && desk.selectedCount > 1) {
                            desk.selectOnly(item.fileName);
                        }
                    }
                    onDoubleClicked: m => {
                        if (m.button === Qt.LeftButton) {
                            desk.open([item.fileName]);
                        }
                    }
                }
            }
        }
    }

    // ---- menus ----------------------------------------------------------------------------------
    PC3.Menu {
        id: itemMenu
        property string target: ""
        property bool isDir: false
        readonly property var list: desk.selectedNames().length > 0 ? desk.selectedNames() : [target]
        readonly property bool many: list.length > 1

        PC3.MenuItem {
            text: Tr.t("Открыть")
            icon.name: "document-open"
            onTriggered: desk.open(itemMenu.list)
        }
        PC3.MenuItem {
            text: Tr.t("Показать в Dolphin")
            icon.name: "system-file-manager"
            onTriggered: desk.showInDolphin(itemMenu.list)
        }
        PC3.MenuItem {
            visible: itemMenu.isDir && !itemMenu.many
            height: visible ? implicitHeight : 0
            text: Tr.t("Открыть терминал здесь")
            icon.name: "utilities-terminal"
            onTriggered: desk.terminalAt(desk.path(itemMenu.target))
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: Tr.t("Вырезать")
            icon.name: "edit-cut"
            onTriggered: desk.copy(itemMenu.list, true)
        }
        PC3.MenuItem {
            text: Tr.t("Копировать")
            icon.name: "edit-copy"
            onTriggered: desk.copy(itemMenu.list, false)
        }
        PC3.MenuItem {
            text: Tr.t("Копировать путь")
            icon.name: "edit-copy-path"
            onTriggered: desk.copyPaths(itemMenu.list)
        }
        PC3.MenuItem {
            text: Tr.t("Дублировать")
            icon.name: "edit-duplicate"
            onTriggered: desk.duplicate(itemMenu.list)
        }
        PC3.MenuItem {
            visible: !itemMenu.many
            height: visible ? implicitHeight : 0
            text: Tr.t("Переименовать")
            icon.name: "edit-rename"
            onTriggered: desk.renaming = itemMenu.target
        }
        PC3.MenuItem {
            text: Tr.t("Сжать в ZIP")
            icon.name: "archive-insert"
            onTriggered: desk.compress(itemMenu.list)
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: itemMenu.many ? Tr.t("Удалить в корзину") + " (" + itemMenu.list.length + ")" : Tr.t("Удалить в корзину")
            icon.name: "user-trash"
            onTriggered: desk.trash(itemMenu.list)
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: Tr.t("Свойства")
            icon.name: "document-properties"
            onTriggered: desk.properties(itemMenu.list)
        }
    }

    PC3.Menu {
        id: deskMenu
        PC3.MenuItem {
            text: Tr.t("Новая папка")
            icon.name: "folder-new"
            onTriggered: desk.create(true)
        }
        PC3.MenuItem {
            text: Tr.t("Новый текстовый файл")
            icon.name: "document-new"
            onTriggered: desk.create(false)
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: Tr.t("Вставить")
            icon.name: "edit-paste"
            onTriggered: desk.paste()
        }
        PC3.MenuItem {
            text: Tr.t("Выделить всё")
            icon.name: "edit-select-all"
            onTriggered: desk.selectAll()
        }
        PC3.Menu {
            title: Tr.t("Упорядочить")
            icon.name: "view-sort"
            Repeater {
                model: [
                    { key: "name", label: Tr.t("По имени") },
                    { key: "time", label: Tr.t("По дате изменения") },
                    { key: "size", label: Tr.t("По размеру") },
                    { key: "type", label: Tr.t("По типу") },
                ]
                delegate: PC3.MenuItem {
                    required property var modelData
                    text: modelData.label
                    checkable: true
                    checked: desk.sortBy === modelData.key
                    onTriggered: desk.sortBy = modelData.key
                }
            }
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: Tr.t("Открыть в Dolphin")
            icon.name: "system-file-manager"
            onTriggered: desk.showInDolphin([])
        }
        PC3.MenuItem {
            text: Tr.t("Открыть терминал здесь")
            icon.name: "utilities-terminal"
            onTriggered: desk.terminalAt(desk.dir)
        }
        PC3.MenuSeparator {}
        PC3.MenuItem {
            text: Tr.t("Обои")
            icon.name: "preferences-desktop-wallpaper"
            onTriggered: desk.wallpaperRequested()
        }
        PC3.MenuItem {
            text: Tr.t("Настройки экрана")
            icon.name: "preferences-desktop-display"
            onTriggered: desk.home.runCommand(["kcmshell6", "kcm_kscreen"])
        }
        PC3.MenuItem {
            text: Tr.t("Параметры")
            icon.name: "preferences-system"
            onTriggered: desk.home.runCommand(["systemsettings"])
        }
    }
}

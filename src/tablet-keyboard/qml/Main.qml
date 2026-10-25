// tablet-keyboard: iPad-style keyboard for the ThinkPad 10. English / Russian (with ё and ъ),
// digits & symbols, emoji, a numeric pad for number fields, split mode (pinch apart / together,
// or the globe menu), light/dark following the system.
// Gestures: flick a key down = its grey symbol; hold = a menu with the grey symbol first, then the
// alternates (е → ё, ь → ъ, accents, «»; the first one is shown in the key's corner);
// hold space = trackpad (move the cursor); swipe across space = switch language; double space
// = ". "; double-tap shift = caps lock (green LED); hold the globe = menu.
import QtQuick
import QtMultimedia
import "Layouts.js" as L
import "Emoji.js" as E
import "Tr.js" as Tr

Item {
    id: root

    readonly property bool pixel: uiStyle.pixel

    // ---- options (Настройки -> Клавиатура, ~/.config/tablet-keyboardrc, applied live) ----
    function opt(key, def) {
        const v = keyboard.config[key];
        return v === undefined || v === "" ? def : v;
    }
    function flag(key, def) { return String(opt(key, def)) === "true"; }
    readonly property string themeMode: opt("theme", "auto")            // auto | light | dark
    readonly property bool flicksOn: flag("flicks", true)
    readonly property bool autoCapOn: flag("autoCap", true)
    readonly property bool doubleSpaceOn: flag("doubleSpace", true)
    readonly property bool trackpadOn: flag("spaceTrackpad", true)
    readonly property bool spaceSwipeOn: flag("spaceSwipe", true)
    readonly property bool spaceLabelOn: flag("spaceLabel", true)
    readonly property bool roundKeys: root.pixel || opt("keyShape", "thinkpad") === "rounded"
    readonly property bool soundOn: flag("sound", false)
    readonly property real soundVolume: Number(opt("soundVolume", 50)) / 100
    readonly property var languages: ["en", "ru"].filter(l => flag(l === "en" ? "layoutEn" : "layoutRu", true))

    Connections {
        target: keyboard
        function onConfigChanged() {
            root.split = root.flag("split", false);
            if (root.languages.length && root.languages.indexOf(root.lang) === -1) root.lang = root.languages[0];
        }
    }

    // ---- theme: follows the system light/dark setting (or a fixed choice) ----
    readonly property bool dark: demoMode.indexOf("light") !== -1 ? false
                               : themeMode === "dark" ? true : themeMode === "light" ? false
                               : Application.styleHints.colorScheme === Qt.ColorScheme.Dark
    QtObject {
        id: pal
        readonly property color bg: root.pixel ? (root.dark ? "#201D26" : "#F3EDF7") : root.dark ? "#1C1C1E" : "#D3D6DD"
        readonly property color hairline: root.pixel ? (root.dark ? "#49454F" : "#CAC4D0") : root.dark ? "#2C2C2E" : "#BFC3CB"
        readonly property color key: root.pixel ? (root.dark ? "#49454F" : "#FFFFFF") : root.dark ? "#56565B" : "#FFFFFF"
        readonly property color keyDown: root.pixel ? (root.dark ? "#6750A4" : "#D0BCFF") : root.dark ? "#3A3A3E" : "#C9CCD3"
        readonly property color special: root.pixel ? (root.dark ? "#625B71" : "#E6E0E9") : root.dark ? "#353539" : "#AEB4BF"
        readonly property color shadow: root.pixel ? "transparent" : root.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0.35, 0.37, 0.42, 0.55)
        readonly property color text: root.pixel ? (root.dark ? "#E6E0E9" : "#1D1B20") : root.dark ? "#FFFFFF" : "#0B0B0C"
        readonly property color subText: root.dark ? "#A1A1A8" : "#7C818B"
        readonly property color ledOff: root.dark ? "#2A2A2D" : "#9097A3"
        readonly property color popup: root.pixel ? (root.dark ? "#605D68" : "#EADDFF") : root.dark ? "#6A6A70" : "#FFFFFF"
        readonly property color accent: root.pixel ? (root.dark ? "#D0BCFF" : "#6750A4") : "#0A84FF"
    }

    // ---- key clicks (sounds/make-sounds.py): letters, backspace, the rest ----
    component Click: SoundEffect {
        volume: root.soundVolume
    }
    Click { id: clickKey; source: root.soundOn ? Qt.resolvedUrl("../sounds/key.wav") : "" }
    Click { id: clickDelete; source: root.soundOn ? Qt.resolvedUrl("../sounds/delete.wav") : "" }
    Click { id: clickModifier; source: root.soundOn ? Qt.resolvedUrl("../sounds/modifier.wav") : "" }
    function click(kind) {
        if (!soundOn) return;
        (kind === "c" ? clickKey : kind === "bs" ? clickDelete : clickModifier).play();
    }

    // ---- state ----
    property string lang: keyboard.setting("lang", "en")
    property string page: "letters"             // letters | symbols | more | emoji
    property int shift: 0                       // 0 off, 1 next letter, 2 caps lock
    property bool autoShift: false
    property bool split: String(keyboard.setting("split", "false")) === "true"
    property bool trackpad: false
    property string typed: ""                   // what we typed, when the app sends no surrounding text
    property bool surroundingKnown: false
    property var lastSpace: 0
    property var lastShiftTap: 0
    property var pressed: ({})                  // key index -> true
    property var flicks: ({})                   // key index -> 0..1 while pulled down

    readonly property bool padMode: [2, 3, 4].indexOf(keyboard.purpose) !== -1   // digits, number, phone
    readonly property var layout: padMode ? L.numpad
                                : page === "symbols" ? L.symbols
                                : page === "more" ? L.more
                                : (lang === "ru" ? L.ru : L.en)

    onLangChanged: keyboard.setSetting("lang", lang)
    onSplitChanged: {
        keyboard.setSetting("split", split);
        rebuild();
    }
    onLayoutChanged: rebuild()
    onWidthChanged: rebuild()
    onHeightChanged: rebuild()

    Connections {
        target: keyboard
        function onActiveChanged() {
            root.typed = "";
            root.surroundingKnown = false;
            root.page = "letters";
            if (root.shift !== 2) root.shift = 0;
            root.updateAutoCap();
        }
        function onSurroundingChanged() {
            root.surroundingKnown = true;
            root.updateAutoCap();
        }
        function onContentChanged() { root.updateAutoCap(); }
        function onResetRequested() { root.typed = ""; }
    }

    // ---- geometry: flat list of keys with positions ----
    readonly property real padTop: height * 0.05
    readonly property real padBottom: height * 0.04
    readonly property real rowGap: height * 0.04
    readonly property real keyH: (height - padTop - padBottom - 3 * rowGap) / 4
    readonly property real hGap: Math.max(5, width * 0.0055)
    readonly property real side: width * 0.008
    readonly property real halfW: width * Math.max(0.25, Math.min(0.48, Number(opt("splitWidth", 36)) / 100))
    property var keys: []
    property var halves: []                     // split mode: the two panels (also the input region)

    function rebuild() {
        if (width <= 0 || height <= 0) return;
        const out = [];
        const lay = layout;
        const rows = lay.rows.map(r => ({ keys: r.keys, split: r.split }));
        rows.push(lay.pad ? null : { keys: L.bottom(lay.units, lay.letters), split: 4 });
        let unitW, left0, right0 = 0;
        const doSplit = split && !lay.pad;
        if (lay.pad) {
            const padW = Math.min(width * 0.5, keyH * 6.5);
            unitW = padW / lay.units;
            left0 = (width - padW) / 2;
        } else if (doSplit) {
            unitW = halfW / Math.max(...rows.map(r => r ? r.keys.slice(0, r.split).reduce((a, k) => a + k[3], 0) : 0),
                                     ...rows.map(r => r ? r.keys.slice(r.split).reduce((a, k) => a + k[3], 0) : 0));
            left0 = side;
        } else {
            unitW = (width - 2 * side) / lay.units;
            left0 = side;
        }
        for (let ri = 0; ri < rows.length; ++ri) {
            if (!rows[ri]) continue;
            let rowKeys = rows[ri].keys;
            const y = padTop + ri * (keyH + rowGap);
            if (doSplit) {
                let leftKeys = rowKeys.slice(0, rows[ri].split);
                let rightKeys = rowKeys.slice(rows[ri].split);
                if (ri === 3) {
                    const b = L.bottomSplit(lay.units, lay.letters);
                    leftKeys = b.left;
                    rightKeys = b.right;
                }
                let x = left0;
                for (const k of leftKeys) { out.push({ x: x, y: y, w: k[3] * unitW, spec: k, row: ri }); x += k[3] * unitW; }
                const rw = rightKeys.reduce((a, k) => a + k[3], 0) * unitW;
                x = width - side - rw;
                for (const k of rightKeys) { out.push({ x: x, y: y, w: k[3] * unitW, spec: k, row: ri }); x += k[3] * unitW; }
            } else {
                let x = left0;
                for (const k of rowKeys) { out.push({ x: x, y: y, w: k[3] * unitW, spec: k, row: ri }); x += k[3] * unitW; }
            }
        }
        keys = out;
        halves = doSplit ? [Qt.rect(0, 0, side * 2 + halfW, height), Qt.rect(width - side * 2 - halfW, 0, side * 2 + halfW, height)] : [];
        keyboard.setInputRegion(halves);
    }
    Component.onCompleted: {
        // demo / screenshots: TABLET_KEYBOARD_DEMO=ru,split,emoji,symbols,shift
        if (demoMode) {
            const d = demoMode.split(",");
            lang = d.indexOf("ru") !== -1 ? "ru" : "en";
            split = d.indexOf("split") !== -1;
            page = d.indexOf("emoji") !== -1 ? "emoji" : d.indexOf("symbols") !== -1 ? "symbols" : "letters";
            shift = d.indexOf("shift") !== -1 ? 2 : 0;
        }
        rebuild();
    }

    function hit(x, y) {
        for (let i = 0; i < keys.length; ++i) {
            const k = keys[i];
            if (x >= k.x && x < k.x + k.w && y >= k.y - rowGap / 2 && y < k.y + keyH + rowGap / 2) {
                return k.spec[0] === "gap" ? -1 : i;
            }
        }
        return -1;
    }

    // ---- typing ----
    function autoCapAllowed() {
        const p = keyboard.purpose;
        return autoCapOn && page === "letters" && [5, 6, 8, 12].indexOf(p) === -1 && !(keyboard.hints & 0x8);
    }
    function updateAutoCap() {
        if (shift === 2) return;
        const ctx = surroundingKnown ? keyboard.textBeforeCursor : typed;
        const want = autoCapAllowed() && /(^|[.!?…]\s+|\n\s*)$/.test(ctx);
        if (want) { shift = 1; autoShift = true; }
        else if (autoShift && shift === 1) { shift = 0; autoShift = false; }
    }
    function commit(text) {
        keyboard.commit(text);
        typed = (typed + text).slice(-64);
        if (!surroundingKnown) updateAutoCap();
    }
    function backspace() {
        keyboard.key("BackSpace");
        typed = typed.slice(0, -1);
        if (!surroundingKnown) updateAutoCap();
    }
    function letter(ch) {
        return shift > 0 && page === "letters" ? ch.toUpperCase() : ch;
    }

    // long press menu of a letter key: the grey (flick) symbol, then its alternates
    function holdOptions(spec) {
        const out = [];
        const add = ch => {
            const t = letter(ch);
            if (t !== "" && out.indexOf(t) === -1) out.push(t);
        };
        add(spec[2]);
        (spec[4] || []).forEach(add);
        return out;
    }
    // corner hint: the first alternate that is not the key itself
    function hintFor(spec) {
        const alts = (spec[4] || []).filter(a => a !== spec[1]);
        return alts.length ? letter(alts[0]) : "";
    }
    function setFlick(i, v) {
        if ((flicks[i] || 0) === v) return;
        const f = Object.assign({}, flicks);
        if (v > 0) f[i] = v; else delete f[i];
        flicks = f;
    }

    function typeKey(k, st) {
        const t = k.spec[0];
        if (t === "c") {
            const text = st && st.flick && flicksOn && k.spec[2] !== "" ? k.spec[2] : letter(k.spec[1]);
            commit(text);
            if (shift === 1) { shift = 0; autoShift = false; }
            if (page === "symbols" && text === "'") page = "letters";
        } else if (t === "ret") {
            keyboard.key("Return");
            typed += "\n";
            updateAutoCap();
        } else if (t === "sh") {
            const now = Date.now();
            if (shift === 0) shift = now - lastShiftTap < 350 ? 2 : 1;
            else if (shift === 1 && now - lastShiftTap < 350) shift = 2;
            else shift = 0;
            autoShift = false;
            lastShiftTap = now;
        } else if (t === "num") {
            page = page === "letters" ? "symbols" : "letters";
        } else if (t === "more") {
            page = page === "more" ? "symbols" : "more";
        } else if (t === "glb") {
            switchLanguage();
        } else if (t === "emo") {
            page = "emoji";
        } else if (t === "spc") {
            const now = Date.now();
            const before = surroundingKnown ? keyboard.textBeforeCursor : typed;
            if (doubleSpaceOn && now - lastSpace < 450 && /[\wа-яё]\s$/i.test(before)) {
                backspace();
                commit(". ");
                lastSpace = 0;
            } else {
                commit(" ");
                lastSpace = now;
            }
            updateAutoCap();
        } else if (t === "hide") {
            keyboard.hide();
        }
    }
    function switchLanguage() {
        const langs = languages.length ? languages : ["en"];
        lang = langs[(langs.indexOf(lang) + 1) % langs.length];
        page = "letters";
        langHint.restart();
    }

    // ---- background ----
    Rectangle {
        anchors.fill: parent
        visible: !root.split || root.padMode
        color: pal.bg
        Rectangle { width: parent.width; height: 1; color: pal.hairline }
    }
    Repeater {
        model: root.halves
        delegate: Rectangle {
            required property var modelData
            x: modelData.x; y: root.padTop * 0.4
            width: modelData.width; height: root.height - root.padTop * 0.4
            radius: root.keyH * 0.35
            color: pal.bg
            border.color: pal.hairline
        }
    }

    // ---- keys ----
    Item {
        anchors.fill: parent
        visible: root.page !== "emoji"
        Repeater {
            model: root.keys
            delegate: KeyFace {
                required property var modelData
                required property int index
                x: modelData.x + root.hGap / 2
                y: modelData.y
                width: modelData.w - root.hGap
                height: root.keyH
                visible: modelData.spec[0] !== "gap"
                spec: modelData.spec
                theme: pal
                down: !!root.pressed[index]
                blank: root.trackpad
                showSecondary: root.flicksOn
                flick: root.flicks[index] || 0
                hint: modelData.spec[0] === "c" ? root.hintFor(modelData.spec) : ""
                smileFactor: root.roundKeys ? 0 : 1
                label: modelData.spec[0] === "c" ? root.letter(modelData.spec[1])
                     : modelData.spec[0] === "spc" ? (root.layout.letters && root.spaceLabelOn ? root.layout.name : "")
                     : modelData.spec[0] === "ret" ? (root.lang === "ru" ? "ввод" : "return")
                     : modelData.spec[1]
                icon: ({ bs: "⌫", sh: root.shift === 2 ? "⇪" : "⇧" })[modelData.spec[0]] || ""
                iconName: ({ glb: "globe-symbolic", emo: "face-smile-symbolic", hide: "input-keyboard-virtual-hide-symbolic" })[modelData.spec[0]] || ""
                ledVisible: modelData.spec[0] === "sh"
                led: root.shift === 2
            }
        }
    }

    // language name flashes on the space bar after switching
    Timer { id: langHint; interval: 1200 }

    // ---- touch: one area for the whole keyboard (rollover typing with two thumbs) ----
    property var touches: ({})
    property var popup: null                    // {key, options, selected, x, y, actions}

    MultiPointTouchArea {
        anchors.fill: parent
        enabled: root.page !== "emoji"
        maximumTouchPoints: 5
        mouseEnabled: true

        function setPressed(i, on) {
            const p = Object.assign({}, root.pressed);
            if (on) p[i] = true; else delete p[i];
            root.pressed = p;
        }

        onPressed: points => {
            for (const tp of points) {
                const i = root.hit(tp.x, tp.y);
                root.touches[tp.pointId] = { i: i, x0: tp.x, y0: tp.y, t0: Date.now(), flick: false, swipe: false, done: false, moved: 0, lastX: tp.x, lastY: tp.y };
                if (i < 0) continue;
                setPressed(i, true);
                root.click(root.keys[i].spec[0]);
                if (root.keys[i].spec[0] === "bs") root.backspace();
            }
            // two fingers moving apart / together: split / merge
            const ids = Object.keys(root.touches);
            if (ids.length === 2) {
                const a = root.touches[ids[0]], b = root.touches[ids[1]];
                root.pinchStart = Math.hypot(a.x0 - b.x0, a.y0 - b.y0);
            }
            holdTimer.start();
        }
        onUpdated: points => {
            const ids = Object.keys(root.touches);
            for (const tp of points) {
                const st = root.touches[tp.pointId];
                if (!st || st.done || st.i < 0) continue;
                const k = root.keys[st.i];
                const dx = tp.x - st.x0, dy = tp.y - st.y0;
                if (root.popup && root.popup.id === tp.pointId) {
                    const n = root.popup.options.length;
                    const w = root.popup.cell;
                    root.popup = Object.assign({}, root.popup, { selected: Math.max(0, Math.min(n - 1, Math.floor((tp.x - root.popup.x) / w))) });
                } else if (root.trackpad && st.trackpad) {
                    // trackpad: arrow keys per step of finger movement
                    const step = root.keyH * 0.35;
                    while (tp.x - st.lastX > step) { keyboard.key("Right"); st.lastX += step; }
                    while (st.lastX - tp.x > step) { keyboard.key("Left"); st.lastX -= step; }
                    while (tp.y - st.lastY > step * 2) { keyboard.key("Down"); st.lastY += step * 2; }
                    while (st.lastY - tp.y > step * 2) { keyboard.key("Up"); st.lastY -= step * 2; }
                } else if (root.flicksOn && k.spec[0] === "c" && k.spec[2] !== "" && !st.held && dy > root.keyH * 0.08) {
                    // the grey symbol follows the finger; past 40 % of a key it is the one typed
                    root.setFlick(st.i, Math.min(1, dy / (root.keyH * 0.4)));
                    st.flick = dy > root.keyH * 0.4;
                } else if (st.flick || root.flicks[st.i]) {
                    root.setFlick(st.i, 0);
                    st.flick = false;
                } else if (root.spaceSwipeOn && root.languages.length > 1 && k.spec[0] === "spc" && Math.abs(dx) > root.keyH * 1.4 && Date.now() - st.t0 < 450) {
                    st.swipe = true;
                }
            }
            if (ids.length === 2 && root.pinchStart > 0) {
                const a = points.find(p => String(p.pointId) === ids[0]) || null;
                const b = points.find(p => String(p.pointId) === ids[1]) || null;
                if (a && b) {
                    const d = Math.hypot(a.x - b.x, a.y - b.y);
                    if (d / root.pinchStart > 1.45 && !root.split) { root.split = true; cancelAll(); }
                    else if (d / root.pinchStart < 0.65 && root.split) { root.split = false; cancelAll(); }
                }
            }
        }
        onReleased: points => {
            for (const tp of points) {
                const st = root.touches[tp.pointId];
                delete root.touches[tp.pointId];
                if (!st || st.i < 0) continue;
                setPressed(st.i, false);
                root.setFlick(st.i, 0);
                if (st.done) continue;
                const k = root.keys[st.i];
                if (root.popup && root.popup.id === tp.pointId) {
                    const pick = root.popup.selected;
                    const actions = root.popup.actions;
                    const options = root.popup.options;
                    root.popup = null;
                    if (actions) actions[pick]();
                    else { root.commit(options[pick]); if (root.shift === 1) root.shift = 0; }
                } else if (st.trackpad) {
                    root.trackpad = false;
                } else if (st.swipe) {
                    root.switchLanguage();
                } else if (k.spec[0] !== "bs") {
                    root.typeKey(k, st);
                }
            }
            if (Object.keys(root.touches).length === 0) { holdTimer.stop(); root.pinchStart = 0; }
        }
        onCanceled: points => {
            for (const tp of points) {
                const st = root.touches[tp.pointId];
                delete root.touches[tp.pointId];
                if (st && st.i >= 0) { setPressed(st.i, false); root.setFlick(st.i, 0); }
            }
            root.popup = null;
            root.trackpad = false;
        }
        function cancelAll() {
            for (const id in root.touches) {
                root.touches[id].done = true;
            }
            root.pressed = {};
            root.flicks = {};
            root.popup = null;
        }
    }
    property real pinchStart: 0

    // long press: alternates, globe menu, trackpad, backspace repeat
    Timer {
        id: holdTimer
        interval: 50
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const id in root.touches) {
                const st = root.touches[id];
                if (st.done || st.i < 0 || st.flick || st.swipe || root.flicks[st.i]) continue;
                const k = root.keys[st.i];
                const held = now - st.t0;
                if (k.spec[0] === "bs") {
                    // repeat, faster after a second
                    if (held > 450 && now - (st.lastRepeat || 0) > (held > 1500 ? 45 : 90)) { root.backspace(); root.click("bs"); st.lastRepeat = now; }
                } else if (held > 420 && !st.held) {
                    st.held = true;
                    if (k.spec[0] === "spc" && root.trackpadOn) {
                        st.trackpad = true;
                        root.trackpad = true;
                    } else if (k.spec[0] === "c" && root.holdOptions(k.spec).length) {
                        root.openPopup(id, k, root.holdOptions(k.spec), null);
                    } else if (k.spec[0] === "glb") {
                        root.openPopup(id, k, [root.split ? Tr.t("Объединить") : Tr.t("Разделить"), Tr.t("Эмодзи"), Tr.t("Скрыть")],
                                       [() => root.split = !root.split, () => root.page = "emoji", () => keyboard.hide()]);
                    }
                }
            }
        }
    }
    function openPopup(id, k, options, actions) {
        const cell = Math.max(keyH * 0.95, actions ? keyH * 2.3 : 0);
        const w = cell * options.length;
        const x = Math.max(side, Math.min(width - side - w, k.x + k.w / 2 - (actions ? w / 2 : cell / 2)));
        popup = { id: Number(id), options: options, actions: actions, selected: 0, cell: cell, x: x, y: k.y - keyH * 1.1,
                  key: Qt.rect(k.x + hGap / 2, k.y, k.w - hGap, keyH) };
    }

    // alternates / globe menu: an iOS callout, the bubble grows out of the held key
    Item {
        id: callout
        visible: !!root.popup
        anchors.fill: parent
        readonly property rect keyRect: root.popup ? root.popup.key : Qt.rect(0, 0, 0, 0)
        readonly property real bubbleY: root.popup ? Math.max(0, root.popup.y) : 0
        readonly property real bubbleH: root.keyH * 1.05
        readonly property real bubbleW: root.popup ? root.popup.cell * root.popup.options.length : 0

        component CalloutShape: Item {
            property color fill
            anchors.fill: parent
            // the held key
            Rectangle {
                x: callout.keyRect.x; y: callout.keyRect.y
                width: callout.keyRect.width; height: callout.keyRect.height
                radius: root.keyH * 0.16
                color: parent.fill
            }
            // neck between key and bubble
            Rectangle {
                x: callout.keyRect.x
                y: callout.bubbleY + callout.bubbleH - radius
                width: callout.keyRect.width
                height: Math.max(0, callout.keyRect.y - y + radius)
                color: parent.fill
                radius: 0
            }
            // the bubble
            Rectangle {
                x: root.popup ? root.popup.x : 0
                y: callout.bubbleY
                width: callout.bubbleW
                height: callout.bubbleH
                radius: root.keyH * 0.24
                color: parent.fill
            }
        }
        CalloutShape { fill: pal.shadow; anchors.topMargin: 2; anchors.bottomMargin: -2; opacity: 0.6 }
        CalloutShape { fill: pal.popup }

        Row {
            x: root.popup ? root.popup.x : 0
            y: callout.bubbleY
            height: callout.bubbleH
            Repeater {
                model: root.popup ? root.popup.options : []
                delegate: Item {
                    required property string modelData
                    required property int index
                    readonly property bool current: index === root.popup.selected
                    width: root.popup.cell
                    height: callout.bubbleH
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.keyH * 0.08
                        radius: root.keyH * 0.18
                        color: pal.accent
                        opacity: parent.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: parent.current ? "white" : pal.text
                        font.family: "Inter"
                        font.pixelSize: root.popup.actions ? root.keyH * 0.3 : root.keyH * 0.46
                    }
                }
            }
        }
    }

    // ---- emoji ----
    EmojiPanel {
        anchors.fill: parent
        visible: root.page === "emoji"
        theme: pal
        keyH: root.keyH
        onPicked: e => {
            root.commit(e);
            const recent = String(keyboard.setting("recentEmoji", "")).split(" ").filter(x => x && x !== e);
            keyboard.setSetting("recentEmoji", [e].concat(recent).slice(0, 32).join(" "));
        }
        onBackspace: root.backspace()
        onLetters: root.page = "letters"
    }
}

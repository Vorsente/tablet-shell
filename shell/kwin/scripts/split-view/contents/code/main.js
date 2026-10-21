// Split View: put the active window on the left and the most recently used other window on the right.
// Running it again while a split is active restores both windows to full screen.
var split = null;   // [left, right] while split

function candidates() {
    var list = [];
    var order = workspace.stackingOrder;
    for (var i = order.length - 1; i >= 0; --i) {  // topmost first = most recently used
        var w = order[i];
        if (w.normalWindow && !w.minimized && !w.skipTaskbar && w.onCurrentDesktop !== false) {
            list.push(w);
        }
    }
    return list;
}

function place(w, rect) {
    w.setMaximize(false, false);
    w.frameGeometry = rect;
}

function toggleSplit() {
    if (split) {
        split.forEach(function (w) { if (w) { w.setMaximize(true, true); } });
        split = null;
        return;
    }
    var active = workspace.activeWindow;
    var others = candidates().filter(function (w) { return w !== active; });
    if (!active || !active.normalWindow || others.length === 0) {
        return;
    }
    var area = workspace.clientArea(KWin.MaximizeArea, active);
    var half = Math.floor(area.width / 2);
    var gap = 4;
    place(active, { x: area.x, y: area.y, width: half - gap, height: area.height });
    place(others[0], { x: area.x + half + gap, y: area.y, width: area.width - half - gap, height: area.height });
    split = [active, others[0]];
}

workspace.windowRemoved.connect(function (w) {
    if (split && split.indexOf(w) !== -1) {
        split.forEach(function (o) { if (o && o !== w) { o.setMaximize(true, true); } });
        split = null;
    }
});

// shortcut names in the UI language (tabletd writes it here: kwinrc [Script-<name>] russian)
var RU = readConfig("russian", true);
registerShortcut("Split View", RU ? "Split View: два окна рядом" : "Split View: two windows side by side", "Meta+S", toggleSplit);

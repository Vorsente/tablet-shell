// Split View, like iPadOS: two apps side by side.
//  - "Split View" (Meta+S, the control center tile): the current app goes to the left half and the
//    previous app (also a minimized one: going home minimizes apps) to the right. With no other app
//    open the left half waits: the next app opened or tapped in the dock takes the right half.
//    Run again: both back to full screen (or the waiting half is cancelled).
//  - "Split View Resize" (Meta+Alt+S, hold the tile): divider at 1/2 -> 2/3 -> 1/3.
//  - "Split View Swap" (Meta+Shift+S): the two apps change sides.
// Opening one app of the pair again (dock, task switcher) brings its partner back with it;
// closing one gives the other the whole screen.
var split = null;     // { left, right } while split
var pending = null;   // left window waiting for its partner
var ratio = 0.5;      // width of the left app
var busy = false;     // our own geometry changes (not "the user maximized a window")
var fresh = null;     // app just opened into the waiting split: KWin may still maximize it (Placement=Maximizing)
var GAP = 6;

function onDesktop(w) {
    return w.onAllDesktops || !w.desktops || w.desktops.length === 0
        || w.desktops.indexOf(workspace.currentDesktop) !== -1;
}

// an app window that can take part (no panels, dialogs, Slide Over / picture-in-picture windows)
function usable(w) {
    return w && w.normalWindow && !w.skipTaskbar && !w.keepAbove && !w.specialWindow
        && w.resizeable !== false && onDesktop(w);
}

// most recently used first, minimized windows included
function candidates() {
    var list = [];
    var order = workspace.stackingOrder;
    for (var i = order.length - 1; i >= 0; --i) {
        if (usable(order[i])) {
            list.push(order[i]);
        }
    }
    return list;
}

function place(w, rect) {
    busy = true;
    w.minimized = false;
    if (w.fullScreen) {
        w.fullScreen = false;
    }
    w.setMaximize(false, false);
    w.frameGeometry = rect;
    busy = false;
}

function maximize(w) {
    if (w) {
        busy = true;
        w.setMaximize(true, true);
        busy = false;
    }
}

function halves(w) {
    var area = workspace.clientArea(KWin.MaximizeArea, w);
    var leftW = Math.round(area.width * ratio);
    return [
        { x: area.x, y: area.y, width: leftW - GAP / 2, height: area.height },
        { x: area.x + leftW + GAP / 2, y: area.y, width: area.width - leftW - GAP / 2, height: area.height }
    ];
}

function layout() {
    var r = halves(split.left);
    place(split.left, r[0]);
    place(split.right, r[1]);
}

function start(left, right) {
    pending = null;
    fresh = null;
    split = { left: left, right: right };
    layout();
    workspace.activeWindow = right;
}

function stop() {
    if (split) {
        var s = split;
        split = null;
        maximize(s.left);
        maximize(s.right);
    }
    if (pending) {
        var w = pending;
        pending = null;
        maximize(w);
    }
}

function toggleSplit() {
    if (split || pending) {
        stop();
        return;
    }
    var list = candidates();
    // from the home screen or the control center the active window is not an app: take the last app
    var active = usable(workspace.activeWindow) ? workspace.activeWindow : list[0];
    if (!active) {
        return;
    }
    var others = list.filter(function (w) { return w !== active; });
    ratio = 0.5;
    if (others.length > 0) {
        start(active, others[0]);
    } else {
        // the only app: left half now, the next app opened takes the right half
        pending = active;
        place(active, halves(active)[0]);
    }
}

function resize() {
    if (!split) {
        return;
    }
    ratio = ratio === 0.5 ? 2 / 3 : ratio > 0.5 ? 1 / 3 : 0.5;
    layout();
}

function swap() {
    if (!split) {
        return;
    }
    split = { left: split.right, right: split.left };
    ratio = 1 - ratio;
    layout();
}

function partnerOf(w) {
    return !split ? null : w === split.left ? split.right : w === split.right ? split.left : null;
}

workspace.windowAdded.connect(function (w) {
    if (pending && w !== pending && usable(w)) {
        start(pending, w);
        fresh = w;
    }
});

workspace.windowActivated.connect(function (w) {
    if (!usable(w)) {
        return;
    }
    if (pending && w !== pending) {
        start(pending, w);
        return;
    }
    // one app of the pair opened again: its partner comes back too, both in their halves
    var other = partnerOf(w);
    if (other && (other.minimized || w.maximizeMode !== 0)) {
        layout();
        workspace.activeWindow = w;
    }
});

workspace.windowRemoved.connect(function (w) {
    if (w === pending) {
        pending = null;
    }
    var other = partnerOf(w);
    if (other) {
        split = null;
        maximize(other);
    }
});

// The waiting app sent home: the split is off. An app of the pair maximized by hand (double click,
// tablet mode switch): it leaves the split, the partner takes the whole screen.
function watch(w) {
    w.minimizedChanged.connect(function () {
        if (w === pending && w.minimized) {
            pending = null;
            maximize(w);
        }
    });
    w.maximizedChanged.connect(function () {
        if (busy || w.maximizeMode !== 3) {
            return;
        }
        if (w === fresh && split) {
            fresh = null;
            layout();
            return;
        }
        var other = partnerOf(w);
        if (other && !w.minimized) {
            split = null;
            maximize(other);
        }
    });
}
workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);

// shortcut names in the UI language (tabletd writes it here: kwinrc [Script-<name>] russian)
var RU = readConfig("russian", true);
registerShortcut("Split View", RU ? "Split View: два окна рядом" : "Split View: two windows side by side", "Meta+S", toggleSplit);
registerShortcut("Split View Resize", RU ? "Split View: размер половин (1/2, 2/3, 1/3)" : "Split View: divider at 1/2, 2/3, 1/3", "Meta+Alt+S", resize);
registerShortcut("Split View Swap", RU ? "Split View: поменять окна местами" : "Split View: swap the two windows", "Meta+Shift+S", swap);

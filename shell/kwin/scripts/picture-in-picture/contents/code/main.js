// Picture in Picture: the active window becomes a small 16:9 window above everything, in a corner,
// on all desktops. Run again on it to put it back as it was. A second shortcut moves it to the
// next corner (borderless windows cannot be dragged by finger). Firefox's own PiP windows are
// placed this way automatically.
var pip = null;        // the PiP window
var saved = null;      // its state before
var corner = 3;        // 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right

function rect(w) {
    var area = workspace.clientArea(KWin.MaximizeArea, w);
    var width = Math.min(Math.round(area.width * 0.32), 480);
    var height = Math.round(width * 9 / 16);
    var m = 16;
    var x = (corner % 2 === 1) ? area.x + area.width - width - m : area.x + m;
    var y = (corner >= 2) ? area.y + area.height - height - m : area.y + m;
    return { x: x, y: y, width: width, height: height };
}

function enter(w) {
    if (pip && pip !== w) {
        leave();
    }
    saved = { geometry: w.frameGeometry, keepAbove: w.keepAbove, onAllDesktops: w.onAllDesktops,
              noBorder: w.noBorder, maximized: w.maximizeMode };
    pip = w;
    w.setMaximize(false, false);
    w.noBorder = true;
    w.keepAbove = true;
    w.onAllDesktops = true;
    w.frameGeometry = rect(w);
}

function leave() {
    if (!pip) {
        return;
    }
    var w = pip;
    pip = null;
    w.keepAbove = saved.keepAbove;
    w.onAllDesktops = saved.onAllDesktops;
    w.noBorder = saved.noBorder;
    if (saved.maximized) {
        w.setMaximize(true, true);
    } else {
        w.frameGeometry = saved.geometry;
    }
    workspace.activeWindow = w;
}

function toggle() {
    var w = workspace.activeWindow;
    if (pip && (w === pip || !w || !w.normalWindow)) {
        leave();
    } else if (w && w.normalWindow) {
        enter(w);
    }
}

function nextCorner() {
    if (!pip) {
        return;
    }
    corner = (corner + 1) % 4;
    pip.frameGeometry = rect(pip);
}

workspace.windowRemoved.connect(function (w) {
    if (w === pip) {
        pip = null;
    }
});

// Firefox's "Picture-in-Picture" video windows
workspace.windowAdded.connect(function (w) {
    if (/firefox/i.test(w.resourceClass) && /Picture-in-Picture|Картинка в картинке/i.test(w.caption)) {
        enter(w);
    }
});

// shortcut names in the UI language (tabletd writes it here: kwinrc [Script-<name>] russian)
var RU = readConfig("russian", true);
registerShortcut("Picture in Picture", RU ? "Картинка в картинке" : "Picture in picture", "Meta+P", toggle);
registerShortcut("Picture in Picture Corner", RU ? "Картинка в картинке: следующий угол" : "Picture in picture: next corner", "Meta+Shift+P", nextCorner);

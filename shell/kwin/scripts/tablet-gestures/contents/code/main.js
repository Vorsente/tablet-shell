// Touch screen edge gestures handled by ~/.local/bin/tabletshell (org.ipad.TabletShell)
function shellCall(method) {
    callDBus("org.ipad.TabletShell", "/", "org.ipad.TabletShell", method);
}
// each edge can be turned off in the tablet-settings app (kwinrc [Script-tablet-gestures])
if (readConfig("topEdge", true)) {
    registerTouchScreenEdge(KWin.ElectricTop, function () { shellCall("ToggleControlCenter"); });
}
// left edge = Back: tabletshell's BackGesture.qml (an arrow that follows the finger; KWin's touch
// edge only reports a finished swipe), still switched by leftEdge in this group
if (readConfig("rightEdge", true)) {
    registerTouchScreenEdge(KWin.ElectricRight, function () { shellCall("ToggleNotifications"); });
}

// Screen time: report which app is in front (desktop file name, or window class)
function reportActive(w) {
    var id = w ? (w.desktopFileName || w.resourceClass || "") : "";
    if (w && (w.desktopWindow || w.dock || w.specialWindow)) {
        id = "";   // desktop / panels / overlays do not count as app time
    }
    shellCall2("WindowActivated", id);
}
function shellCall2(method, arg) {
    callDBus("org.ipad.TabletShell", "/", "org.ipad.TabletShell", method, arg);
}
workspace.windowActivated.connect(reportActive);
reportActive(workspace.activeWindow);

// Text menu (long press on text): where the app in front is, so touches on panels, the dock and
// overlays are not taken for it. "pid x y width height" as fractions of the built-in screen
// (the touch screen), pid 0 = no app window. The home screen (Plasma's desktop window, its search
// bar has no menu of its own) is reported without the panels and marked "home".
function builtInScreen() {
    var screens = workspace.screens;
    for (var i = 0; i < screens.length; ++i) {
        if (/^(eDP|LVDS|DSI)/.test(screens[i].name)) {
            return screens[i];
        }
    }
    return screens[0];
}
var areaWindow = null;
function reportArea() {
    var w = areaWindow;
    var s = builtInScreen();
    var home = w && w.desktopWindow;
    if (!w || !s || (!home && (w.dock || w.specialWindow)) || !w.pid) {
        shellCall2("WindowArea", "0 0 0 0 0");
        return;
    }
    var g = home ? workspace.clientArea(KWin.MaximizeArea, s, workspace.currentDesktop) : w.frameGeometry;
    var o = s.geometry;
    var area = [w.pid, (g.x - o.x) / o.width, (g.y - o.y) / o.height, g.width / o.width, g.height / o.height];
    if (home) {
        area.push("home");
    }
    shellCall2("WindowArea", area.join(" "));
}
function followArea(w) {
    if (areaWindow) {
        areaWindow.frameGeometryChanged.disconnect(reportArea);
    }
    areaWindow = w;
    if (w) {
        w.frameGeometryChanged.connect(reportArea);
    }
    reportArea();
}
workspace.windowActivated.connect(followArea);
workspace.screensChanged.connect(reportArea);
followArea(workspace.activeWindow);

// Android on demand: tabletshell stops the Waydroid session after some idle minutes without a
// Waydroid window (tabletrc [Android] autoStopMinutes); it needs to know how many are open
function isWaydroid(w) {
    var id = (w.desktopFileName || "") + " " + (w.resourceClass || "");
    return w.normalWindow && /(^|\s)waydroid/i.test(id);
}
function reportWaydroid(closing) {
    var n = 0;
    workspace.windowList().forEach(function (w) { if (w !== closing && isWaydroid(w)) n++; });
    shellCall2("WaydroidWindows", n);
}
workspace.windowAdded.connect(function (w) { if (isWaydroid(w)) reportWaydroid(); });
workspace.windowRemoved.connect(function (w) { if (isWaydroid(w)) reportWaydroid(w); });
reportWaydroid();

// Tablet mode: a newly opened app fills the screen as it is now. Apps restore the size they had
// last time; after the screen was rotated that size belongs to the other orientation and the
// window stuck out or left a gap. KWin's own "maximizing" placement runs before that restore, so
// the window is maximized again a moment later.
function fitNewWindow(w) {
    if (!w.normalWindow || w.transient || w.fullScreen || !w.maximizable || w.specialWindow) {
        return;
    }
    callDBus("org.kde.KWin", "/org/kde/KWin", "org.freedesktop.DBus.Properties", "Get",
             "org.kde.KWin.TabletModeManager", "tabletMode", function (tablet) {
        if (!tablet) {
            return;
        }
        w.setMaximize(true, true);
        var again = new QTimer();
        again.singleShot = true;
        again.interval = 350;
        again.timeout.connect(function () {
            if (!w.deleted && !w.fullScreen) {
                w.setMaximize(true, true);
            }
        });
        again.start();
    });
}
workspace.windowAdded.connect(fitNewWindow);

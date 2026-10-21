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

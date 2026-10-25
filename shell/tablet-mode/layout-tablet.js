// Non-destructive bootstrap. Safe to retry after a partially completed Plasma script.
(function () {
    var bar = null;
    panels().some(function (p) {
        if (p.widgets().some(function (w) { return w.type === "org.kde.plasma.systemtray"; })) {
            bar = p;
            return true;
        }
        // Reuse a shell bar whose tray failed to load.
        if (p.widgets().some(function (w) { return w.type === "org.ipad.statusclock"; })) bar = p;
        return false;
    });
    if (!bar) bar = new Panel("org.kde.panel");
    bar.location = "top";
    bar.height = 28;
    bar.floating = false;
    bar.hiding = "none";
    bar.lengthMode = "fill";
    bar.alignment = "center";
    bar.offset = 0;
    bar.opacity = "opaque";
    function ensure(type) {
        var widget = null;
        bar.widgets().forEach(function (w) { if (w.type === type) widget = w; });
        return widget || bar.addWidget(type);
    }
    ensure("org.ipad.statusclock");
    ensure("org.kde.plasma.panelspacer");
    var tray = ensure("org.kde.plasma.systemtray");
    tray.currentConfigGroup = ["General"];
    tray.writeConfig("scaleIconsToFit", true);
    print("BUILT");
})();

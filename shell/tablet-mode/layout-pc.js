// PC (Samsung DeX style): one full-width taskbar at the bottom with an apps button,
// pinned and running apps, tray, clock and show-desktop.
// Legacy standalone layout: reuse the tray panel and preserve other user panels.
var existing = null;
panels().some(function (p) {
    if (p.widgets().some(function (w) { return w.type === "org.kde.plasma.systemtray"; })) {
        existing = p; return true;
    }
    return false;
});

var bar = existing || new Panel("org.kde.panel");
function ensure(type) {
    var found = null;
    bar.widgets().forEach(function (w) { if (w.type === type) found = w; });
    return found || bar.addWidget(type);
}
bar.location = "bottom";
bar.height = 44;
bar.floating = false;
bar.hiding = "none";
bar.opacity = "opaque";
var apps = ensure("org.kde.plasma.kickoff");
apps.currentConfigGroup = ["General"];
apps.writeConfig("icon", "view-app-grid-symbolic");
apps.writeConfig("favoritesDisplay", 0);
apps.writeConfig("applicationsDisplay", 0);
apps.writeConfig("showActionButtonCaptions", false);
apps.writeConfig("primaryActions", 3);
apps.currentConfigGroup = [];
apps.writeConfig("popupWidth", 760);
apps.writeConfig("popupHeight", 600);
var tasks = ensure("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", LAUNCHERS);
tasks.writeConfig("maxStripes", 1);
tasks.writeConfig("indicateAudioStreams", true);
var tray = ensure("org.kde.plasma.systemtray");
var clock = ensure("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BelowTime");
clock.writeConfig("use24hFormat", 2);
ensure("org.kde.plasma.showdesktop");

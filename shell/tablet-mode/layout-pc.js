// PC (Samsung DeX style): one full-width taskbar at the bottom with an apps button,
// pinned and running apps, tray, clock and show-desktop.
panels().forEach(function (p) { p.remove(); });

var bar = new Panel("org.kde.panel");
bar.location = "bottom";
bar.height = 44;
bar.floating = false;
bar.hiding = "none";
bar.opacity = "translucent";
var apps = bar.addWidget("org.kde.plasma.kickoff");
apps.currentConfigGroup = ["General"];
apps.writeConfig("icon", "view-app-grid-symbolic");
apps.writeConfig("favoritesDisplay", 0);
apps.writeConfig("applicationsDisplay", 0);
apps.writeConfig("showActionButtonCaptions", false);
apps.writeConfig("primaryActions", 3);
apps.currentConfigGroup = [];
apps.writeConfig("popupWidth", 760);
apps.writeConfig("popupHeight", 600);
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", LAUNCHERS);
tasks.writeConfig("maxStripes", 1);
tasks.writeConfig("indicateAudioStreams", true);
var quick = bar.addWidget("org.kde.plasma.quicklaunch");
quick.currentConfigGroup = ["General"];
quick.writeConfig("launcherUrls", ["file://" + HOME + "/.local/share/applications/appearance-toggle.desktop"]);
quick.writeConfig("showLauncherNames", false);
var tray = bar.addWidget("org.kde.plasma.systemtray");
var clock = bar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BelowTime");
clock.writeConfig("use24hFormat", 2);
bar.addWidget("org.kde.plasma.showdesktop");

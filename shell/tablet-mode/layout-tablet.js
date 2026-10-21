// Tablet (iPadOS): glass status bar on top, floating dock that hides under windows.
panels().forEach(function (p) { p.remove(); });

var top = new Panel("org.kde.panel");
top.location = "top";
top.height = 28;
top.floating = false;
top.opacity = "translucent";
var clock = top.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BesideTime");
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd d MMM");
clock.writeConfig("fontWeight", 600);
clock.writeConfig("use24hFormat", 2);
top.addWidget("org.kde.plasma.panelspacer");
var quick = top.addWidget("org.kde.plasma.quicklaunch");
quick.currentConfigGroup = ["General"];
quick.writeConfig("launcherUrls", ["file://" + HOME + "/.local/share/applications/appearance-toggle.desktop"]);
quick.writeConfig("showLauncherNames", false);
var tray = top.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", true);

var dock = new Panel("org.kde.panel");
dock.location = "bottom";
dock.height = 64;
dock.floating = true;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.hiding = "dodgewindows";
dock.opacity = "translucent";
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", LAUNCHERS);
tasks.writeConfig("maxStripes", 1);
tasks.writeConfig("iconSpacing", 2);
tasks.writeConfig("indicateAudioStreams", true);

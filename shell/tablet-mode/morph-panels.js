// Switch the panels between tablet and PC mode (tabletd prepends TABLET, PHASE, HOME and LAUNCHERS).
// The system tray costs ~3 s to create on this Atom, so the panel holding it is kept in both modes
// and only reshaped; the cheaper widgets around it are added/removed:
//   tablet: status bar on top  [clock | spacer | quicklaunch | tray]   + floating dock [tasks]
//   PC:     one bottom bar     [apps | tasks | spacer | quicklaunch | tray | clock | show desktop]
// (the spacer stays in both, expanding only in the tablet status bar). Prints "REBUILD" when the
// tray panel is missing (first run): tabletd then builds the tablet layout and runs this again.
// Runs in PHASEs: Plasma lays the panel out between script calls, and "insert at the start"
// (addWidget at 0,0) is only reliable against an up-to-date layout:
//   phase 1: remove/move/reshape, append clock + show desktop (PC)
//   phase 2: tablet: clock at the start;  PC: tasks at the start
//   phase 3: PC: apps button at the start (in front of the tasks)
//   phase 9: put the widgets in ORDER (run last and once more later; a widget added in the same
//            script call gets its final index only after Plasma lays the panel out)
(function () {
    var bar = null;
    var docks = [];
    panels().forEach(function (p) {
        var types = p.widgets().map(function (w) { return w.type; });
        if (!bar && types.indexOf("org.kde.plasma.systemtray") !== -1) {
            bar = p;
        } else {
            docks.push(p);
        }
    });
    if (!bar) {
        print("REBUILD");
        return;
    }

    function find(type) {
        var found = null;
        bar.widgets().forEach(function (w) { if (w.type === type) { found = w; } });
        return found;
    }
    function remove(type) {
        var w = find(type);
        if (w) { w.remove(); }
    }
    // Widget order of the bar. addWidget(0, 0) alone sometimes appended at the end (tasks after
    // show desktop), so every phase ends by putting the widgets in this order via Widget.index.
    var ORDER = TABLET ? ["org.kde.plasma.digitalclock", "org.kde.plasma.panelspacer", "org.kde.plasma.quicklaunch",
                          "org.kde.plasma.systemtray"]
                       : ["org.kde.plasma.kickoff", "org.kde.plasma.icontasks", "org.kde.plasma.panelspacer",
                          "org.kde.plasma.quicklaunch", "org.kde.plasma.systemtray", "org.kde.plasma.digitalclock",
                          "org.kde.plasma.showdesktop"];
    function ordered() {
        var types = bar.widgets().slice().sort(function (a, b) { return a.index - b.index; })
                       .map(function (w) { return w.type; })
                       .filter(function (t) { return ORDER.indexOf(t) !== -1; });
        var want = ORDER.filter(function (t) { return types.indexOf(t) !== -1; });
        return types.join() === want.join();
    }
    function arrange() {
        var i = 0;
        ORDER.forEach(function (type) {
            var w = find(type);
            if (w) {
                if (w.index !== i) { w.index = i; }
                ++i;
            }
        });
    }

    if (PHASE === 9) {
        if (!ordered()) {
            arrange();
        }
        print(ordered() ? "DONE" : "UNORDERED");
        return;
    }

    // already in the requested shape (e.g. at login): nothing to rebuild
    if (PHASE === 1) {
        var hasDock = docks.some(function (p) { return p.widgets().some(function (w) { return w.type === "org.kde.plasma.icontasks"; }); });
        var ready = TABLET ? (bar.location === "top" && find("org.kde.plasma.digitalclock") && hasDock && !find("org.kde.plasma.icontasks"))
                           : (bar.location === "bottom" && find("org.kde.plasma.kickoff") && find("org.kde.plasma.icontasks") && docks.length === 0);
        if (ready && !ordered()) {
            arrange();
        }
        if (ready) {
            print("DONE");
            return;
        }
    }

    function configureClock(w) {
        w.currentConfigGroup = ["Appearance"];
        w.writeConfig("showDate", true);
        w.writeConfig("use24hFormat", 2);
        if (TABLET) {
            w.writeConfig("fontWeight", 600);
            w.writeConfig("dateDisplayFormat", "BesideTime");
            w.writeConfig("dateFormat", "custom");
            w.writeConfig("customDateFormat", "ddd d MMM");
        } else {
            w.writeConfig("dateDisplayFormat", "BelowTime");
        }
    }
    function configureTasks(w, dock) {
        w.currentConfigGroup = ["General"];
        w.writeConfig("launchers", LAUNCHERS);
        w.writeConfig("maxStripes", 1);
        w.writeConfig("indicateAudioStreams", true);
        if (dock) {
            w.writeConfig("iconSpacing", 2);
        }
    }

    if (PHASE === 2) {
        if (TABLET) {
            if (!find("org.kde.plasma.digitalclock")) {
                configureClock(bar.addWidget("org.kde.plasma.digitalclock", 0, 0, -1, -1));
            }
        } else if (!find("org.kde.plasma.icontasks")) {
            configureTasks(bar.addWidget("org.kde.plasma.icontasks", 0, 0, -1, -1), false);
        }
        arrange();
        return;
    }
    if (PHASE === 3) {
        if (!TABLET && !find("org.kde.plasma.kickoff")) {
            var apps = bar.addWidget("org.kde.plasma.kickoff", 0, 0, -1, -1);
            apps.currentConfigGroup = ["General"];
            apps.writeConfig("icon", "view-app-grid-symbolic");
            apps.writeConfig("favoritesDisplay", 0);
            apps.writeConfig("applicationsDisplay", 0);
            apps.writeConfig("showActionButtonCaptions", false);
            apps.writeConfig("primaryActions", 3);
            apps.currentConfigGroup = [];
            apps.writeConfig("popupWidth", 760);
            apps.writeConfig("popupHeight", 600);
        }
        arrange();
        return;
    }

    // phase 1. The clock moves: left of everything in the tablet status bar (added in phase 2),
    // after the tray in the PC bar
    remove("org.kde.plasma.digitalclock");
    if (!TABLET) {
        configureClock(bar.addWidget("org.kde.plasma.digitalclock"));
    }

    var tray = find("org.kde.plasma.systemtray");
    tray.currentConfigGroup = ["General"];
    tray.writeConfig("scaleIconsToFit", TABLET);
    tray.reloadConfig();

    var spacer = find("org.kde.plasma.panelspacer");
    if (spacer) {
        spacer.currentConfigGroup = ["General"];
        spacer.writeConfig("expanding", TABLET);
        spacer.writeConfig("length", TABLET ? 1 : 0);
        spacer.reloadConfig();
    }

    if (TABLET) {
        remove("org.kde.plasma.kickoff");
        remove("org.kde.plasma.icontasks");
        remove("org.kde.plasma.showdesktop");
        bar.location = "top";
        bar.height = 28;
        bar.floating = false;
        bar.hiding = "none";
        bar.lengthMode = "fill";
        bar.opacity = "translucent";

        // the dock: keep an existing one, create it otherwise
        var dock = null;
        docks.forEach(function (p) {
            var hasTasks = p.widgets().some(function (w) { return w.type === "org.kde.plasma.icontasks"; });
            if (!dock && hasTasks) { dock = p; } else { p.remove(); }
        });
        if (!dock) {
            dock = new Panel("org.kde.panel");
            configureTasks(dock.addWidget("org.kde.plasma.icontasks"), true);
        }
        dock.location = "bottom";
        dock.height = 64;
        dock.floating = true;
        dock.lengthMode = "fit";
        dock.alignment = "center";
        dock.hiding = "dodgewindows";
        dock.opacity = "translucent";
    } else {
        docks.forEach(function (p) { p.remove(); });
        // tasks and the apps button go in front in phases 2 and 3
        remove("org.kde.plasma.kickoff");
        remove("org.kde.plasma.icontasks");
        remove("org.kde.plasma.showdesktop");
        bar.addWidget("org.kde.plasma.showdesktop");
        bar.location = "bottom";
        bar.height = 44;
        bar.floating = false;
        bar.hiding = "none";
        bar.lengthMode = "fill";
        bar.alignment = "left";
        bar.opacity = "translucent";
    }
    arrange();
})();

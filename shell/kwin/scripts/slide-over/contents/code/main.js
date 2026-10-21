// Slide Over: the active window becomes a narrow panel floating on the right above everything.
//  - run on a normal window: it becomes the Slide Over panel (an earlier panel goes back to full screen)
//  - run while the panel is hidden or behind: show it; run on the panel itself: back to full screen
// "Slide Over Quick Note" makes the next Rnote window open as the panel (pen corner swipe).
var panel = null;
var quickNotePending = false;

function panelRect(w) {
    var area = workspace.clientArea(KWin.MaximizeArea, w);
    var width = Math.min(Math.round(area.width * 0.36), 520);
    var margin = 12;
    return { x: area.x + area.width - width - margin, y: area.y + margin,
             width: width, height: area.height - 2 * margin };
}

function release(w) {
    if (!w) {
        return;
    }
    w.keepAbove = false;
    w.setMaximize(true, true);
}

function makePanel(w) {
    if (panel && panel !== w) {
        release(panel);
    }
    panel = w;
    w.setMaximize(false, false);
    w.keepAbove = true;
    w.minimized = false;
    w.frameGeometry = panelRect(w);
    workspace.activeWindow = w;
}

function slideOver() {
    var w = workspace.activeWindow;
    if (panel && w === panel) {
        panel.minimized = true;          // on the panel: slide it away
    } else if (panel && panel.minimized) {
        panel.minimized = false;         // panel hidden: bring it back
        workspace.activeWindow = panel;
    } else if (w && w.normalWindow) {
        makePanel(w);                    // any other window: it becomes the panel
    }
}

function backToFullScreen() {
    if (panel) {
        var w = panel;
        panel = null;
        release(w);
        workspace.activeWindow = w;
    }
}

workspace.windowRemoved.connect(function (w) {
    if (w === panel) {
        panel = null;
    }
});

workspace.windowAdded.connect(function (w) {
    if (quickNotePending && w.normalWindow && /rnote/i.test(w.resourceClass + " " + w.desktopFileName)) {
        quickNotePending = false;
        makePanel(w);
    }
});

// shortcut names in the UI language (tabletd writes it here: kwinrc [Script-<name>] russian)
var RU = readConfig("russian", true);
registerShortcut("Slide Over", RU ? "Slide Over: плавающее окно" : "Slide Over: floating window", "Meta+O", slideOver);
registerShortcut("Slide Over Full Screen", RU ? "Slide Over: окно на весь экран" : "Slide Over: window to full screen", "Meta+Shift+O", backToFullScreen);
registerShortcut("Slide Over Quick Note", RU ? "Slide Over: быстрая заметка" : "Slide Over: quick note", "", function () {
    // an already open Rnote becomes the panel right away; otherwise wait for it to open
    var list = workspace.windowList();
    for (var i = 0; i < list.length; ++i) {
        if (list[i].normalWindow && /rnote/i.test(list[i].resourceClass + " " + list[i].desktopFileName)) {
            makePanel(list[i]);
            return;
        }
    }
    quickNotePending = true;
});

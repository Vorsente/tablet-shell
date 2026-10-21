// Dock mode (loaded by tabletd only while docked with an external monitor): the built-in panel
// shows the dashboard, so app windows that land on it are moved to the external screen.
function isInternal(output) {
    return output && output.name.indexOf("eDP") === 0;
}

function externalOutput() {
    var screens = workspace.screens;
    for (var i = 0; i < screens.length; ++i) {
        if (!isInternal(screens[i])) {
            return screens[i];
        }
    }
    return null;
}

function keepOffInternal(w) {
    if (!w.normalWindow || w.specialWindow || w.skipTaskbar || !isInternal(w.output)) {
        return;
    }
    var ext = externalOutput();
    if (ext) {
        workspace.sendClientToScreen(w, ext);
    }
}

function watch(w) {
    keepOffInternal(w);
    w.outputChanged.connect(function () { keepOffInternal(w); });
}

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);

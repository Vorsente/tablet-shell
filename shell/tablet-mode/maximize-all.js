// Tablet mode: maximize every normal window, like apps on iPadOS
for (const w of workspace.windowList()) {
    if (w.normalWindow && w.maximizable && !w.minimized) {
        w.setMaximize(true, true);
    }
}

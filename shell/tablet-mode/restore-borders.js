// PC mode: windows opened in tablet mode lost their title bars (the tablet-noborder rule); give
// them back, with close / minimize / maximize, and let maximized ones be restored like on a desktop.
// Full-screen windows (the typewriter) are left alone.
for (const w of workspace.windowList()) {
    if (w.normalWindow && !w.fullScreen) {
        w.noBorder = false;
    }
}

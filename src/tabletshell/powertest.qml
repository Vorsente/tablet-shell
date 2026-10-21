// Test: the power menu without doing anything. POWER_FRAME="close,shrink,dot" shows one frame of
// the switch-off animation instead of the menu.
import QtQuick

PowerMenu {
    id: menu
    dryRun: true
    Component.onCompleted: open()
    Timer {
        interval: 600
        running: true
        onTriggered: {
            const f = shell.env("POWER_FRAME");
            if (f) {
                const v = f.split(",").map(Number);
                menu.preview(v[0], v[1], v[2]);
            }
        }
    }
    Timer { interval: 7000; running: true; onTriggered: Qt.quit() }
}

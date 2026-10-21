// Test: one frame of the mode animation. MODE_FROM, MODE_TO, MODE_AT (ms) from the environment.
import QtQuick

ModeTransition {
    id: scene
    Component.onCompleted: play(shell.env("MODE_FROM"), shell.env("MODE_TO"))
    // seek once the window has its size (the zoom target is measured in window coordinates)
    Timer { interval: 600; running: true; onTriggered: scene.seek(parseInt(shell.env("MODE_AT")) || 1000) }
    Timer { interval: 7000; running: true; onTriggered: Qt.quit() }
}

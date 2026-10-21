// Login screen (greetd): the shared lock surface with the greeter backend from main.cpp
import QtQuick

LockSurface {
    id: surface
    cfg: greeter.config
    wallpaperFile: greeter.wallpaper
    auth: QtObject {
        readonly property string mode: "login"
        readonly property string fullName: greeter.fullName
        readonly property string avatar: greeter.avatar
        readonly property bool busy: greeter.busy
        readonly property bool passwordless: false
        signal failed(string message)
        signal succeeded()
        function login(password) { greeter.login(password); }
        function unlockNow() {}
        function powerOff() { greeter.powerOff(); }
        function reboot() { greeter.reboot(); }
        function suspend() { greeter.suspend(); }
    }
    Connections {
        target: greeter
        function onFailed(message) { surface.auth.failed(message); }
        function onLoggedIn() { surface.auth.succeeded(); }
    }
    unlocking: Qt.application.arguments.indexOf("--panel") !== -1
}

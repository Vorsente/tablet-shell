// Web app window: the site fills the window, its own persistent profile (cookies, logins),
// links that want a new window open in the normal browser.
import QtQuick
import QtQuick.Window
import QtWebEngine

Window {
    id: win
    width: 1100
    height: 720
    visible: true
    title: view.title || appName
    color: "black"

    WebEngineView {
        id: view
        anchors.fill: parent
        url: startUrl
        profile: WebEngineProfile {
            storageName: appId
            offTheRecord: false
            persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
            httpCacheType: WebEngineProfile.DiskHttpCache
        }
        settings.touchIconsEnabled: true
        settings.scrollAnimatorEnabled: true

        onNewWindowRequested: request => Qt.openUrlExternally(request.requestedUrl)
        onPermissionRequested: permission => {
            if (permission.permissionType === WebEnginePermission.PermissionType.Notifications) {
                permission.grant();
            } else {
                permission.deny();
            }
        }
        onFileDialogRequested: request => {}  // default dialog
    }

    // Back: mouse back button or Alt+Left, like a browser
    Shortcut { sequences: ["Alt+Left", "Back"]; onActivated: view.goBack() }
    Shortcut { sequences: ["Alt+Right", "Forward"]; onActivated: view.goForward() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; onActivated: view.reload() }
    Shortcut { sequence: "F11"; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
}

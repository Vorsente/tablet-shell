// Lock screen (kscreenlocker greeter): the shared lock surface (LockSurface.qml, also the login
// screen) with kscreenlocker's authenticator. lockscreen-sync copies this directory into the user
// copy of the desktop shell and writes LockConfig.js from /var/lib/tablet-greeter/lock.conf.
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as Notifications
import org.kde.plasma.private.mpris as Mpris
import "LockConfig.js" as LockConfig
import "Tr.js" as Tr

Item {
    id: root
    // what kscreenlocker sets on the root item
    property bool debug: false
    property string notification
    property bool viewVisible: false
    signal clearPassword()
    signal notificationRepeated()

    implicitWidth: 800
    implicitHeight: 600

    // One unlock attempt = one PAM response. PAM only accepts a response while its conversation
    // waits at a prompt; a response sent too early is dropped ("no pending prompt") and then
    // neither succeeded nor failed arrives, so only in that case it is sent once more. Never
    // resend while a check may be running: every extra wrong check counts for pam_faillock.
    property string pendingPassword
    property bool sent: false
    function sendPassword() {
        if (pendingPassword.length > 0 && !sent) {
            sent = true;
            authenticator.respond(pendingPassword);
        }
    }
    function finishAttempt() {
        lostTimer.stop();
        failTimer.stop();
        pendingPassword = "";
        sent = false;
    }

    // keep the PAM worker alive and waiting at its prompt (same heartbeat as the stock lock screen)
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: !authenticator.unlocked && root.pendingPassword.length === 0
        onTriggered: authenticator.startAuthenticating()
    }
    // no answer at all -> the response was dropped: start a conversation and send it again
    Timer {
        id: lostTimer
        interval: 4000
        onTriggered: {
            root.sent = false;
            authenticator.startAuthenticating();
            root.sendPassword();
            restart();
        }
    }
    // "failed" may be followed by "succeeded" (other PAM workers); report it only if it stays
    Timer {
        id: failTimer
        interval: 1500
        onTriggered: {
            root.finishAttempt();
            surface.auth.failed(Tr.t("Неверный пароль"));
            graceTimer.restart();
        }
    }

    // the player playing now, for the media card
    Mpris.Mpris2Model {
        id: mpris
    }

    LockSurface {
        id: surface
        anchors.fill: parent
        cfg: LockConfig.config
        wallpaperItem: typeof wallpaper !== "undefined" ? wallpaper : null
        notifications: Notifications.WatchedNotificationsModel {}
        player: mpris.currentPlayer
        auth: QtObject {
            readonly property string mode: "lock"
            readonly property string fullName: kscreenlocker_userName
            readonly property string avatar: kscreenlocker_userImage ? String(kscreenlocker_userImage) : ""
            property bool busy: false
            // grace period after locking / no password set: a swipe unlocks
            readonly property bool passwordless: authenticator.unlocked
            // KWin tablet mode (tabletd: on when no keyboard is attached): the on-screen keyboard by touch
            readonly property bool touchFirst: Kirigami.Settings.tabletMode
            signal failed(string message)
            signal succeeded()
            function login(password) {
                busy = true;
                root.finishAttempt();
                root.pendingPassword = password;
                authenticator.startAuthenticating();   // may have stopped after suspend
                root.sendPassword();
                lostTimer.restart();
            }
            function unlockNow() { Qt.quit(); }
            function powerOff() {}
            function reboot() {}
            function suspend() {}
        }
        focus: true
    }

    Connections {
        target: authenticator
        function onPromptForSecretChanged() {
            if (authenticator.promptForSecret.length > 0) {
                root.sendPassword();
            }
        }
        function onSucceeded() {
            authenticator.stopAuthenticating();
            const typed = root.pendingPassword.length > 0;
            root.finishAttempt();
            if (authenticator.hadPrompt || typed) {
                surface.auth.busy = false;
                surface.auth.succeeded();
                quitTimer.start();
            }
        }
        function onFailed(kind) {
            if (kind !== 0) {
                return;     // non-interactive authenticators (fingerprint etc.)
            }
            if (root.pendingPassword.length === 0) {
                return;     // nothing typed: a stale conversation ended
            }
            lostTimer.stop();
            failTimer.restart();
        }
    }
    // after a wrong password PAM needs a moment before the next try
    Timer {
        id: graceTimer
        interval: 1500
        onTriggered: surface.auth.busy = false
    }
    Timer {
        id: quitTimer
        interval: 300
        onTriggered: Qt.quit()
    }
}

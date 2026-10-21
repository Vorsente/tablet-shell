// Control center (iPadOS style): swipe down from the top edge. Quick setting tiles come from
// Plasma Mobile (plasmamobilerc [QuickSettings] enabledQuickSettings), plus dark mode,
// the typewriter, and brightness / volume sliders. Tap outside the panel to close.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.private.mobileshell.quicksettingsplugin as QS
import org.kde.plasma.private.mobileshell.screenbrightnessplugin as ScreenBrightness
import org.kde.plasma.private.volume as PA
import QtMultimedia
import "Tr.js" as Tr

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Пункт управления")

    LayerShell.Window.scope: "tabletshell-control"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    property string home: shell.env("HOME")
    property int battery: 0
    property bool charging: false
    property string appearance: "auto"
    property string now: ""

    function refresh() {
        now = Qt.formatTime(new Date(), "HH:mm");
        battery = parseInt(shell.readFile(shell.batteryDir() + "/capacity")) || 0;
        charging = shell.readFile(shell.batteryDir() + "/status") === "Charging";
        appearance = shell.run([home + "/.local/bin/appearance", "status"]).trim() || "auto";
        reading = shell.run([home + "/.local/bin/reading-mode", "status"]).trim() === "on";
        // Android session = the user's own "python3 /usr/bin/waydroid ..." process
        android = shell.run(["pgrep", "-u", shell.env("USER"), "-f", "^python3 /usr/bin/waydroid"]).trim() !== "";
    }
    property bool android: false
    // Waydroid installed at all (the Android tile is hidden without it)
    readonly property bool hasWaydroid: shell.run(["sh", "-c", "command -v waydroid"]).trim() !== ""

    // give memory back a few seconds after the control center (or a panel opened from it) closed
    Timer {
        id: trimTimer
        interval: 4000
        onTriggered: {
            gc();
            shell.trim();
        }
    }
    onVisibleChanged: if (!visible) trimTimer.restart()

    // Back gesture along the left edge (tablet mode): its own top-level windows
    property var backGesture: null
    Component {
        id: backGestureComponent
        BackGesture {}
    }

    // Separate top-level window (a child Window would only show together with this one)
    property var notificationCenter: null
    Component {
        id: notificationCenterComponent
        NotificationCenter {}
    }
    property var screenTime: null
    Component {
        id: screenTimeComponent
        ScreenTime {}
    }
    // mode change animation: built at start, so the first switch does not pay for it
    property var modeTransition: null
    Component {
        id: modeTransitionComponent
        ModeTransition {}
    }
    // privacy indicator: orange / green dot at the top while an app uses the microphone / camera
    // (its own top-level window, like the others)
    property var recording: null
    Component {
        id: recordingComponent
        RecordingIndicator {}
    }

    // pen tool ring (pen button held in the air), built on first use
    property var penRing: null
    Component {
        id: penRingComponent
        PenRing {}
    }

    // power menu (held power button), built on first use
    property var powerMenu: null
    Component {
        id: powerMenuComponent
        PowerMenu {}
    }

    // charging animation; when the charger comes with a mode change it waits for that animation
    property var charge: null
    Component {
        id: chargeComponent
        ChargeAnimation {}
    }
    property bool chargePending: false
    function showCharging() {
        if (modeTransition && modeTransition.visible) {
            chargePending = true;
            return;
        }
        if (!charge) {
            charge = chargeComponent.createObject(null);
        }
        charge.play();
    }
    Connections {
        target: win.modeTransition
        function onVisibleChanged() {
            if (!win.modeTransition.visible && win.chargePending) {
                win.chargePending = false;
                win.showCharging();
            }
        }
    }
    SoundEffect {
        id: unlockSound
        source: "file://" + win.home + "/.local/share/tabletshell/sounds/unlock.wav"
        volume: 0.5
    }
    SoundEffect {
        id: lockSound
        source: "file://" + win.home + "/.local/share/tabletshell/sounds/lock.wav"
        volume: 0.5
    }
    property bool reading: false
    // the notification center watches notifications from login on, so it exists from the start;
    // screen time is only built when it is first opened
    Component.onCompleted: {
        notificationCenter = notificationCenterComponent.createObject(null);
        backGesture = backGestureComponent.createObject(null);
        modeTransition = modeTransitionComponent.createObject(null);
        recording = recordingComponent.createObject(null);
    }
    function showScreenTime() {
        if (!screenTime) {
            screenTime = screenTimeComponent.createObject(null);
        }
        screenTime.toggle();
    }

    Connections {
        target: shell
        function onModeTransitionRequested(from, to, sound) {
            win.visible = false;
            notificationCenter.visible = false;
            modeTransition.play(from, to, sound);
        }
        function onPenRingRequested(x, y) {
            if (!penRing) {
                penRing = penRingComponent.createObject(null);
            }
            penRing.show(x, y);
        }
        function onPowerMenuRequested() {
            win.visible = false;
            notificationCenter.visible = false;
            if (!powerMenu) {
                powerMenu = powerMenuComponent.createObject(null);
            }
            powerMenu.open();
        }
        function onChargingStarted() {
            win.showCharging();
        }
        function onUnlocked() {
            unlockSound.play();
        }
        function onLockedNow() {
            lockSound.play();
        }
        function onModeReadyRequested() {
            modeTransition.ready();
        }
        function onScreenTimeRequested() {
            win.visible = false;
            win.showScreenTime();
        }
        function onNotificationsRequested() {
            win.visible = false;
            notificationCenter.toggle();
        }
        function onToggleRequested() {
            notificationCenter.visible = false;
            if (!win.visible) {
                win.refresh();
            }
            win.visible = !win.visible;
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: win.visible
        onTriggered: win.refresh()
    }

    QS.QuickSettingsModel { id: quickSettings }
    ScreenBrightness.ScreenBrightnessUtil { id: brightness }

    // dimmed backdrop: tap to close
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: win.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MouseArea { anchors.fill: parent; onClicked: win.visible = false }
    }

    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.gridUnit
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 22)
        height: content.implicitHeight + Kirigami.Units.gridUnit * 2
        radius: Kirigami.Units.gridUnit * 1.4
        color: Qt.rgba(0.12, 0.12, 0.15, 0.88)
        border.color: Qt.rgba(1, 1, 1, 0.16)
        border.width: 1

        MouseArea { anchors.fill: parent }  // keep taps inside

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            // Clock and battery
            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    Layout.fillWidth: true
                    text: win.now
                    color: "white"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2
                    font.weight: Font.DemiBold
                }
                Kirigami.Icon {
                    source: win.charging ? "battery-charging" : "battery"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                }
                PC3.Label {
                    text: win.battery + "%"
                    color: "white"
                    font.weight: Font.DemiBold
                }
            }

            // Tiles
            GridLayout {
                id: tiles
                Layout.fillWidth: true
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing * 2
                rowSpacing: Kirigami.Units.smallSpacing * 2

                component Tile: ColumnLayout {
                    id: tile
                    property string label
                    property string iconName
                    property bool on: false
                    signal activated()
                    signal held()
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Kirigami.Units.gridUnit * 3.4
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: tile.on ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.14)
                        scale: area.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: 80 } }
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: tile.iconName
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: implicitWidth
                            color: "white"
                            isMask: true
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            onClicked: tile.activated()
                            onPressAndHold: tile.held()
                        }
                    }
                    PC3.Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 4.6
                        text: tile.label
                        color: "white"
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }

                Repeater {
                    model: quickSettings
                    delegate: Tile {
                        required property var modelData
                        visible: modelData.available
                        label: modelData.text
                        iconName: modelData.icon
                        on: modelData.enabled
                        onActivated: {
                            modelData.toggle();
                            // actions that act on the screen: get out of the way
                            if (/screenshot|record|system-shutdown|application-exit/.test(modelData.icon)) {
                                win.visible = false;
                            }
                        }
                        onHeld: {
                            if (modelData.settingsCommand) {
                                shell.start(["sh", "-c", modelData.settingsCommand]);
                                win.visible = false;
                            }
                        }
                    }
                }

                Tile {
                    label: Tr.t("Тёмная тема")
                    iconName: "weather-clear-night"
                    on: win.appearance === "dark"
                    onActivated: {
                        shell.start([win.home + "/.local/bin/appearance", on ? "light" : "dark"]);
                        win.appearance = on ? "light" : "dark";
                    }
                    onHeld: {
                        shell.start([win.home + "/.local/bin/appearance", "auto"]);
                        win.appearance = "auto";
                    }
                }
                Tile {
                    label: "Split View"
                    iconName: "view-split-left-right"
                    onActivated: {
                        win.visible = false;
                        shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Split View"]);
                    }
                }
                Tile {
                    label: "Slide Over"
                    iconName: "window-duplicate"
                    onActivated: {
                        win.visible = false;
                        shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Slide Over"]);
                    }
                }
                Tile {
                    label: Tr.t("Картинка в картинке")
                    iconName: "window-restore-pip"
                    onActivated: {
                        win.visible = false;
                        shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Picture in Picture"]);
                    }
                }
                Tile {
                    label: Tr.t("Заметка")
                    iconName: "draw-freehand"
                    onActivated: {
                        win.visible = false;
                        shell.start([win.home + "/.local/bin/quick-note"]);
                    }
                }
                Tile {
                    label: Tr.t("Читалка")
                    iconName: "view-readermode"
                    on: win.reading
                    onActivated: {
                        win.visible = false;
                        const firefox = shell.currentApp().toLowerCase().indexOf("firefox") !== -1;
                        shell.start([win.home + "/.local/bin/reading-mode", "toggle", firefox ? "firefox" : ""]);
                    }
                }
                Tile {
                    label: Tr.t("Экранное время")
                    iconName: "chronometer"
                    onActivated: {
                        win.visible = false;
                        win.showScreenTime();
                    }
                }
                Tile {
                    label: Tr.t("Уведомления")
                    iconName: "notifications-symbolic"
                    onActivated: {
                        win.visible = false;
                        notificationCenter.visible = true;
                    }
                }
                Tile {
                    // Android holds ~1 GB even when idle: tap stops it, it starts again with any Android app
                    visible: win.hasWaydroid
                    label: on ? Tr.t("Android: стоп") : "Android"
                    iconName: "waydroid"
                    on: win.android
                    onActivated: {
                        if (on) {
                            shell.start(["waydroid", "session", "stop"]);
                            win.android = false;
                        } else {
                            shell.start(["waydroid", "show-full-ui"]);
                            win.visible = false;
                        }
                    }
                }
                Tile {
                    label: Tr.t("Настройки")
                    iconName: "preferences-system"
                    onActivated: {
                        win.visible = false;
                        shell.start([win.home + "/.local/bin/tablet-settings"]);
                    }
                }
                Tile {
                    label: Tr.t("Машинка")
                    iconName: "document-edit"
                    onActivated: {
                        shell.start([win.home + "/.local/bin/typewriter"]);
                        win.visible = false;
                    }
                }
            }

            // Sliders
            component SliderRow: RowLayout {
                property alias iconName: icon.source
                property alias value: slider.value
                signal moved(real v)
                Layout.fillWidth: true
                Kirigami.Icon {
                    id: icon
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                    color: "white"
                    isMask: true
                }
                PC3.Slider {
                    id: slider
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    onMoved: parent.moved(value)
                }
            }

            SliderRow {
                visible: brightness.brightnessAvailable
                iconName: "brightness-high"
                value: brightness.maxBrightness > 0 ? brightness.brightness / brightness.maxBrightness : 0
                onMoved: v => brightness.brightness = Math.max(1, Math.round(v * brightness.maxBrightness))
            }
            SliderRow {
                visible: PA.PreferredDevice.sink !== null
                iconName: "audio-volume-high"
                value: PA.PreferredDevice.sink ? PA.PreferredDevice.sink.volume / 65536 : 0
                onMoved: v => {
                    if (PA.PreferredDevice.sink) {
                        PA.PreferredDevice.sink.muted = false;
                        PA.PreferredDevice.sink.volume = Math.round(v * 65536);
                    }
                }
            }
        }
    }
}

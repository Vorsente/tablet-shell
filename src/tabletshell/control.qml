// Control center (iOS 26 style): swipe down from the top edge. Liquid Glass modules over a dimmed,
// blurred backdrop: connectivity (airplane, Wi-Fi, Bluetooth, rotation), Do Not Disturb, tall
// brightness slider and round controls. Quick settings come from Plasma Mobile
// (plasmamobilerc [QuickSettings] enabledQuickSettings), the rest are the shell's own. Hold a
// control for its settings. Tap outside the modules to close.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mobileshell.quicksettingsplugin as QS
import org.kde.plasma.private.mobileshell.screenbrightnessplugin as ScreenBrightness
import org.kde.notificationmanager as NotificationManager
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

    readonly property bool pixel: uiStyle.pixel
    property string home: shell.env("HOME")
    property int battery: 0
    property bool charging: false
    property string now: ""
    property string today: ""

    function refresh() {
        now = Qt.formatTime(new Date(), "HH:mm");
        battery = parseInt(shell.readFile(shell.batteryDir() + "/capacity")) || 0;
        charging = shell.readFile(shell.batteryDir() + "/status") === "Charging";
        const day = new Date().toLocaleDateString(Tr.locale(), "dddd, d MMMM");
        today = day.charAt(0).toUpperCase() + day.slice(1);
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
        interval: 10000
        onTriggered: {
            gc();
            shell.trim();
        }
    }
    onVisibleChanged: {
        if (visible) {
            dndClock = new Date();
            enter.restart();
            blurTimer.restart();
        } else {
            trimTimer.restart();
        }
    }

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

    // text menu (long press on text, Shell::watchTouch), built on first use
    property var textMenu: null
    Component {
        id: textMenuComponent
        TextMenu {}
    }

    // power menu (held power button), built on first use
    property var powerMenu: null
    Component {
        id: powerMenuComponent
        PowerMenu {}
    }

    // volume / brightness bars when a key changes them (Osd.qml), built on first use
    property var osd: null
    Component {
        id: osdComponent
        Osd {}
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
        function onTextMenuRequested(x, y, editable, selected, canPaste, app, sel) {
            if (win.visible || notificationCenter.visible || (powerMenu && powerMenu.visible)) {
                return;   // the touch was meant for our own panel
            }
            if (!textMenu) {
                textMenu = textMenuComponent.createObject(null);
            }
            textMenu.show(x, y, editable, selected, canPaste, app, sel);
        }
        function onPowerMenuRequested() {
            win.showPowerMenu();
        }
        function onOsdRequested(member, args) {
            if (!win.osd) {
                win.osd = osdComponent.createObject(null);
            }
            win.osd.show(member, args);
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
            win.dismiss();
            win.showScreenTime();
        }
        function onNotificationsRequested() {
            win.dismiss();
            notificationCenter.toggle();
        }
        function onToggleRequested() {
            notificationCenter.visible = false;
            if (win.visible && !win.closing) {
                win.dismiss();
                return;
            }
            leave.stop();
            win.closing = false;
            win.refresh();
            win.visible = true;
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

    // ---- quick settings sorted into the modules ------------------------------------------------
    // Plasma Mobile's tiles, by their icon: the connectivity module takes its four, the rest become
    // round controls. Tiles that repeat something the control center already has are left out:
    // Waydroid (the Android control does more), Do Not Disturb (the Focus module), sound and
    // battery (the slider and the header), the settings app (own Settings control), and a second
    // tile of the same kind.
    property var qs: ({})        // airplane / wifi / bluetooth / rotation -> QuickSetting
    property var qsRest: []
    function category(q) {
        const i = String(q.icon || "");
        if (/flightmode|airplane/.test(i)) return "airplane";
        if (/hotspot/.test(i)) return "";
        if (/network-wireless/.test(i)) return "wifi";
        if (/bluetooth/.test(i)) return "bluetooth";
        if (/^rotation/.test(i)) return "rotation";
        if (/^notifications/.test(i)) return "skip";
        if (/android/.test(i)) return "skip";
        if (/^audio-|^battery|^configure|^preferences-system|^settings/.test(i)) return "skip";
        return "";
    }
    function collect() {
        const map = {}, rest = [], seen = {};
        for (let i = 0; i < qsSource.count; ++i) {
            const item = qsSource.itemAt(i);
            if (!item) continue;
            const q = item.modelData;
            const c = category(q);
            const key = String(q.icon) + "|" + String(q.text);
            if (c === "skip" || seen[key]) continue;
            seen[key] = true;
            if (c) {
                if (!map[c]) map[c] = q;
            } else {
                rest.push(q);
            }
        }
        qs = map;
        qsRest = rest;
    }

    // Do Not Disturb: Plasma's own notification setting (what the tray and the dashboard use).
    // Plasma Mobile's tile talks to the mobile shell, which is not running here.
    NotificationManager.Settings { id: notificationSettings }
    property date dndClock: new Date()
    readonly property bool dnd: notificationSettings.notificationsInhibitedByApplication
                                || (notificationSettings.notificationsInhibitedUntil !== undefined
                                    && new Date(notificationSettings.notificationsInhibitedUntil) > dndClock)
    function toggleDnd() {
        if (dnd) {
            notificationSettings.notificationsInhibitedUntil = undefined;
            notificationSettings.revokeApplicationInhibitions();
        } else {
            const until = new Date();
            until.setFullYear(until.getFullYear() + 1);      // until turned off
            notificationSettings.notificationsInhibitedUntil = until;
        }
        notificationSettings.save();
        dndClock = new Date();
    }
    // "hold for settings": Plasma Mobile names modules that a desktop install may not have
    function openSettings(command) {
        let kcm = String(command || "").replace(/^plasma-open-settings\s+/, "").trim();
        const renamed = { kcm_mobile_onscreenkeyboard: "kcm_virtualkeyboard", kcm_nightcolor: "kcm_nightlight" };
        kcm = renamed[kcm] || kcm;
        if (!kcm) {
            return;
        }
        shell.start([home + "/.local/bin/tablet-settings", kcm]);
        win.dismiss();
    }
    function showPowerMenu() {
        win.dismiss();
        notificationCenter.visible = false;
        if (!powerMenu) {
            powerMenu = powerMenuComponent.createObject(null);
        }
        powerMenu.open();
    }
    Repeater {
        id: qsSource
        model: quickSettings
        delegate: Item {
            required property var modelData
            Component.onCompleted: Qt.callLater(win.collect)
            Component.onDestruction: Qt.callLater(win.collect)
        }
    }
    // monochrome icons for Plasma Mobile's tiles (colour icons turn into blobs as masks)
    function iconFor(q) {
        const i = String(q.icon || "");
        if (/view-fullscreen/.test(i)) return "camera-photo-symbolic";
        if (/camera-video/.test(i)) return "media-record-symbolic";
        if (/redshift/.test(i)) return "redshift-status-on-symbolic";
        if (/system-shutdown/.test(i)) return "system-shutdown-symbolic";
        return i.endsWith("-symbolic") ? i : i + "-symbolic";
    }
    // plasma-mobile's record tile loses its translation domain: translate it here
    function labelFor(q) {
        return q.text === "Record Screen" ? Tr.t("Запись экрана") : q.text;
    }
    function kwinShortcut(name) {
        shell.start(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", name]);
    }

    // ---- look ----------------------------------------------------------------------------------
    readonly property real gu: (Kirigami.Units.gridUnit * uiStyle.dp)
    readonly property real sp: gu * 0.7                                   // gap between modules
    readonly property int cols: pixel ? 6 : 5   // Apple: connectivity 2 | brightness 1 | focus 2
    readonly property real cell: Math.min(gu * 4.4, (width - gu * 2 - sp * (cols - 1)) / cols)
    readonly property real span2: cell * 2 + sp
    // frosted, a little lighter than the dimmed backdrop (KWin blurs what is behind)
    // Pixel uses distinct Material light/dark surfaces; the Apple translucency is unchanged.
    readonly property bool materialDark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
    readonly property color materialInk: materialDark ? "#F4EFF4" : "#1D1B20"
    readonly property color headerInk: pixel ? materialInk : "white"
    readonly property color materialOnAccent: materialDark ? "#211A2E" : "#FFFFFF"
    readonly property color glassFill: pixel ? (materialDark ? "#2B2932" : "#F7F2FA") : Qt.rgba(0.96, 0.96, 1, 0.13)
    readonly property color glassRim: pixel ? (materialDark ? "#57515E" : "#D8CEDF") : Qt.rgba(1, 1, 1, 0.12)
    readonly property color offFill: pixel ? (materialDark ? "#49454F" : "#E6E0E9") : Qt.rgba(1, 1, 1, 0.17)
    readonly property color blue: pixel ? (materialDark ? "#D0BCFF" : "#6750A4") : "#0A84FF"
    readonly property color orange: pixel ? (materialDark ? "#FFB86C" : "#935F00") : "#FF9F0A"
    readonly property color purple: pixel ? (materialDark ? "#B69DF8" : "#6750A4") : "#5E5CE6"

    // one band of a glass rim: the outline of `target`, cut to its top (or bottom) `part` pixels
    component RimPart: Item {
        visible: !win.pixel
        required property Item target
        property real part
        property real strength
        property bool atBottom: false
        y: atBottom ? target.height - height : 0
        width: target.width
        height: Math.min(target.height, part)
        clip: true
        Rectangle {
            y: parent.atBottom ? parent.height - parent.target.height : 0
            width: parent.target.width
            height: parent.target.height
            radius: parent.target.radius
            color: "transparent"
            border.width: 1.2
            border.color: Qt.rgba(1, 1, 1, parent.strength)
        }
    }

    // Liquid Glass module: translucent fill, a rim lit from above (bright along the top, faint at
    // the bottom), a sheen over the upper half and, for the big modules (shadow: true), a soft
    // shadow around it - cut out under the glass itself so it does not darken it. Every module
    // registers itself for the blur behind it.
    component Glass: Rectangle {
        id: glass
        property bool shadow: false
        radius: win.pixel ? Math.min(width, height) * 0.22 : Math.min(width, height) * 0.36
        color: win.glassFill
        border.width: 1
        border.color: win.glassRim

        // shadow (below the fill: z -1), its inside masked away
        Item {
            id: shadowBox
            readonly property real pad: win.gu * 2
            visible: glass.shadow && !win.pixel
            z: -1
            x: -pad
            y: -pad
            width: glass.width + pad * 2
            height: glass.height + pad * 2
            layer.enabled: glass.shadow && !win.pixel
            layer.effect: MultiEffect {
                maskEnabled: true
                maskInverted: true
                maskSource: shadowHole
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
            RectangularShadow {
                x: shadowBox.pad
                y: shadowBox.pad + win.gu * 0.35
                width: glass.width
                height: glass.height
                radius: glass.radius
                blur: win.gu * 1.6
                color: Qt.rgba(0, 0, 0, 0.55)
            }
        }
        Item {
            id: shadowHole
            visible: false
            x: shadowBox.x
            y: shadowBox.y
            width: shadowBox.width
            height: shadowBox.height
            layer.enabled: glass.shadow && !win.pixel
            Rectangle {
                x: shadowBox.pad
                y: shadowBox.pad
                width: glass.width
                height: glass.height
                radius: glass.radius
            }
        }

        // sheen
        Rectangle {
            visible: !win.pixel
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, glass.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0; color: win.pixel ? "transparent" : Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        // rim lit from above: the top part of a brighter outline, and a faint one at the bottom
        RimPart { target: glass; part: glass.radius * 2.2; strength: 0.22 }
        RimPart { target: glass; part: glass.radius * 1.1; strength: 0.3 }
        RimPart { target: glass; part: glass.radius * 1.2; strength: 0.14; atBottom: true }

        Component.onCompleted: win.glassItems.push(glass)
    }

    // round control: glass circle with a symbolic icon, label below
    component Control: Item {
        id: control
        property string label
        property bool wideTile: false
        property string iconName
        property bool on: false
        property color onColor: win.pixel ? win.blue : "white"
        signal activated()
        signal held()
        width: win.pixel && wideTile ? win.span2 : win.cell
        height: win.pixel && wideTile ? win.cell : Math.max(win.cell, caption.y + caption.implicitHeight)

        Glass {
            id: circle
            anchors.horizontalCenter: parent.horizontalCenter
            width: win.pixel && control.wideTile ? control.width : win.cell * 0.68
            height: win.pixel && control.wideTile ? control.height : width
            radius: win.pixel ? height * 0.5 : width / 2
            color: control.on ? control.onColor : win.offFill
            scale: area.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 150 } }
            Kirigami.Icon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: win.pixel && control.wideTile ? -circle.width * 0.31 : 0
                source: control.iconName
                implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
                implicitHeight: implicitWidth
                isMask: true
                color: win.pixel ? (control.on ? win.materialOnAccent : win.materialInk) : control.on && Qt.colorEqual(control.onColor, "white") ? "#1C1C1E" : "white"
            }
            MouseArea {
                id: area
                anchors.fill: parent
                // scrolling the control center over a control is no tap
                property point from
                property bool moved: false
                onPressed: m => { from = Qt.point(m.x, m.y); moved = false; }
                onPositionChanged: m => { moved = moved || Math.hypot(m.x - from.x, m.y - from.y) > 18 * uiStyle.dp; }
                onClicked: if (!moved) control.activated()
                onPressAndHold: control.held()
            }
        }
        Text {
            id: caption
            y: win.pixel && control.wideTile ? (control.height - implicitHeight) / 2 : circle.height + (Kirigami.Units.smallSpacing * uiStyle.dp)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: win.pixel && control.wideTile ? control.width * 0.14 : 0
            width: win.pixel && control.wideTile ? control.width * 0.58 : win.cell + win.sp * 0.4
            text: control.label
            color: win.pixel ? (control.on ? win.materialOnAccent : win.materialInk) : Qt.rgba(1, 1, 1, 0.9)
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.9
            horizontalAlignment: win.pixel && control.wideTile ? Text.AlignLeft : Text.AlignHCenter
            font.family: Kirigami.Theme.defaultFont.family
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.weight: Font.Medium
        }
    }

    // a Plasma Mobile tile as a control
    component QsControl: Control {
        required property var q
        visible: q !== undefined && q !== null && q.available
        label: q ? win.labelFor(q) : ""
        iconName: q ? win.iconFor(q) : ""
        on: q ? q.enabled : false
        onActivated: {
            const icon = String(q.icon);
            // Plasma Mobile's screenshot and power tiles wait for the mobile shell, which is not
            // running here: the control center does these itself
            if (/view-fullscreen|screenshot/.test(icon)) {
                win.dismiss();
                shell.start(["sh", "-c", "sleep 0.5; exec spectacle --background --fullscreen"]);
                return;
            }
            if (/system-shutdown|application-exit/.test(icon)) {
                win.showPowerMenu();
                return;
            }
            q.toggle();
            // actions that act on the screen: get out of the way
            if (/record|camera/.test(icon)) {
                win.dismiss();
            }
        }
        onHeld: win.openSettings(q.settingsCommand)
    }

    // tall slider like iOS: fills from the bottom, follows the finger relative to where it went down
    component TallSlider: Glass {
        id: slider
        property real value: 0                  // 0..1 from outside
        property string iconName
        signal moved(real v)
        property real dragValue: 0
        readonly property real shown: drag.pressed ? dragValue : value
        width: win.pixel ? win.span2 : win.cell
        height: win.pixel ? win.cell : win.span2
        radius: win.pixel ? height / 2 : win.cell * 0.36
        shadow: true
        scale: drag.pressed ? 1.03 : 1
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: win.pixel ? parent.width * Math.max(0, Math.min(1, slider.shown)) : parent.width
            height: win.pixel ? parent.height : parent.height * Math.max(0, Math.min(1, slider.shown))
            radius: Math.min(slider.radius, height / 2)
            color: win.pixel ? win.blue : Qt.rgba(1, 1, 1, 0.92)
            // square top while the fill is tall: only the bottom follows the module's corners
            Rectangle {
                visible: !win.pixel && parent.height > slider.radius * 2 && parent.height < slider.height - slider.radius
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: slider.radius
                color: parent.color
            }
        }
        Kirigami.Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: win.pixel ? (slider.height - height) / 2 : win.cell * 0.28
            source: slider.iconName
            implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
            implicitHeight: implicitWidth
            isMask: true
            color: win.pixel ? (slider.shown >= 0.5 ? win.materialOnAccent : win.materialInk) : slider.shown * slider.height > win.cell * 0.28 + height / 2 ? "#3A3A3C" : "white"
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            preventStealing: true
            property real y0
            property real x0
            property real v0
            onPressed: m => {
                y0 = m.y;
                x0 = m.x;
                v0 = slider.value;
                slider.dragValue = v0;
            }
            onPositionChanged: m => {
                slider.dragValue = Math.max(0, Math.min(1, v0 + (win.pixel ? (m.x - x0) / slider.width : (y0 - m.y) / slider.height)));
                slider.moved(slider.dragValue);
            }
        }
    }

    // ---- blur behind the glass -------------------------------------------------------------------
    property var glassItems: []
    function updateBlur() {
        if (!visible || closing) {
            return;
        }
        if (pixel) { shell.blurBehind(win, []); return; }
        const areas = [];
        glassItems = glassItems.filter(g => !!g);   // controls of a rebuilt list are gone
        for (const g of glassItems) {
            if (!g || !g.visible || g.width <= 0) continue;
            let shownInTree = true;
            for (let p = g.parent; p && p !== stage; p = p.parent) {
                if (!p.visible) { shownInTree = false; break; }
            }
            if (!shownInTree) continue;
            const r = g.mapToItem(stage, 0, 0);
            areas.push({ x: stage.x + r.x, y: stage.y + r.y, width: g.width, height: g.height, radius: g.radius });
        }
        shell.blurBehind(win, areas);
    }
    Timer {
        id: blurTimer
        interval: 90
        onTriggered: win.updateBlur()
    }
    onPixelChanged: blurTimer.restart()
    onWidthChanged: blurTimer.restart()
    onHeightChanged: blurTimer.restart()

    // Closing: the blur behind the modules goes first (KWin would keep drawing its rectangles while
    // the window fades), then the modules fade out quickly and the dimming last: what is seen is
    // only the screen getting lighter again.
    property bool closing: false
    property real dim: 0
    function dismiss() {
        if (!visible || closing) {
            return;
        }
        closing = true;
        blurTimer.stop();
        shell.blurBehind(win, []);
        enter.stop();
        leave.restart();
    }
    SequentialAnimation {
        id: leave
        NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InCubic }
        NumberAnimation { target: win; property: "dim"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        ScriptAction {
            script: {
                win.visible = false;
                win.closing = false;
            }
        }
    }

    // dimmed backdrop: tap to close
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, win.pixel ? 0.5 : 0.38)
        opacity: win.dim
        MouseArea { anchors.fill: parent; onClicked: win.dismiss() }
    }
    // Material: the modules sit on an opaque quick-settings sheet (Apple: glass on the backdrop)
    Rectangle {
        visible: win.pixel
        readonly property real pad: win.sp * 1.6
        x: stage.x - pad
        y: stage.y - pad
        width: stage.width + pad * 2
        height: stage.height + pad * 2
        radius: win.gu * 1.6
        color: win.materialDark ? "#141218" : "#ECE6F0"
        opacity: stage.opacity
        scale: stage.scale
        transformOrigin: Item.TopRight
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "dim"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: stage; property: "scale"; from: 0.94; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }

    Flickable {
        id: stage
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: win.pixel || contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        onContentYChanged: blurTimer.restart()
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: win.gu * 1.4
        anchors.rightMargin: win.gu
        width: win.cols * win.cell + (win.cols - 1) * win.sp
        height: Math.min(column.implicitHeight, win.height - anchors.topMargin - win.gu)
        transformOrigin: Item.TopRight
        onHeightChanged: blurTimer.restart()

        MouseArea { anchors.fill: parent }  // taps between the modules do not close it

        Column {
            id: column
            width: parent.width
            spacing: win.sp

            // date and battery, straight on the backdrop
            Item {
                width: parent.width
                height: win.gu * 1.6
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: win.gu * 0.3
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.today
                    color: win.headerInk
                    font.family: Kirigami.Theme.defaultFont.family
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: win.gu * 0.3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: (Kirigami.Units.smallSpacing * uiStyle.dp)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.battery + "%"
                        color: win.headerInk
                        font.family: Kirigami.Theme.defaultFont.family
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        font.weight: Font.DemiBold
                    }
                    Kirigami.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: win.charging ? "battery-full-charging-symbolic" : "battery-good-symbolic"
                        implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
                        implicitHeight: implicitWidth
                        isMask: true
                        color: win.charging ? (win.pixel ? (win.materialDark ? "#6DD58C" : "#146C2E") : "#30D158") : win.headerInk
                    }
                }
            }

            // connectivity 2x2 | brightness | Do Not Disturb over Split View and Slide Over
            Item {
                width: parent.width
                height: win.span2

                Glass {
                    id: connectivity
                    shadow: true
                    width: win.span2
                    height: win.span2
                    radius: win.pixel ? win.cell * 0.22 : win.cell * 0.36
                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: win.cell * 0.26
                        component Toggle: Rectangle {
                            id: toggle
                            property var q: null
                            property color onColor: win.blue
                            property string iconOverride: ""
                            visible: !!q && q.available
                            width: win.cell * 0.66
                            height: width
                            radius: width / 2
                            color: q && q.enabled ? onColor : win.offFill
                            scale: tap.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: toggle.iconOverride || (toggle.q ? win.iconFor(toggle.q) : "")
                                implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
                                implicitHeight: implicitWidth
                                isMask: true
                                color: win.pixel ? (toggle.q && toggle.q.enabled ? win.materialOnAccent : win.materialInk) : "white"
                            }
                            MouseArea {
                                id: tap
                                anchors.fill: parent
                                property point from
                                property bool moved: false
                                onPressed: m => { from = Qt.point(m.x, m.y); moved = false; }
                                onPositionChanged: m => { moved = moved || Math.hypot(m.x - from.x, m.y - from.y) > 18 * uiStyle.dp; }
                                onClicked: if (!moved) toggle.q.toggle()
                                onPressAndHold: win.openSettings(toggle.q.settingsCommand)
                            }
                        }
                        Toggle { q: win.qs.airplane || null; onColor: win.orange; iconOverride: "network-flightmode-on-symbolic" }
                        Toggle {
                            q: win.qs.rotation || null
                            onColor: win.blue
                            iconOverride: q && q.enabled ? "rotation-allowed-symbolic" : "rotation-locked-symbolic"
                        }
                        Toggle { q: win.qs.wifi || null; iconOverride: "network-wireless-symbolic" }
                        Toggle { q: win.qs.bluetooth || null; iconOverride: "network-bluetooth-symbolic" }
                    }
                }

                // brightness only: sound has its keys, the OSD and the tray
                TallSlider {
                    x: win.span2 + win.sp
                    y: win.pixel ? (win.span2 - height) / 2 : 0
                    visible: brightness.brightnessAvailable
                    iconName: "brightness-high-symbolic"
                    value: brightness.maxBrightness > 0 ? brightness.brightness / brightness.maxBrightness : 0
                    onMoved: v => brightness.brightness = Math.max(1, Math.round(v * brightness.maxBrightness))
                }
                // Do Not Disturb, the wide Focus module
                Glass {
                    id: focusModule
                    shadow: true
                    readonly property bool on: win.dnd
                    x: win.pixel ? win.span2 * 2 + win.sp * 2 : win.span2 + win.cell + win.sp * 2
                    width: win.span2
                    height: win.cell
                    radius: win.pixel ? height * 0.27 : height * 0.42
                    color: on ? (win.pixel ? win.blue : Qt.rgba(0.37, 0.36, 0.9, 0.55)) : win.glassFill
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: focusTap.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Rectangle {
                        id: moon
                        anchors.left: parent.left
                        anchors.leftMargin: (parent.height - height) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.height * (win.pixel ? 0.5 : 0.6)
                        height: width
                        radius: width / 2
                        color: win.pixel ? (focusModule.on ? win.materialOnAccent : win.offFill) : (focusModule.on ? "white" : win.offFill)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "weather-clear-night-symbolic"
                            implicitWidth: Math.round(Kirigami.Units.iconSizes.smallMedium * uiStyle.dp)
                            implicitHeight: implicitWidth
                            isMask: true
                            color: win.pixel ? (focusModule.on ? win.blue : win.materialInk) : (focusModule.on ? win.purple : "white")
                        }
                    }
                    Column {
                        anchors.left: moon.right
                        anchors.leftMargin: (Kirigami.Units.largeSpacing * uiStyle.dp)
                        anchors.right: parent.right
                        anchors.rightMargin: (Kirigami.Units.smallSpacing * uiStyle.dp)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            text: Tr.t("Не беспокоить")
                            color: win.pixel ? (focusModule.on ? win.materialOnAccent : win.materialInk) : "white"
                            elide: Text.ElideRight
                            fontSizeMode: Text.HorizontalFit
                            minimumPointSize: Kirigami.Theme.smallFont.pointSize
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: focusModule.on ? Tr.t("Вкл.") : Tr.t("Выкл.")
                            color: win.pixel ? (focusModule.on ? win.materialOnAccent : win.materialInk) : Qt.rgba(1, 1, 1, 0.65)
                            opacity: 0.76
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    MouseArea {
                        id: focusTap
                        anchors.fill: parent
                        onClicked: win.toggleDnd()
                        onPressAndHold: win.openSettings("kcm_notifications")
                    }
                }
                Control {
                    x: focusModule.x
                    y: win.cell + win.sp
                    label: Tr.t("Два окна")
                    iconName: "view-split-left-right-symbolic"
                    onActivated: {
                        win.dismiss();
                        win.kwinShortcut("Split View");
                    }
                    // hold: divider at 1/2, 2/3, 1/3
                    onHeld: win.kwinShortcut("Split View Resize")
                }
                Control {
                    x: focusModule.x + win.cell + win.sp
                    y: win.cell + win.sp
                    label: Tr.t("Окно поверх")
                    iconName: "window-duplicate-symbolic"
                    onActivated: {
                        win.dismiss();
                        win.kwinShortcut("Slide Over");
                    }
                }
            }

            // round controls
            Grid {
                columns: win.pixel ? 3 : win.cols
                columnSpacing: win.sp
                rowSpacing: win.sp
                onHeightChanged: blurTimer.restart()

                Repeater {
                    model: win.qsRest
                    delegate: QsControl {
                        wideTile: true
                        required property var modelData
                        q: modelData
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Картинка в картинке")
                    iconName: Qt.resolvedUrl("icons/pip.svg")
                    onActivated: {
                        win.dismiss();
                        win.kwinShortcut("Picture in Picture");
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Заметка")
                    iconName: "draw-freehand-symbolic"
                    onActivated: {
                        win.dismiss();
                        shell.start([win.home + "/.local/bin/quick-note"]);
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Читалка")
                    iconName: "view-readermode-symbolic"
                    on: win.reading
                    onActivated: {
                        win.dismiss();
                        const firefox = shell.currentApp().toLowerCase().indexOf("firefox") !== -1;
                        shell.start([win.home + "/.local/bin/reading-mode", "toggle", firefox ? "firefox" : ""]);
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Экранное время")
                    iconName: "chronometer-symbolic"
                    onActivated: {
                        win.dismiss();
                        win.showScreenTime();
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Уведомления")
                    iconName: "notifications-symbolic"
                    onActivated: {
                        win.dismiss();
                        notificationCenter.visible = true;
                    }
                }
                Control {
                    wideTile: true
                    // Android holds ~1 GB even when idle: tap stops it, it starts again with any Android app
                    visible: win.hasWaydroid
                    label: on ? Tr.t("Android: стоп") : "Android"
                    iconName: "folder-android-symbolic"
                    on: win.android
                    onColor: win.pixel ? (win.materialDark ? "#6DD58C" : "#146C2E") : "#30D158"
                    onActivated: {
                        if (on) {
                            shell.start(["waydroid", "session", "stop"]);
                            win.android = false;
                        } else {
                            shell.start(["waydroid", "show-full-ui"]);
                            win.dismiss();
                        }
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Машинка")
                    iconName: "document-edit-symbolic"
                    onActivated: {
                        shell.start([win.home + "/.local/bin/typewriter"]);
                        win.dismiss();
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Кодинг")
                    iconName: "code-context-symbolic"
                    onActivated: {
                        shell.start([win.home + "/.local/bin/coding-mode"]);
                        win.dismiss();
                    }
                }
                Control {
                    wideTile: true
                    label: Tr.t("Настройки")
                    iconName: "configure-symbolic"
                    onActivated: {
                        win.dismiss();
                        shell.start([win.home + "/.local/bin/tablet-settings"]);
                    }
                }
            }
        }
    }
}

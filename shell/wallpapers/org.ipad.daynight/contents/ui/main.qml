// Live day/night wallpaper: the light and the dark picture of a wallpaper package (images/ and
// images_dark/, like Monterey-iPad) cross-fade with the height of the sun: light from +6° up,
// dark from -6° down, a blend in between (about an hour around sunrise and sunset). The sun is
// recomputed every minute and the fade follows it smoothly. Set by ~/.local/bin/wallpaper when
// "Живые обои" is on (tabletrc [Appearance] liveWallpaper); also used by the lock screen.
import QtQuick
import Qt.labs.folderlistmodel

import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property string base: String(root.configuration.Image || "").replace(/\/$/, "")
    readonly property bool isPackage: !/\.(jpe?g|png|webp|avif)$/i.test(base)

    // the largest picture in a folder of the package
    component Largest: FolderListModel {
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif"]
        showDirs: false
        sortField: FolderListModel.Size
        readonly property string best: count > 0 ? String(get(0, "fileUrl")) : ""
    }
    Largest { id: lightFiles; folder: root.isPackage ? root.base + "/contents/images" : "" }
    Largest { id: darkFiles; folder: root.isPackage ? root.base + "/contents/images_dark" : "" }
    readonly property string lightSource: isPackage ? lightFiles.best : base
    readonly property string darkSource: isPackage ? (darkFiles.best || lightFiles.best) : base

    // ---- the sun ----
    // solar elevation in degrees (NOAA approximation, good to a fraction of a degree)
    function sunElevation(date, lat, lon) {
        const rad = Math.PI / 180;
        const day = (Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) - Date.UTC(date.getUTCFullYear(), 0, 0)) / 86400000;
        const hours = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600;
        const g = 2 * Math.PI / 365 * (day - 1 + (hours - 12) / 24);
        const eqTime = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
                     + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        const trueSolarMinutes = hours * 60 + eqTime + 4 * lon;
        const hourAngle = (trueSolarMinutes / 4 - 180) * rad;
        const cosZenith = Math.sin(lat * rad) * Math.sin(decl) + Math.cos(lat * rad) * Math.cos(decl) * Math.cos(hourAngle);
        return 90 - Math.acos(Math.max(-1, Math.min(1, cosZenith))) / rad;
    }
    // 0 = day picture, 1 = night picture
    function darknessNow() {
        const e = sunElevation(new Date(), Number(root.configuration.Latitude), Number(root.configuration.Longitude));
        const t = Math.max(0, Math.min(1, (6 - e) / 12));
        return t * t * (3 - 2 * t);     // smoothstep
    }
    property real darkness: darknessNow()
    // every minute: glide to the new value over that minute
    NumberAnimation {
        id: glide
        target: root
        property: "darkness"
        duration: 50000
        easing.type: Easing.Linear
    }
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            glide.to = root.darknessNow();
            glide.restart();
        }
    }
    // another place or a time jump (after sleep): straight there
    function jump() {
        glide.stop();
        darkness = darknessNow();
    }
    Connections {
        target: root.configuration
        function onValueChanged() { root.jump(); }
    }
    Connections {
        target: Qt.application
        function onStateChanged() { root.jump(); }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }
    Image {
        id: light
        anchors.fill: parent
        source: root.lightSource
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: true
        cache: false
        visible: root.darkness < 0.999
    }
    Image {
        id: dark
        anchors.fill: parent
        source: root.darkSource !== root.lightSource ? root.darkSource : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: true
        cache: false
        opacity: root.darkness
        visible: root.darkness > 0.001 && source != ""
    }
}

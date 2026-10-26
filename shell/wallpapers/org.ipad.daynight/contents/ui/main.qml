// Live day/night wallpaper: the light and the dark picture of a wallpaper package (images/ and
// images_dark/, like Monterey-iPad) follow the light/dark appearance: the light picture with the
// light theme, the dark one with the dark theme, cross-faded when the theme changes (with
// "Авто" Plasma switches the theme by time of day, and the wallpaper goes along). Set by
// ~/.local/bin/wallpaper when "Живые обои" is on (tabletrc [Appearance] liveWallpaper); also
// used by the lock screen.
import QtQuick
import Qt.labs.folderlistmodel

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

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

    // the theme is dark when its text is light (glass themes have a translucent black
    // background in their light variant too, so the background colour cannot tell)
    readonly property bool darkTheme: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
    // 0 = light picture, 1 = dark picture
    property real darkness: darkTheme ? 1 : 0
    Behavior on darkness {
        NumberAnimation { duration: 1200; easing.type: Easing.InOutQuad }
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

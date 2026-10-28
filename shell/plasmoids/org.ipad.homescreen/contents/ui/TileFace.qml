// Icon + label of one home screen entry: an app, or a folder showing a 3x3 preview of its apps.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: face

    required property var home
    required property var entry
    // inside an open folder the label sits on the folder sheet, not on the wallpaper
    property bool onSheet: false
    readonly property bool isFolder: entry !== null && typeof entry === "object"
    readonly property var app: !isFolder && entry ? home.catalog[entry] : null

    // Unread count from the task manager's smart launcher (Unity LauncherEntry + notifications).
    // Its QML module is only registered once the panel's task manager is loaded, so retry until then.
    property var badge: null
    readonly property int badgeCount: home.showBadges && badge && badge.countVisible ? badge.count : 0

    function attachBadge() {
        if (badge || isFolder || !entry) {
            return;
        }
        try {
            badge = Qt.createQmlObject('import plasma.applet.org.kde.plasma.taskmanager as T; T.SmartLauncherItem {}',
                                       face, "badge");
            badge.launcherUrl = "applications:" + entry;
        } catch (e) {
            badgeRetry.start();
        }
    }
    Component.onCompleted: attachBadge()
    onEntryChanged: {
        if (badge) {
            badge.destroy();
            badge = null;
        }
        attachBadge();
    }
    Timer {
        id: badgeRetry
        interval: 5000
        onTriggered: face.attachBadge()
    }

    spacing: Kirigami.Units.smallSpacing
    // the icon square: the launch animation grows out of it
    readonly property alias iconItem: iconBox

    Item {
        id: iconBox
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: face.home.iconSize
        implicitHeight: implicitWidth

        AppIcon {
            anchors.fill: parent
            visible: !face.isFolder
            home: face.home
            source: face.app ? face.app.icon : ""
        }

        // Red unread badge, top-right like iPadOS
        Rectangle {
            visible: face.badgeCount > 0
            z: 1
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -height / 3
            anchors.rightMargin: -height / 3
            height: Math.round(face.home.iconSize * 0.34)
            width: Math.max(height, badgeText.implicitWidth + height * 0.5)
            radius: height / 2
            color: face.home.pal.red
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: face.badgeCount > 99 ? "99+" : face.badgeCount
                color: "white"
                font.bold: true
                font.pixelSize: parent.height * 0.62
            }
        }

        // Material folder: a tonal circle with the first four apps, 2x2 (Pixel launcher)
        Rectangle {
            anchors.fill: parent
            anchors.margins: parent.width * 0.04
            visible: face.isFolder && face.home.pixel
            radius: width / 2
            color: face.home.tone("secondary").container
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: parent.width * 0.06
                Repeater {
                    model: face.isFolder && face.home.pixel ? face.entry.apps.slice(0, 4) : []
                    // themed icons: the apps inside are round and two-toned like the rest
                    delegate: Item {
                        id: mini
                        required property var modelData
                        readonly property string icon: face.home.catalog[modelData] ? face.home.catalog[modelData].icon : ""
                        width: face.home.iconSize * 0.3
                        height: width
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !face.home.themedIcons
                            source: visible ? mini.icon : ""
                        }
                        Loader {
                            anchors.fill: parent
                            active: face.home.themedIcons
                            sourceComponent: AppIcon {
                                home: face.home
                                source: mini.icon
                            }
                        }
                    }
                }
            }
        }

        // Folder: frosted glass squircle with mini icons (Apple)
        Glass {
            anchors.fill: parent
            visible: face.isFolder && !face.home.pixel
            home: face.home
            tone: "light"
            radius: face.home.pixel ? width / 2 : width * 0.24

            Grid {
                anchors.centerIn: parent
                columns: 3
                spacing: parent.width * 0.05

                Repeater {
                    model: face.isFolder && !face.home.pixel ? face.entry.apps.slice(0, 9) : []
                    delegate: Kirigami.Icon {
                        required property var modelData
                        width: face.home.iconSize * 0.24
                        height: width
                        source: face.home.catalog[modelData] ? face.home.catalog[modelData].icon : ""
                    }
                }
            }
        }
    }

    PC3.Label {
        Layout.alignment: Qt.AlignHCenter
        font.family: face.home.fontFamily
        font.weight: face.home.pixel ? Font.Medium : Font.Normal
        Layout.maximumWidth: face.home.cellWidth * 0.95
        text: face.isFolder ? face.entry.folder : (face.app ? face.app.name : "")
        color: face.onSheet ? face.home.pal.text : "white"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        style: face.onSheet ? Text.Normal : Text.Raised
        styleColor: Qt.rgba(0, 0, 0, face.home.pixel ? 0.3 : 0.45)
    }
}

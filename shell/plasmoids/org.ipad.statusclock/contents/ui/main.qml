// Status bar clock like iPadOS: "17:03  Пт 23 окт." in one line at the left edge of the tablet
// status bar, the time a bit bolder than the date. Tap: notification center (tabletshell).
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    readonly property bool pixel: Plasmoid.configuration.shellStyle === "pixel"

    preferredRepresentation: fullRepresentation

    property date now: new Date()
    readonly property string time: Qt.locale().toString(now, "HH:mm")
    readonly property string date: {
        const d = Qt.locale().toString(now, "ddd d MMM");
        return d.charAt(0).toUpperCase() + d.slice(1);
    }

    // once a minute, on the minute
    Timer {
        running: true
        repeat: true
        interval: (60 - root.now.getSeconds()) * 1000 + 50
        onTriggered: root.now = new Date()
    }

    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        readonly property real size: Math.min(height * 0.56, Kirigami.Units.gridUnit * 0.9)
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignVCenter
        onClicked: run.connectSource("qdbus6 org.ipad.TabletShell / org.ipad.TabletShell.ToggleNotifications")

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: Kirigami.Units.largeSpacing
            spacing: Math.round(parent.size * 0.45)
            Text {
                text: root.time
                color: Kirigami.Theme.textColor
                font.family: Kirigami.Theme.defaultFont.family
                font.pixelSize: parent.parent.size
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Text {
                visible: true
                text: root.date
                color: Kirigami.Theme.textColor
                font.family: Kirigami.Theme.defaultFont.family
                font.pixelSize: parent.parent.size
                font.weight: Font.Medium
            }
        }
    }
}

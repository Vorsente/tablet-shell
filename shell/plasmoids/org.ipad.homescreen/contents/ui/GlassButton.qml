// Capsule button in the iOS 26 style (Glass.qml), used instead of the Plasma theme's buttons so the
// home screen keeps one look: on the wallpaper (edit mode, Today) or on a sheet (onSheet: true).
// An icon-only button is round.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Item {
    id: button

    required property var home
    property string text
    property string iconName
    property bool onSheet: false
    property bool prominent: false      // accent colour: the main action (Done, Add)
    signal clicked()

    readonly property color foreground: home.pixel ? (prominent ? (home.dark ? "#381E72" : "white") : onSheet ? home.pal.text : "#F3EDF7")
                                                       : prominent || !onSheet ? "white" : home.pal.text

    implicitHeight: Kirigami.Units.gridUnit * 2.2
    implicitWidth: text === "" ? implicitHeight : row.implicitWidth + implicitHeight * 0.9
    opacity: enabled ? 1 : 0.4
    scale: area.pressed ? 0.94 : (area.containsMouse ? 1.025 : 1)
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Glass {
        anchors.fill: parent
        home: button.home
        tone: button.onSheet ? "fill" : "wallpaper"
        tinted: button.prominent
        highlighted: area.containsMouse || button.activeFocus
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            visible: button.iconName !== ""
            source: button.iconName
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
            isMask: true
            color: button.foreground
        }
        Text {
            visible: button.text !== ""
            text: button.text
            color: button.foreground
            font.family: Kirigami.Theme.defaultFont.family
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            font.weight: button.home.pixel ? Font.Medium : button.prominent ? Font.Bold : Font.DemiBold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: button.enabled
        onClicked: button.clicked()
    }
    activeFocusOnTab: true
    Keys.onReturnPressed: button.clicked()
    Keys.onSpacePressed: button.clicked()
}

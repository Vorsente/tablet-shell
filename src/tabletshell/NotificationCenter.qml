// Notification center: swipe in from the right edge. Notifications seen since login (watched from
// Plasma's notification server), newest first; tap runs the default action, × dismisses,
// "Очистить" clears all.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.notificationmanager as NotificationManager
import "Tr.js" as Tr
import "MaterialYou.js" as MY

Window {
    id: win
    visible: false
    color: "transparent"
    title: Tr.t("Уведомления")
    readonly property bool materialDark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
    readonly property color materialSurface: materialDark ? MY.you("#25232C", uiStyle.pixel, Kirigami.Theme.highlightColor) : MY.you("#F9F4FF", uiStyle.pixel, Kirigami.Theme.highlightColor)
    readonly property color materialCard: materialDark ? MY.you("#36343F", uiStyle.pixel, Kirigami.Theme.highlightColor) : MY.you("#E9E2F0", uiStyle.pixel, Kirigami.Theme.highlightColor)
    readonly property color materialText: materialDark ? MY.you("#F1EAF5", uiStyle.pixel, Kirigami.Theme.highlightColor) : MY.you("#1D1B20", uiStyle.pixel, Kirigami.Theme.highlightColor)

    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    function toggle() {
        if (visible) {
            dismiss();
        } else {
            visible = true;
        }
    }
    // dims the whole screen and dissolves in / out (nothing grows or shrinks)
    property real shown: 0
    onVisibleChanged: if (visible) { fadeOut.stop(); fadeIn.restart(); }
    NumberAnimation { id: fadeIn; target: win; property: "shown"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: fadeOut
        NumberAnimation { target: win; property: "shown"; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScriptAction { script: win.visible = false }
    }
    function dismiss() {
        if (visible && !fadeOut.running) {
            fadeOut.start();
        }
    }


    // Out of process, so the watcher model (Plasma's own history model only works inside plasmashell)
    NotificationManager.WatchedNotificationsModel { id: history }

    function clearAll() {
        const ids = [];
        for (let i = 0; i < history.rowCount(); ++i) {
            ids.push(history.data(history.index(i, 0), NotificationManager.Notifications.IdRole));
        }
        ids.forEach(id => history.close(id));
    }

    function age(date) {
        const min = Math.round((Date.now() - date.getTime()) / 60000);
        if (min < 1) return Tr.t("сейчас");
        if (min < 60) return min + Tr.t(" мин");
        if (min < 1440) return Math.round(min / 60) + Tr.t(" ч");
        return Qt.formatDate(date, "d MMM");
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea { anchors.fill: parent; onClicked: win.dismiss() }
        opacity: win.shown
    }

    Rectangle {
        id: panel
        opacity: win.shown
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: (Kirigami.Units.gridUnit * uiStyle.dp)
        width: Math.min(parent.width - (Kirigami.Units.gridUnit * uiStyle.dp) * 2, (Kirigami.Units.gridUnit * uiStyle.dp) * 24)
        radius: uiStyle.pixel ? (Kirigami.Units.gridUnit * uiStyle.dp) * 2.1 : (Kirigami.Units.gridUnit * uiStyle.dp) * 1.4
        color: uiStyle.pixel ? win.materialSurface : Qt.rgba(0.12, 0.12, 0.15, 0.9)
        border.color: uiStyle.pixel ? (win.materialDark ? MY.you("#625C69", uiStyle.pixel, Kirigami.Theme.highlightColor) : MY.you("#D8CEDF", uiStyle.pixel, Kirigami.Theme.highlightColor)) : Qt.rgba(1, 1, 1, 0.16)
        border.width: uiStyle.pixel ? 0 : 1

        MouseArea { anchors.fill: parent }  // keep taps inside

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: (Kirigami.Units.gridUnit * uiStyle.dp)
            spacing: (Kirigami.Units.largeSpacing * uiStyle.dp)

            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    Layout.fillWidth: true
                    text: Tr.t("Уведомления")
                    color: uiStyle.pixel ? win.materialText : "white"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
                    font.weight: Font.DemiBold
                }
                PC3.Button {
                    visible: list.count > 0
                    text: Tr.t("Очистить")
                    onClicked: win.clearAll()
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: list.count === 0
                text: Tr.t("Нет уведомлений")
                color: uiStyle.pixel ? Qt.alpha(win.materialText, 0.64) : Qt.rgba(1, 1, 1, 0.6)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.maximumHeight: contentHeight  // hug the top; the spacer below takes the rest
                visible: count > 0
                clip: true
                verticalLayoutDirection: ListView.BottomToTop  // newest (last added) on top
                spacing: (Kirigami.Units.smallSpacing * uiStyle.dp) * 2
                model: history

                delegate: Rectangle {
                    id: card
                    required property int index
                    required property var model
                    width: list.width
                    height: cardRow.implicitHeight + (Kirigami.Units.largeSpacing * uiStyle.dp) * 2
                    radius: uiStyle.pixel ? (Kirigami.Units.gridUnit * uiStyle.dp) * 1.4 : (Kirigami.Units.gridUnit * uiStyle.dp) * 0.8
                    color: uiStyle.pixel ? win.materialCard : Qt.rgba(1, 1, 1, 0.1)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (card.model.hasDefaultAction) {
                                history.invokeDefaultAction(card.model.notificationId, NotificationManager.Notifications.None);
                                win.visible = false;
                            }
                        }
                    }

                    RowLayout {
                        id: cardRow
                        anchors.fill: parent
                        anchors.margins: (Kirigami.Units.largeSpacing * uiStyle.dp)
                        spacing: (Kirigami.Units.largeSpacing * uiStyle.dp)

                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignTop
                            source: card.model.image || card.model.iconName || card.model.applicationIconName || "preferences-desktop-notification"
                            implicitWidth: Math.round(Kirigami.Units.iconSizes.medium * uiStyle.dp)
                            implicitHeight: implicitWidth
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            PC3.Label {
                                text: card.model.applicationName || ""
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.capitalization: Font.AllUppercase
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                PC3.Label {
                                    Layout.fillWidth: true
                                    text: card.model.summary || card.model.applicationName || ""
                                    color: uiStyle.pixel ? win.materialText : "white"
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                PC3.Label {
                                    text: card.model.updated ? win.age(card.model.updated) : (card.model.created ? win.age(card.model.created) : "")
                                    color: Qt.rgba(1, 1, 1, 0.5)
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                            }
                            PC3.Label {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: card.model.body || ""
                                textFormat: Text.StyledText
                                color: Qt.rgba(1, 1, 1, 0.85)
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                            }
                        }
                        PC3.ToolButton {
                            Layout.alignment: Qt.AlignTop
                            icon.name: "window-close"
                            onClicked: history.close(card.model.notificationId)
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
                visible: list.count > 0
            }
        }
    }
}

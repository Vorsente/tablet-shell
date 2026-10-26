// Widget gallery ("+ Виджет" in edit mode): every widget in both sizes as a live preview;
// a tap puts it at the start of the current home page. In PC mode it fills the desktop
// (DesktopWidgets.qml) and offers the large size too.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: picker

    required property var home
    visible: false

    function show() {
        visible = true;
    }

    readonly property var kinds: [
        ["weather", Tr.t("Погода")], ["calendar", Tr.t("Календарь")], ["clock", Tr.t("Часы")],
        ["typewriter", Tr.t("Печатная машинка")], ["screentime", Tr.t("Экранное время")], ["battery", Tr.t("Батарея")],
        ["youtube", "YouTube"], ["linux", Tr.t("Новости Linux")], ["russia", Tr.t("Новости страны")], ["rates", Tr.t("Курс валют")],
        ["claude", Tr.t("Лимиты Claude")], ["onthisday", Tr.t("В этот день")], ["sky", Tr.t("Небо: солнце и луна")],
    ]
    readonly property real unit: Math.min(width, height) / 9

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: picker.visible = false }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, picker.unit * 10)
        height: parent.height - Kirigami.Units.gridUnit * 4
        radius: picker.home.pixel ? Kirigami.Units.gridUnit * 1.6 : Kirigami.Units.gridUnit
        color: picker.home.pal.sheet
        GlassSheen { home: picker.home }
        MouseArea { anchors.fill: parent }   // keep taps on the sheet

        Text {
            id: title
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Kirigami.Units.gridUnit
            text: Tr.t("Виджеты")
            color: picker.home.pal.text
            font.pixelSize: Kirigami.Units.gridUnit * 1.4
            font.bold: true
        }
        Text {
            anchors.verticalCenter: title.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Kirigami.Units.gridUnit
            text: Tr.t("Готово")
            color: picker.home.pal.blue
            font.pixelSize: Kirigami.Units.gridUnit
            font.bold: true
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: picker.visible = false }
        }

        Flickable {
            anchors.top: title.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Kirigami.Units.gridUnit
            contentHeight: list.height
            clip: true

            Column {
                id: list
                width: parent.width
                spacing: Kirigami.Units.gridUnit * 1.2
                Repeater {
                    model: picker.visible ? picker.kinds : []
                    delegate: Column {
                        required property var modelData
                        spacing: Kirigami.Units.smallSpacing
                        Text {
                            text: modelData[1]
                            color: picker.home.pal.secondary
                            font.pixelSize: Kirigami.Units.gridUnit * 0.9
                            font.weight: Font.DemiBold
                        }
                        Row {
                            spacing: Kirigami.Units.gridUnit
                            Repeater {
                                model: picker.home.pcMode ? ["small", "wide", "large"] : ["small", "wide"]
                                delegate: HomeWidget {
                                    required property string modelData
                                    home: picker.home
                                    kind: parent.parent.modelData[0]
                                    wide: modelData !== "small"
                                    height: picker.unit * (modelData === "large" ? 1.9 * 2 + 0.2 : 1.9)
                                    width: wide ? picker.unit * 1.9 * 2.1 : height
                                    swipe: false
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            picker.home.addWidget(parent.kind, parent.modelData);
                                            picker.visible = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

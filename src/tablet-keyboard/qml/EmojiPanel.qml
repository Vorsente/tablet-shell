// Emoji page: horizontally scrolling grid like on iPad, categories at the bottom (recent first)
import QtQuick
import "Emoji.js" as E
import "Tr.js" as Tr

Item {
    id: panel

    required property QtObject theme
    property real keyH: 50
    signal picked(string emoji)
    signal backspace()
    signal letters()

    property int category: 0                    // 0 = recent, then E.categories
    readonly property var recent: String(keyboard.setting("recentEmoji", "")).split(" ").filter(x => x)
    readonly property var current: category === 0 ? recent : E.list(category - 1)
    onVisibleChanged: if (visible) category = recent.length > 0 ? 0 : 1

    Rectangle {
        anchors.fill: parent
        color: panel.theme.bg
        Rectangle { width: parent.width; height: 1; color: panel.theme.hairline }
    }

    Text {
        id: title
        x: panel.keyH * 0.4
        y: panel.keyH * 0.15
        text: panel.category === 0 ? Tr.t("Часто используемые") : Tr.t(E.categories[panel.category - 1].name)
        color: panel.theme.subText
        font.family: "Inter"
        font.pixelSize: panel.keyH * 0.24
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
    }

    GridView {
        id: grid
        anchors.top: title.bottom
        anchors.topMargin: panel.keyH * 0.1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bar.top
        anchors.leftMargin: panel.keyH * 0.2
        flow: GridView.FlowTopToBottom
        clip: true
        cellHeight: height / 3
        cellWidth: cellHeight * 1.1
        model: panel.current
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 0
        delegate: Item {
            required property string modelData
            width: grid.cellWidth
            height: grid.cellHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: height * 0.2
                color: tap.pressed ? panel.theme.keyDown : "transparent"
            }
            Text {
                anchors.centerIn: parent
                text: modelData
                font.pixelSize: grid.cellHeight * 0.62
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                onClicked: panel.picked(modelData)
            }
        }
        Text {
            anchors.centerIn: parent
            visible: grid.count === 0
            text: Tr.t("Здесь появятся эмодзи, которые вы используете")
            color: panel.theme.subText
            font.family: "Inter"
            font.pixelSize: panel.keyH * 0.26
        }
    }

    // bottom bar: ABC, categories, backspace
    Row {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: panel.keyH * 0.15
        height: panel.keyH * 0.8
        spacing: panel.keyH * 0.08

        component BarKey: Rectangle {
            property string glyph
            property bool selected: false
            property bool special: false
            signal activated()
            width: special ? panel.keyH * 1.5 : panel.keyH * 0.85
            height: bar.height
            radius: height * 0.25
            color: area.pressed ? panel.theme.keyDown : selected ? panel.theme.key : special ? panel.theme.special : "transparent"
            Text {
                anchors.centerIn: parent
                text: parent.glyph
                color: panel.theme.text
                font.family: "Inter"
                font.pixelSize: parent.height * (special ? 0.36 : 0.52)
                font.weight: Font.Medium
            }
            MouseArea {
                id: area
                anchors.fill: parent
                onClicked: parent.activated()
            }
        }
        BarKey { glyph: "ABC"; special: true; onActivated: panel.letters() }
        BarKey { glyph: "🕘"; selected: panel.category === 0; onActivated: panel.category = 0 }
        Repeater {
            model: E.categories
            delegate: BarKey {
                required property var modelData
                required property int index
                glyph: modelData.icon
                selected: panel.category === index + 1
                onActivated: { panel.category = index + 1; grid.positionViewAtBeginning(); }
            }
        }
    }
    // backspace on the right, kept apart from the categories
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: panel.keyH * 0.15
        width: panel.keyH * 1.5
        height: panel.keyH * 0.8
        radius: height * 0.25
        color: bsArea.pressed ? panel.theme.keyDown : panel.theme.special
        Text {
            anchors.centerIn: parent
            text: "⌫"
            color: panel.theme.text
            font.pixelSize: parent.height * 0.42
        }
        MouseArea {
            id: bsArea
            anchors.fill: parent
            onPressed: panel.backspace()
            onPressAndHold: bsRepeat.start()
            onReleased: bsRepeat.stop()
            Timer { id: bsRepeat; interval: 80; repeat: true; onTriggered: panel.backspace() }
        }
    }
}

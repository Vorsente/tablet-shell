// "Today" page, left of the first home page (like iPadOS Today View): date and greeting, then the
// widgets chosen in its edit mode (containment config "todayWidgets", a JSON list of kinds in
// order; "note" is the quick note, saved to ~/.local/share/today/note.txt as you type).
// "Изменить" (or a long press on a card) edits: "−" hides a card, ↑ ↓ move it, the hidden
// ones are listed below to add back. Two columns in landscape, one in portrait. News and "on this
// day" cards page through their lists: swipe sideways on the card or tap its dots.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: today

    required property var home
    readonly property var d: home.homeData
    readonly property bool twoColumns: width > height
    readonly property real gap: Kirigami.Units.gridUnit
    readonly property real columnWidth: twoColumns ? Math.min((width - gap * 5) / 2, Kirigami.Units.gridUnit * 30)
                                                   : Math.min(width - gap * 4, Kirigami.Units.gridUnit * 32)
    readonly property real cardHeight: columnWidth * 0.46
    readonly property string notePath: home.homeDir + "/.local/share/today/note.txt"

    readonly property var names: ({
        weather: Tr.t("Погода"), calendar: Tr.t("Календарь"), clock: Tr.t("Часы"), youtube: "YouTube", typewriter: Tr.t("Печатная машинка"),
        linux: Tr.t("Новости Linux"), russia: Tr.t("Новости страны"), custom: Tr.t("Моя лента"), note: Tr.t("Заметка"), rates: Tr.t("Курс валют"), sky: Tr.t("Небо"),
        onthisday: Tr.t("В этот день"), claude: Tr.t("Лимиты Claude"), screentime: Tr.t("Экранное время"), battery: Tr.t("Батарея"),
        weekly: Tr.t("Итоги недели"),
    })
    readonly property var allKinds: Object.keys(names)
    readonly property var tall: ["linux", "russia", "custom", "onthisday", "note", "weekly"]

    property bool editing: false
    property var shown: {
        try {
            return JSON.parse(Plasmoid.configuration.todayWidgets).filter(k => names[k] !== undefined);
        } catch (e) {
            return ["weather", "calendar", "note"];
        }
    }
    readonly property var hidden: allKinds.filter(k => shown.indexOf(k) < 0)
    function save(list) {
        Plasmoid.configuration.todayWidgets = JSON.stringify(list);
    }
    function move(kind, by) {
        const l = shown.slice();
        const i = l.indexOf(kind), j = i + by;
        if (j < 0 || j >= l.length) {
            return;
        }
        l.splice(i, 1);
        l.splice(j, 0, kind);
        save(l);
    }

    function greeting() {
        const h = d.now.getHours();
        return h < 5 ? Tr.t("Доброй ночи") : h < 12 ? Tr.t("Доброе утро") : h < 18 ? Tr.t("Добрый день") : Tr.t("Добрый вечер");
    }

    // ---- quick note ----
    property string noteText: ""
    property bool noteLoaded: false
    Component.onCompleted: home.runCommand(["cat", notePath], out => {
        noteText = out;
        noteLoaded = true;
    })
    Timer {
        id: saveNote
        interval: 800
        onTriggered: home.runCommand(["sh", "-c", 'mkdir -p "$(dirname "$2")" && printf %s "$1" > "$2"', "sh", today.noteText, today.notePath])
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            today.home.editing = false;
            today.editing = false;
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.height + today.gap * 3
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: (today.width - width) / 2
            y: today.gap
            width: today.twoColumns ? today.columnWidth * 2 + today.gap : today.columnWidth
            spacing: today.gap

            // Material: a quiet title row (the date and weather are in the glance line above)
            RowLayout {
                visible: today.home.pixel
                width: parent.width
                Text {
                    Layout.fillWidth: true
                    text: today.greeting()
                    color: "white"
                    font.family: today.home.fontFamily
                    font.pixelSize: Kirigami.Units.gridUnit * 1.5
                    font.weight: Font.Medium
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.25)
                }
                GlassButton {
                    home: today.home
                    prominent: today.editing
                    text: today.editing ? Tr.t("Готово") : Tr.t("Изменить")
                    iconName: today.editing ? "dialog-ok-apply-symbolic" : "document-edit-symbolic"
                    onClicked: today.editing = !today.editing
                }
            }

            Item {
                visible: !today.home.pixel
                width: parent.width
                height: header.height
                Column {
                    id: header
                    Text {
                        text: today.d.now.toLocaleDateString(Tr.locale(), "dddd, d MMMM")
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.pixelSize: Kirigami.Units.gridUnit * 1.1
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.3)
                    }
                    Text {
                        text: today.greeting()
                        color: "white"
                        font.pixelSize: Kirigami.Units.gridUnit * 2.4
                        font.weight: Font.Bold
                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.3)
                    }
                }
                GlassButton {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    home: today.home
                    visible: today.editing
                    prominent: true
                    text: Tr.t("Готово")
                    onClicked: today.editing = false
                }
            }

            // two independent columns, cards alternate between them (masonry, like iPadOS)
            Row {
                spacing: today.gap
                Repeater {
                    model: today.twoColumns ? 2 : 1
                    delegate: Column {
                        id: column
                        required property int index
                        width: today.columnWidth
                        spacing: today.gap
                        Repeater {
                            model: today.shown.filter((k, i) => !today.twoColumns || i % 2 === column.index)
                            delegate: Item {
                                id: slot
                                required property string modelData
                                width: today.columnWidth
                                height: today.tall.indexOf(modelData) >= 0 ? today.cardHeight * 1.55 : today.cardHeight

                                Loader {
                                    id: cardLoader
                                    anchors.fill: parent
                                    sourceComponent: slot.modelData === "note" ? noteCard : widgetCard
                                    Component {
                                        id: widgetCard
                                        HomeWidget {
                                            home: today.home
                                            kind: slot.modelData
                                            wide: true
                                            onHeld: today.editing = true
                                            MouseArea {
                                                anchors.fill: parent
                                                z: -1           // under the headline links of news cards
                                                pressAndHoldInterval: 500
                                                onClicked: if (!today.editing) parent.activate()
                                                onPressAndHold: today.editing = true
                                            }
                                        }
                                    }
                                }
                                // edit controls
                                Row {
                                    visible: today.editing
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    Repeater {
                                        model: [["↑", -1], ["↓", 1], ["−", 0]]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: Kirigami.Units.gridUnit * 2.2
                                            height: width
                                            radius: width / 2
                                            color: modelData[1] === 0 ? today.home.pal.red : today.home.pal.control
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData[0]
                                                color: modelData[1] === 0 ? "white" : today.home.pal.text
                                                font.bold: true
                                                font.pixelSize: parent.height * 0.6
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    if (modelData[1] === 0) {
                                                        today.save(today.shown.filter(k => k !== slot.modelData));
                                                    } else {
                                                        // in two columns a step is two places (same column)
                                                        today.move(slot.modelData, modelData[1] * (today.twoColumns ? 2 : 1));
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                SequentialAnimation on rotation {
                                    running: today.editing
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.5; duration: 140 }
                                    NumberAnimation { to: -0.5; duration: 280 }
                                    NumberAnimation { to: 0; duration: 140 }
                                    onRunningChanged: if (!running) slot.rotation = 0
                                }
                            }
                        }
                    }
                }
            }

            // hidden widgets, to add back
            Column {
                visible: today.editing && today.hidden.length > 0
                width: parent.width
                spacing: Kirigami.Units.smallSpacing
                Text {
                    text: Tr.t("Добавить")
                    color: "white"
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                    font.weight: Font.DemiBold
                }
                Flow {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: today.hidden
                        delegate: Rectangle {
                            required property string modelData
                            width: chip.implicitWidth + Kirigami.Units.gridUnit * 1.6
                            height: Kirigami.Units.gridUnit * 2.4
                            radius: height / 2
                            color: today.home.pixel ? today.home.tone(modelData).container : today.home.pal.card
                            border.color: today.home.pixel ? "transparent" : today.home.pal.cardBorder
                            Text {
                                id: chip
                                anchors.centerIn: parent
                                text: "+ " + today.names[modelData]
                                color: today.home.pixel ? today.home.tone(modelData).on : today.home.pal.text
                                font.family: today.home.fontFamily
                                font.pixelSize: Kirigami.Units.gridUnit * 0.9
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: today.save(today.shown.concat([modelData]))
                            }
                        }
                    }
                }
            }

            GlassButton {
                anchors.horizontalCenter: parent.horizontalCenter
                home: today.home
                visible: !today.editing && !today.home.pixel
                text: Tr.t("Изменить")
                iconName: "document-edit-symbolic"
                onClicked: today.editing = true
            }
        }
    }

    // quick note card
    Component {
        id: noteCard
        Rectangle {
            radius: today.home.pixel ? Math.min(30, Math.min(width, height) * 0.16) : Math.min(width, height) * 0.13
            color: today.home.pixel ? today.home.tone("note").container : today.home.pal.card
            border.color: today.home.pal.cardBorder
            border.width: today.home.pixel ? 0 : 1
            Text {
                id: noteTitle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Kirigami.Units.gridUnit
                text: Tr.t("Заметка")
                color: today.home.pixel ? today.home.tone("note").on : today.home.pal.yellow
                font.family: today.home.fontFamily
                font.pixelSize: Kirigami.Units.gridUnit * 0.95
                font.weight: Font.DemiBold
            }
            QQC2.ScrollView {
                anchors.top: noteTitle.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                QQC2.TextArea {
                    background: null
                    color: today.home.pixel ? today.home.tone("note").on : today.home.pal.text
                    font.family: today.home.fontFamily
                    wrapMode: TextEdit.Wrap
                    placeholderText: Tr.t("Мысль, список, что угодно…")
                    placeholderTextColor: today.home.pal.tertiary
                    font.pixelSize: Kirigami.Units.gridUnit * 0.95
                    text: today.noteText
                    onTextChanged: if (today.noteLoaded && text !== today.noteText) {
                        today.noteText = text;
                        saveNote.restart();
                    }
                }
            }
        }
    }
}

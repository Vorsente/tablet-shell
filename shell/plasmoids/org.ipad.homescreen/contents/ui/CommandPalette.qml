// Command palette: the actions of the shell in one searchable list (Ctrl+Alt+Space, the home
// screen menu, or the search bar's suggestions). Typing filters by title, subtitle and keywords;
// Enter runs the first match, Esc closes.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import "Tr.js" as Tr

Item {
    id: palette

    required property var home
    property bool open: false
    property string query: ""
    property int current: 0

    readonly property bool pixel: home.pixel === true
    readonly property color text: home.pal && home.pal.text !== undefined ? home.pal.text : "#FFFFFF"
    readonly property color secondary: home.pal && home.pal.secondary !== undefined ? home.pal.secondary : "#AAAAAA"
    readonly property color sheet: home.pal && home.pal.sheet !== undefined ? home.pal.sheet : "#2B2932"
    readonly property color sheetBorder: home.pal && home.pal.sheetBorder !== undefined ? home.pal.sheetBorder : "#53505B"
    readonly property color fill: home.pal && home.pal.fill !== undefined ? home.pal.fill : "#49454F"
    readonly property color fieldFill: home.pal && home.pal.fillWeak !== undefined ? home.pal.fillWeak
                                  : home.pal && home.pal.fill !== undefined ? home.pal.fill : "#33313B"
    readonly property color accent: home.pal && home.pal.blue !== undefined ? home.pal.blue : "#D0BCFF"
    readonly property string family: home.fontFamily ? home.fontFamily : Qt.application.font.family

    function show() {
        query = "";
        current = 0;
        open = true;
        field.forceActiveFocus();
    }
    function close() {
        open = false;
        if (field.activeFocus) {
            field.focus = false;
        }
    }
    function run(i) {
        const list = shown;
        if (i < 0 || i >= list.length) {
            return;
        }
        const action = list[i];
        close();
        action.run();
    }

    readonly property var actions: [
        { title: Tr.t("Пункт управления"), subtitle: Tr.t("Яркость, звук, сеть и Bluetooth"),
          icon: "preferences-system-symbolic", keywords: "control center пункт управления яркость звук сеть bluetooth wifi",
          run: () => home.runCommand(["qdbus6", "org.ipad.TabletShell", "/", "org.ipad.TabletShell.ToggleControlCenter"]) },
        { title: Tr.t("Центр уведомлений"), subtitle: Tr.t("Последние уведомления и «не беспокоить»"),
          icon: "notifications-symbolic", keywords: "notifications уведомления dnd",
          run: () => home.runCommand(["qdbus6", "org.ipad.TabletShell", "/", "org.ipad.TabletShell.ToggleNotifications"]) },
        { title: Tr.t("Экранное время"), subtitle: Tr.t("Что было открыто за сегодня"),
          icon: "chronometer-symbolic", keywords: "screen time экранное время статистика",
          run: () => home.runCommand(["qdbus6", "org.ipad.TabletShell", "/", "org.ipad.TabletShell.ToggleScreenTime"]) },
        { title: Tr.t("Распознать текст"), subtitle: Tr.t("Выделить область и скопировать текст"),
          icon: "edit-find-symbolic", keywords: "ocr текст распознать tesseract copy",
          run: () => home.runCommand([home.homeDir + "/.local/bin/ocr"]) },
        { title: Tr.t("Скриншот"), subtitle: Tr.t("Снимок всего экрана в ~/Pictures/Screenshots"),
          icon: "image-x-generic-symbolic", keywords: "screenshot снимок экран screenshot",
          run: () => home.runCommand(["sh", "-c",
              "mkdir -p \"$HOME/Pictures/Screenshots\"; spectacle -b -n -f -o \"$HOME/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png\""]) },
        { title: Tr.t("Режим чтения"), subtitle: Tr.t("Спокойный полноэкранный просмотр"),
          icon: "view-readermode-symbolic", keywords: "reading режим чтения книга",
          run: () => home.runCommand([home.homeDir + "/.local/bin/reading-mode"]) },
        { title: Tr.t("Режим кодинга"), subtitle: Tr.t("LazyVim в полноэкранном терминале"),
          icon: "code-context-symbolic", keywords: "coding режим кодинга lazyvim код",
          run: () => home.runCommand([home.homeDir + "/.local/bin/coding-mode"]) },
        { title: Tr.t("Печатная машинка"), subtitle: Tr.t("Сценарии, цель на день, экспорт"),
          icon: "document-edit-symbolic", keywords: "typewriter печатная машинка текст",
          run: () => home.runCommand([home.homeDir + "/.local/bin/typewriter"]) },
        { title: "OpenCode", subtitle: Tr.t("Открыть OpenCode в терминале"),
          icon: "utilities-terminal-symbolic", keywords: "opencode deepseek ai терминал",
          run: () => home.runCommand(["konsole", "-e", "opencode"]) },
        { title: Tr.t("Светлая тема"), subtitle: Tr.t("Светлое оформление оболочки"),
          icon: "weather-clear-symbolic", keywords: "light theme светлая тема",
          run: () => home.runCommand([home.homeDir + "/.local/bin/appearance", "light"]) },
        { title: Tr.t("Тёмная тема"), subtitle: Tr.t("Тёмное оформление оболочки"),
          icon: "weather-clear-night-symbolic", keywords: "dark theme тёмная тема",
          run: () => home.runCommand([home.homeDir + "/.local/bin/appearance", "dark"]) },
        { title: Tr.t("Авто-тема"), subtitle: Tr.t("Светлая днём, тёмная ночью"),
          icon: "contrast-symbolic", keywords: "auto theme авто тема",
          run: () => home.runCommand([home.homeDir + "/.local/bin/appearance", "auto"]) },
        { title: Tr.t("Стиль Pixel"), subtitle: Tr.t("Material Design для всей оболочки"),
          icon: "preferences-desktop-theme-global-symbolic", keywords: "pixel material design стиль",
          run: () => home.runCommand([home.homeDir + "/.local/bin/shell-style", "pixel"]) },
        { title: Tr.t("Стиль Apple"), subtitle: Tr.t("iPadOS и Liquid Glass"),
          icon: "preferences-desktop-theme-global-symbolic", keywords: "apple ipados стиль",
          run: () => home.runCommand([home.homeDir + "/.local/bin/shell-style", "apple"]) },
        { title: Tr.t("Внешний экран: расширить"), subtitle: Tr.t("Второй рабочий стол справа"),
          icon: "video-display-symbolic", keywords: "display extend external монитор экран расширить",
          run: () => home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "display-mode", "extend", "right"]) },
        { title: Tr.t("Внешний экран: дублировать"), subtitle: Tr.t("Одна картинка на обоих экранах"),
          icon: "video-display-symbolic", keywords: "display mirror external монитор экран дублировать",
          run: () => home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "display-mode", "mirror", "right"]) },
        { title: Tr.t("Внешний экран: только монитор"), subtitle: Tr.t("Погасить экран планшета"),
          icon: "video-display-symbolic", keywords: "display external only монитор только внешний",
          run: () => home.runCommand([home.homeDir + "/.local/bin/tablet-tools", "display-mode", "external", "right"]) },
        { title: Tr.t("Обновить данные виджетов"), subtitle: Tr.t("Погода, новости, курсы и расход ИИ"),
          icon: "view-refresh-symbolic", keywords: "refresh обновить данные виджеты погода новости",
          run: () => home.homeData.reload() },
        { title: Tr.t("Открыть проекты"), subtitle: Tr.t("Папка ~/Projects"),
          icon: "folder-symbolic", keywords: "projects проекты файлы",
          run: () => home.runCommand(["dolphin", home.homeDir + "/Projects"]) },
        { title: Tr.t("Терминал"), subtitle: Tr.t("Konsole"),
          icon: "utilities-terminal-symbolic", keywords: "terminal konsole терминал",
          run: () => home.runCommand(["konsole"]) },
        { title: Tr.t("Настройки"), subtitle: Tr.t("Настройки планшета"),
          icon: "preferences-system-symbolic", keywords: "settings настройки параметры",
          run: () => home.runCommand([home.homeDir + "/.local/bin/tablet-settings"]) },
    ]

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        if (!q) {
            return actions;
        }
        return actions.filter(a => (a.title + " " + a.subtitle + " " + a.keywords).toLowerCase().indexOf(q) !== -1);
    }
    onShownChanged: current = Math.max(0, Math.min(current, shown.length - 1))
    onOpenChanged: if (!open) query = ""

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: open ? 120 : 160 } }
    z: 100

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: palette.close() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 38)
        height: Math.min(parent.height - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 36)
        radius: palette.pixel ? Kirigami.Units.gridUnit * 1.6 : Kirigami.Units.gridUnit * 1.1
        color: palette.sheet
        border.width: 1
        border.color: palette.sheetBorder
        clip: true
        scale: palette.open ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.2
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.8
                radius: height / 2
                color: palette.fieldFill
                border.width: field.activeFocus ? 2 : 0
                border.color: palette.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Layout.preferredWidth
                        source: "search-symbolic"
                        isMask: true
                        color: palette.accent
                    }
                    TextInput {
                        id: field
                        Layout.fillWidth: true
                        color: palette.text
                        font.family: palette.family
                        font.pixelSize: Kirigami.Units.gridUnit
                        selectionColor: palette.accent
                        selectedTextColor: palette.pixel ? "#211A2E" : "white"
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhNoPredictiveText
                        onTextChanged: palette.query = text
                        onAccepted: palette.run(palette.current)
                        Keys.onEscapePressed: palette.close()
                        Keys.onDownPressed: palette.current = Math.min(palette.shown.length - 1, palette.current + 1)
                        Keys.onUpPressed: palette.current = Math.max(0, palette.current - 1)
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !field.length && !field.preeditText
                            text: Tr.t("Команда или действие")
                            color: palette.secondary
                            font: field.font
                        }
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: palette.open ? palette.shown : []
                currentIndex: palette.current
                boundsBehavior: Flickable.StopAtBounds
                spacing: Kirigami.Units.smallSpacing

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: Kirigami.Units.gridUnit * 3.2
                    radius: palette.pixel ? height / 2 : Kirigami.Units.gridUnit * 0.7
                    color: index === palette.current || hit.pressed ? palette.fill : "transparent"
                    border.width: index === palette.current ? 1 : 0
                    border.color: palette.sheetBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Layout.preferredWidth
                            source: row.modelData.icon
                            isMask: true
                            color: row.modelData.icon === "video-display-symbolic" ? palette.accent : palette.text
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                color: palette.text
                                elide: Text.ElideRight
                                font.family: palette.family
                                font.pixelSize: Kirigami.Units.gridUnit * 0.95
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.subtitle
                                color: palette.secondary
                                elide: Text.ElideRight
                                font.family: palette.family
                                font.pixelSize: Kirigami.Units.gridUnit * 0.75
                            }
                        }
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: palette.run(row.index)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: palette.shown.length === 0 ? Tr.t("Ничего не найдено")
                    : Tr.t("↑ ↓ выбрать · Enter выполнить · Esc закрыть")
                color: palette.secondary
                horizontalAlignment: Text.AlignHCenter
                font.family: palette.family
                font.pixelSize: Kirigami.Units.gridUnit * 0.72
                elide: Text.ElideRight
            }
        }
    }
}

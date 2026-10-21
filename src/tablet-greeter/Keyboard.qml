// On-screen keyboard of the login / lock screen: the same island keys as tablet-keyboard
// (dark, over the blurred wallpaper), letters en/ru (with ё), digits and symbols
import QtQuick
import QtQuick.Layouts
import "Tr.js" as Tr

Rectangle {
    id: kb

    signal typed(string text)
    signal backspace()
    signal enter()

    property real u: 20
    property bool shift: false
    property int layout: 0              // 0 latin, 1 cyrillic, 2 digits and symbols

    readonly property var layouts: [
        ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
        ["йцукенгшщзхъ", "фывапролджэ", "ячсмитьбюё"],
        ["1234567890", "-/:;()$&@*", ".,?!'_#%+="],
    ]

    QtObject {
        id: keyTheme
        readonly property color key: "#56565B"
        readonly property color keyDown: "#3A3A3E"
        readonly property color special: "#353539"
        readonly property color shadow: Qt.rgba(0, 0, 0, 0.55)
        readonly property color text: "#FFFFFF"
        readonly property color subText: "#A1A1A8"
        readonly property color ledOff: "#2A2A2D"
    }

    color: Qt.rgba(0.11, 0.11, 0.12, 0.94)
    implicitHeight: rows.implicitHeight + u * 1.2

    component Key: Item {
        id: key
        property string label
        property string output: label
        property string type: "c"
        property real span: 1
        signal pressedKey()
        Layout.fillWidth: true
        Layout.preferredWidth: span * 100
        Layout.preferredHeight: kb.u * 2.6
        KeyFace {
            anchors.fill: parent
            spec: [key.type, key.label, "", key.span, null]
            theme: keyTheme
            down: area.pressed
            label: key.label
        }
        MouseArea {
            id: area
            anchors.fill: parent
            onClicked: key.output.length ? kb.typed(key.output) : key.pressedKey()
        }
    }

    ColumnLayout {
        id: rows
        anchors.fill: parent
        anchors.margins: kb.u * 0.6
        spacing: kb.u * 0.45

        Repeater {
            model: kb.layouts[kb.layout]
            delegate: RowLayout {
                required property string modelData
                required property int index
                spacing: kb.u * 0.35
                Key {
                    visible: index === 2 && kb.layout !== 2
                    type: "sh"
                    label: kb.shift ? "⇪" : "⇧"
                    output: ""
                    span: 1.5
                    onPressedKey: kb.shift = !kb.shift
                }
                Repeater {
                    model: modelData.split("")
                    delegate: Key {
                        required property string modelData
                        label: kb.shift ? modelData.toUpperCase() : modelData
                    }
                }
                Key {
                    visible: index === 2
                    type: "bs"
                    label: "⌫"
                    output: ""
                    span: 1.5
                    onPressedKey: kb.backspace()
                }
            }
        }
        RowLayout {
            spacing: kb.u * 0.35
            Key {
                type: "num"
                label: kb.layout === 2 ? "ABC" : "123"
                output: ""
                span: 1.5
                onPressedKey: kb.layout = kb.layout === 2 ? 0 : 2
            }
            Key {
                type: "glb"
                label: kb.layout === 1 ? "EN" : "РУ"
                output: ""
                span: 1.2
                onPressedKey: kb.layout = kb.layout === 1 ? 0 : 1
            }
            Key { type: "spc"; label: " "; span: 5 }
            Key {
                type: "ret"
                label: Tr.t("Войти")
                output: ""
                span: 2
                onPressedKey: kb.enter()
            }
        }
    }
}

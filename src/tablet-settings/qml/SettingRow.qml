// One setting. `item` describes it (type, label, note, where it is stored, how it is applied);
// the look follows the mode: big touch controls in tablet mode, compact keyboard-friendly ones in PC mode.
//   switch | choice | number | button | info
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: row

    required property var item
    required property var settings    // Main.qml: value(item) / setValue(item, v)
    property bool touch: false
    property var value: settings.value(item)

    function commit(v) {
        value = v;
        settings.setValue(item, v);
    }

    implicitHeight: content.implicitHeight + (touch ? Kirigami.Units.gridUnit * (settings.pixel ? 1.8 : 1.2)
                                              : Kirigami.Units.smallSpacing * (settings.pixel ? 4 : 3))
    Layout.fillWidth: true
    color: settings.pixel ? (Kirigami.Theme.colorSet === Kirigami.Theme.View
                              ? Kirigami.Theme.backgroundColor : Kirigami.Theme.alternateBackgroundColor)
                          : touch ? Kirigami.Theme.alternateBackgroundColor : "transparent"
    radius: settings.pixel ? Kirigami.Units.gridUnit * 1.75 : touch ? Kirigami.Units.gridUnit * 0.7 : 0

    border.width: settings.pixel ? 1 : 0
    border.color: settings.pixel ? Qt.alpha(Kirigami.Theme.textColor, 0.09) : "transparent"

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: row.touch ? Kirigami.Units.gridUnit : Kirigami.Units.smallSpacing
        anchors.rightMargin: anchors.leftMargin
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            QQC2.Label {
                Layout.fillWidth: true
                text: row.item.label
                wrapMode: Text.Wrap
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * (row.touch ? 1.15 : 1)
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: !!row.item.note
                text: row.item.note || ""
                wrapMode: Text.Wrap
                opacity: 0.65
                font.pointSize: Kirigami.Theme.smallFont.pointSize * (row.touch ? 1.1 : 1)
            }
            // touch: segmented buttons and sliders get their own line under the label
            Loader {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                active: row.touch && (row.item.type === "choice" || row.item.type === "number")
                visible: active
                sourceComponent: row.item.type === "choice" ? touchChoice : touchNumber
            }
        }

        // right-hand control
        Loader {
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: {
                switch (row.item.type) {
                case "switch": return switchControl;
                case "choice": return row.touch ? null : comboControl;
                case "number": return row.touch ? null : spinControl;
                case "button": return buttonControl;
                case "info": return infoControl;
                case "text": return textControl;
                }
                return null;
            }
        }
    }

    Component {
        id: switchControl
        QQC2.Switch {
            id: toggle
            Rectangle {
                id: materialTrack
                visible: row.settings.pixel
                x: toggle.leftPadding
                y: (toggle.height - height) / 2
                implicitWidth: 52; implicitHeight: 32
                width: 52; height: 32; radius: 16
                color: toggle.checked ? Kirigami.Theme.highlightColor : Kirigami.Theme.alternateBackgroundColor
                border.width: toggle.checked ? 0 : 2
                border.color: Kirigami.Theme.disabledTextColor
                Rectangle {
                    width: toggle.checked ? 24 : 16
                    height: width; radius: width / 2
                    x: toggle.checked ? parent.width - width - 4 : 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: toggle.checked ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.disabledTextColor
                    Behavior on x { NumberAnimation { duration: 140 } }
                }
            }
            Binding { target: toggle; property: "indicator"; when: row.settings.pixel; value: materialTrack }
            checked: !!row.value
            scale: row.touch ? 1.4 : 1
            transformOrigin: Item.Right
            onToggled: row.commit(checked)
            Accessible.name: row.item.label
        }
    }

    Component {
        id: comboControl
        QQC2.ComboBox {
            model: row.item.options
            textRole: "label"
            valueRole: "value"
            currentIndex: Math.max(0, row.item.options.findIndex(o => o.value == row.value))
            onActivated: row.commit(currentValue)
            Accessible.name: row.item.label
        }
    }

    Component {
        id: spinControl
        QQC2.SpinBox {
            from: row.item.min
            to: row.item.max
            stepSize: row.item.step || 1
            value: Number(row.value)
            editable: true
            textFromValue: v => v + (row.item.suffix || "")
            valueFromText: t => parseInt(t)
            onValueModified: row.commit(value)
            Accessible.name: row.item.label
        }
    }

    Component {
        id: buttonControl
        QQC2.Button {
            id: actionButton
            Rectangle {
                id: actionSurface
                visible: row.settings.pixel
                implicitHeight: 48
                radius: height / 2
                color: actionButton.down ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.highlightColor, 0.16)
                border.width: actionButton.activeFocus ? 2 : 0
                border.color: Kirigami.Theme.highlightColor
            }
            Binding { target: actionButton; property: "background"; when: row.settings.pixel; value: actionSurface }
            text: row.item.button
            icon.name: row.item.icon || ""
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on implicitHeight { when: row.touch; value: Kirigami.Units.gridUnit * 2.6 }
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on leftPadding { when: row.touch; value: Kirigami.Units.gridUnit }
            rightPadding: leftPadding
            onClicked: row.item.action()
        }
    }

    // free text (e.g. a city): saved when editing is finished
    Component {
        id: textControl
        QQC2.TextField {
            implicitWidth: Kirigami.Units.gridUnit * (row.touch ? 14 : 11)
            // Qt 6.12: assigning undefined no longer restores the default
            Binding on implicitHeight { when: row.touch; value: Kirigami.Units.gridUnit * 2.6 }
            text: row.value === undefined ? "" : String(row.value)
            placeholderText: row.item.placeholder || ""
            onEditingFinished: if (text !== String(row.value)) row.commit(text)
            Accessible.name: row.item.label
        }
    }

    Component {
        id: infoControl
        QQC2.Label {
            text: row.value === undefined ? "" : String(row.value)
            opacity: 0.8
            horizontalAlignment: Text.AlignRight
        }
    }

    // touch: one big button per option
    Component {
        id: touchChoice
        Flow {
            spacing: Kirigami.Units.smallSpacing * 2
            Repeater {
                model: row.item.options
                delegate: QQC2.Button {
                    required property var modelData
                    text: modelData.label
                    checkable: true
                    checked: modelData.value == row.value
                    implicitHeight: Kirigami.Units.gridUnit * 2.6
                    leftPadding: Kirigami.Units.gridUnit * 1.2
                    rightPadding: leftPadding
                    onClicked: row.commit(modelData.value)
                }
            }
        }
    }

    // touch: a slider with big − / + buttons and the value
    Component {
        id: touchNumber
        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            QQC2.Button {
                icon.name: "list-remove"
                implicitWidth: Kirigami.Units.gridUnit * 2.6
                implicitHeight: implicitWidth
                onClicked: row.commit(Math.max(row.item.min, Number(row.value) - (row.item.step || 1)))
            }
            QQC2.Slider {
                Layout.fillWidth: true
                from: row.item.min
                to: row.item.max
                stepSize: row.item.step || 1
                snapMode: QQC2.Slider.SnapAlways
                value: Number(row.value)
                onMoved: row.commit(value)
            }
            QQC2.Button {
                icon.name: "list-add"
                implicitWidth: Kirigami.Units.gridUnit * 2.6
                implicitHeight: implicitWidth
                onClicked: row.commit(Math.min(row.item.max, Number(row.value) + (row.item.step || 1)))
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                horizontalAlignment: Text.AlignRight
                text: row.value + (row.item.suffix || "")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            }
        }
    }
}

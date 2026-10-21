// Screen Time-style history: thin rounded bars, newest on the right, 2 px gaps.
// A fixed set of bars whose heights follow the samples: nothing is created per update.
import QtQuick

Item {
    id: bars

    property var values: []
    property real maximum: 100
    property color color: "#0A84FF"
    property int count: 40

    readonly property real barWidth: Math.max(2, (width - (count - 1) * 2) / count)

    Repeater {
        model: bars.count
        delegate: Rectangle {
            required property int index
            // bar i shows the sample (count - 1 - i) steps back
            readonly property int sample: bars.values.length - bars.count + index
            visible: sample >= 0
            x: index * (bars.barWidth + 2)
            width: bars.barWidth
            height: visible ? Math.max(width, bars.height * Math.min(1, bars.values[sample] / bars.maximum)) : 0
            anchors.bottom: parent.bottom
            radius: Math.min(width / 2, 4)
            color: bars.color
            opacity: index === bars.count - 1 ? 1 : 0.55
        }
    }
}

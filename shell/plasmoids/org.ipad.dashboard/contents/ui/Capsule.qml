// Capsule bar (fill level), or (weather: true) a Weather-style temperature gradient with a dot
import QtQuick

Rectangle {
    id: capsule

    property real value: 0               // 0..1
    property color tint: "#0A84FF"
    property bool weather: false
    property bool material: false        // Material tonal colours for the gradient
    property color ring: "#1C1C1E"       // ring around the dot: the card colour

    readonly property real v: Math.max(0, Math.min(1, value))

    radius: height / 2
    color: weather ? "transparent" : Qt.rgba(tint.r, tint.g, tint.b, 0.24)

    Rectangle {
        visible: !capsule.weather && capsule.v > 0
        width: Math.max(height, parent.width * capsule.v)
        height: parent.height
        radius: height / 2
        color: capsule.tint
    }

    Rectangle {
        visible: !!capsule.weather
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: capsule.material ? "#81C995" : "#30D158" }
            GradientStop { position: 0.55; color: capsule.material ? "#F9DE81" : "#FFD60A" }
            GradientStop { position: 0.8; color: capsule.material ? "#FFB86C" : "#FF9F0A" }
            GradientStop { position: 1.0; color: capsule.material ? "#F2B8B5" : "#FF453A" }
        }
    }
    // current value: white dot with a dark ring, like the Weather app
    Rectangle {
        visible: !!capsule.weather
        width: capsule.height * 1.6
        height: width
        radius: width / 2
        x: capsule.v * (capsule.width - width)
        anchors.verticalCenter: parent.verticalCenter
        color: "white"
        border.color: capsule.ring
        border.width: capsule.height * 0.3
    }
}

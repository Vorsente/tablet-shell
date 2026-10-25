// The top-edge highlight of Liquid Glass (iOS 26), laid over a rounded card or sheet: declare it
// as the parent's first child so the content stays above it.
import QtQuick

Rectangle {
    required property var home
    visible: !home.pixel
    anchors.fill: parent
    anchors.margins: 1
    radius: Math.max(0, parent.radius - 1)
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, home.dark ? 0.12 : 0.28) }
        GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0) }
    }
}

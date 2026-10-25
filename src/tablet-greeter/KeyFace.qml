// One key: a ThinkPad-style island (flat top, gently curved "smile" bottom edge) with an Apple
// keyboard finish: soft bottom shadow, lowercase legends, a small grey flick symbol on top.
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: key

    required property var spec          // [type, label, secondary, width, alternates]
    required property QtObject theme
    property bool down: false
    property bool special: ["bs", "ret", "sh", "num", "abc", "more", "glb", "emo", "hide"].indexOf(spec[0]) !== -1
    property string label: spec[1]
    property string icon: ""            // glyph for special keys
    property string iconName: ""        // or a monochrome system icon
    property bool led: false            // caps lock LED (shift key), like the ThinkPad Caps Lock
    property bool ledVisible: false
    property bool blank: false          // space-bar trackpad: legends fade out

    property bool pixel: false
    readonly property real r: Math.min(width, height) * (pixel ? 0.28 : 0.16)
    property bool showSecondary: true
    property real smileFactor: 1        // 0: plain rounded keys instead of the ThinkPad smile
    readonly property real smile: pixel ? 0 : height * 0.07 * smileFactor

    // shadow, then face: same island path, the shadow shifted down
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        component Island: ShapePath {
            property real dy: 0
            strokeWidth: -1
            startX: key.r; startY: dy
            PathLine { x: key.width - key.r; y: dy }
            PathArc { x: key.width; y: key.r + dy; radiusX: key.r; radiusY: key.r }
            PathLine { x: key.width; y: key.height - key.r - key.smile + dy }
            PathArc { x: key.width - key.r; y: key.height - key.smile + dy; radiusX: key.r; radiusY: key.r }
            // the smile: bottom edge bows down in the middle
            PathQuad { x: key.r; y: key.height - key.smile + dy; controlX: key.width / 2; controlY: key.height + key.smile * 0.6 + dy }
            PathArc { x: 0; y: key.height - key.r - key.smile + dy; radiusX: key.r; radiusY: key.r }
            PathLine { x: 0; y: key.r + dy }
            PathArc { x: key.r; y: dy; radiusX: key.r; radiusY: key.r }
        }
        Island { dy: 1.5; fillColor: key.theme.shadow }
        Island {
            fillColor: key.down ? (key.special ? key.theme.key : key.theme.keyDown)
                                : (key.special ? key.theme.special : key.theme.key)
        }
    }

    // flick symbol (top) and main legend
    Text {
        visible: key.spec[2] !== "" && !key.blank && key.showSecondary
        anchors.horizontalCenter: parent.horizontalCenter
        y: key.height * 0.08
        text: key.spec[2]
        color: key.theme.subText
        font.family: key.pixel ? "Noto Sans" : "Inter"
        font.pixelSize: key.height * 0.2
    }
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (key.spec[2] !== "" && key.showSecondary ? key.height * 0.08 : 0) - key.smile * 0.4
        visible: !key.blank && key.iconName === ""
        text: key.icon !== "" ? key.icon : key.label
        color: key.theme.text
        font.family: key.pixel ? "Noto Sans" : "Inter"
        font.pixelSize: key.icon !== "" ? key.height * 0.36
                       : (key.label.length > 1 ? key.height * 0.27 : key.height * 0.4)
        font.weight: key.label.length > 1 ? Font.Medium : Font.Normal
    }
    Kirigami.Icon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -key.smile * 0.4
        visible: key.iconName !== "" && !key.blank
        width: key.height * 0.4
        height: width
        source: key.iconName
        isMask: true
        color: key.theme.text
    }
    // caps lock LED
    Rectangle {
        visible: key.ledVisible
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: key.height * 0.14
        width: key.height * 0.09
        height: width
        radius: width / 2
        color: key.led ? "#34C759" : key.theme.ledOff
    }
}

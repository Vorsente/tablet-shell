// Activity-style ring: tinted track, rounded progress arc from 12 o'clock
import QtQuick
import QtQuick.Shapes

Item {
    id: ring

    property real value: 0               // 0..1
    property color color: "#0A84FF"
    property real thickness: width * 0.13

    readonly property real r: (Math.min(width, height) - thickness) / 2
    readonly property real v: Math.max(0, Math.min(1, value))

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(ring.color.r, ring.color.g, ring.color.b, 0.24)
            strokeWidth: ring.thickness
            fillColor: "transparent"
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring.r; radiusY: ring.r
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: ring.v > 0.004 ? ring.color : "transparent"
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring.r; radiusY: ring.r
                startAngle: -90; sweepAngle: 360 * ring.v
            }
        }
    }
}

// macOS/iOS-style widget: rounded dark plate, tinted symbol + caption in the accent colour.
// Material: tonal container in the accent hue, the symbol in a filled accent circle.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: widget

    required property QtObject pal
    property string title
    property string icon
    property color accent: pal.blue
    property real u: 20                  // layout unit from the dashboard
    default property alias content: body.data
    signal tapped()

    // Material: a tonal container in the widget's own accent hue (Material You widgets)
    radius: pal.pixel ? u * 1.6 : u * 1.4
    color: pal.pixel ? Qt.tint(pal.plate, Qt.alpha(accent, pal.dark ? 0.2 : 0.16)) : pal.plate
    clip: true
    // equal cells whatever the content: the grid shares the space out, content never widens a column
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredWidth: 0
    Layout.preferredHeight: 0
    Layout.minimumWidth: 0
    Layout.minimumHeight: 0

    MouseArea {
        anchors.fill: parent
        onClicked: widget.tapped()
    }

    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: widget.u * (widget.pal.pixel ? 1.0 : 0.9)
        spacing: widget.u * (widget.pal.pixel ? 0.65 : 0.35)
        height: widget.pal.pixel ? widget.u * 1.8 : widget.u
        Kirigami.Icon {
            visible: !widget.pal.pixel
            implicitWidth: widget.u * 0.85
            implicitHeight: implicitWidth
            source: widget.icon
            isMask: true
            color: widget.accent
        }
        Rectangle {
            visible: widget.pal.pixel
            Layout.preferredWidth: widget.u * 1.55
            Layout.preferredHeight: widget.u * 1.55
            radius: height / 2
            color: widget.accent
            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.58; height: width
                source: widget.icon
                isMask: true
                color: widget.pal.plate
            }
        }
        Text {
            Layout.fillWidth: true
            text: widget.title
            color: widget.pal.pixel ? widget.pal.label : widget.accent
            elide: Text.ElideRight
            font.family: widget.pal.fontFamily
            font.pixelSize: widget.u * (widget.pal.pixel ? 0.85 : 0.72)
            font.weight: widget.pal.pixel ? Font.Medium : Font.DemiBold
        }
    }

    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: widget.u * 0.9
        anchors.rightMargin: widget.u * 0.9
        anchors.topMargin: widget.u * (widget.pal.pixel ? 0.85 : 0.5)
        anchors.bottomMargin: widget.u * 0.9
    }
}

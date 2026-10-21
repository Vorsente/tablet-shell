// macOS/iOS-style widget: rounded dark plate, tinted symbol + caption in the accent colour
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

    radius: u * 1.4
    color: pal.plate
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
        anchors.margins: widget.u * 0.9
        spacing: widget.u * 0.35
        Kirigami.Icon {
            implicitWidth: widget.u * 0.85
            implicitHeight: implicitWidth
            source: widget.icon
            isMask: true
            color: widget.accent
        }
        Text {
            Layout.fillWidth: true
            text: widget.title
            color: widget.accent
            elide: Text.ElideRight
            font.pixelSize: widget.u * 0.72
            font.weight: Font.DemiBold
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
        anchors.topMargin: widget.u * 0.5
        anchors.bottomMargin: widget.u * 0.9
    }
}

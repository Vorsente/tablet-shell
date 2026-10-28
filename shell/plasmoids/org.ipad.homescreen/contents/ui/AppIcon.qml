// An app icon that sits in the grid like an iOS icon (Apple) or a round adaptive icon (Material). Most icons of the theme already are rounded
// squares; the rest are evened out by their measured shape (main.qml iconShape()):
//   square: a full-bleed square (Haruna) gets the theme's rounded corners and size
//   free:   a logo or a round icon (Throne, Android apps) sits on a white squircle plate
import QtQuick

import org.kde.kirigami as Kirigami

Item {
    id: appIcon

    required property var home
    property string source
    readonly property var measured: home.iconShape(source)
    readonly property string shape: measured.shape
    // the theme's icons leave 1/16 free around their squircle: shaped icons match that
    readonly property real inset: width / 16
    readonly property real squircle: (width - inset * 2) * 0.225

    // ---- Material: adaptive round icons (Pixel launcher) ----
    // Icons that are a filled shape (the theme's rounded squares, full-bleed squares) are blown
    // up to their visible box and cut to a circle; free-form logos sit on a light round plate,
    // like legacy icons on Android.
    readonly property bool roundFill: home.pixel && shape !== "free"
    // Themed icons (home screen setting themedIcons): the finished round icon redrawn in two tones
    // of the wallpaper's palette (shaders/themed-icon.frag): a light plate with a dark drawing, in
    // the dark theme a dark plate with a light one
    readonly property bool themed: home.pixel && home.themedIcons
    Item {
        id: pixelFace
        anchors.fill: parent
        visible: appIcon.home.pixel
        layer.enabled: appIcon.themed
        layer.smooth: true
        layer.effect: ShaderEffect {
            readonly property color plate: appIcon.home.dark ? appIcon.home.my("#2B2632") : appIcon.home.my("#EADDFF")
            readonly property color glyph: appIcon.home.dark ? appIcon.home.my("#D0BCFF") : appIcon.home.my("#21005D")
            fragmentShader: Qt.resolvedUrl("shaders/themed-icon.frag.qsb")
        }
        Item {
            id: roundIcon
            anchors.fill: parent
            anchors.margins: appIcon.width * 0.04
            // drawn only through the texture below (opacity 0 keeps the icon loading and the layer live)
            opacity: 0
            layer.enabled: appIcon.roundFill
            Kirigami.Icon {
                // 6 % more than the visible box: the squircle's own rim falls outside the circle
                width: parent.width * appIcon.measured.scale * 1.06
                height: width
                x: (parent.width - width) / 2 + appIcon.measured.dx * width
                y: (parent.height - height) / 2 + appIcon.measured.dy * height
                source: appIcon.roundFill ? appIcon.source : ""
                roundToIconSize: false
            }
        }
        // cut to a circle by Kirigami's rounded texture (MultiEffect's mask drew nothing with Qt 6.10)
        Kirigami.ShadowedTexture {
            anchors.fill: roundIcon
            visible: appIcon.roundFill
            radius: width / 2
            color: "transparent"
            source: appIcon.roundFill ? roundIcon : null
        }
        Rectangle {
            anchors.fill: roundIcon
            visible: appIcon.home.pixel && appIcon.shape === "free"
            radius: width / 2
            color: appIcon.home.my("#F3EDF7")   // icon plate in the wallpaper's palette
            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.64
                height: width
                source: parent.visible ? appIcon.source : ""
                roundToIconSize: false
            }
        }
    }

    Kirigami.Icon {
        anchors.fill: parent
        source: appIcon.source
        visible: !appIcon.home.pixel && appIcon.shape === "native"
        roundToIconSize: false
    }

    // square: rounded corners through a rounded texture (the icon drawn into a layer of exactly its
    // box: the texture would otherwise be Kirigami.Icon's own, which is laid out differently)
    Item {
        id: squareIcon
        anchors.fill: parent
        anchors.margins: appIcon.inset
        opacity: 0
        layer.enabled: !appIcon.home.pixel && appIcon.shape === "square"
        // blown up so the icon's visible square fills the box (its own transparent margin goes)
        Kirigami.Icon {
            width: parent.width * appIcon.measured.scale
            height: width
            x: (parent.width - width) / 2 + appIcon.measured.dx * width
            y: (parent.height - height) / 2 + appIcon.measured.dy * height
            source: appIcon.shape === "square" ? appIcon.source : ""
            roundToIconSize: false
        }
    }
    Kirigami.ShadowedTexture {
        anchors.fill: squareIcon
        visible: !appIcon.home.pixel && appIcon.shape === "square"
        radius: appIcon.squircle
        color: "transparent"
        source: visible ? squareIcon : null
    }

    // free form: on a plate
    Rectangle {
        anchors.fill: parent
        anchors.margins: appIcon.inset
        visible: !appIcon.home.pixel && (appIcon.shape === "free" || appIcon.shape === "round")
        radius: appIcon.squircle
        // white in both looks, like the theme's own white icons (a dark plate stood out among them)
        color: "#FFFFFF"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.06)
        Kirigami.Icon {
            anchors.centerIn: parent
            width: parent.width * 0.72
            height: width
            source: appIcon.source
            visible: parent.visible
        }
    }
}

// Weather on the wallpaper (home screen, tablet mode), drawn by a shader over the live wallpaper
// (shaders/weather.frag). The weather code is Open-Meteo's (WMO), from HomeData.
// The home screen picks the style: live wallpapers on -> animated, off -> static.
//   style "static" (default): the wallpaper itself changes and stays still — a snowy day (cold
//     light, frosty haze, flakes in the air), drops sitting on the glass over a wet grey world, fog.
//     Drawn once, at full resolution, again only when the weather or the wallpaper changes.
//   style "animated": rain runs down the glass, snow falls at three depths, fog drifts, lightning
//     flashes; half resolution and 30 frames a second for the Atom GPU.
//   style "off".
import QtQuick

Item {
    id: fx
    property int code: -1
    property bool allowed: true
    property bool shown: true                // e.g. not in PC mode
    property string style: "static"
    readonly property bool animated: style === "animated"
    property Item wallpaper: null           // what is behind the glass

    // [mode, intensity]: 1 rain, 2 snow, 3 fog
    readonly property var kind: {
        const c = code;
        if (!allowed || style === "off" || c < 0) return [0, 0];
        if (c === 45 || c === 48) return [3, 0.7];
        if (c >= 51 && c <= 55) return [1, 0.15 + (c - 51) * 0.06];   // drizzle
        if (c === 56 || c === 57) return [1, 0.3];
        if (c === 61) return [1, 0.4];
        if (c === 63) return [1, 0.6];
        if (c === 65) return [1, 0.85];
        if (c === 66 || c === 67) return [1, 0.55];
        if (c === 71) return [2, 0.35];
        if (c === 73) return [2, 0.6];
        if (c === 75) return [2, 0.9];
        if (c === 77) return [2, 0.3];
        if (c === 80) return [1, 0.6];
        if (c === 81) return [1, 0.8];
        if (c === 82) return [1, 0.95];
        if (c === 85) return [2, 0.6];
        if (c === 86) return [2, 0.95];
        if (c >= 95) return [1, 0.9];                                // thunderstorm
        return [0, 0];
    }
    // still snow = snow lying on the mountains
    readonly property real mode: kind[0] === 2 && !animated ? 4 : kind[0]
    readonly property bool active: kind[0] > 0 && wallpaper !== null && shown
    // The old full-screen shader used TWO render targets, one at native resolution.
    // At 2560x1600 this was a sizeable GPU bandwidth penalty during swipes/zoom.
    // Sampling the wallpaper directly is sufficient for both still and animated effects.
    readonly property real textureFactor: animated ? 0.5 : 0.75
    readonly property bool storm: allowed && code >= 95
    visible: active

    ShaderEffectSource {
        id: wall
        sourceItem: fx.active ? fx.wallpaper : null
        hideSource: false
        mipmap: false
        live: fx.active && fx.animated
        textureSize: Qt.size(Math.max(1, Math.round(fx.width * fx.textureFactor)), Math.max(1, Math.round(fx.height * fx.textureFactor)))
        visible: false
    }

    Item {
        anchors.fill: parent
        // Do not render the shader a second time through Item.layer. The effect
        // already samples the downscaled source texture.
        layer.enabled: false

        ShaderEffect {
            id: shader
            anchors.fill: parent
            property var source: wall
            property real time: 17       // the still picture is this moment
            property real intensity: fx.kind[1]
            property real flash: 0
            property real mode: fx.mode
            property real aspect: width / Math.max(1, height)
            property real storm: fx.storm ? 1 : 0
            property size texel: Qt.size(1 / Math.max(1, wall.textureSize.width), 1 / Math.max(1, wall.textureSize.height))
            fragmentShader: Qt.resolvedUrl("shaders/weather.frag.qsb")
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: fx.active && fx.visible && fx.animated
        onTriggered: shader.time = (shader.time + 0.033) % 3600
    }

    // lightning: a double flash every 8-20 s
    Timer {
        running: fx.storm && fx.active && fx.animated
        repeat: true
        interval: 8000 + Math.random() * 12000
        onTriggered: {
            interval = 8000 + Math.random() * 12000;
            lightning.start();
        }
    }
    SequentialAnimation {
        id: lightning
        NumberAnimation { target: shader; property: "flash"; to: 0.9; duration: 50 }
        NumberAnimation { target: shader; property: "flash"; to: 0.1; duration: 90 }
        NumberAnimation { target: shader; property: "flash"; to: 0.6; duration: 40 }
        NumberAnimation { target: shader; property: "flash"; to: 0; duration: 600; easing.type: Easing.OutQuad }
    }
}

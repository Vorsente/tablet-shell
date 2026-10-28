// Themed app icons (Material look, AppIcon.qml): the finished round icon redrawn in two tones of
// the wallpaper's palette, like Pixel's themed icons. The icon's own plate is what lies along the
// rim of the circle (sampled there); whatever differs from it in brightness is the drawing. The
// plate takes `plate`, the drawing `glyph`, so every icon gets the same polarity and enough
// contrast, whatever its colours were. The shape and its alpha stay.
// Build: qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o themed-icon.frag.qsb themed-icon.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 plate;
    vec4 glyph;
};
layout(binding = 1) uniform sampler2D source;

float lum(vec4 c)
{
    vec3 rgb = c.a > 0.0001 ? c.rgb / c.a : vec3(0.0);
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

void main()
{
    // the plate's brightness: 12 points on a ring just inside the circle's edge
    float sum = 0.0;
    float weight = 0.0;
    for (int i = 0; i < 12; ++i) {
        float a = float(i) * 0.5235988;
        vec4 s = texture(source, vec2(0.5) + 0.41 * vec2(cos(a), sin(a)));
        sum += lum(s) * s.a;
        weight += s.a;
    }
    float plateL = weight > 0.001 ? sum / weight : 0.5;

    vec4 c = texture(source, qt_TexCoord0);
    float t = smoothstep(0.07, 0.32, abs(lum(c) - plateL));
    vec3 ink = mix(plate.rgb, glyph.rgb, t);
    fragColor = vec4(ink * c.a, c.a) * qt_Opacity;
}

// Weather over the wallpaper (WeatherEffects.qml). `source` is the wallpaper with mipmaps; the mip
// level is the blur.
//   mode 1  rain on glass: the world behind the glass is out of focus, drops and the trails they
//           leave are clear and refract it (technique of "Heartfelt" by Martijn Steinrucken,
//           shadertoy.com/view/ltffzl, CC BY-NC-SA 3.0); `flash` lights it up (thunderstorm)
//   mode 2  snow: three depths of flakes, near ones big and out of focus, swaying in the wind
//   mode 3  fog: slow banks of fog drifting over a softened wallpaper
//   mode 4  snowy landscape (still): snow lies on the top edge of every layer of the picture (the
//           ridges of mountains and hills), a wintry tint, a few flakes in the air
// The still version of rain and fog is the same picture at a fixed time.
// Build: qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o weather.frag.qsb weather.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;        // seconds
    float intensity;   // 0..1
    float flash;       // lightning 0..1
    float mode;
    float aspect;      // width / height
    float storm;       // 0..1: darker, heavier sky
    vec2 texel;        // 1 / source size
};
layout(binding = 1) uniform sampler2D source;

// ---- hashes ----
vec3 N13(float p)
{
    vec3 p3 = fract(vec3(p) * vec3(.1031, .11369, .13787));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract(vec3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}
float N(float t)
{
    return fract(sin(t * 12345.564) * 7658.76);
}
float Saw(float b, float t)
{
    return smoothstep(0., b, t) * smoothstep(1., b, t);
}

// ---- rain on glass ----
// running drops: x = the drop (and its little left-behind droplets), y = the clear trail
vec2 DropLayer(vec2 uv, float t)
{
    vec2 UV = uv;
    uv.y += t * .75;
    vec2 a = vec2(6., 1.);
    vec2 grid = a * 2.;
    vec2 id = floor(uv * grid);
    uv.y += N(id.x);
    id = floor(uv * grid);
    vec3 n = N13(id.x * 35.2 + id.y * 2376.1);
    vec2 st = fract(uv * grid) - vec2(.5, 0.);

    float x = n.x - .5;
    float y = UV.y * 20.;
    float wiggle = sin(y + sin(y));
    x += wiggle * (.5 - abs(x)) * (n.z - .5);
    x *= .7;
    float ti = fract(t + n.z);
    y = (Saw(.85, ti) - .5) * .9 + .5;
    vec2 p = vec2(x, y);

    float d = length((st - p) * a.yx);
    float mainDrop = smoothstep(.4, .0, d);

    float r = sqrt(smoothstep(1., y, st.y));
    float cd = abs(st.x - x);
    float trail = smoothstep(.23 * r, .15 * r * r, cd);
    float trailFront = smoothstep(-.02, .02, st.y - y);
    trail *= trailFront * r * r;

    y = fract(UV.y * 10.) + (st.y - .5);
    float dd = length(st - vec2(x, y));
    float droplets = smoothstep(.3, 0., dd);
    return vec2(mainDrop + droplets * r * trailFront, trail);
}

// small drops sitting on the glass, appearing and drying up
float StaticDrops(vec2 uv, float t)
{
    uv *= 40.;
    vec2 id = floor(uv);
    uv = fract(uv) - .5;
    vec3 n = N13(id.x * 107.45 + id.y * 3543.654);
    vec2 p = (n.xy - .5) * .7;
    float d = length(uv - p);
    float fade = Saw(.025, fract(t + n.z));
    return smoothstep(.3, 0., d) * fract(n.z * 10.) * fade;
}

vec2 Drops(vec2 uv, float t, float l0, float l1, float l2)
{
    float s = StaticDrops(uv, t) * l0;
    vec2 m1 = DropLayer(uv, t) * l1;
    vec2 m2 = DropLayer(uv * 1.85, t) * l2;
    float c = smoothstep(.3, 1., s + m1.x + m2.x);
    return vec2(c, max(m1.y * l0, m2.y * l1));
}

vec3 rain(vec2 UV)
{
    // shader space: y up, centred, height 1
    vec2 uv = (UV - .5) * vec2(aspect, -1.);
    float t = time * .2;
    float amount = intensity;
    float l0 = smoothstep(-.5, 1., amount) * 2.;
    float l1 = smoothstep(.25, .75, amount);
    float l2 = smoothstep(.0, .5, amount);

    vec2 c = Drops(uv, t, l0, l1, l2);
    // surface normal of the water from two more samples: the refraction offset
    vec2 e = vec2(.001, 0.);
    float cx = Drops(uv + e, t, l0, l1, l2).x;
    float cy = Drops(uv + e.yx, t, l0, l1, l2).x;
    vec2 n = vec2(cx - c.x, cy - c.x);

    // out of focus behind the glass, sharp through the water
    float focus = mix(mix(4.5, 6.5, amount) - c.y, 1.5, smoothstep(.1, .2, c.x));
    vec3 col = textureLod(source, UV + vec2(n.x, -n.y), focus).rgb;

    // wet, overcast light; a lightning strike lights the whole scene up
    col *= mix(vec3(1.), vec3(.82, .86, .92), .55);
    col *= mix(1., .62, storm);
    col += flash * vec3(.75, .8, 1.) * (.35 + .65 * c.x);
    return col;
}

// ---- snow ----
// one depth of flakes; `blur` softens the edge, `sway` is the wind
float snowLayer(vec2 uv, float scale, float speed, float size, float blur, float t)
{
    uv *= scale;
    uv.y -= t * speed;
    uv.x += sin(uv.y * .35 + t * .6) * .35 + t * .25;
    vec2 id = floor(uv);
    vec2 st = fract(uv) - .5;
    vec3 n = N13(id.x * 31.7 + id.y * 517.3);
    if (n.z > intensity * 1.15) {
        return 0.;              // fewer flakes in light snow
    }
    vec2 p = (n.xy - .5) * .6;
    p.x += sin(t * (1. + n.z) + n.x * 6.28) * .12;
    float r = size * mix(.6, 1.2, n.y);
    float d = length(st - p);
    return smoothstep(r, r * (1. - blur), d) * mix(.55, 1., n.x);
}

vec3 snow(vec2 UV)
{
    vec2 uv = (UV - .5) * vec2(aspect, 1.);
    float t = time;
    // the cold, white-grey sky softens the world a little
    vec3 col = textureLod(source, UV, 1.6).rgb;
    col = mix(col, vec3(.86, .9, .96), .16) * vec3(.97, .99, 1.04);
    float far = snowLayer(uv, 26., .55, .07, .25, t);
    float mid = snowLayer(uv + 3.1, 11., .9, .09, .45, t);
    float near = snowLayer(uv + 7.7, 4.2, 1.4, .13, .95, t);   // big, out of focus
    col = mix(col, vec3(1.), far * .55);
    col = mix(col, vec3(1.), mid * .8);
    col = mix(col, vec3(1.), near * .45);
    return col;
}

// ---- fog ----
float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3. - 2. * f);
    float a = N(i.x + i.y * 57.);
    float b = N(i.x + 1. + i.y * 57.);
    float c = N(i.x + (i.y + 1.) * 57.);
    float d = N(i.x + 1. + (i.y + 1.) * 57.);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p)
{
    float v = 0., a = .5;
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= .5;
    }
    return v;
}

vec3 fog(vec2 UV)
{
    vec2 uv = (UV - .5) * vec2(aspect, 1.) * 2.2;
    float t = time * .025;
    float bank = fbm(uv + vec2(t, t * .3)) * .65 + fbm(uv * 1.8 - vec2(t * 1.7, 0.)) * .35;
    // thicker towards the bottom, like fog lying low
    float amount = clamp(smoothstep(.3, .85, bank) * mix(.55, .95, UV.y) * (.6 + .4 * intensity), 0., .92);
    vec3 col = textureLod(source, UV, mix(1., 4., amount)).rgb;
    return mix(col, vec3(.82, .84, .86), amount * .75);
}

// ---- winter (still): the same picture on a snowy day ----
// No snow is painted on the landscape (on drawn wallpapers that only looks like artefacts): cold,
// muted light, a bright frosty haze towards the distance, and snowflakes caught mid-air at three
// depths, the near ones big and out of focus.
vec3 snowcap(vec2 UV)
{
    vec3 col = textureLod(source, UV, .6).rgb;
    float l = dot(col, vec3(.299, .587, .114));
    col = mix(col, vec3(l), .42);                         // muted
    col = col * vec3(.92, .97, 1.07) + vec3(.03, .04, .06); // cold, lifted shadows
    // frosty haze: thicker high up, where the distance usually is
    float haze = mix(.34, .1, smoothstep(0., .85, UV.y));
    col = mix(col, vec3(.88, .91, .96), haze);
    // flakes in the air
    vec2 uv = (UV - .5) * vec2(aspect, 1.);
    col = mix(col, vec3(1.), snowLayer(uv, 30., 0., .055, .35, 3.) * .5);
    col = mix(col, vec3(1.), snowLayer(uv + 3.1, 13., 0., .075, .55, 5.) * .7);
    col = mix(col, vec3(1.), snowLayer(uv + 7.7, 4.5, 0., .12, .95, 7.) * .38);
    return col;
}

void main()
{
    vec2 UV = qt_TexCoord0;
    vec3 col;
    if (mode < 1.5) {
        col = rain(UV);
    } else if (mode < 2.5) {
        col = snow(UV);
    } else if (mode < 3.5) {
        col = fog(UV);
    } else {
        col = snowcap(UV);
    }
    fragColor = vec4(col, 1.) * qt_Opacity;
}

// Material You for the shell's QML (copies of scripts/MaterialYou.js next to the QML that uses it;
// the build refreshes them from this file).
//
// The Pixel look's colours were written in Material 3's baseline purple. tablet-tools material-you
// makes the KDE colour scheme from the wallpaper's colour, so Kirigami's highlight colour is the
// dynamic primary. tint(colour, seedHue) moves a baseline colour to the same tone (CIELAB L*) in the
// dynamic palette: the primary / secondary / neutral purples to the seed hue, the tertiary rose to
// the seed hue + 60 (Material's Tonal spot); greens, oranges, reds stay what they are.
//   import "MaterialYou.js" as MY
//   readonly property real seedHue: MY.hueOf(Kirigami.Theme.highlightColor)
//   color: MY.tint("#6750A4", seedHue)
.pragma library

const Xn = 0.95047, Zn = 1.08883;
const baselinePrimary = 305, baselineTertiary = 358;

function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function gam(c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055; }
function f(t) { return t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116; }
function fi(t) { return t * t * t > 216 / 24389 ? t * t * t : (116 * t - 16) / (24389 / 27); }

// "#rrggbb" / "#aarrggbb" / a color -> {r, g, b, a} (0..1)
function rgba(c) {
    if (typeof c === "string") {
        const h = c.replace("#", "");
        const n = h.length === 8 ? 2 : 0;
        return { r: parseInt(h.substr(n, 2), 16) / 255, g: parseInt(h.substr(n + 2, 2), 16) / 255,
                 b: parseInt(h.substr(n + 4, 2), 16) / 255, a: n ? parseInt(h.substr(0, 2), 16) / 255 : 1 };
    }
    return { r: c.r, g: c.g, b: c.b, a: c.a === undefined ? 1 : c.a };
}

function lch(c) {
    const r = lin(c.r), g = lin(c.g), b = lin(c.b);
    const x = 0.4124 * r + 0.3576 * g + 0.1805 * b;
    const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const z = 0.0193 * r + 0.1192 * g + 0.9505 * b;
    const fx = f(x / Xn), fy = f(y), fz = f(z / Zn);
    const A = 500 * (fx - fy), B = 200 * (fy - fz);
    let h = Math.atan2(B, A) * 180 / Math.PI;
    return { L: 116 * fy - 16, C: Math.hypot(A, B), h: h < 0 ? h + 360 : h };
}

// null when outside sRGB
function fromLch(L, C, h) {
    const A = C * Math.cos(h * Math.PI / 180), B = C * Math.sin(h * Math.PI / 180);
    const fy = (L + 16) / 116, fx = fy + A / 500, fz = fy - B / 200;
    const x = Xn * fi(fx), y = fi(fy), z = Zn * fi(fz);
    const v = [3.2406 * x - 1.5372 * y - 0.4986 * z, -0.9689 * x + 1.8758 * y + 0.0415 * z, 0.0557 * x - 0.2040 * y + 1.0570 * z];
    if (v.some(e => e < -1e-4 || e > 1 + 1e-4)) {
        return null;
    }
    return v.map(e => Math.max(0, Math.min(1, gam(Math.max(0, Math.min(1, e))))));
}

function hueOf(color) {
    return lch(rgba(color)).h;
}

function hueDistance(a, b) {
    const d = Math.abs(a - b) % 360;
    return d > 180 ? 360 - d : d;
}

function hex2(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2); }

function tint(color, seedHue) {
    // the baseline purple itself (Material You off): as written
    if (seedHue === undefined || isNaN(seedHue) || hueDistance(seedHue, baselinePrimary) < 2) {
        return color;
    }
    const c = rgba(color);
    const p = lch(c);
    let hue;
    let chroma = p.C;
    if (p.C < 10 || hueDistance(p.h, baselinePrimary) < 25) {
        hue = seedHue;
        // baseline primary is more saturated than Tonal spot's primary (36)
        if (chroma > 25) chroma *= 0.75;
    } else if (hueDistance(p.h, baselineTertiary) < 25) {
        hue = (seedHue + 60) % 360;
    } else {
        return color;
    }
    let rgb = fromLch(p.L, chroma, hue);
    if (!rgb) {
        // too colourful for sRGB at this tone: as much chroma as fits
        rgb = fromLch(p.L, 0, hue) || [c.r, c.g, c.b];
        for (let lo = 0, hi = chroma, i = 0; i < 14; ++i) {
            const mid = (lo + hi) / 2;
            const m = fromLch(p.L, mid, hue);
            if (m) { lo = mid; rgb = m; } else { hi = mid; }
        }
    }
    return "#" + (c.a < 1 ? hex2(c.a) : "") + hex2(rgb[0]) + hex2(rgb[1]) + hex2(rgb[2]);
}

// the colour for the current look: tinted in the Pixel look, as written in the Apple one
// (accent: Kirigami.Theme.highlightColor, the dynamic primary)
function you(color, pixel, accent) {
    return pixel ? tint(color, hueOf(accent)) : color;
}

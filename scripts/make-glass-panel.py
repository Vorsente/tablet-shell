#!/usr/bin/python3 -I
# Generate an iPadOS-style panel-background.svgz for the WhiteSur Liquid themes:
# unprefixed elements = flat glass status bar, "south-" elements = rounded glass dock.
# Usage: make-glass-panel.py [DESKTOPTHEME_DIR]   (default ~/.local/share/plasma/desktoptheme)
import gzip, os, sys

BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/share/plasma/desktoptheme")
THEMES = {
    # theme: (bar tint, bar opacity, dock tint, dock opacity, edge highlight opacity, shadow opacity)
    "WhiteSurLiquid-dark": ("#000000", 0.18, "#26262c", 0.42, 0.22, 0.25),
    "WhiteSurLiquid": ("#ffffff", 0.22, "#ffffff", 0.38, 0.55, 0.18),
}
R = 22   # dock corner radius (logical px)
S = 12   # shadow size
M = 7    # dock content margin


def frame(prefix, x0, y0, tint, opacity, radius, edge, edge_op):
    """9-slice frame with rounded corners and a 1px glass edge.

    Every shape stays inside its element's box (no strokes), so FrameSvg measures borders exactly.
    """
    b = radius
    c = 10  # tile size of edges and center
    fill = f'fill="{tint}" fill-opacity="{opacity}"'
    hi = f'fill="#ffffff" fill-opacity="{edge_op}"'
    out = []

    def g(name, body):
        out.append(f'<g id="{prefix}{name}">{body}</g>')

    def rect(x, y, w, h, extra):
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" {extra}/>'

    X1, X2, Y1, Y2 = x0 + b, x0 + b + c, y0 + b, y0 + b + c
    if radius:
        r2 = b - 1
        # (corner origin = the inner corner point, direction signs)
        for name, cx, cy, sx, sy in (("topleft", X1, Y1, -1, -1), ("topright", X2, Y1, 1, -1),
                                     ("bottomleft", X1, Y2, -1, 1), ("bottomright", X2, Y2, 1, 1)):
            sweep = 1 if sx * sy > 0 else 0
            # filled quarter disc
            disc = (f'M{cx},{cy} L{cx + sx * b},{cy} A{b},{b} 0 0 {sweep} {cx},{cy + sy * b} Z')
            # 1px quarter ring along the outer arc
            ring = (f'M{cx + sx * b},{cy} A{b},{b} 0 0 {sweep} {cx},{cy + sy * b} '
                    f'L{cx},{cy + sy * r2} A{r2},{r2} 0 0 {1 - sweep} {cx + sx * r2},{cy} Z')
            body = f'<path d="{disc}" {fill}/>' + (f'<path d="{ring}" {hi}/>' if edge else "")
            # invisible box pins the element size to exactly b x b
            box = rect(min(cx, cx + sx * b), min(cy, cy + sy * b), b, b, 'fill="none"')
            g(name, box + body)
        g("top", rect(X1, y0, c, b, fill) + (rect(X1, y0, c, 1, hi) if edge else ""))
        g("bottom", rect(X1, Y2, c, b, fill) + (rect(X1, Y2 + b - 1, c, 1, hi) if edge else ""))
        g("left", rect(x0, Y1, b, c, fill) + (rect(x0, Y1, 1, c, hi) if edge else ""))
        g("right", rect(X2, Y1, b, c, fill) + (rect(X2 + b - 1, Y1, 1, c, hi) if edge else ""))
    else:
        # Flat bar: 1px borders, faint hairline at the bottom
        for name, (x, y, w, h) in {"topleft": (x0, y0, 1, 1), "topright": (X2, y0, 1, 1),
                                   "bottomleft": (x0, Y2, 1, 1), "bottomright": (X2, Y2, 1, 1),
                                   "top": (X1, y0, c, 1), "left": (x0, Y1, 1, c), "right": (X2, Y1, 1, c)}.items():
            g(name, rect(x, y, w, h, fill))
        g("bottom", rect(X1, Y2, c, 1, fill) + rect(X1, Y2, c, 1, f'fill="#ffffff" fill-opacity="{edge_op / 3:.2f}"'))
    g("center", rect(X1, Y1, c, c, fill))
    return "".join(out)


def shadow(prefix, x0, y0, op):
    """Soft drop shadow tiles (shadow-*) drawn by KWin around the floating dock."""
    out = [f'<defs><linearGradient id="{prefix}gv" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0"/>'
           f'<stop offset="1" stop-color="#000" stop-opacity="{op}"/></linearGradient>'
           f'<linearGradient id="{prefix}gh" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000" stop-opacity="0"/>'
           f'<stop offset="1" stop-color="#000" stop-opacity="{op}"/></linearGradient>'
           f'<radialGradient id="{prefix}gr" cx="1" cy="1" r="1"><stop offset="0" stop-color="#000" stop-opacity="{op}"/>'
           f'<stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient></defs>']
    c = 10
    t = lambda a: f'transform="rotate({a} {x0 + S + c / 2} {y0 + S + c / 2})"'
    # corners: one radial quarter rotated into place
    for name, (x, y, a) in {"topleft": (x0, y0, 0), "topright": (x0 + S + c, y0, 90),
                            "bottomright": (x0 + S + c, y0 + S + c, 180), "bottomleft": (x0, y0 + S + c, 270)}.items():
        out.append(f'<rect id="{prefix}shadow-{name}" x="{x}" y="{y}" width="{S}" height="{S}" fill="url(#{prefix}gr)" '
                   f'transform="rotate({a} {x + S / 2} {y + S / 2})"/>')
    out.append(f'<rect id="{prefix}shadow-top" x="{x0 + S}" y="{y0}" width="{c}" height="{S}" fill="url(#{prefix}gv)"/>')
    out.append(f'<rect id="{prefix}shadow-bottom" x="{x0 + S}" y="{y0 + S + c}" width="{c}" height="{S}" fill="url(#{prefix}gv)" '
               f'transform="rotate(180 {x0 + S + c / 2} {y0 + S + c + S / 2})"/>')
    out.append(f'<rect id="{prefix}shadow-left" x="{x0}" y="{y0 + S}" width="{S}" height="{c}" fill="url(#{prefix}gh)"/>')
    out.append(f'<rect id="{prefix}shadow-right" x="{x0 + S + c}" y="{y0 + S}" width="{S}" height="{c}" fill="url(#{prefix}gh)" '
               f'transform="rotate(180 {x0 + S + c + S / 2} {y0 + S + c / 2})"/>')
    out.append(f'<rect id="{prefix}shadow-center" x="{x0 + S}" y="{y0 + S}" width="{c}" height="{c}" fill="none"/>')
    return "".join(out)


def hints(prefix, x0, y0, top, bottom, left, right):
    return (f'<rect id="{prefix}hint-top-margin" x="{x0}" y="{y0}" width="1" height="{top}" fill="none"/>'
            f'<rect id="{prefix}hint-bottom-margin" x="{x0 + 2}" y="{y0}" width="1" height="{bottom}" fill="none"/>'
            f'<rect id="{prefix}hint-left-margin" x="{x0 + 4}" y="{y0}" width="{left}" height="1" fill="none"/>'
            f'<rect id="{prefix}hint-right-margin" x="{x0 + 4}" y="{y0 + 2}" width="{right}" height="1" fill="none"/>')


for theme, (bar, bar_op, dock, dock_op, edge_op, sh_op) in THEMES.items():
    body = (frame("", 0, 0, bar, bar_op, 0, False, edge_op)
            + hints("", 0, 40, 2, 2, 4, 4)
            + frame("south-", 100, 0, dock, dock_op, R, True, edge_op)
            # opaque masks: KWin blurs/contrasts exactly this shape
            + frame("mask-south-", 100, 200, "#000000", 1, R, False, 0)
            + frame("mask-", 0, 200, "#000000", 1, 0, False, 0)
            + hints("south-", 100, 80, M, M, M + 4, M + 4)
            + shadow("", 200, 0, sh_op))  # panel shadows only read unprefixed shadow-* elements
    body += ('<rect id="hint-stretch-borders" x="0" y="110" width="1" height="1" fill="none"/>'
             '<rect id="south-hint-stretch-borders" x="2" y="110" width="1" height="1" fill="none"/>')
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">{body}</svg>'
    out = os.path.join(BASE, theme, "widgets", "panel-background.svgz")
    with gzip.open(out, "wt") as f:
        f.write(svg)
    print("wrote", out)

# Popups (app launcher, tray popups, calendar…): WhiteSur draws them as see-through glass that
# relies on KWin's blur, which is off here (Atom GPU). Make their fill opaque instead (a partly transparent fill still shows through a lot).
DIALOG_FILLS = {
    "WhiteSurLiquid": ("opacity:0.35;fill:#cccccc", "opacity:1;fill:#f2f2f5"),
    "WhiteSurLiquid-dark": ("opacity:0.65;fill:#1a1a1a", "opacity:1;fill:#1e1e20"),
}
for theme, (old, new) in DIALOG_FILLS.items():
    path = os.path.join(BASE, theme, "dialogs", "background.svgz")
    with gzip.open(path, "rt") as f:
        svg = f.read()
    if old in svg:
        with gzip.open(path, "wt") as f:
            f.write(svg.replace(old, new))
        print("made opaque", path)

# Text: the light theme's text is white everywhere (glass over a dark backdrop). With opaque popups
# and a light glass bar that is unreadable: classic dark text on light, white stays for the dark
# theme. Selection (white on blue) and Complementary (dark surfaces like OSDs) are left alone.
import configparser
LIGHT_TEXT = {
    "ForegroundNormal": "29,29,31",
    "ForegroundActive": "0,0,0",
    "ForegroundInactive": "0,0,0,130",
}
path = os.path.join(BASE, "WhiteSurLiquid", "colors")
colors = configparser.ConfigParser(interpolation=None, strict=False)
colors.optionxform = str
colors.read(path)
for group in ("Colors:Button", "Colors:Window", "Colors:View", "Colors:Tooltip", "Colors:Header", "Colors:Header][Inactive"):
    if colors.has_section(group):
        for key, value in LIGHT_TEXT.items():
            colors[group][key] = value
for group in ("Colors:Header", "Colors:Header][Inactive"):
    if colors.has_section(group):
        colors[group]["BackgroundNormal"] = "0,0,0,20"
        colors[group]["BackgroundAlternate"] = "0,0,0,30"
if colors.has_section("Colors:Header][Inactive"):
    colors["Colors:Header][Inactive"]["ForegroundNormal"] = "0,0,0,150"
with open(path, "w") as f:
    colors.write(f, space_around_delimiters=False)
print("dark text on light", path)

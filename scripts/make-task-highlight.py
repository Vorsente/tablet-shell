#!/usr/bin/python3 -I
# Task highlight of the panel / dock task manager (widgets/tasks.svg): a compact rounded plate a
# little larger than the icon, instead of a block filling the whole task cell from the bar's top to
# its bottom (Breeze, which the Pixel themes fell back to, and WhiteSur).
#   make-task-highlight.py THEME_DIR...            writes THEME_DIR/widgets/tasks.svg
#   make-task-highlight.py --apple THEME_DIR...    WhiteSur Liquid: running apps without a plate
#                                                  (the iPadOS dock look), focus and hover compact
# Each prefix is a 9-slice frame: the corner tiles are INSET_X / INSET_Y px of transparent edge plus
# the rounded corner, so the plate stays that far inside the cell; hint margins keep the icon as
# large as before (the icon is the bar's height minus 2 * MARGIN).
import os, sys

INSET_X = 12   # transparent edge left and right of the plate (task cells are wide)
INSET_Y = 4    # and above / below it
RADIUS = 12    # corner radius of the plate
MARGIN = 9     # content margin: the icon's distance from the cell edge
BX = INSET_X + RADIUS
BY = INSET_Y + RADIUS
W = 4          # edge / centre tile size

COLORS = '<style id="current-color-scheme" type="text/css">' \
         '.ColorScheme-Text { color:#fcfcfc; } .ColorScheme-Highlight { color:#3daee9; } ' \
         '.ColorScheme-NegativeText { color:#da4453; }</style>'


def frame(prefix, x0, y0, cls, opacity):
    """9-slice frame at (x0, y0); the visible plate is drawn with fill="currentColor"."""
    paint = f'class="{cls}" fill="currentColor" fill-opacity="{opacity}"'
    out = []

    def tile(name, x, y, w, h, shape):
        box = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none"/>'
        out.append(f'<g id="{prefix}{name}">{box}{shape}</g>')

    r, ix, iy = RADIUS, INSET_X, INSET_Y
    xs = [x0, x0 + BX, x0 + BX + W]        # left column, middle, right column
    ys = [y0, y0 + BY, y0 + BY + W]
    # corners: a quarter disc touching the inner corner of the tile
    tile("topleft", xs[0], ys[0], BX, BY, f'<path {paint} d="M{xs[0] + ix},{ys[0] + BY} A{r},{r} 0 0 1 {xs[0] + BX},{ys[0] + iy} L{xs[0] + BX},{ys[0] + BY} Z"/>')
    tile("topright", xs[2], ys[0], BX, BY, f'<path {paint} d="M{xs[2]},{ys[0] + iy} A{r},{r} 0 0 1 {xs[2] + r},{ys[0] + BY} L{xs[2]},{ys[0] + BY} Z"/>')
    tile("bottomleft", xs[0], ys[2], BX, BY, f'<path {paint} d="M{xs[0] + BX},{ys[2] + r} A{r},{r} 0 0 1 {xs[0] + ix},{ys[2]} L{xs[0] + BX},{ys[2]} Z"/>')
    tile("bottomright", xs[2], ys[2], BX, BY, f'<path {paint} d="M{xs[2] + r},{ys[2]} A{r},{r} 0 0 1 {xs[2]},{ys[2] + r} L{xs[2]},{ys[2]} Z"/>')
    # edges: the plate part of the strip
    tile("top", xs[1], ys[0], W, BY, f'<rect {paint} x="{xs[1]}" y="{ys[0] + iy}" width="{W}" height="{r}"/>')
    tile("bottom", xs[1], ys[2], W, BY, f'<rect {paint} x="{xs[1]}" y="{ys[2]}" width="{W}" height="{r}"/>')
    tile("left", xs[0], ys[1], BX, W, f'<rect {paint} x="{xs[0] + ix}" y="{ys[1]}" width="{r}" height="{W}"/>')
    tile("right", xs[2], ys[1], BX, W, f'<rect {paint} x="{xs[2]}" y="{ys[1]}" width="{r}" height="{W}"/>')
    tile("center", xs[1], ys[1], W, W, f'<rect {paint} x="{xs[1]}" y="{ys[1]}" width="{W}" height="{W}"/>')
    # content margins: the icon keeps its size whatever the corner tiles are
    hy = y0 + 2 * BY + W + 4
    for k, (name, w, h) in enumerate([("top", 1, MARGIN), ("bottom", 1, MARGIN), ("left", MARGIN, 1), ("right", MARGIN, 1)]):
        out.append(f'<rect id="{prefix}hint-{name}-margin" x="{x0 + k * (MARGIN + 2)}" y="{hy}" width="{w}" height="{h}" fill="none"/>')
    return "".join(out)


def svg(apple):
    # prefix: (colour class, opacity); 0 = no plate
    plates = {
        "normal-": ("ColorScheme-Text", 0 if apple else 0.07),       # running, not in front
        "minimized-": ("ColorScheme-Text", 0 if apple else 0.04),
        "focus-": ("ColorScheme-Highlight", 0.26),
        "hover-": ("ColorScheme-Text", 0.12),
        "attention-": ("ColorScheme-NegativeText", 0.32),
        "progress-": ("ColorScheme-Highlight", 0.35),
    }
    body = "".join(frame(p, k * 80, 0, c, o) for k, (p, (c, o)) in enumerate(plates.items()))
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{80 * len(plates)}" height="80">{COLORS}{body}</svg>\n'


def merge_apple(path_svgz, out_svg):
    """WhiteSur Liquid: keep its own elements (the dot under running apps, see make-glass-panel.py)
    and replace only the big hover / attention blocks with compact plates."""
    import gzip, re
    with gzip.open(path_svgz, "rt") as f:
        svg_text = f.read()
    svg_text = re.sub(r'<g\s+id="(?:hover|attention)-[a-z-]+".*?</g>', "", svg_text, flags=re.S)
    svg_text = re.sub(r'<(?:rect|path)\b[^>]*id="(?:hover|attention)-[a-z-]+"[^>]*/>', "", svg_text)
    ours = frame("hover-", 2000, 0, "ColorScheme-Text", 0.12) + frame("attention-", 2080, 0, "ColorScheme-NegativeText", 0.32)
    svg_text = svg_text.replace("</svg>", COLORS + ours + "</svg>") if "current-color-scheme" not in svg_text \
        else svg_text.replace("</svg>", ours + "</svg>")
    with open(out_svg, "w") as f:
        f.write(svg_text)


if __name__ == "__main__":
    args = sys.argv[1:]
    apple = "--apple" in args
    for theme in (a for a in args if a != "--apple"):
        if not os.path.isdir(theme):
            continue
        widgets = os.path.join(theme, "widgets")
        os.makedirs(widgets, exist_ok=True)
        svgz, plain = os.path.join(widgets, "tasks.svgz"), os.path.join(widgets, "tasks.svg")
        if apple and os.path.exists(svgz):
            merge_apple(svgz, plain)
            os.remove(svgz)          # the compressed copy would win over tasks.svg
        elif not apple or not os.path.exists(plain):
            if os.path.exists(svgz):
                os.remove(svgz)
            with open(plain, "w") as f:
                f.write(svg(apple))
        print("task highlight", theme)

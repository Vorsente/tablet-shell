#!/usr/bin/env python3
"""Regenerate the bundled Material Plasma surfaces; no external dependencies.

Frame IDs follow https://develop.kde.org/docs/plasma/theme/background-svg/ .
Artifacts are committed/bundled so installation does not depend on this generator.
"""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]

def frame(prefix, fill, radius=16):
    r = radius
    # Nine independently rendered pieces, sharing exact boundary coordinates.
    paths = {
        'topleft': f'M {r} 0 A {r} {r} 0 0 0 0 {r} H {r} Z',
        'topright': f'M 32 0 A {r} {r} 0 0 1 {32+r} {r} H 32 Z',
        'bottomleft': f'M 0 32 A {r} {r} 0 0 0 {r} {32+r} V 32 Z',
        'bottomright': f'M {32+r} 32 A {r} {r} 0 0 1 32 {32+r} V 32 Z',
    }
    pieces = [f'<path id="{prefix}{key}" fill="{fill}" d="{d}"/>' for key,d in paths.items()]
    for key,x,y,w,h in [('top',r,0,32-r,r),('bottom',r,32,32-r,r),
                        ('left',0,r,r,32-r),('right',32,r,r,32-r),('center',r,r,32-r,32-r)]:
        pieces.append(f'<rect id="{prefix}{key}" x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"/>')
    return '\n'.join(pieces)

def rgb(value):
    return ','.join(str(int(value[i:i+2],16)) for i in (1,3,5))

for dark in (False, True):
    mode = 'dark' if dark else 'light'
    name = 'TabletPixel' + mode.title()
    theme = 'tablet-pixel-' + mode
    surface, plate, text, secondary, primary, onprimary = (
        ('#141218','#2B2932','#E6E0E9','#CAC4D0','#D0BCFF','#381E72') if dark else
        ('#FEF7FF','#F3EDF7','#1D1B20','#49454F','#6750A4','#FFFFFF'))
    sections = ['[General]\nName=Tablet Pixel '+mode.title()+'\nColorScheme='+name]
    for role in ['Window','View','Button','Tooltip','Complementary','Selection','Header']:
        bg = primary if role == 'Selection' else surface if role in ('Window','View') else plate
        fg = onprimary if role == 'Selection' else text
        sections.append(f'''[Colors:{role}]
BackgroundNormal={rgb(bg)}
BackgroundAlternate={rgb(plate)}
ForegroundNormal={rgb(fg)}
ForegroundInactive={rgb(secondary)}
ForegroundActive={rgb(primary)}
ForegroundLink={rgb(primary)}
ForegroundVisited={rgb(secondary)}
ForegroundNegative={rgb('#F2B8B5' if dark else '#B3261E')}
ForegroundNeutral={rgb('#FFB86C' if dark else '#825500')}
ForegroundPositive={rgb('#81C995' if dark else '#146C2E')}
DecorationFocus={rgb(primary)}
DecorationHover={rgb(primary)}''')
    sections.append(f'[WM]\nactiveBackground={rgb(surface)}\nactiveForeground={rgb(text)}\ninactiveBackground={rgb(plate)}\ninactiveForeground={rgb(secondary)}')
    colors = '\n\n'.join(sections)+'\n'
    target = ROOT/'shell/desktoptheme'/theme
    target.mkdir(parents=True, exist_ok=True)
    (ROOT/'shell/color-schemes').mkdir(exist_ok=True)
    (ROOT/'shell/color-schemes'/f'{name}.colors').write_text(colors)
    (target/'colors').write_text(colors)
    (target/'metadata.json').write_text(json.dumps({'KPlugin':{'Id':theme,'Name':'Tablet Pixel '+mode.title(),'Description':'Opaque Material surfaces for Tablet Shell','Version':'1.0','License':'GPL-3.0-or-later'},'X-Plasma-API':'5.0'},indent=2)+'\n')
    (target/'plasmarc').write_text('[Settings]\nFallbackTheme=default\n[ContrastEffect]\nenabled=false\n[BlurBehindEffect]\nenabled=false\n')
    for resource in ['widgets/panel-background.svg','widgets/background.svg','dialogs/background.svg','widgets/tooltip.svg']:
        file=target/resource; file.parent.mkdir(parents=True,exist_ok=True)
        # Explicit opaque fallback mirrors the composited surface.
        svg='<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">\n'+frame('',plate,12 if 'panel-' in resource else 16)+ '\n'+frame('mask-','#000000',12 if 'panel-' in resource else 16)+'\n<rect id="hint-stretch-borders" width="1" height="1" fill="none"/>\n</svg>\n'
        file.write_text(svg)
    defaults=ROOT/f'shell/look-and-feel/org.tabletshell.pixel.{mode}/contents/defaults'
    content=defaults.read_text().replace('ColorScheme=Breeze'+mode.title(),'ColorScheme='+name).replace('name=default','name='+theme)
    defaults.write_text(content)

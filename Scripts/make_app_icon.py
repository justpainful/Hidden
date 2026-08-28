#!/usr/bin/env python3
"""Render the Hidden app icon in the Apple system-app idiom.

Apple's own icons (Books, Music, Podcasts, Journal) are one flat glyph on a clean
vertical gradient: no drop shadows, no bevels, generous margins, and overlapping
shapes separated by knocked-out hairline gaps rather than by shading.

Mark: a photographic print sliding into a sleeve — most of the print is already
inside, a corner still shows. The print carries a tiny knocked-out sun so it reads
as a photograph rather than as a card. "A photo being put away" is the whole
product in one shape.

Palette: a midnight slate-blue family — dusk, not brand purple. The dark variant
deepens the same hues rather than swapping them.

    python Scripts/make_app_icon.py
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

SIZE = 1024
SS = 3
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Hidden", "Resources", "Assets.xcassets", "AppIcon.appiconset")

# three-stop vertical gradients, light -> deep, in a midnight slate family
BACKDROPS = {
    "light": [(0x8F, 0xA6, 0xC9), (0x46, 0x62, 0x92), (0x1B, 0x2E, 0x52)],
    "dark":  [(0x5E, 0x74, 0x99), (0x2C, 0x41, 0x68), (0x0D, 0x17, 0x2E)],
}

PRINT_W, PRINT_H, PRINT_R = 0.44, 0.44, 0.10   # the photograph, relative to canvas
TILT = 10                                       # degrees, leaning as it slides in
GAP = 0.030                                     # knocked-out hairline around the sleeve lip
SLEEVE_TOP = 0.565                              # sleeve's top edge, relative to canvas height


def gradient(size, stops):
    """Vertical multi-stop gradient, built as a 1xN strip then stretched."""
    n = 512
    strip = Image.new("RGB", (1, n))
    px = strip.load()
    seg = n / (len(stops) - 1)
    for i in range(n):
        k = min(int(i / seg), len(stops) - 2)
        t = (i - k * seg) / seg
        a, b = stops[k], stops[k + 1]
        px[0, i] = (round(a[0] + (b[0] - a[0]) * t),
                    round(a[1] + (b[1] - a[1]) * t),
                    round(a[2] + (b[2] - a[2]) * t))
    return strip.resize((size, size), Image.BILINEAR)


def build_mark(s):
    """White glyph as an alpha mask, auto-fitted and optically centred on s x s."""
    mark = Image.new("L", (s, s), 0)
    pw, ph, pr = s * PRINT_W, s * PRINT_H, s * PRINT_R

    # --- The print, tilted, its lower part destined for the sleeve. ---
    print_layer = Image.new("L", (s, s), 0)
    shape = Image.new("L", (round(pw), round(ph)), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=pr, fill=255)

    # The photograph inside the print: a hill and a sun, knocked back to the gradient.
    scene = Image.new("L", (round(pw), round(ph)), 0)
    sd = ImageDraw.Draw(scene)
    hx, hy = pw * 0.38, ph * 1.06
    rx, ry = pw * 0.78, ph * 0.42
    sd.ellipse([hx - rx, hy - ry, hx + rx, hy + ry], fill=255)
    sr = pw * 0.115
    sx, sy = pw * 0.70, ph * 0.26
    sd.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=255)

    inset = pw * 0.085
    clip = Image.new("L", (round(pw), round(ph)), 0)
    ImageDraw.Draw(clip).rounded_rectangle(
        [inset, inset, pw - inset, ph - inset], radius=pr - inset * 0.75, fill=255)
    shape.paste(0, (0, 0), Image.composite(scene, Image.new("L", shape.size, 0), clip))

    pcx, pcy = s * 0.50, s * 0.40
    print_layer.paste(shape, (round(pcx - pw / 2), round(pcy - ph / 2)))
    print_layer = print_layer.rotate(TILT, resample=Image.BICUBIC, center=(pcx, pcy))
    mark.paste(255, (0, 0), print_layer)

    # --- The sleeve: a wide rounded pocket across the lower canvas. ---
    # Knock a gap-inflated sleeve out of the print first so a hairline of gradient
    # separates the two, the way Apple separates overlapping shapes.
    gap = s * GAP
    sw, sh = s * 0.62, s * 0.34
    sx0, sy0 = s * 0.50 - sw / 2, s * SLEEVE_TOP
    sr_ = s * 0.075

    d = ImageDraw.Draw(mark)
    d.rounded_rectangle([sx0 - gap, sy0 - gap, sx0 + sw + gap, sy0 + sh + gap],
                        radius=sr_ + gap, fill=0)
    d.rounded_rectangle([sx0, sy0, sx0 + sw, sy0 + sh], radius=sr_, fill=255)

    # A slot line on the sleeve, knocked out, so the pocket reads as an opening.
    slot_w, slot_h = sw * 0.46, s * 0.018
    slot_y = sy0 + sh * 0.30
    d.rounded_rectangle([s * 0.50 - slot_w / 2, slot_y,
                         s * 0.50 + slot_w / 2, slot_y + slot_h],
                        radius=slot_h / 2, fill=0)

    cropped = mark.crop(mark.getbbox())
    scale = min(s * 0.66 / cropped.width, s * 0.66 / cropped.height)
    cropped = cropped.resize((round(cropped.width * scale), round(cropped.height * scale)),
                             Image.LANCZOS)
    fitted = Image.new("L", (s, s), 0)
    fitted.paste(cropped, ((s - cropped.width) // 2, (s - cropped.height) // 2))
    return fitted


def render(variant):
    s = SIZE * SS
    stops = BACKDROPS["dark" if variant == "dark" else "light"]
    base = gradient(s, stops).convert("RGB")
    base.paste((255, 255, 255), (0, 0), build_mark(s))

    icon = base.resize((SIZE, SIZE), Image.LANCZOS)
    if variant == "tinted":
        g = icon.convert("L")
        icon = Image.merge("RGB", (g, g, g))
    return icon


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return m


def contact_sheet():
    light = Image.open(os.path.join(OUT_DIR, "AppIcon-Light.png"))
    dark = Image.open(os.path.join(OUT_DIR, "AppIcon-Dark.png"))
    sizes = (180, 120, 80, 60, 40)
    width = 32 + sum(px + 28 for px in sizes)
    sheet = Image.new("RGB", (width, 300), (0xEF, 0xEF, 0xF2))
    ImageDraw.Draw(sheet).rectangle([0, 150, width, 300], fill=(0x1C, 0x1C, 0x1E))
    for row, img in ((0, light), (1, dark)):
        x = 32
        for px in sizes:
            sheet.paste(img.resize((px, px), Image.LANCZOS),
                        (x, row * 150 + (150 - px) // 2),
                        rounded_mask(px, px, int(px * 0.2237)))
            x += px + 28
    path = os.path.join(ROOT, "docs", "icon-preview.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    print(f"wrote {path}")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for variant, name in (("light", "AppIcon-Light.png"),
                          ("dark", "AppIcon-Dark.png"),
                          ("tinted", "AppIcon-Tinted.png")):
        path = os.path.join(OUT_DIR, name)
        render(variant).save(path, "PNG", optimize=True)
        print(f"wrote {path}")
    contact_sheet()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the Pocket platform image (521x165) and core icon (36x36).

Pocket images are raw 16-bit little-endian pixels, stored rotated 90 degrees
counter-clockwise. This follows the encoding used by Analogue's core
template: low byte 0xFF for background, 0x00 for the drawing, high byte 0.

Usage: make_images.py <platform.bin> <icon.bin> [preview_dir]
"""
import math
import sys
from PIL import Image, ImageDraw

INK, BG = 0, 255

# Stroke font for the few letters needed, on a 4 x 6 grid (vector-game style)
GLYPHS = {
    "T": [((0, 0), (4, 0)), ((2, 0), (2, 6))],
    "E": [((4, 0), (0, 0)), ((0, 0), (0, 6)), ((0, 6), (4, 6)), ((0, 3), (3, 3))],
    "M": [((0, 6), (0, 0)), ((0, 0), (2, 3)), ((2, 3), (4, 0)), ((4, 0), (4, 6))],
    "P": [((0, 6), (0, 0)), ((0, 0), (4, 0)), ((4, 0), (4, 3)), ((4, 3), (0, 3))],
    "S": [((4, 0), (0, 0)), ((0, 0), (0, 3)), ((0, 3), (4, 3)), ((4, 3), (4, 6)), ((4, 6), (0, 6))],
}


def draw_text(d, text, x, y, scale, width):
    for ch in text:
        for (a, b) in GLYPHS[ch]:
            d.line([(x + a[0] * scale, y + a[1] * scale), (x + b[0] * scale, y + b[1] * scale)],
                   fill=INK, width=width)
        x += 6 * scale


def draw_tube(d, cx, cy, r_out, r_in, sides, width, squash=1.0):
    outer, inner = [], []
    for i in range(sides):
        a = 2 * math.pi * i / sides - math.pi / 2
        outer.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a) * squash))
        inner.append((cx + r_in * math.cos(a), cy - r_in * 0.15 + r_in * math.sin(a) * squash))
    d.line(outer + [outer[0]], fill=INK, width=width)
    d.line(inner + [inner[0]], fill=INK, width=width)
    for o, n in zip(outer, inner):
        d.line([o, n], fill=INK, width=max(1, width - 1))


def to_bin(img):
    rot = img.rotate(90, expand=True)          # stored rotated counter-clockwise
    out = bytearray()
    for p in rot.tobytes():
        out += bytes((p, 0))
    return bytes(out)


def main():
    plat = Image.new("L", (521, 165), BG)
    d = ImageDraw.Draw(plat)
    draw_tube(d, 82, 84, 66, 20, 16, 3)
    draw_text(d, "TEMPEST", 172, 58, 8, 5)
    icon = Image.new("L", (36, 36), BG)
    draw_tube(ImageDraw.Draw(icon), 18, 18, 16, 5, 8, 2)

    open(sys.argv[1], "wb").write(to_bin(plat))
    open(sys.argv[2], "wb").write(to_bin(icon))
    if len(sys.argv) > 3:
        plat.save(f"{sys.argv[3]}/platform_preview.png")
        icon.resize((144, 144), Image.NEAREST).save(f"{sys.argv[3]}/icon_preview.png")


if __name__ == "__main__":
    main()

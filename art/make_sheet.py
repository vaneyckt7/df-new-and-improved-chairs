#!/usr/bin/env python3
"""Turn the chair tint template (art/sets/slat_template.png) into the sprite sheet that replaces
the game's own chair pictures in worlds generated with this mod: graphics/images/improved_chairs.png.

The sheet has the game's layout for a chair: rows wood, stone, metal, glass; columns 0-6 the
seven style variants (here all the same chair, facing south); column 7 the leg variants, which
the game draws over the seat (here empty: the legs are part of the chair).

The template marks a pixel's tone (1..255) in pure red or pure blue.  The script paints red on
the material's own ramp of its palette (the first ramp for wood, the second for the rest) and
blue on the first ramp.  The game recolours a sprite by swapping each pixel that exactly matches
a shade of its default palette for the same shade of the material's palette, so here the tones
are written out as default-palette shades on those same ramps.  The template's tones sit on the
shades to within a twentieth of a step (the script paints that remainder, the game cannot, which
is a difference of at most 2 in 255 per channel); a tone further off is refused.  Two things keep the result the same as what the script paints for a built
chair:
  - the outline is the darkest shade, which both ramps share; it is moved one step in blue so
    that the game does not recolour it (the script does not either)
  - the half-transparent shadow is stored darkened by its own opacity, as the script draws it

Usage: make_sheet.py            write graphics/images/improved_chairs.png
       make_sheet.py --check    fail if that file does not match the template
"""
import pathlib
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / "sets" / "slat_template.png"
OUT = HERE.parent / "graphics" / "images" / "improved_chairs.png"
TILE, ROWS, SOUTH, VARIANTS, COLUMNS = 32, 4, 2, 7, 8

# The game's default palette (df.global.gps.default_palette), shades 0..8 of its first two ramps.
FIRST = [(47, 48, 56), (70, 62, 61), (78, 71, 67), (86, 79, 73), (96, 88, 82), (116, 106, 99),
        (148, 135, 126), (179, 165, 158), (215, 211, 210)]
SECOND = [(47, 48, 56), (60, 62, 70), (73, 76, 84), (90, 94, 101), (107, 112, 118), (138, 144, 145),
        (165, 166, 165), (199, 196, 180), (255, 255, 255)]
OUTLINE = (47, 48, 56)
OUTLINE_KEPT = (47, 48, 57)


def shade(ramp, tone):
    at = (tone - 1) * 6 / 254                           # the template's tones sit on shades 2..8
    if abs(at - round(at)) > 0.05:
        sys.exit(f"{SRC}: tone {tone} is between two shades; the game cannot recolour it")
    return ramp[2 + round(at)]


def render():
    src = Image.open(SRC).convert("RGBA")
    out = Image.new("RGBA", (COLUMNS * TILE, ROWS * TILE), (0, 0, 0, 0))
    for row in range(ROWS):
        tile = src.crop((SOUTH * TILE, row * TILE, (SOUTH + 1) * TILE, (row + 1) * TILE))
        own = FIRST if row == 0 else SECOND
        px = tile.load()
        for y in range(TILE):
            for x in range(TILE):
                r, g, b, a = px[x, y]
                if a == 255 and g == 0 and b == 0 and r > 0:
                    r, g, b = shade(own, r)
                elif a == 255 and r == 0 and g == 0 and b > 0:
                    r, g, b = shade(FIRST, b)
                if (r, g, b) == OUTLINE and a > 0:
                    r, g, b = OUTLINE_KEPT
                    if a < 255:
                        r, g, b = OUTLINE[0] * a // 255, OUTLINE[1] * a // 255, OUTLINE[2] * a // 255
                px[x, y] = (r, g, b, a)
        for col in range(VARIANTS):
            out.paste(tile, (col * TILE, row * TILE))
    return out


if __name__ == "__main__":
    sheet = render()
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or Image.open(OUT).convert("RGBA").tobytes() != sheet.tobytes():
            sys.exit(f"{OUT} does not match {SRC}: run art/make_sheet.py")
        print(f"{OUT.name} matches the template")
    else:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(OUT)
        print(f"wrote {OUT}")

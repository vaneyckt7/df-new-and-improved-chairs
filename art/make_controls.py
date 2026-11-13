"""Draws art/controls.png, the sheet controls: ten 8x12 interface cells in a row.

  1 turn | 2-5 left, up, down, right (lit) | 6-9 the same, dim | 10 reset x

The turn button is an 8x8 ring with an arrowhead on rows 2-9 (the font's capitals). The triangles
and the x are 6x6 on rows 3-8, columns 1-6, so side by side they keep a 2 px gap and one centre line.
Left/right are up/down turned a quarter, so all four are the same size.
"""
import os
from PIL import Image

BG, LIT, DIM, RED = (28, 28, 28), (19, 253, 101), (85, 85, 85), (255, 85, 85)
W, H = 8, 12
UP = ["..XX..", "..XX..", ".XXXX.", ".XXXX.", "XXXXXX", "XXXXXX"]
LEFT = ["".join(UP[x][5 - y] for x in range(6)) for y in range(6)]
TRIS = [LEFT, UP, UP[::-1], [r[::-1] for r in LEFT]]
TURN = ["..XXXX..", ".XX..XX.", "XX.XXXXX", "XX..XXX.", "XX...X..", "XX......", ".XX...XX", "..XXXXX."]
RESET = ["X....X", "XX..XX", ".XXXX.", ".XXXX.", "XX..XX", "X....X"]

def cell(pattern, colour):
    t = Image.new('RGB', (W, H), BG)
    x0, y0 = (W - len(pattern[0])) // 2, (H - len(pattern)) // 2
    for y, row in enumerate(pattern):
        for x, c in enumerate(row):
            if c == 'X': t.putpixel((x0 + x, y0 + y), colour)
    return t

cells = [cell(TURN, LIT)] + [cell(t, LIT) for t in TRIS] + [cell(t, DIM) for t in TRIS] + [cell(RESET, RED)]
sheet = Image.new('RGB', (W * len(cells), H), BG)
for i, c in enumerate(cells): sheet.paste(c, (W * i, 0))
sheet.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'controls.png'))

"""Render a small test map per material (unlit albedo + normal side by side) for review."""
from __future__ import annotations

import sys

import numpy as np
from PIL import Image

from build_tiles import E, MACRO, N, NE, NW, S, SE, SW, T, W, atlas_cell, canonical
from pixel import ART, ROOT

TEST_MAP = [
    "....................",
    "....................",
    "......####..........",
    ".....######.....##..",
    "....###..###...###..",
    "..#####..#####.###..",
    "####################",
    "########....########",
    "####################",
]


def mask_at(grid, x, y):
    h, w = len(grid), len(grid[0])

    def solid(xx, yy):
        xx = min(max(xx, 0), w - 1)
        yy = min(max(yy, 0), h - 1)
        return grid[yy][xx] == "#"

    m = 0
    for bit, (dx, dy) in ((N, (0, -1)), (NE, (1, -1)), (E, (1, 0)), (SE, (1, 1)),
                          (S, (0, 1)), (SW, (-1, 1)), (W, (-1, 0)), (NW, (-1, -1))):
        if solid(x + dx, y + dy):
            m |= bit
    return canonical(m)


def render(material: str, scale: int = 3) -> Image.Image:
    alb = np.asarray(Image.open(ART / "tiles" / f"{material}.png").convert("RGBA"))
    nrm = np.asarray(Image.open(ART / "tiles" / f"{material}_n.png").convert("RGB"))
    h, w = len(TEST_MAP), len(TEST_MAP[0])
    out_a = np.zeros((h * T, w * T, 4), np.uint8)
    out_a[..., :3] = (20, 22, 40)
    out_a[..., 3] = 255
    out_n = np.zeros((h * T, w * T, 3), np.uint8)
    for y in range(h):
        for x in range(w):
            if TEST_MAP[y][x] != "#":
                continue
            m = mask_at(TEST_MAP, x, y)
            v = (x % MACRO) + MACRO * (y % MACRO)
            cx, cy = atlas_cell(m, v)
            sx, sy = cx * T, cy * T
            out_a[y * T:(y + 1) * T, x * T:(x + 1) * T] = alb[sy:sy + T, sx:sx + T]
            out_n[y * T:(y + 1) * T, x * T:(x + 1) * T] = nrm[sy:sy + T, sx:sx + T]
    both = np.concatenate([out_a[..., :3], out_n], axis=1)
    img = Image.fromarray(both, "RGB")
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


if __name__ == "__main__":
    out = ROOT / "out"
    out.mkdir(exist_ok=True)
    for mat in sys.argv[1:]:
        render(mat).save(out / f"tiles_{mat}.png")
        print(out / f"tiles_{mat}.png")

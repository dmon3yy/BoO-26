"""Build the pixel font (content/fonts/*.pxf) into a BMFont that Godot imports.

Output: game/art/fonts/<name>.png + <name>.fnt (text BMFont format).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "content" / "fonts"
OUT = ROOT / "game" / "art" / "fonts"
CELL_H = 8
SPACE_ADVANCE = 3


def parse(text: str) -> dict[str, list[str]]:
    glyphs: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        if line.startswith("@"):
            current = line[1:]
            glyphs[current] = []
        elif current is not None and line and not line.startswith(";"):
            glyphs[current].append(line)
    return glyphs


def build(name: str) -> None:
    glyphs = parse((SRC / f"{name}.pxf").read_text())
    cols = 16
    cw = max(len(r[0]) for r in glyphs.values()) + 1
    rows = (len(glyphs) + cols - 1) // cols
    W, H = cols * cw, rows * (CELL_H + 1)
    img = np.zeros((H, W, 4), np.uint8)
    chars = []
    for i, (ch, grid) in enumerate(glyphs.items()):
        gx, gy = (i % cols) * cw, (i // cols) * (CELL_H + 1)
        w = len(grid[0])
        for y, row in enumerate(grid[:CELL_H]):
            for x, c in enumerate(row):
                if c == "#":
                    img[gy + y, gx + x] = (255, 255, 255, 255)
        chars.append(f"char id={ord(ch)} x={gx} y={gy} width={w} height={CELL_H} xoffset=0 yoffset=0 "
                     f"xadvance={w + 1} page=0 chnl=15")
    chars.append(f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance={SPACE_ADVANCE} page=0 chnl=15")
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img, "RGBA").save(OUT / f"{name}.png")
    fnt = [
        f'info face="{name}" size={CELL_H} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        f'padding=0,0,0,0 spacing=1,1',
        f"common lineHeight={CELL_H + 3} base=7 scaleW={W} scaleH={H} pages=1 packed=0",
        f'page id=0 file="{name}.png"',
        f"chars count={len(chars)}",
        *chars,
    ]
    (OUT / f"{name}.fnt").write_text("\n".join(fnt) + "\n")
    print(f"font: {name} ({len(glyphs)} glyphs)")


if __name__ == "__main__":
    for p in sorted(SRC.glob("*.pxf")):
        build(p.stem)

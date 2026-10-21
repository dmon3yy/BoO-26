"""Procedural props: albedo + normal (+ emission) per prop.

Props are drawn with a tiny "canvas" helper that paints material ids and a
height field; colours come from palette ramps chosen by shading tone, so every
prop shares the tiles' pixel-art look and reacts to the same lights.
Placement and lights live in content/props.json.
"""
from __future__ import annotations

import numpy as np

from pixel import ART, load_palette, normals_from_height, outline, save_normal, save_rgba, value_noise


class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.col = np.zeros((h, w, 4), np.float32)
        self.height = np.zeros((h, w), np.float32)
        self.em = np.zeros((h, w, 4), np.float32)
        self.ys, self.xs = np.mgrid[0:h, 0:w]

    def paint(self, mask, color, height=None, emit=None):
        self.col[mask, :3] = color[mask] if np.ndim(color) == 3 else color
        self.col[mask, 3] = 1
        if height is not None:
            self.height[mask] = height[mask] if np.ndim(height) == 2 else height
        if emit is not None:
            self.em[mask, :3] = emit[mask] if np.ndim(emit) == 3 else emit
            self.em[mask, 3] = 1

    def rect(self, x0, y0, x1, y1):
        return (self.xs >= x0) & (self.xs <= x1) & (self.ys >= y0) & (self.ys <= y1)

    def ellipse(self, cx, cy, rx, ry):
        return ((self.xs - cx) / rx) ** 2 + ((self.ys - cy) / ry) ** 2 <= 1.0

    def save(self, name: str, outlined: bool = True, emissive: bool = False):
        out = ART / "props"
        col = outline(self.col, (0.05, 0.04, 0.07)) if outlined else self.col
        alpha = col[..., 3]
        n = normals_from_height(self.height, alpha, strength=1.5)
        save_rgba(out / f"{name}.png", col)
        save_normal(out / f"{name}_n.png", n, alpha)
        if emissive:
            save_rgba(out / f"{name}_e.png", self.em)
        print(f"prop: {name}")


def ramp_pick(p, names, t):
    table = np.stack([p[n] for n in names])
    idx = np.clip((np.asarray(t) * len(names)).astype(int), 0, len(names) - 1)
    return table[idx]


def cylinder_tone(xs, cx, r):
    """Light from the upper left: bright left of centre, dark right edge."""
    u = np.clip((xs - cx) / max(r, 1), -1, 1)
    return np.clip(0.75 - 0.55 * (u + 0.35) ** 2 + 0.1 * (u < -0.6), 0, 0.999)


def cylinder_height(xs, cx, r):
    u = np.clip((xs - cx) / max(r, 1), -1, 1)
    return np.sqrt(np.clip(1 - u * u, 0, 1))


def column(broken: bool):
    p = load_palette("arcadia_winter")
    W, H = 22, (46 if broken else 78)
    c = Canvas(W, H)
    cx = W / 2 - 0.5
    marble = ["marble0", "marble1", "marble2", "marble3", "marble4"]
    shaft_top = 4 if broken else 9
    r_shaft = 6.5
    shaft = c.rect(cx - r_shaft, shaft_top, cx + r_shaft, H - 1)
    flute = ((c.xs - int(cx)) % 3 == 0)
    tone = cylinder_tone(c.xs, cx, r_shaft) - np.where(flute, 0.18, 0)
    c.paint(shaft, ramp_pick(p, marble, tone), cylinder_height(c.xs, cx, r_shaft) * 0.8 - flute * 0.15)
    if broken:
        jag = (np.abs(np.sin(c.xs * 1.7)) * 4 + 1).astype(int)
        cut = shaft & (c.ys < shaft_top + jag)
        c.col[cut] = 0
        c.height[cut] = 0
        top = shaft & (c.ys >= shaft_top + jag) & (c.ys < shaft_top + jag + 2)
        c.paint(top, ramp_pick(p, ["snow2", "snow3"], np.full(c.xs.shape, 0.6)), 1.0)
    else:
        abacus = c.rect(0, 2, W - 1, 4)
        echinus = c.rect(2, 5, W - 3, 8) & ~(c.rect(2, 7, 3, 8) | c.rect(W - 4, 7, W - 3, 8))
        c.paint(echinus, ramp_pick(p, marble, cylinder_tone(c.xs, cx, 9)), 0.9)
        c.paint(abacus, ramp_pick(p, marble, np.full(c.xs.shape, 0.75)), 1.0)
        snow = c.rect(0, 0, W - 1, 1) & ~c.rect(0, 0, 0, 0) & ~c.rect(W - 1, 0, W - 1, 0)
        c.paint(snow, ramp_pick(p, ["snow2", "snow3"], (c.xs % 5 > 1) * 0.6 + 0.3), 1.1)
    c.save("broken_column" if broken else "column")


def olive_tree():
    p = load_palette("arcadia_winter")
    W, H = 60, 66
    c = Canvas(W, H)
    rng = np.random.default_rng(12)
    # Gnarled trunk: two twisting strands that wrap around each other.
    for strand, phase in ((0, 0.0), (1, 2.6)):
        for y in range(H - 1, 24, -1):
            t = (H - y) / (H - 24)
            x = 29 + np.sin(t * 5 + phase) * (2.5 + strand) + t * 4
            r = 3.2 - t * 1.4
            m = (np.abs(c.xs - x) <= r) & (c.ys == y)
            tone = 0.35 + 0.25 * np.sin(t * 9 + phase + c.xs * 0.6)
            c.paint(m, ramp_pick(p, ["bark0", "bark1", "bark2"], np.clip(tone, 0, 0.999)), 0.7)
    # Branches
    for (x0, y0, x1, y1) in ((32, 30, 14, 20), (33, 28, 50, 18), (31, 26, 30, 10), (34, 34, 46, 30)):
        for t in np.linspace(0, 1, 40):
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t + np.sin(t * 6) * 1.5
            m = (np.abs(c.xs - x) <= 1.2 - 0.6 * t) & (np.abs(c.ys - y) <= 1.0)
            c.paint(m, p["bark1"], 0.6)
    # Leaf clumps (olives stay green in winter), snow on their crowns.
    leaf_noise = value_noise(H, W, 2, 33)
    for (bx, by, rx, ry) in ((14, 18, 10, 7), (24, 11, 11, 7), (36, 9, 10, 6), (49, 16, 10, 7),
                             (30, 20, 12, 6), (44, 27, 8, 5), (18, 26, 7, 4)):
        blob = c.ellipse(bx, by, rx, ry) & (leaf_noise > 0.28)
        d = 1 - (((c.xs - bx) / rx) ** 2 + ((c.ys - by) / ry) ** 2)
        tone = np.clip(0.3 + d * 0.5 + (leaf_noise - 0.5) * 0.5 - (c.ys - by) / ry * 0.2, 0, 0.999)
        c.paint(blob, ramp_pick(p, ["leaf0", "leaf1", "leaf2"], tone), 0.4 + d * 0.6)
        crown = blob & (c.ys < by - ry * 0.35) & (leaf_noise > 0.4)
        c.paint(crown, ramp_pick(p, ["snow1", "snow2", "snow3"], np.clip(d, 0, 0.999)), 0.9 + d * 0.3)
    c.save("olive_tree")


def brazier(name: str = "torch"):
    """Bronze bowl on a tripod; the flame is a separate animated sprite."""
    p = load_palette("arcadia_winter")
    pe = load_palette("erebos")
    W, H = 16, 26
    c = Canvas(W, H)
    bronze = ["brass0", "brass1", "brass2", "brass3"]
    legs = (np.abs(c.xs - 7.5 - (c.ys - 10) * 0.18) < 0.8) | (np.abs(c.xs - 7.5 + (c.ys - 10) * 0.18) < 0.8)
    legs &= (c.ys >= 9)
    c.paint(legs, pe["brass1"], 0.5)
    bowl = c.ellipse(7.5, 6, 7, 4) & (c.ys >= 5)
    c.paint(bowl, ramp_pick(pe, bronze, cylinder_tone(c.xs, 7.5, 7)), cylinder_height(c.xs, 7.5, 7))
    coals = c.rect(2, 4, 13, 5)
    c.paint(coals, pe["molten1"], 0.6, emit=pe["molten2"])
    c.save(name, emissive=True)


def hearth():
    """Hearth of Hestia: a round stone altar holding a never-dying fire (save point)."""
    p = load_palette("arcadia_winter")
    pe = load_palette("erebos")
    W, H = 30, 20
    c = Canvas(W, H)
    base = c.rect(1, 12, W - 2, H - 1)
    c.paint(base, ramp_pick(p, ["marble0", "marble1", "marble2", "marble3"], cylinder_tone(c.xs, 14.5, 14)),
            cylinder_height(c.xs, 14.5, 14) * 0.8)
    band = c.rect(1, 14, W - 2, 15)
    c.paint(band, p["fire0"], 0.6)
    rim = c.ellipse(14.5, 11, 13, 3)
    c.paint(rim, ramp_pick(p, ["marble2", "marble3", "marble4"], cylinder_tone(c.xs, 14.5, 13)), 1.0)
    embers = c.ellipse(14.5, 11, 10, 1.6)
    glow = value_noise(H, W, 2, 5)
    c.paint(embers, pe["molten1"], 0.7, emit=ramp_pick(pe, ["molten1", "molten2", "molten3"], glow))
    c.save("hearth", emissive=True)


def lantern():
    pe = load_palette("erebos")
    W, H = 10, 44
    c = Canvas(W, H)
    chain = (c.xs == 5) & (c.ys < 30) & ((c.ys % 4) != 3)
    links = ((c.xs == 4) | (c.xs == 6)) & (c.ys < 30) & ((c.ys % 4) == 1)
    c.paint(chain | links, pe["iron3"], 0.5)
    cap = c.rect(2, 30, 7, 31)
    c.paint(cap, pe["brass2"], 0.8)
    glass = c.rect(2, 32, 7, 39)
    cage = glass & ((c.xs == 2) | (c.xs == 7) | (c.ys == 35))
    c.paint(glass & ~cage, pe["molten3"], 0.6, emit=pe["molten3"])
    c.paint(cage, pe["brass1"], 0.9)
    foot = c.rect(3, 40, 6, 41)
    c.paint(foot, pe["brass1"], 0.7)
    c.save("lantern", emissive=True)


def furnace():
    pe = load_palette("erebos")
    W, H = 52, 56
    c = Canvas(W, H)
    # Riveted iron body with a brick-lined arched mouth.
    body = c.rect(2, 10, W - 3, H - 1)
    tone = 0.5 + 0.12 * (value_noise(H, W, 4, 8) - 0.5) - np.where(c.xs % 12 == 0, 0.2, 0)
    c.paint(body, ramp_pick(pe, ["iron1", "iron2", "iron3", "iron4"], np.clip(tone, 0, 0.999)), 0.7)
    rivets = body & (c.xs % 6 == 3) & ((c.ys == 13) | (c.ys == H - 4))
    c.paint(rivets, pe["iron5"], 0.95)
    stack = c.rect(18, 0, 31, 10)
    c.paint(stack, ramp_pick(pe, ["iron1", "iron2", "iron3"], cylinder_tone(c.xs, 24.5, 7)), cylinder_height(c.xs, 24.5, 7))
    lip = c.rect(16, 0, 33, 1)
    c.paint(lip, pe["brass1"], 0.9)
    arch = c.ellipse(25.5, 38, 15, 15) & (c.ys >= 24)
    bricks = arch & ~c.ellipse(25.5, 38, 12, 12)
    brick_tone = 0.3 + 0.4 * (((c.xs // 3 + c.ys // 2) % 2) == 0)
    c.paint(bricks, ramp_pick(pe, ["rust0", "rust1", "rust2"], brick_tone), 0.8)
    mouth = c.ellipse(25.5, 38, 12, 12) & (c.ys >= 27)
    heat = np.clip((c.ys - 27) / 26 + value_noise(H, W, 3, 4) * 0.4, 0, 0.999)
    hot = ramp_pick(pe, ["molten1", "molten2", "molten3", "molten4"], heat)
    c.paint(mouth, hot, 0.2, emit=hot)
    c.save("furnace", emissive=True)


def olive():
    p = load_palette("arcadia_winter")
    W, H = 7, 9
    c = Canvas(W, H)
    stem = c.rect(3, 0, 3, 1)
    c.paint(stem, p["bark2"], 0.4)
    fruit = c.ellipse(3, 5, 2.6, 3.2)
    c.paint(fruit, ramp_pick(p, ["leaf0", "leaf1", "leaf2"], cylinder_tone(c.xs, 3, 2.6)), cylinder_height(c.xs, 3, 2.6))
    c.paint(c.rect(2, 3, 2, 3), p["snow2"], 1.0)
    c.save("olive")


def song_seal():
    p = load_palette("arcadia_winter")
    W, H = 30, 48
    c = Canvas(W, H)
    slab = c.rect(1, 0, W - 2, H - 1)
    tone = 0.45 + 0.1 * (value_noise(H, W, 3, 21) - 0.5) + np.where(c.xs < 4, 0.12, 0)
    c.paint(slab, ramp_pick(p, ["marble0", "marble1", "marble2", "marble3"], np.clip(tone, 0, 0.999)), 0.7)
    # Carved lyre glyph that glows when a song is near.
    arms = (np.abs(c.xs - 9 - (c.ys - 14) * -0.1) < 1.0) | (np.abs(c.xs - 20 - (c.ys - 14) * 0.1) < 1.0)
    arms &= (c.ys >= 12) & (c.ys <= 32)
    yoke = c.rect(8, 12, 21, 13)
    base = c.ellipse(14.5, 32, 6, 3)
    strings = (np.isin(c.xs, (12, 14, 16, 18))) & (c.ys > 13) & (c.ys < 30)
    glyph = arms | yoke | base | strings
    blue = np.array([0.55, 0.85, 1.0], np.float32)
    c.paint(glyph, blue * 0.7, 0.4, emit=blue)
    c.save("song_seal", emissive=True)


def main():
    column(False)
    column(True)
    olive_tree()
    brazier()
    hearth()
    lantern()
    furnace()
    olive()
    song_seal()


if __name__ == "__main__":
    main()

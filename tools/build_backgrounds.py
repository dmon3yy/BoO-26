"""Parallax background layers, drawn procedurally.

Each layer tiles horizontally. Layers are listed per theme in content/themes.json
with their scroll factor; anything bright that should *glow* (moon, lit windows)
goes into a separate `_e` layer that the game draws unshaded.
"""
from __future__ import annotations

import numpy as np

from pixel import ART, bayer4, fbm, load_palette, save_rgba, value_noise

VW, VH = 480, 270


def dithered_gradient(h: int, w: int, colors: list[np.ndarray], stops: list[float]) -> np.ndarray:
    """Vertical gradient through palette colours with ordered dithering at each seam."""
    t = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    b = np.tile(bayer4(), (h // 4 + 1, w // 4 + 1))[:h, :w]
    img = np.zeros((h, w, 4), np.float32)
    img[..., 3] = 1
    idx = np.zeros((h, w), int)
    for i, s in enumerate(stops):
        idx = np.where(t + (b - 0.5) * 0.06 > s, i + 1, idx)
    table = np.stack(colors)
    img[..., :3] = table[np.clip(idx, 0, len(colors) - 1)]
    return img


def ridge(w: int, seed: int, base: float, amp: float, cells=(64, 32, 16, 8)) -> np.ndarray:
    """1D tileable ridge line (y position per column)."""
    line = np.zeros(w, np.float32)
    amp_i = 1.0
    total = 0.0
    for i, c in enumerate(cells):
        line += amp_i * value_noise(c, w, c, seed + i * 13, period=(c, w))[0]
        total += amp_i
        amp_i *= 0.55
    line /= total
    return base - (line - 0.5) * 2 * amp


def mountains(w: int, h: int, seed: int, base: float, amp: float, body: np.ndarray, snow: np.ndarray,
              rim: np.ndarray | None = None, snowline: float = 0.35) -> np.ndarray:
    top = ridge(w, seed, base, amp)
    ys = np.arange(h)[:, None]
    img = np.zeros((h, w, 4), np.float32)
    solid = ys >= top[None, :]
    img[solid, :3] = body
    img[solid, 3] = 1
    # Snow: near the ridge top, more of it on high peaks; streaky downhill.
    peak = (base + amp - top) / (2 * amp)                     # 0 low .. 1 high
    streak = value_noise(h, w, 3, seed + 5, period=(h, w))
    depth = (peak[None, :] ** 1.5 * 40 * snowline) * (0.5 + streak)
    snowy = solid & ((ys - top[None, :]) < depth)
    img[snowy, :3] = snow
    if rim is not None:
        edge = solid & (ys - top[None, :] < 1)
        img[edge, :3] = rim
    return img


def olive_silhouette(img: np.ndarray, x0: int, ground: int, scale: float, color: np.ndarray, seed: int) -> None:
    rng = np.random.default_rng(seed)
    h, w = img.shape[:2]
    trunk_h = int(18 * scale)
    # Twisting trunk
    x = float(x0)
    for y in range(ground, ground - trunk_h, -1):
        x += rng.uniform(-0.6, 0.6)
        tw = max(1, int(3 * scale * (0.6 + 0.4 * (y - ground + trunk_h) / trunk_h)))
        for dx in range(-tw, tw + 1):
            img[y % h, int(x + dx) % w, :3] = color
            img[y % h, int(x + dx) % w, 3] = 1
    # Canopy blobs
    cy = ground - trunk_h
    for _ in range(9):
        bx = x + rng.uniform(-14, 14) * scale
        by = cy + rng.uniform(-8, 3) * scale
        r = rng.uniform(4, 8) * scale
        ys, xs = np.ogrid[0:h, 0:w]
        dxw = np.minimum(np.abs(xs - bx), w - np.abs(xs - bx))
        blob = (dxw ** 2 + ((ys - by) * 1.3) ** 2) < r * r
        img[blob, :3] = color
        img[blob, 3] = 1


def column_silhouette(img: np.ndarray, x0: int, ground: int, height: int, color: np.ndarray, broken: bool) -> None:
    w = img.shape[1]
    for y in range(ground - height, ground):
        for dx in range(-3, 4):
            img[y, (x0 + dx) % w, :3] = color
            img[y, (x0 + dx) % w, 3] = 1
    if not broken:
        for dx in range(-5, 6):
            for y in range(ground - height - 3, ground - height):
                img[y, (x0 + dx) % w, :3] = color
                img[y, (x0 + dx) % w, 3] = 1
    else:
        for dx in range(-3, 4):
            jag = abs((dx * 7) % 5)
            for y in range(ground - height, ground - height + jag):
                img[y, (x0 + dx) % w, 3] = 0


def arcadia() -> None:
    p = load_palette("arcadia_winter")
    out = ART / "backgrounds"
    sky = dithered_gradient(VH, VW, [p["sky0"], p["sky1"], p["sky2"], p["sky3"], p["sky4"], p["horizon"]],
                            [0.18, 0.36, 0.55, 0.72, 0.86])
    rng = np.random.default_rng(7)
    stars = np.zeros((VH, VW, 4), np.float32)
    for _ in range(140):
        sx, sy = rng.integers(0, VW), rng.integers(0, int(VH * 0.62))
        b = rng.uniform(0.35, 1.0)
        stars[sy, sx, :3] = p["star"]
        stars[sy, sx, 3] = b
        if b > 0.92 and 1 <= sx < VW - 1 and sy >= 1:
            for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                stars[sy + oy, sx + ox, :3] = p["star"]
                stars[sy + oy, sx + ox, 3] = 0.45
    # Moon with craters, upper right
    ys, xs = np.mgrid[0:VH, 0:VW]
    mx, my, mr = 372, 58, 17
    disc = (xs - mx) ** 2 + (ys - my) ** 2 <= mr * mr
    crater = value_noise(VH, VW, 4, 99) > 0.62
    stars[disc, :3] = p["moon"]
    stars[disc & crater, :3] = p["snow2"]
    stars[disc, 3] = 1
    save_rgba(out / "arcadia_sky.png", sky)
    save_rgba(out / "arcadia_sky_e.png", stars)

    W2 = VW * 2
    far = mountains(W2, VH, 11, base=150, amp=44, body=p["mtn_far"], snow=p["mtn_snow"], snowline=0.6)
    save_rgba(out / "arcadia_far.png", far)
    mid = mountains(W2, VH, 23, base=190, amp=30, body=p["mtn_mid"], snow=p["snow0"], rim=p["sky3"], snowline=0.4)
    save_rgba(out / "arcadia_mid.png", mid)

    grove = np.zeros((VH, W2, 4), np.float32)
    ground = ridge(W2, 41, 236, 6, cells=(120, 60))
    gy = np.arange(VH)[:, None]
    solid = gy >= ground[None, :]
    grove[solid, :3] = p["grove"]
    grove[solid, 3] = 1
    rng = np.random.default_rng(3)
    for i in range(9):
        x = int(i * W2 / 9 + rng.integers(-20, 20))
        olive_silhouette(grove, x, int(ground[x % W2]) + 2, rng.uniform(0.9, 1.4), p["grove"], 100 + i)
    for x, hgt, broken in ((140, 52, False), (162, 40, True), (650, 46, True), (700, 58, False)):
        column_silhouette(grove, x, int(ground[x]) + 1, hgt, p["grove"], broken)
    save_rgba(out / "arcadia_grove.png", grove)
    print("backgrounds: arcadia")


def erebos() -> None:
    p = load_palette("erebos")
    out = ART / "backgrounds"
    cave = dithered_gradient(VH, VW, [p["cav0"], p["cav1"], p["cav2"], p["cav3"], p["haze"]],
                             [0.3, 0.55, 0.75, 0.9])
    # Stalactites hanging from the cavern roof
    W = VW
    tips = np.zeros(W)
    rng = np.random.default_rng(5)
    for _ in range(26):
        cx = rng.integers(0, W)
        length = rng.integers(10, 46)
        half = rng.integers(3, 9)
        for dx in range(-half, half + 1):
            tips[(cx + dx) % W] = max(tips[(cx + dx) % W], length * (1 - abs(dx) / (half + 1)))
    ys = np.arange(VH)[:, None]
    roof = ys < (6 + tips[None, :])
    cave[roof, :3] = p["cav0"]
    save_rgba(out / "erebos_cave.png", cave)

    W2 = VW * 2
    city = np.zeros((VH, W2, 4), np.float32)
    lit = np.zeros((VH, W2, 4), np.float32)
    x = 0
    rng = np.random.default_rng(17)
    while x < W2:
        bw = int(rng.integers(18, 46))
        bh = int(rng.integers(50, 130))
        top = VH - 40 - bh
        city[top:VH, x:x + bw, :3] = p["city"]
        city[top:VH, x:x + bw, 3] = 1
        # Windows in a grid, some lit
        for wy in range(top + 6, VH - 44, 9):
            for wx in range(x + 4, x + bw - 4, 7):
                if rng.random() < 0.38:
                    lit[wy:wy + 4, wx:wx + 3, :3] = p["city_lit"] * rng.uniform(0.6, 1.0)
                    lit[wy:wy + 4, wx:wx + 3, 3] = 1
        # Smokestack with a hot mouth
        if rng.random() < 0.45:
            sx = x + bw // 2
            sh = int(rng.integers(30, 70))
            city[top - sh:top, sx - 3:sx + 3, :3] = p["city"]
            city[top - sh:top, sx - 3:sx + 3, 3] = 1
            lit[top - sh:top - sh + 2, sx - 3:sx + 3, :3] = p["molten2"]
            lit[top - sh:top - sh + 2, sx - 3:sx + 3, 3] = 1
        x += bw + int(rng.integers(0, 10))
    save_rgba(out / "erebos_city.png", city)
    save_rgba(out / "erebos_city_e.png", lit)

    # Mid layer: scaffolds, pipes and a gantry, as near-black silhouettes.
    mid = np.zeros((VH, W2, 4), np.float32)
    col = p["cav1"] * 0.7
    for gx in range(0, W2, 96):
        mid[120:VH, gx:gx + 3, :3] = col
        mid[120:VH, gx:gx + 3, 3] = 1
        mid[120:VH, gx + 30:gx + 33, :3] = col
        mid[120:VH, gx + 30:gx + 33, 3] = 1
        for yy in range(126, VH, 22):
            for t in range(33):
                yv = yy + int(t * 22 / 33)
                if yv < VH:
                    mid[yv, gx + t, :3] = col
                    mid[yv, gx + t, 3] = 1
    mid[150:156, :, :3] = col
    mid[150:156, :, 3] = 1
    save_rgba(out / "erebos_mid.png", mid)
    print("backgrounds: erebos")


if __name__ == "__main__":
    arcadia()
    erebos()

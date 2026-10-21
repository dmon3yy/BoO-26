"""Procedural terrain tiles: albedo + normal (+ emission) atlases.

Atlas layout (shared with game/world/autotiler.gd):
  * 16 "macro variants" in a 4x4 grid of blocks; each block is 16x16 tiles.
    A tile at world cell (tx, ty) uses variant v = (tx % 4) + 4 * (ty % 4), so
    texture detail flows seamlessly across a 4x4-tile (64px) macro texture.
  * Inside a block, a tile's cell is its canonical 8-neighbour mask:
    col = (v % 4) * 16 + mask % 16, row = (v // 4) * 16 + mask // 16.
  * Mask bits: N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128 (bit set = neighbour solid).
  * A corner bit only counts when both touching sides are solid, so 256 masks
    collapse to 47 distinct shapes. Unused cells stay transparent.

Each tile's edge treatment (bevels, snow caps, inner corners) comes from a
48x48 pixel neighbourhood built from its mask; its surface detail comes from
the 64x64 macro fields, sliced at the variant's position.
"""
from __future__ import annotations

import numpy as np

from pixel import (ART, distance_inside, fbm, load_palette, normals_from_height, save_normal, save_rgba, value_noise,
                   voronoi)

T = 16
MACRO = 4                      # macro texture is MACRO x MACRO tiles
VARIANTS = MACRO * MACRO
M = T * MACRO                  # macro texture size in px
N, NE, E, SE, S, SW, W, NW = 1, 2, 4, 8, 16, 32, 64, 128


def canonical(mask: int) -> int:
    m = mask
    if not (m & N and m & E):
        m &= ~NE
    if not (m & S and m & E):
        m &= ~SE
    if not (m & S and m & W):
        m &= ~SW
    if not (m & N and m & W):
        m &= ~NW
    return m


CANONICAL = sorted({canonical(m) for m in range(256)})
assert len(CANONICAL) == 47


def atlas_cell(mask: int, variant: int) -> tuple[int, int]:
    return (variant % MACRO) * 16 + mask % 16, (variant // MACRO) * 16 + mask // 16


def neighbourhood(mask: int) -> np.ndarray:
    """48x48 boolean solid map for a tile in the middle of its mask."""
    g = np.zeros((3, 3), bool)
    g[1, 1] = True
    g[0, 1] = bool(mask & N)
    g[0, 2] = bool(mask & NE)
    g[1, 2] = bool(mask & E)
    g[2, 2] = bool(mask & SE)
    g[2, 1] = bool(mask & S)
    g[2, 0] = bool(mask & SW)
    g[1, 0] = bool(mask & W)
    g[0, 0] = bool(mask & NW)
    return np.kron(g, np.ones((T, T), bool))


def dist_up(solid: np.ndarray, cap: int = 8) -> np.ndarray:
    """For each pixel: how many solid pixels lie between it and open air above (top surface = 1)."""
    h, w = solid.shape
    out = np.full((h, w), cap, np.float32)
    run = np.zeros(w, np.float32)
    for y in range(h):
        run = np.where(solid[y], run + 1, 0)
        out[y] = np.minimum(run, cap)
    return out


def dist_down(solid: np.ndarray, cap: int = 8) -> np.ndarray:
    return dist_up(solid[::-1], cap)[::-1]


def pick(pal: dict, names: list[str], t: np.ndarray) -> np.ndarray:
    table = np.stack([pal[n] for n in names])
    idx = np.clip((t * len(names)).astype(int), 0, len(names) - 1)
    return table[idx]


class Material:
    """Subclasses describe macro fields and colour each tile."""
    palette = "arcadia_winter"
    emissive = False
    voronoi_points = 0

    def __init__(self, seed: int):
        self.p = load_palette(self.palette)
        self.fields = {
            "n1": fbm(M, M, seed, cells=(16, 8, 4, 2), period=(M, M)),
            "n2": value_noise(M, M, 2, seed + 900, period=(M, M)),
            "n8": value_noise(M, M, 8, seed + 77, period=(M, M)),
        }
        if self.voronoi_points:
            d1, d2, cell = voronoi(M, M, self.voronoi_points, seed + 500)
            self.fields.update({"d1": d1, "d2": d2, "cell": cell.astype(np.float32)})

    def draw(self, c: dict):
        raise NotImplementedError


def tile_context(mat: Material, mask: int, variant: int) -> dict:
    solid = neighbourhood(mask)
    ox, oy = (variant % MACRO) * T, (variant // MACRO) * T
    c = {k: v[oy:oy + T, ox:ox + T] for k, v in mat.fields.items()}
    ys, xs = np.mgrid[0:T, 0:T]
    c.update({
        "mask": mask, "variant": variant,
        "d": distance_inside(solid, cap=8)[T:2 * T, T:2 * T],
        "up": dist_up(solid)[T:2 * T, T:2 * T],
        "down": dist_down(solid)[T:2 * T, T:2 * T],
        "x": xs, "y": ys, "gx": xs + ox, "gy": ys + oy,
    })
    return c


def snow_cap(p, c, col, height, min_depth=2.0, extra=3.0):
    """Irregular snow lying on every upward-facing surface."""
    up, n2 = c["up"], c["n2"]
    depth = min_depth + extra * c["n8"]
    snow = (up >= 1) & (up <= depth)
    edge = snow & (up > depth - 1)                       # shadowed lower edge of the drift
    st = 0.95 - (up / (depth + 0.01)) * 0.45 + 0.08 * (n2 - 0.5)
    scol = pick(p, ["snow1", "snow2", "snow3"], np.clip(st, 0, 0.999))
    scol = np.where(edge[..., None], p["snow0"], scol)
    col = np.where(snow[..., None], scol, col)
    height = np.where(snow, 1.1 - up * 0.08, height)
    return col, height


class LimestoneSnow(Material):
    palette = "arcadia_winter"
    voronoi_points = 34

    def draw(self, c):
        p = self.p
        d, down, n1, n2 = c["d"], c["down"], c["n1"], c["n2"]
        crack = (c["d2"] - c["d1"]) < 1.0
        bevel = np.clip((c["d2"] - c["d1"]) / 4.0, 0, 1)
        chunk_tone = (np.sin(c["cell"] * 12.9898) * 0.5 + 0.5) * 0.16
        tone = 0.47 + chunk_tone + 0.12 * (n1 - 0.5) + 0.1 * bevel
        tone = np.where(crack, tone - 0.26, tone)
        tone = np.where(d <= 1, tone + 0.2, tone)            # weathered rim
        tone = np.where(d >= 6, tone - 0.12, tone)           # depth
        tone = np.where(down <= 1, tone - 0.3, tone)         # underside
        col = pick(p, ["stone0", "stone1", "stone2", "stone3", "stone4", "stone5"], np.clip(tone, 0, 0.999))
        height = 0.3 + 0.5 * bevel + 0.35 * (1 - np.exp(-d / 2.0)) + 0.06 * n2
        col, height = snow_cap(p, c, col, height)
        return col, height, None


class MarbleSnow(Material):
    palette = "arcadia_winter"

    def draw(self, c):
        p = self.p
        d, down, n1, gx, gy = c["d"], c["down"], c["n1"], c["gx"], c["gy"]
        # Ashlar courses: 8px courses, 16px blocks, joints offset per course.
        course = gy // 8
        jx = np.where(course % 2 == 0, 0, 8)
        bx = (gx - jx) % 16
        joint = (gy % 8 == 7) | (bx == 15)
        block = course * 7 + (gx - jx) // 16
        block_tone = (np.sin(block * 7.31) * 0.5 + 0.5) * 0.12
        vein = (np.abs(np.sin(gx * 0.31 + gy * 0.83 + n1 * 7.0)) < 0.07) & (n1 > 0.55)
        tone = 0.48 + block_tone + 0.06 * (n1 - 0.5)
        tone = np.where((gy % 8 == 0) | (bx == 0), tone + 0.12, tone)   # lit block edges
        tone = np.where(d <= 1, tone + 0.12, tone)
        tone = np.where(down <= 1, tone - 0.28, tone)
        tone = np.where(joint, 0.1, tone)
        col = pick(p, ["marble0", "marble1", "marble2", "marble3", "marble4"], np.clip(tone, 0, 0.999))
        col = np.where((vein & ~joint)[..., None], p["vein"], col)
        bevel = np.minimum(np.minimum(gy % 8, 7 - gy % 8), np.minimum(bx, 15 - bx))
        height = 0.55 + 0.12 * np.minimum(bevel, 2) - np.where(joint, 0.45, 0) + 0.25 * (1 - np.exp(-d / 2))
        col, height = snow_cap(p, c, col, height, min_depth=1.5, extra=2.0)
        return col, height, None


class LimestoneBack(Material):
    """Back wall (no collision): darker, flatter, so the playable layer pops."""
    palette = "arcadia_winter"

    def draw(self, c):
        p = self.p
        d, n1, n2, gx, gy = c["d"], c["n1"], c["n2"], c["gx"], c["gy"]
        course = gy // 12
        jx = np.where(course % 2 == 0, 5, 17)
        joint = (gy % 12 == 11) | ((gx - jx) % 24 == 23)
        tone = 0.36 + 0.22 * (n1 - 0.5) + 0.06 * (n2 - 0.5)
        tone = np.where(joint, tone - 0.22, tone)
        tone = np.where(d <= 1, tone - 0.12, tone)
        col = pick(p, ["stone0", "stone1", "stone2", "stone3"], np.clip(tone, 0, 0.999))
        height = 0.4 + 0.2 * n1 - np.where(joint, 0.3, 0)
        return col, height, None


class IronPlate(Material):
    palette = "erebos"

    def draw(self, c):
        p = self.p
        d, up, down, n1, n2, x, y = c["d"], c["up"], c["down"], c["n1"], c["n2"], c["x"], c["y"]
        v = c["variant"]
        seam = (x == 0) | (y == 0)
        rivet = np.isin(x, (3, 12)) & np.isin(y, (3, 12))
        rivet_shadow = np.isin(x, (4, 13)) & np.isin(y, (4, 13))
        # Thin rust runs dripping from a few rivets; lengths vary by variant.
        r1, r2 = (v * 5) % 7, (v * 3 + 2) % 6
        streak = ((x == 3) & (y > 3) & (y <= 3 + r1)) | ((x == 12) & (y > 12) & (y <= 12 + r2 // 2))
        stain = (n1 > 0.66) & ~seam
        tone = 0.5 + 0.14 * (n1 - 0.5)
        tone = np.where(d >= 5, tone - 0.12, tone)
        tone = np.where((x == 1) | (y == 1), tone + 0.15, tone)           # plate bevel catch-light
        tone = np.where(seam, tone - 0.32, tone)
        tone = np.where(down <= 1, tone - 0.25, tone)
        col = pick(p, ["iron0", "iron1", "iron2", "iron3", "iron4", "iron5"], np.clip(tone, 0, 0.999))
        col = np.where(stain[..., None], p["rust0"], col)
        col = np.where(streak[..., None], p["rust1"], col)
        col = np.where(rivet[..., None], p["iron5"], col)
        col = np.where(rivet_shadow[..., None], p["iron0"], col)
        lip = (up >= 1) & (up <= 2)
        col = np.where(lip[..., None], np.where((up <= 1)[..., None], p["brass2"], p["brass1"]), col)
        height = 0.55 + 0.1 * n1 - np.where(seam, 0.35, 0) + np.where(rivet, 0.45, 0) + 0.3 * (1 - np.exp(-d / 2))
        return col, height, None


class Basalt(Material):
    palette = "erebos"
    emissive = True
    voronoi_points = 18

    def draw(self, c):
        p = self.p
        d, down, n1 = c["d"], c["down"], c["n1"]
        crack = (c["d2"] - c["d1"]) < 1.0
        bevel = np.clip((c["d2"] - c["d1"]) / 5.0, 0, 1)
        chunk_tone = (np.sin(c["cell"] * 4.7) * 0.5 + 0.5) * 0.12
        tone = 0.42 + chunk_tone + 0.1 * (n1 - 0.5) + 0.1 * bevel
        tone = np.where(crack, tone - 0.3, tone)
        tone = np.where(d <= 1, tone + 0.25, tone)
        tone = np.where(down <= 1, tone - 0.25, tone)
        col = pick(p, ["rock0", "rock1", "rock2", "rock3", "rock4"], np.clip(tone, 0, 0.999))
        height = 0.3 + 0.5 * bevel + 0.3 * (1 - np.exp(-d / 2))
        heat = c["n8"]
        glow = crack & (d >= 5) & (heat > 0.55)
        em = np.zeros((T, T, 4), np.float32)
        em[glow, :3] = p["molten2"]
        em[glow, 3] = 1.0
        em[glow & (heat > 0.8), :3] = p["molten3"]
        col = np.where(glow[..., None], p["molten1"], col)
        return col, height, em


class IronBack(Material):
    palette = "erebos"
    emissive = True

    def draw(self, c):
        p = self.p
        n1, n2, gx, gy = c["n1"], c["n2"], c["gx"], c["gy"]
        panel = (gx % 8 == 0)
        bolt = (gx % 8 == 2) & (gy % 16 == 2)
        # One lit factory window per macro texture.
        window = (gx >= 37) & (gx <= 42) & (gy >= 20) & (gy <= 29)
        mullion = window & ((gx == 39) | (gy == 24))
        tone = 0.32 + 0.15 * (n1 - 0.5)
        tone = np.where(panel, tone - 0.18, tone)
        col = pick(p, ["iron0", "iron1", "iron2", "iron3"], np.clip(tone, 0, 0.999))
        col = np.where(bolt[..., None], p["iron4"], col)
        lit = window & ~mullion
        col = np.where(lit[..., None], p["city_lit"], col)
        col = np.where(mullion[..., None], p["iron0"], col)
        height = 0.4 + 0.1 * n1 - np.where(panel, 0.2, 0) - np.where(lit, 0.3, 0)
        em = np.zeros((T, T, 4), np.float32)
        em[lit, :3] = p["city_lit"] * (0.8 + 0.2 * n2[lit, None])
        em[lit, 3] = 0.9
        return col, height, em


MATERIALS = {
    "limestone_snow": LimestoneSnow,
    "marble_snow": MarbleSnow,
    "limestone_back": LimestoneBack,
    "iron_plate": IronPlate,
    "basalt": Basalt,
    "iron_back": IronBack,
}


def build_material(name: str, cls) -> None:
    seed = sum(ord(ch) * (i + 1) for i, ch in enumerate(name))
    mat = cls(seed)
    size = 16 * T * MACRO
    albedo = np.zeros((size, size, 4), np.float32)
    normal = np.zeros((size, size, 3), np.float32)
    normal[...] = (0.5, 0.5, 1.0)
    emission = np.zeros((size, size, 4), np.float32)
    for v in range(VARIANTS):
        for m in CANONICAL:
            col, height, em = mat.draw(tile_context(mat, m, v))
            n = normals_from_height(np.pad(height, 1, mode="edge"), strength=1.6)[1:-1, 1:-1]
            cx, cy = atlas_cell(m, v)
            ox, oy = cx * T, cy * T
            albedo[oy:oy + T, ox:ox + T, :3] = col
            albedo[oy:oy + T, ox:ox + T, 3] = 1.0
            normal[oy:oy + T, ox:ox + T] = n
            if em is not None:
                emission[oy:oy + T, ox:ox + T] = em
    out = ART / "tiles"
    save_rgba(out / f"{name}.png", albedo)
    save_normal(out / f"{name}_n.png", normal)
    if mat.emissive:
        save_rgba(out / f"{name}_e.png", emission)
    print(f"tiles: {name}")


def build_ledges() -> None:
    """One-way platform strips: 4 tiles (single, left end, middle, right end)."""
    specs = {"marble_ledge": ("arcadia_winter", ["marble1", "marble2", "marble3", "marble4"], "snow2"),
             "iron_grate": ("erebos", ["iron1", "iron2", "iron3", "iron4"], "brass2")}
    for name, (pal_name, ramp_names, lip) in specs.items():
        p = load_palette(pal_name)
        img = np.zeros((T, T * 4, 4), np.float32)
        height = np.zeros((T, T * 4), np.float32)
        ys, xs = np.mgrid[0:T, 0:T]
        for i in range(4):
            body = ys < 6
            if i in (0, 1):
                body &= ~((xs < 2) & (ys > 3))
            if i in (0, 3):
                body &= ~((xs > 13) & (ys > 3))
            tone = np.where(ys == 0, 0.95, np.where(ys >= 4, 0.15, 0.55))
            if name == "iron_grate":
                tone = np.where((xs % 4 == 0) & (ys > 0), tone - 0.3, tone)
            col = pick(p, ramp_names, np.clip(tone, 0, 0.999))
            col = np.where((ys == 0)[..., None], p[lip], col)
            sl = slice(i * T, (i + 1) * T)
            img[:, sl, :3] = np.where(body[..., None], col, 0)
            img[:, sl, 3] = body.astype(np.float32)
            height[:, sl] = np.where(body, 0.6 - ys * 0.06, 0)
        out = ART / "tiles"
        save_rgba(out / f"{name}.png", img)
        save_normal(out / f"{name}_n.png", normals_from_height(height, img[..., 3], 1.5), img[..., 3])
        print(f"tiles: {name}")


def main() -> None:
    for name, cls in MATERIALS.items():
        build_material(name, cls)
    build_ledges()


if __name__ == "__main__":
    main()

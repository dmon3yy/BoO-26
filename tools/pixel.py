"""Shared pixel-art helpers for the asset builders.

Everything works on numpy arrays:
  * colour images are float32 RGBA in 0..1, shape (h, w, 4)
  * height maps are float32, shape (h, w), roughly 0..1 (higher = closer to viewer)

Normal maps follow Godot's 2D convention: R = +x (right), G = +y (UP), B = +z.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "game" / "art"
CONTENT = ROOT / "content"


# --- colour ------------------------------------------------------------------

def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def load_palette(name: str) -> dict[str, np.ndarray]:
    data = json.loads((CONTENT / "palettes" / f"{name}.json").read_text())
    return {k: hex_rgb(v) for k, v in data["colors"].items()}


def ramp(colors: list[np.ndarray], t: np.ndarray) -> np.ndarray:
    """Map t (0..1) onto a hard-stepped colour ramp (no blending: pixel art)."""
    idx = np.clip((t * len(colors)).astype(int), 0, len(colors) - 1)
    table = np.stack(colors)
    return table[idx]


# --- noise -------------------------------------------------------------------

def value_noise(h: int, w: int, cell: int, seed: int, period: tuple[int, int] | None = None) -> np.ndarray:
    """Smooth value noise in 0..1. With `period`, the noise tiles seamlessly."""
    rng = np.random.default_rng(seed)
    gh = (period[0] if period else h) // cell + 2
    gw = (period[1] if period else w) // cell + 2
    grid = rng.random((gh, gw)).astype(np.float32)
    if period:
        ph, pw = period[0] // cell, period[1] // cell
        grid = grid[: ph, : pw]
        grid = np.pad(grid, ((0, 2), (0, 2)), mode="wrap")
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    if period:
        y0 %= period[0] // cell
        x0 %= period[1] // cell
    a = grid[y0][:, x0]
    b = grid[y0][:, x0 + 1]
    c = grid[y0 + 1][:, x0]
    d = grid[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h: int, w: int, seed: int, cells=(8, 4, 2), period=None) -> np.ndarray:
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    total = 0.0
    for i, c in enumerate(cells):
        out += amp * value_noise(h, w, c, seed + i * 101, period)
        total += amp
        amp *= 0.5
    return out / total


def voronoi(h: int, w: int, points: int, seed: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Periodic (tileable) Voronoi over an h x w tile.

    Returns (d1, d2, cell): distance to the nearest and second-nearest site and
    the nearest site's index. Cracks live where d2 - d1 is small.
    """
    rng = np.random.default_rng(seed)
    pts = rng.random((points, 2)) * (h, w)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    best = np.full((h, w), 1e9, np.float32)
    second = np.full((h, w), 1e9, np.float32)
    cell = np.zeros((h, w), int)
    for i, (py, px) in enumerate(pts):
        for oy in (-h, 0, h):
            for ox in (-w, 0, w):
                dist = np.hypot(ys - (py + oy), xs - (px + ox))
                closer = dist < best
                second = np.where(closer, best, np.minimum(second, dist))
                cell = np.where(closer, i, cell)
                best = np.where(closer, dist, best)
    return best, second, cell


def bayer4() -> np.ndarray:
    return np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) / 16.0


def dither(t: np.ndarray, levels: int) -> np.ndarray:
    """Ordered-dither a 0..1 field to `levels` bands; returns 0..1 stepped values."""
    h, w = t.shape
    b = np.tile(bayer4(), (h // 4 + 1, w // 4 + 1))[:h, :w]
    return np.clip(np.floor(t * (levels - 1) + b) / (levels - 1), 0, 1)


# --- height -> normal --------------------------------------------------------

def normals_from_height(height: np.ndarray, alpha: np.ndarray | None = None, strength: float = 2.0) -> np.ndarray:
    """Sobel gradient of a height field -> RGB normal map (Godot 2D, Y up)."""
    hp = np.pad(height, 1, mode="edge")
    if alpha is not None:
        # Outside the sprite is height 0, so silhouettes get a strong rim.
        ap = np.pad(alpha, 1, mode="constant")
        hp = np.where(ap > 0, hp, 0.0)
    gx = (hp[1:-1, 2:] - hp[1:-1, :-2]) * 2 + (hp[:-2, 2:] - hp[:-2, :-2]) + (hp[2:, 2:] - hp[2:, :-2])
    gy = (hp[2:, 1:-1] - hp[:-2, 1:-1]) * 2 + (hp[2:, 2:] - hp[:-2, 2:]) + (hp[2:, :-2] - hp[:-2, :-2])
    nx = -gx * strength
    ny = gy * strength           # image y grows downward; Godot wants +y = up
    nz = np.ones_like(nx)
    n = np.stack([nx, ny, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def distance_inside(mask: np.ndarray, cap: int = 4) -> np.ndarray:
    """Chebyshev distance (in px) from each opaque pixel to the nearest transparent one."""
    d = np.where(mask, cap, 0).astype(np.float32)
    m = mask.copy()
    for step in range(1, cap):
        p = np.pad(m, 1, constant_values=False)
        shrunk = (p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
        d = np.where(m & ~shrunk, np.minimum(d, step), d)
        m = shrunk
    return d


# --- sprite ops --------------------------------------------------------------

def outline(img: np.ndarray, color=(0.06, 0.04, 0.08)) -> np.ndarray:
    """Add a 1px outer outline around opaque pixels (4-neighbour)."""
    a = img[..., 3] > 0.5
    p = np.pad(a, 1)
    near = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    ring = near & ~a
    out = img.copy()
    out[ring, :3] = color
    out[ring, 3] = 1.0
    return out


def scale2x(img: np.ndarray) -> np.ndarray:
    """EPX/Scale2x on an indexed or RGBA array (compares exact pixel values)."""
    h, w = img.shape[:2]
    p = np.pad(img, ((1, 1), (1, 1)) + ((0, 0),) * (img.ndim - 2), mode="edge")
    E = p[1:-1, 1:-1]
    B = p[:-2, 1:-1]
    H = p[2:, 1:-1]
    D = p[1:-1, :-2]
    F = p[1:-1, 2:]

    def eq(a, b):
        return np.all(a == b, axis=-1) if img.ndim == 3 else a == b

    cond = ~eq(B, H) & ~eq(D, F)
    sel = (lambda c, x, y: np.where(c[..., None], x, y)) if img.ndim == 3 else np.where
    e0 = sel(cond & eq(D, B), D, E)
    e1 = sel(cond & eq(B, F), F, E)
    e2 = sel(cond & eq(D, H), D, E)
    e3 = sel(cond & eq(H, F), F, E)
    out = np.empty((h * 2, w * 2) + img.shape[2:], img.dtype)
    out[0::2, 0::2] = e0
    out[0::2, 1::2] = e1
    out[1::2, 0::2] = e2
    out[1::2, 1::2] = e3
    return out


def rotsprite(layers: list[np.ndarray], angle_deg: float, pivot: tuple[float, float], out_size: tuple[int, int],
              out_pivot: tuple[float, float]) -> list[np.ndarray]:
    """Rotate pixel art cleanly (RotSprite): upscale x8 with Scale2x, rotate with
    nearest-neighbour, sample back down. All layers share the same transform.

    `pivot` is in source pixels; the pivot lands on `out_pivot` in an output
    canvas of `out_size` (w, h).
    """
    k = 8
    big = []
    for L in layers:
        b = L
        for _ in range(3):
            b = scale2x(b)
        big.append(b)
    ow, oh = out_size
    # For every output pixel centre, find the matching source pixel at x8.
    ys, xs = np.mgrid[0:oh, 0:ow].astype(np.float32)
    ys += 0.5
    xs += 0.5
    dx = xs - out_pivot[0]
    dy = ys - out_pivot[1]
    a = np.deg2rad(angle_deg)
    ca, sa = np.cos(a), np.sin(a)
    # inverse rotation
    sx = (ca * dx + sa * dy + pivot[0]) * k
    sy = (-sa * dx + ca * dy + pivot[1]) * k
    ix = np.floor(sx).astype(int)
    iy = np.floor(sy).astype(int)
    out = []
    for b in big:
        bh, bw = b.shape[:2]
        valid = (ix >= 0) & (iy >= 0) & (ix < bw) & (iy < bh)
        res = np.zeros((oh, ow) + b.shape[2:], b.dtype)
        res[valid] = b[iy[valid], ix[valid]]
        out.append(res)
    return out


# --- .pxl files --------------------------------------------------------------

def parse_pxl(text: str) -> dict[str, list[str]]:
    """A .pxl file holds named grids:

        @head
        ..hhhh..
        .hhffhh.

    Each character is a palette key; '.' is transparent.
    """
    grids: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        if line.startswith(";"):
            continue
        if line.startswith("@"):
            current = line[1:].strip()
            grids[current] = []
        elif current is not None and line.strip():
            grids[current].append(line.rstrip())
    for name, rows in grids.items():
        w = max(len(r) for r in rows)
        grids[name] = [r.ljust(w, ".") for r in rows]
    return grids


def grid_to_rgba(rows: list[str], palette: dict[str, np.ndarray]) -> np.ndarray:
    h, w = len(rows), len(rows[0])
    img = np.zeros((h, w, 4), np.float32)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != "." and ch != " ":
                if ch not in palette:
                    raise KeyError(f"palette has no key {ch!r}")
                img[y, x, :3] = palette[ch]
                img[y, x, 3] = 1.0
    return img


# --- output ------------------------------------------------------------------

def save_rgba(path: Path, img: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    arr = np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA" if arr.shape[-1] == 4 else "RGB").save(path, optimize=True)


def save_normal(path: Path, n: np.ndarray, alpha: np.ndarray | None = None) -> None:
    rgb = np.clip(n * 255 + 0.5, 0, 255).astype(np.uint8)
    if alpha is not None:
        a = (alpha > 0.5).astype(np.uint8) * 255
        rgb = np.dstack([rgb, a])
        Image.fromarray(rgb, "RGBA").save(path, optimize=True)
    else:
        Image.fromarray(rgb, "RGB").save(path, optimize=True)

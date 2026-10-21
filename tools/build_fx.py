"""Light textures, glow halos, particles and animated flames."""
from __future__ import annotations

import numpy as np

from pixel import ART, bayer4, load_palette, save_rgba, value_noise


def radial(size: int) -> np.ndarray:
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) + 0.5
    c = size / 2
    return np.clip(np.hypot(xs - c, ys - c) / c, 0, 1)


def banded_light(size: int = 128, bands: int = 7) -> np.ndarray:
    """Pixel-art light falloff: hard bands with a dithered seam between them."""
    r = radial(size)
    t = np.clip(1 - r, 0, 1) ** 1.7
    b = np.tile(bayer4(), (size // 4, size // 4))
    # Dither only near band edges, so bands stay readable as bands.
    stepped = np.clip(np.floor(t * bands + (b - 0.5) * 0.6 + 0.5) / bands, 0, 1)
    img = np.ones((size, size, 4), np.float32)
    img[..., :3] = stepped[..., None]   # falloff in colour *and* alpha, so any blend reads it
    img[..., 3] = stepped
    return img


def halo(size: int = 64) -> np.ndarray:
    r = radial(size)
    a = np.clip(1 - r, 0, 1) ** 2.2
    img = np.ones((size, size, 4), np.float32)
    img[..., 3] = a
    return img


def flame_frames(w: int = 12, h: int = 20, frames: int = 8) -> np.ndarray:
    """A looping campfire/brazier flame, palette-stepped."""
    p = load_palette("arcadia_winter")
    ramp = [p["fire0"], p["fire1"], p["fire2"], p["fire3"]]
    sheet = np.zeros((h, w * frames, 4), np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    big = value_noise(h * 3, w, 3, 4242, period=(h * 3, w))
    for f in range(frames):
        scroll = int(f * h * 3 / frames)
        n = np.roll(big, -scroll, axis=0)[:h]
        # Teardrop envelope: wide at the base, licking to a point.
        v = ys / h                                            # 0 at the tip, 1 at the base
        cx = w / 2 - 0.5 + np.sin(f / frames * 2 * np.pi + ys * 0.35) * (1 - v) * 1.4
        width = 0.6 + v ** 0.75 * (w * 0.48)
        dist = np.abs(xs - cx) / width
        heat = (1 - dist) * (0.35 + 0.65 * v) + (n - 0.5) * 0.45
        on = heat > 0.06
        lvl = np.clip(((heat - 0.06) / 0.7 * 4).astype(int), 0, 3)
        frame = np.zeros((h, w, 4), np.float32)
        table = np.stack(ramp)
        frame[on, :3] = table[lvl[on]]
        frame[on, 3] = 1.0
        sheet[:, f * w:(f + 1) * w] = frame
    return sheet


def particles() -> dict[str, np.ndarray]:
    out = {}
    snow = np.zeros((3, 3, 4), np.float32)
    snow[1, :] = (1, 1, 1, 0.9)
    snow[:, 1] = (1, 1, 1, 0.9)
    snow[1, 1] = (1, 1, 1, 1)
    out["snowflake"] = snow
    dot = np.ones((2, 2, 4), np.float32)
    out["ember"] = dot
    ash = np.ones((1, 2, 4), np.float32)
    out["ash"] = ash
    px = np.ones((1, 1, 4), np.float32)
    out["pixel"] = px
    return out


def main() -> None:
    fx = ART / "fx"
    save_rgba(fx / "light_banded.png", banded_light())
    save_rgba(fx / "light_banded_large.png", banded_light(256, 9))
    save_rgba(fx / "halo.png", halo())
    save_rgba(fx / "flame.png", flame_frames())
    for name, img in particles().items():
        save_rgba(fx / f"{name}.png", img)
    print("fx: lights, halo, flame, particles")


if __name__ == "__main__":
    main()

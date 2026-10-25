"""Bake rigged characters into sprite sheets + normal-map sheets + metadata.

Rig format: content/rigs/<name>.json (parts, hierarchy, animation cycles).
Every rig in content/rigs is baked unless names are given on the command line.
Pixels:     content/sprites/<sprite>.pxl
Output:     game/art/characters/<name>.png, <name>_n.png, <name>.json

Each part is rotated with RotSprite (see pixel.rotsprite), so limbs stay crisp
pixel art at any angle. Normal maps come from a per-part "pillow" height field
(thicker in the middle of each part, plus a little extra for parts drawn in
front) so lights wrap around the silhouette.
"""
from __future__ import annotations

import json
import math
import sys

import numpy as np

from pixel import ART, CONTENT, distance_inside, grid_to_rgba, load_palette, normals_from_height, outline, parse_pxl, \
    rotsprite, save_normal, save_rgba


def cycle(spec: dict | None, t: float) -> float:
    if not spec:
        return 0.0
    v = spec.get("mean", 0.0) + spec.get("amp", 0.0) * math.sin(
        2 * math.pi * (spec.get("harmonic", 1) * t + spec.get("phase", 0.0)))
    if "min" in spec:
        v = max(v, spec["min"])
    return v


def rot(v: tuple[float, float], deg: float) -> tuple[float, float]:
    """Same forward rotation as pixel.rotsprite (screen space, y down)."""
    a = math.radians(deg)
    return (math.cos(a) * v[0] - math.sin(a) * v[1], math.sin(a) * v[0] + math.cos(a) * v[1])


def solve_pose(rig: dict, anim: dict, t: float) -> dict[str, tuple[float, float, float]]:
    """World (x, y, angle) of every part's pivot for time t."""
    hx, hy = rig["hip"]
    hip = (hx, hy + round(cycle(anim.get("hip_dy"), t)))
    torso_dy = round(cycle(anim.get("torso_dy"), t))
    world: dict[str, tuple[float, float, float]] = {}
    parts = rig["parts"]

    def resolve(name: str):
        if name in world:
            return world[name]
        part = parts[name]
        local = cycle(anim.get(name), t)
        if part["parent"] == "hip":
            x, y = hip
            if name == "torso":
                y += torso_dy
            world[name] = (x, y, local)
        else:
            px, py, pa = resolve(part["parent"])
            parent = parts[part["parent"]]
            off = (part["attach"][0] - parent["pivot"][0], part["attach"][1] - parent["pivot"][1])
            ox, oy = rot(off, pa)
            world[name] = (px + ox, py + oy, pa + local)
        return world[name]

    for name in parts:
        resolve(name)
    return world


def bake(name: str) -> None:
    rig = json.loads((CONTENT / "rigs" / f"{name}.json").read_text())
    grids = parse_pxl((CONTENT / "sprites" / f"{rig['sprite']}.pxl").read_text())
    pal = load_palette(rig["palette"])
    fw, fh = rig["frame"]

    # Pre-render each part's colour and pillow height.
    part_img = {}
    for pname, part in rig["parts"].items():
        rgba = grid_to_rgba(grids[part["grid"]], pal)
        if "shade" in part:
            rgba[..., :3] *= part["shade"]
        mask = rgba[..., 3] > 0.5
        height = distance_inside(mask, cap=3) / 3.0
        part_img[pname] = (rgba, height.astype(np.float32))

    frames_rgba, frames_n, meta = [], [], {"frame_size": [fw, fh], "origin": [rig["hip"][0], fh - 3], "anims": {}}
    for aname, anim in rig["anims"].items():
        start = len(frames_rgba)
        for f in range(anim["frames"]):
            t = f / anim["frames"]
            pose = solve_pose(rig, anim, t)
            color = np.zeros((fh, fw, 4), np.float32)
            height = np.zeros((fh, fw), np.float32)
            for z, pname in enumerate(rig["draw_order"]):
                part = rig["parts"][pname]
                # A part can appear only in some animations ("only") or be
                # hidden in some ("not_in"): the club only shows mid-swing.
                if ("only" in part and aname not in part["only"]) or aname in part.get("not_in", []):
                    continue
                rgba, h = part_img[pname]
                x, y, ang = pose[pname]
                piv = (part["pivot"][0] + 0.5, part["pivot"][1] + 0.5)
                out_piv = (round(x) + 0.5, round(y) + 0.5)
                r_rgba, r_h = rotsprite([rgba, h], ang, piv, (fw, fh), out_piv)
                on = r_rgba[..., 3] > 0.5
                color[on] = r_rgba[on]
                height[on] = 0.35 + 0.65 * r_h[on] + z * 0.04
            color = outline(color)
            alpha = color[..., 3]
            n = normals_from_height(height, alpha, strength=1.4)
            frames_rgba.append(color)
            frames_n.append(n)
        meta["anims"][aname] = {"start": start, "count": anim["frames"], "fps": anim["fps"],
                                "loop": anim.get("loop", aname not in ("jump", "fall"))}

    sheet = np.concatenate(frames_rgba, axis=1)
    nsheet = np.concatenate(frames_n, axis=1)
    out = ART / "characters"
    save_rgba(out / f"{name}.png", sheet)
    save_normal(out / f"{name}_n.png", nsheet, sheet[..., 3])
    meta["frames"] = len(frames_rgba)
    (out / f"{name}.json").write_text(json.dumps(meta, indent=2))
    print(f"character: {name} ({len(frames_rgba)} frames)")


if __name__ == "__main__":
    for n in (sys.argv[1:] or sorted(p.stem for p in (CONTENT / "rigs").glob("*.json"))):
        bake(n)

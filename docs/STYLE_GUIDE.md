# Style guide

## Pixels
- **Native resolution 480×270**, integer-scaled (×4 → 1080p, ×8 → 4K). Nothing is drawn at a fractional pixel: `snap_2d_transforms_to_pixel` is on.
- **Tiles are 16×16.** A room is a whole number of 30×17-tile screens.
- **Orpheus is about 24×40 px** inside a 32×48 frame; feet sit 3 px above the frame bottom.
- Every sprite has a **1-px dark outline** (`#0d0a12`-ish, never pure black) so it reads against any background.

## Palettes (`content/palettes/`)
| Palette | Mood | Rules |
|---|---|---|
| `arcadia_winter` | Cold moonlit blues; warmth only from fire and people | Shadows lean violet, highlights lean cyan. Amber is reserved for flame. |
| `erebos` | Soot, iron, molten orange; the Styx glows sick teal | Brass is the only "wealth" colour and it belongs to Hades. |
| `orpheus` | Wine-red cloak, laurel green, lyre gold | He must read against both of the above. |

Ramps are **hue-shifted**, not just darker: each step down shifts toward the palette's shadow hue.

## Light
- **Everything that lights the world is a real light** (`PointLight2D`) with a banded falloff (`game/art/fx/light_banded.png`): hard bands with dithered seams, so light reads as pixel art, not airbrush.
- Surfaces carry **normal maps** generated from height; light wraps around rocks, bricks, columns and Orpheus.
- **Shadows** come from merged outlines of each room's solid tiles; surfaces facing a light stay lit, and everything behind them falls into shadow.
- **Glow** is faked with additive halo sprites (Compatibility renderer has no HDR 2D). Keep halos subtle; they support the light, they don't replace it.
- **Ambient** is per theme (`content/themes.json`): Arcadia ≈ `(0.40, 0.45, 0.66)`, Erebos ≈ `(0.34, 0.27, 0.29)`. A dark scene is not a black scene: the silhouette must always read.
- **Emissive** pixels (lava seams, lit windows, glowing glyphs) live in `_e.png` layers drawn unshaded. On rock, glow is scattered per tile (`glow_chance`) so it never repeats on a grid.

## Tiles
- Terrain is autotiled from 47 shapes × 16 **macro variants** (a 64-px texture cut into 4×4 tiles), so texture detail flows across tile seams with no visible grid.
- Back walls are darker and flatter than the playable layer, so what you can stand on always pops.

## Characters
- Built as **rigs** of pixel parts (`content/rigs/*.json`) and baked with RotSprite, never rotated at runtime: no shimmering.
- Animate in **cycles** (mean, amplitude, phase); hold strong silhouettes on key poses.
- Back limbs are shaded 70% so depth reads without extra colours.

## Text
- Font: **Hearthstone 5×8** (`content/fonts/hearthstone.pxf`), drawn at size 8, never scaled by fractions.
- Dialogue box: bottom of screen, 464×70, gold speaker name, ivory text, 45 characters per second.
- Voice: wry, warm, short lines. Gods are transactional and a little vain; Hermes talks to the player; Hades is weary, not cartoonish. No lyrics or phrases borrowed from anywhere (see `IP_RULES.md`).

## Sound
- Music is composed in `content/music/*.score` and rendered by `tools/build_audio.py`.
- Surface: Mediterranean folk + blues lyre (Karplus-Strong pluck), frame drum, soft pads. Underworld: swung industrial blues — FM bass, brass, anvils on 2 and 4.
- Each region uses its namesake Greek mode (see the design doc).
- Mix peaks ≤ 0.85 across all stems together; stems are the same length to the sample and loop seamlessly.

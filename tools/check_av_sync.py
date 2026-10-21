"""A/V sync check on a Movie Maker recording of the Beat Lab playing the metronome.

    BOO_SCENE=beat_lab BOO_LAB_SONG=metronome xvfb-run -a godot --path . \
        --rendering-driver opengl3 --write-movie out/sync/f.png --fixed-fps 60 --quit-after 420
    python3 tools/check_av_sync.py out/sync

Movie Maker renders audio and video in lockstep, so this measures the game's
own beat logic (MusicClock), not your speakers. For every click in the audio
it finds the frame where the beat dial is brightest and reports the offset.
Passes when every beat shows on the first frame at or after its click (0-16.7 ms at 60 fps).
"""
from __future__ import annotations

import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image

FPS = 60
DIAL = (240, 105)       # centre of the Beat Lab dial (game/spikes/beat_lab.gd)


def onsets(path: Path) -> list[float]:
    with wave.open(str(path)) as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        width = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dtype = {2: np.int16, 4: np.int32}[width]
    x = np.frombuffer(raw, dtype).astype(np.float32).reshape(-1, ch).mean(1)
    x /= np.max(np.abs(x)) + 1e-9
    env = np.abs(x)
    hop = sr // 1000                                    # 1 ms resolution
    e = env[: len(env) // hop * hop].reshape(-1, hop).max(1)
    out, last = [], -1000
    for i in range(1, len(e)):
        if e[i] > 0.3 and e[i - 1] <= 0.3 and i - last > 200:
            out.append(i / 1000.0)
            last = i
    return out


def dial_brightness(frames: list[Path]) -> np.ndarray:
    vals = []
    for f in frames:
        img = np.asarray(Image.open(f).convert("RGB"), np.float32)
        h, w = img.shape[:2]
        sx, sy = w / 480, h / 270
        x0, y0 = int((DIAL[0] - 40) * sx), int((DIAL[1] - 40) * sy)
        x1, y1 = int((DIAL[0] + 40) * sx), int((DIAL[1] + 40) * sy)
        vals.append(img[y0:y1, x0:x1].mean())
    return np.array(vals)


def main(folder: str) -> int:
    d = Path(folder)
    frames = sorted(d.glob("f*.png"))
    clicks = onsets(next(d.glob("*.wav")))
    bright = dial_brightness(frames)
    # Visual beats: local maxima of dial brightness.
    peaks = [i for i in range(1, len(bright) - 1) if bright[i] > bright[i - 1] and bright[i] >= bright[i + 1]
             and bright[i] > np.percentile(bright, 70)]
    errors = []
    for c in clicks:
        if c < 0.5 or c > len(frames) / FPS - 0.5:
            continue
        nearest = min(peaks, key=lambda p: abs(p / FPS - c)) if peaks else None
        if nearest is None:
            continue
        errors.append(nearest / FPS - c)
    if not errors:
        print("no beats measured")
        return 1
    err_ms = np.array(errors) * 1000
    print(f"{len(err_ms)} beats: mean {err_ms.mean():+.1f} ms, worst {np.abs(err_ms).max():.1f} ms")
    # A frame can only show a beat at or after it happens: expect 0..1 frame late.
    ok = err_ms.min() >= -2.0 and err_ms.max() <= 1000 / FPS + 1.0
    print("A/V sync OK" if ok else "A/V sync FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "out/sync"))

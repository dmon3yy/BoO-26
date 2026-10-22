"""A small synthesizer that turns text scores into game music.

    python3 tools/build_audio.py            # every content/music/*.score
    python3 tools/build_audio.py arcadia    # one score

For each score it writes game/audio/music/<name>_<stem>.ogg (one file per stem,
all exactly the same length so they stay in sync) and <name>.json, the beat
map the game's MusicClock reads. It also renders the lyre's single notes used
for d-pad songs (game/audio/sfx/lyre_*.wav), plus the combat sounds.

Score format (see content/music/arcadia.score for a full example):

    bpm = 84
    meter = 4            ; beats per bar (each beat = 4 steps)
    key = D3             ; tonic
    mode = dorian
    bars = 8
    swing = 0.0          ; 0 = straight, 0.33 = triplet swing on 8ths

    [track lyre]
    instrument = lyre    ; lyre | bass | pad | brass | kit
    stem = melody        ; which stem file it goes to
    octave = 1
    volume = 0.8
    | 1 . 3 . 5 . 3 . 8 - - - 7 . 5 .      <- one bar: 16 steps

Notes are scale degrees of the mode (1 = tonic, 8 = tonic an octave up);
add ' for an octave up or , for down (5,  1'); '-' holds, '.' rests.
`pad` reads degrees as chord roots. `kit` uses k s h a (kick, snare, hat,
anvil). Tracks with fewer bars than the song repeat their bars.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SCORES = ROOT / "content" / "music"
OUT_MUSIC = ROOT / "game" / "audio" / "music"
OUT_SFX = ROOT / "game" / "audio" / "sfx"
SR = 44100

MODES = {
    "ionian": [0, 2, 4, 5, 7, 9, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "locrian": [0, 1, 3, 5, 6, 8, 10],
}
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_of(name: str) -> int:
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    n = NOTE[m.group(1)] + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)
    return 12 * (int(m.group(3)) + 1) + n


def hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def degree_to_midi(token: str, tonic: int, mode: list[int], octave: int) -> int:
    up = token.count("'")
    down = token.count(",")
    acc = token.count("#") - token.count("b")
    d = int(re.sub(r"[',#b]", "", token)) - 1
    return tonic + 12 * (octave + up - down + d // 7) + mode[d % 7] + acc


# --- score parsing --------------------------------------------------------------

def parse_score(text: str) -> dict:
    song = {"tracks": []}
    track = None
    for raw in text.splitlines():
        line = raw.split(";", 1)[0].rstrip()
        if not line.strip():
            continue
        if line.startswith("[track"):
            track = {"name": line.strip()[7:-1].strip(), "bars": [], "octave": 0, "volume": 1.0,
                     "instrument": "lyre", "stem": "melody"}
            song["tracks"].append(track)
        elif line.lstrip().startswith("|"):
            track["bars"].append(line.split("|", 1)[1].rstrip().rstrip("|").split())
        elif "=" in line:
            k, v = (s.strip() for s in line.split("=", 1))
            target = track if track is not None else song
            target[k] = v
    return song


# --- instruments ------------------------------------------------------------------

def env_adsr(n: int, a: float, d: float, s: float, r: float, held: int) -> np.ndarray:
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), 1.0)
    e = np.where((t >= a) & (t < a + d), 1 - (1 - s) * (t - a) / max(d, 1e-4), e)
    e = np.where(t >= a + d, s, e)
    rel_start = held / SR
    e = np.where(t > rel_start, e * np.exp(-(t - rel_start) / max(r, 1e-4)), e)
    return e.astype(np.float32)


def lyre(freq: float, held: int, rng) -> np.ndarray:
    """Karplus-Strong plucked string, computed one period at a time."""
    n = int(SR * 2.4)
    period = max(2, int(round(SR / freq)))
    buf = rng.uniform(-1, 1, period).astype(np.float32)
    buf = np.convolve(buf, [0.5, 0.5], mode="same")          # softer pluck
    out = np.empty(n, np.float32)
    decay = 0.996 if freq < 400 else 0.993
    pos = 0
    while pos < n:
        take = min(period, n - pos)
        out[pos:pos + take] = buf[:take]
        nxt = 0.5 * (buf + np.roll(buf, -1)) * decay
        buf = nxt.astype(np.float32)
        pos += period
    # A touch of body resonance and a gentle fade when the note is released.
    fade = np.ones(n, np.float32)
    rel = held + int(0.25 * SR)
    if rel < n:
        fade[rel:] = np.exp(-np.arange(n - rel) / (0.18 * SR))
    return out * fade * 0.6


def fm_bass(freq: float, held: int, rng) -> np.ndarray:
    n = held + int(0.3 * SR)
    t = np.arange(n) / SR
    index = 2.4 * np.exp(-t * 6) + 0.4
    mod = np.sin(2 * np.pi * freq * t) * index
    car = np.sin(2 * np.pi * freq * t + mod)
    return (car * env_adsr(n, 0.005, 0.15, 0.6, 0.08, held) * 0.7).astype(np.float32)


def lowpass(x: np.ndarray, width: int) -> np.ndarray:
    if width <= 1:
        return x
    k = np.hanning(width * 2 + 1)
    k /= k.sum()
    return np.convolve(x, k, mode="same").astype(np.float32)


def pad_chord(freqs: list[float], held: int, rng) -> np.ndarray:
    n = held + int(0.9 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n, np.float32)
    for f in freqs:
        for det in (-0.006, 0.0, 0.007):
            ph = rng.uniform(0, 1)
            out += (2 * ((f * (1 + det) * t + ph) % 1.0) - 1).astype(np.float32)
    out = lowpass(out / (len(freqs) * 3), 9)
    return out * env_adsr(n, 0.35, 0.3, 0.7, 0.6, held) * 0.55


def brass(freq: float, held: int, rng) -> np.ndarray:
    n = held + int(0.15 * SR)
    t = np.arange(n) / SR
    saw = (2 * ((freq * t) % 1.0) - 1) + 0.5 * (2 * ((freq * 1.004 * t) % 1.0) - 1)
    bright = lowpass(saw.astype(np.float32), 3)
    return bright * env_adsr(n, 0.02, 0.1, 0.65, 0.07, held) * 0.35


def kit(hit: str, rng) -> np.ndarray:
    if hit == "k":
        n = int(0.35 * SR)
        t = np.arange(n) / SR
        f = 48 + 90 * np.exp(-t * 32)
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
        click = rng.uniform(-1, 1, n) * np.exp(-t * 400) * 0.3
        return (body + click).astype(np.float32) * 0.9
    if hit == "s":
        n = int(0.25 * SR)
        t = np.arange(n) / SR
        noise = rng.uniform(-1, 1, n)
        noise = noise - lowpass(noise.astype(np.float32), 3)
        tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
        return ((noise * np.exp(-t * 18) * 0.6 + tone * 0.4)).astype(np.float32) * 0.6
    if hit == "h":
        n = int(0.06 * SR)
        t = np.arange(n) / SR
        noise = rng.uniform(-1, 1, n).astype(np.float32)
        noise = noise - lowpass(noise, 2)
        return noise * np.exp(-t * 70).astype(np.float32) * 0.25
    if hit == "d":   # frame drum: warm, low, for the surface
        n = int(0.4 * SR)
        t = np.arange(n) / SR
        f = 95 + 40 * np.exp(-t * 25)
        return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)).astype(np.float32) * 0.6
    if hit == "a":   # anvil: inharmonic metal partials
        n = int(0.9 * SR)
        t = np.arange(n) / SR
        out = np.zeros(n)
        for ratio, amp, dec in ((1.0, 1.0, 5), (2.76, 0.6, 7), (5.4, 0.4, 11), (8.93, 0.25, 16)):
            out += amp * np.sin(2 * np.pi * 880 * ratio * t) * np.exp(-t * dec)
        out += rng.uniform(-1, 1, n) * np.exp(-t * 200) * 0.5
        return (out / 2.2).astype(np.float32) * 0.5
    return np.zeros(1, np.float32)


# --- rendering ----------------------------------------------------------------------

def reverb_circular(x: np.ndarray, seconds: float, wet: float, seed: int) -> np.ndarray:
    """Convolution reverb that wraps around the loop, so the tail feeds the start."""
    rng = np.random.default_rng(seed)
    n = len(x)
    ir_len = int(seconds * SR)
    t = np.arange(ir_len) / SR
    ir = rng.standard_normal(ir_len) * np.exp(-t * 3.2 / seconds)
    ir[0] = 0
    ir = lowpass(ir.astype(np.float32), 2)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    size = n
    X = np.fft.rfft(x, size)
    I = np.fft.rfft(ir, size) if ir_len <= size else np.fft.rfft(ir[:size], size)
    tail = np.fft.irfft(X * I, size).astype(np.float32)
    return x * (1 - wet) + tail * wet * 1.2


def render(name: str) -> dict:
    song = parse_score((SCORES / f"{name}.score").read_text())
    bpm = float(song["bpm"])
    meter = int(song.get("meter", 4))
    steps_per_bar = meter * 4
    bars = int(song["bars"])
    swing = float(song.get("swing", 0.0))
    tonic = midi_of(song.get("key", "C4"))
    mode = MODES[song.get("mode", "ionian")]
    step = 60.0 / bpm / 4
    total = int(round(bars * steps_per_bar * step * SR))
    stems: dict[str, np.ndarray] = {}
    rng = np.random.default_rng(sum(map(ord, name)))

    def step_time(i: int) -> int:
        t = i * step
        if swing and i % 2 == 1:
            t += step * swing
        return int(round(t * SR))

    def place(buf, sample, at):
        at %= total
        end = at + len(sample)
        if end <= total:
            buf[at:end] += sample
        else:                                       # wrap into the loop start
            buf[at:] += sample[:total - at]
            rest = sample[total - at:]
            buf[:len(rest)] += rest[:total]

    for tr in song["tracks"]:
        buf = stems.setdefault(tr["stem"], np.zeros(total, np.float32))
        inst = tr["instrument"]
        vol = float(tr.get("volume", 1.0))
        octave = int(tr.get("octave", 0))
        for b in range(bars):
            tokens = tr["bars"][b % len(tr["bars"])]
            if len(tokens) != steps_per_bar:
                raise ValueError(f"{name}/{tr['name']} bar {b % len(tr['bars']) + 1}: "
                                 f"{len(tokens)} steps, expected {steps_per_bar}")
            for s, tok in enumerate(tokens):
                if tok in (".", "-"):
                    continue
                hold = 1
                while s + hold < steps_per_bar and tokens[s + hold] == "-":
                    hold += 1
                gi = b * steps_per_bar + s
                at = step_time(gi)
                held = int(hold * step * SR * 0.95)
                if inst == "kit":
                    for hit in tok:
                        place(buf, kit(hit, rng) * vol, at)
                    continue
                midi = degree_to_midi(tok, tonic, mode, octave)
                if inst == "lyre":
                    sample = lyre(hz(midi), held, rng)
                elif inst == "bass":
                    sample = fm_bass(hz(midi), held, rng)
                elif inst == "brass":
                    sample = brass(hz(midi), held, rng)
                elif inst == "pad":
                    d = int(re.sub(r"[',#b]", "", tok)) - 1
                    chord = [degree_to_midi(str(d + 1 + k), tonic, mode, octave) for k in (0, 2, 4)]
                    sample = pad_chord([hz(m) for m in chord], held, rng)
                else:
                    raise ValueError(f"unknown instrument {inst}")
                place(buf, sample * vol, at)

    # Shared gain: stems keep their balance when layered.
    for k in stems:
        wet = {"melody": 0.32, "harmony": 0.28, "percussion": 0.12}.get(k, 0.2)
        stems[k] = reverb_circular(stems[k], 2.2, wet, 7)
    # One gain for every stem (keeps their balance) with headroom for the full mix.
    peak = max(np.max(np.abs(sum(stems.values()))), 1e-6)
    gain = 0.82 / peak
    OUT_MUSIC.mkdir(parents=True, exist_ok=True)
    stem_files = []
    for k, x in stems.items():
        y = np.clip(x * gain, -0.98, 0.98)
        path = OUT_MUSIC / f"{name}_{k}.ogg"
        write_ogg(path, y)
        stem_files.append(f"res://game/audio/music/{path.name}")
    beat_map = {
        "song": name,
        "bpm": bpm,
        "beats_per_bar": meter,
        "offset": 0.0,
        "bars": bars,
        "loop_seconds": total / SR,
        "loop_samples": total,
        "swing": swing,
        "stems": stem_files,
    }
    (OUT_MUSIC / f"{name}.json").write_text(json.dumps(beat_map, indent=2))
    print(f"music: {name} ({bars} bars @ {bpm:g} bpm, {total / SR:.2f}s, stems: {', '.join(stems)})")
    return beat_map


def write_wav(path: Path, x: np.ndarray) -> None:
    pcm = np.clip(x * 32767, -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def write_ogg(path: Path, x: np.ndarray) -> None:
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        write_wav(Path(tmp.name), x)
        # bitexact: no random stream serials or version tags, so rebuilds are byte-identical.
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-fflags", "+bitexact",
                        "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "5", str(path)], check=True)


def lyre_notes() -> None:
    """The five lyre notes Orpheus plays on the d-pad (D dorian pentatonic-ish)."""
    OUT_SFX.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(11)
    names = {"up": "A4", "right": "F4", "down": "D4", "left": "C5", "center": "D5"}
    for k, note in names.items():
        x = lyre(hz(midi_of(note)), int(0.6 * SR), rng)[: int(1.6 * SR)]
        x = reverb_circular(np.pad(x, (0, int(0.8 * SR))), 1.2, 0.25, 3)
        write_wav(OUT_SFX / f"lyre_{k}.wav", x / (np.max(np.abs(x)) + 1e-9) * 0.8)
    print("sfx: lyre notes")


def combat_sfx() -> None:
    """Combat sounds, built from the drum kit's own pieces so they sit in the mix.
    An on-beat hit adds a bright ping on top of the thud: you HEAR the bonus."""
    rng = np.random.default_rng(23)

    def t_(sec):
        return np.arange(int(sec * SR)) / SR

    def noise(sec, decay, hp=True):
        n = rng.uniform(-1, 1, int(sec * SR)).astype(np.float32)
        if hp:
            n = n - lowpass(n, 3)
        return n * np.exp(-t_(sec) * decay).astype(np.float32)

    def mixdown(*parts):
        n = max(len(p) for p in parts)
        out = np.zeros(n, np.float32)
        for p in parts:
            out[: len(p)] += p
        return out / (np.max(np.abs(out)) + 1e-9) * 0.8

    t = t_(0.18)
    whoosh = noise(0.18, 0, False) * np.sin(np.pi * t / 0.18).astype(np.float32) ** 2
    whoosh = lowpass(whoosh, 6) * 0.5
    thud = mixdown(kit("k", rng)[: int(0.2 * SR)], noise(0.12, 40) * 0.5)
    ping = kit("a", rng)[: int(0.5 * SR)]
    t = t_(0.5)
    shimmer = (np.sin(2 * np.pi * 1760 * t) + 0.5 * np.sin(2 * np.pi * 2637 * t)) * np.exp(-t * 6)
    t = t_(0.4)
    fall = np.sin(2 * np.pi * np.cumsum(300 * np.exp(-t * 6)) / SR) * np.exp(-t * 7)
    sounds = {
        "club_swing": whoosh,
        "club_hit": thud,
        "club_hit_beat": mixdown(thud, ping * 0.7),
        "parry": mixdown(ping[: int(0.25 * SR)] * 0.6, noise(0.1, 50) * 0.4),
        "parry_perfect": mixdown(ping, shimmer.astype(np.float32) * 0.5),
        "hurt": mixdown(kit("s", rng), kit("d", rng) * 0.8),
        "enemy_die": mixdown(fall.astype(np.float32), noise(0.3, 12) * 0.4),
        "spit": lowpass(noise(0.15, 25, False), 4) * 0.6,
    }
    for k, x in sounds.items():
        write_wav(OUT_SFX / f"{k}.wav", x / (np.max(np.abs(x)) + 1e-9) * 0.7)
    print("sfx: combat")


def main(names: list[str]) -> None:
    targets = names or [p.stem for p in sorted(SCORES.glob("*.score"))]
    for n in targets:
        render(n)
    lyre_notes()
    combat_sfx()


if __name__ == "__main__":
    main(sys.argv[1:])

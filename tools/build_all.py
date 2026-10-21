"""Regenerate every generated asset from content/ (deterministic).

    python3 tools/build_all.py
Then let Godot pick up the changes:  godot --headless --import
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
STEPS = ["build_tiles.py", "build_fx.py", "build_backgrounds.py", "build_props.py", "build_character.py",
         "build_font.py", "build_audio.py"]

if __name__ == "__main__":
    for step in STEPS:
        print(f"== {step}")
        subprocess.run([sys.executable, str(HERE / step)], check=True, cwd=HERE)
    print("all assets built")

"""The Python room parser must produce the golden summary (the GDScript parser
is held to the same file by tests/unit/test_room_data.gd)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from rooms import load_json, parse_room, summary  # noqa: E402

FIX = ROOT / "tests" / "fixtures" / "rooms"


def test_golden_room_summary():
    room = parse_room((FIX / "sample.room").read_text())
    got = summary(room, load_json("legend")["entities"])
    expected = json.loads((FIX / "sample.expected.json").read_text())
    assert got == expected


def test_ragged_rows_are_reported():
    room = parse_room("id = r\n[map]\n....\n...\n")
    assert room.errors and "expected 4" in room.errors[0]


def test_every_real_room_parses_cleanly():
    for path in sorted((ROOT / "content" / "rooms").glob("*.room")):
        room = parse_room(path.read_text())
        assert room.errors == [], (path.name, room.errors)
        assert room.id == path.stem

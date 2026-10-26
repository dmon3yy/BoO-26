"""Tests for tools/validate_world.py using small throwaway worlds."""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from rooms import CONTENT  # noqa: E402
from validate_world import validate  # noqa: E402

W, H = 30, 17


def blank(floor_row: int = 14) -> list[list[str]]:
    g = [["."] * W for _ in range(H)]
    for y in range(floor_row, H):
        g[y] = ["#"] * W
    for y in range(H):
        g[y][0] = g[y][W - 1] = "#"
    return g


def dig_well(g):
    """A one-way well: climb a step onto a tall wall, drop in, walls too high to jump out."""
    for y in (12, 13):
        g[y][9] = g[y][10] = "#"          # step (stand row 11)
    for y in range(10, 16):
        g[y][13] = "#"                    # entry wall, top stand row 9
        g[y][24] = "#"                    # far wall
    for x in range(14, 24):
        g[14][x] = g[15][x] = "."         # well floor at row 16 (stand row 15)


def make_world(tmp: Path, rooms: dict, legend_extra: dict | None = None) -> Path:
    """rooms: id -> (cell_xy, grid, legend_lines). Copies the real legend/movement/themes."""
    for name in ("legend", "movement", "themes"):
        shutil.copy(CONTENT / f"{name}.json", tmp / f"{name}.json")
    (tmp / "rooms").mkdir()
    world = {"cell": [W, H], "rooms": {}}
    for rid, (cell, grid, legend) in rooms.items():
        world["rooms"][rid] = list(cell)
        text = f"id = {rid}\ntheme = arcadia_winter\n\n"
        if legend:
            text += "[legend]\n" + "\n".join(legend) + "\n\n"
        text += "[map]\n" + "\n".join("".join(r) for r in grid) + "\n"
        (tmp / "rooms" / f"{rid}.room").write_text(text)
    (tmp / "world.json").write_text(json.dumps(world))
    return tmp


def test_real_world_is_valid():
    rep = validate()
    assert rep.ok(), rep.errors


def test_simple_room_ok(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][10] = "H"
    g[13][20] = "o"
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert rep.ok(), rep.errors


def test_ledge_four_tiles_up_is_unreachable(tmp_path):
    """Regression: the first Erebos ledge was 4 tiles above the floor (jump is 3)."""
    g = blank()
    g[13][3] = "P"
    g[13][5] = "H"
    for x in range(10, 14):
        g[9][x] = "="          # stand row 8: four rows above the floor stand (13 -> 9 is +4)
    g[8][11] = "o"
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert any("olive" in e and "unreachable" in e for e in rep.errors), rep.errors


def test_ledge_three_tiles_up_is_reachable(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][5] = "H"
    for x in range(10, 14):
        g[10][x] = "="
    g[9][11] = "o"
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert rep.ok(), rep.errors


def test_gate_opens_after_pickup(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][4] = "H"
    g[13][8] = "k"              # pickup: sandals
    g[13][15] = "g"             # gate needing sandals
    g[13][22] = "o"             # only reachable through the gate
    for y in range(0, 14):
        if y not in (11, 12, 13):
            g[y][15] = "#"      # wall with a gate-sized gap
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, ["k = pickup ability=sandals", "g = gate needs=sandals"])}))
    assert rep.ok(), rep.errors
    assert any("gains sandals" in i for i in rep.info)


def test_item_behind_its_own_gate_is_flagged(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][4] = "H"
    g[13][22] = "k"             # the key is behind the door it opens
    g[13][15] = "g"
    for y in range(0, 14):
        if y not in (11, 12, 13):
            g[y][15] = "#"
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, ["k = pickup ability=sandals", "g = gate needs=sandals"])}))
    assert not rep.ok()
    assert any("unreachable" in e for e in rep.errors)


def test_pit_without_escape_is_a_softlock(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][4] = "H"
    dig_well(g)
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert any("softlock" in e for e in rep.errors), rep.errors


def test_pit_with_spikes_is_not_a_softlock(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][4] = "H"
    dig_well(g)
    g[15][18] = "^"             # death returns you to the Hearth
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert not any("softlock" in e for e in rep.errors), rep.errors


def test_opening_onto_nothing_is_an_error(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[13][4] = "H"
    for y in range(10, 14):
        g[y][W - 1] = "."       # right edge open, no neighbour room
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert any("opens onto nothing" in e for e in rep.errors)


def test_neighbour_openings_must_line_up(tmp_path):
    a = blank()
    a[13][3] = "P"
    a[13][4] = "H"
    for y in range(10, 14):
        a[y][W - 1] = "."
    b = blank()
    b[13][20] = "H"             # b's left wall stays closed
    rep = validate(make_world(tmp_path, {"a": ((0, 0), a, []), "b": ((1, 0), b, [])}))
    assert any("runs into a wall" in e for e in rep.errors)


def test_rooms_join_when_openings_match(tmp_path):
    a = blank()
    a[13][3] = "P"
    a[13][4] = "H"
    b = blank()
    b[13][20] = "o"
    for y in range(0, 14):
        a[y][W - 1] = "."
        b[y][0] = "."
    rep = validate(make_world(tmp_path, {"a": ((0, 0), a, []), "b": ((1, 0), b, [])}))
    assert rep.ok(), rep.errors


@pytest.mark.parametrize("bad", ["@", "?"])
def test_unknown_character(tmp_path, bad):
    g = blank()
    g[13][3] = "P"
    g[5][5] = bad
    rep = validate(make_world(tmp_path, {"r": ((0, 0), g, [])}))
    assert any("unknown character" in e for e in rep.errors)


def test_floating_brazier_is_an_error(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[10][8] = "T"              # three rows above the floor
    make_world(tmp_path, {"r": ((0, 0), g, [])})
    shutil.copy(CONTENT / "props.json", tmp_path / "props.json")
    rep = validate(tmp_path)
    assert any("torch_8_10: floating" in e for e in rep.errors), rep.errors


def test_brazier_on_a_ledge_is_fine(tmp_path):
    g = blank()
    g[13][3] = "P"
    g[11][7] = g[11][8] = g[11][9] = "="
    g[10][8] = "T"
    make_world(tmp_path, {"r": ((0, 0), g, [])})
    shutil.copy(CONTENT / "props.json", tmp_path / "props.json")
    rep = validate(tmp_path)
    assert not any("floating" in e for e in rep.errors), rep.errors

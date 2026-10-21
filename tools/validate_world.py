"""Check the whole world: rooms parse, edges line up, everything is reachable,
the progression can be completed, and nothing can trap the player.

Run:  python3 tools/validate_world.py          (exit code 1 on errors)

Reachability uses a tile-level movement model built from the same limits as
the real controller (content/movement.json -> "limits"); GUT tests check the
controller really achieves those limits, so "reachable" here means reachable
in the game.

Movement model (one tile = 16 px, Orpheus is two tiles tall):
  * A *stand* is an open cell with floor (solid, ledge or closed gate) below
    and headroom above.
  * From a stand you can reach another stand up to `jump_height_tiles` higher
    and `jump_gap_tiles` across; falling buys one extra tile of reach for every
    two tiles dropped. The path must be clear (approximate corridor test).
  * Standing on a ledge you can drop through it.
  * Touching a hazard ('^', molten '~') is death, which returns you to a Hearth,
    so a hazard counts as an escape for the softlock check.

Gates and pickups come from the legend:
  S = song_seal song=zeus          -> blocks until ability "song:zeus"
  k = pickup ability=sandals       -> grants "sandals"
  g = gate needs=sandals           -> blocks until "sandals"
"""
from __future__ import annotations

import sys
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rooms import CONTENT, SOLID, Room, load_json, load_room  # noqa: E402

GATE_HEIGHT = 3         # a gate blocks its own cell and the two above
REACH_ABOVE = 4         # entities up to 4 rows above a stand can be touched


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    info: list[str] = field(default_factory=list)

    def ok(self) -> bool:
        return not self.errors


class World:
    def __init__(self, base: Path = CONTENT):
        self.base = base
        self.world = load_json("world", base)
        self.legend = load_json("legend", base)
        self.movement = load_json("movement", base)
        self.themes = load_json("themes", base)
        self.cw, self.ch = self.world["cell"]
        self.rooms: dict[str, Room] = {}
        self.origin: dict[str, tuple[int, int]] = {}
        self.grid: dict[tuple[int, int], tuple[str, str]] = {}   # world cell -> (char, room)
        self.entities: list[dict] = []
        for rid, at in self.world["rooms"].items():
            room = load_room(rid, base)
            self.rooms[rid] = room
            ox, oy = at[0] * self.cw, at[1] * self.ch
            self.origin[rid] = (ox, oy)
            for y, row in enumerate(room.map_rows):
                for x, c in enumerate(row):
                    self.grid[(ox + x, oy + y)] = (c, rid)
            for kind, x, y, params in room.entities(self.legend["entities"]):
                self.entities.append({"kind": kind, "room": rid, "x": ox + x, "y": oy + y, "params": params,
                                      "id": f"{rid}:{kind}_{x}_{y}"})
        lim = self.movement["limits"]
        self.H = int(lim["jump_height_tiles"])
        self.G = int(lim["jump_gap_tiles"])

    # --- cell queries ---------------------------------------------------------

    def char(self, c: tuple[int, int]) -> str:
        return self.grid.get(c, ("#", ""))[0]   # outside every room = solid

    def gate_cells(self, abilities: frozenset) -> set[tuple[int, int]]:
        cells = set()
        for e in self.entities:
            need = self.needs(e)
            if need and need not in abilities:
                for dy in range(GATE_HEIGHT):
                    cells.add((e["x"], e["y"] - dy))
        return cells

    @staticmethod
    def needs(e: dict) -> str:
        if e["kind"] == "song_seal":
            return "song:" + e["params"].get("song", "")
        return e["params"].get("needs", "") if e["kind"] == "gate" else ""

    def blocked(self, c, gates) -> bool:
        return self.char(c) in SOLID or c in gates

    def hazard(self, c) -> bool:
        return self.char(c) in ("^", "~")

    def is_stand(self, c, gates) -> bool:
        x, y = c
        if c not in self.grid or self.blocked(c, gates) or self.hazard(c):
            return False
        if self.blocked((x, y - 1), gates):
            return False
        below = (x, y + 1)
        return self.blocked(below, gates) or self.char(below) == "="

    # --- movement ---------------------------------------------------------------

    def _clear(self, cells, gates) -> bool:
        return all(not self.blocked(c, gates) for c in cells)

    def moves(self, s, gates):
        """Stands reachable in one jump/walk/fall from stand s (approximate arc test)."""
        x, y = s
        out = []
        for dy in range(-self.H, 40):
            y2 = y + dy
            reach = self.G + max(0, dy) // 2
            for dx in range(-reach, reach + 1):
                t = (x + dx, y2)
                if t == s or not self.is_stand(t, gates):
                    continue
                step = 1 if dx >= 0 else -1
                if dy <= 0:
                    # Rise in place to the target's head height, then cross above both.
                    rise = [(x, r) for r in range(y2 - 1, y + 1)]
                    top = min(y, y2)
                    cross = [(cx, r) for cx in range(x + step, x + dx + step, step) for r in (top - 1, top)] \
                        if dx else []
                    if self._clear(rise + cross, gates):
                        out.append(t)
                else:
                    # Move across at the start height, then fall into the target column.
                    cross = [(cx, r) for cx in range(x + step, x + dx + step, step) for r in (y - 1, y)] \
                        if dx else []
                    fall = [(x + dx, r) for r in range(y, y2 + 1)]
                    through_ledge = dx == 0 and self.char((x, y + 1)) == "="
                    path = cross + (fall if dx else [(x, r) for r in range(y + 2, y2 + 1)])
                    if (dx or through_ledge) and self._clear(path, gates):
                        out.append(t)
        return out

    def touches_hazard(self, s, gates) -> bool:
        x, y = s
        return any(self.hazard((x + dx, y + dy)) for dx in (-1, 0, 1) for dy in (0, 1))

    def reachable(self, starts, abilities: frozenset):
        gates = self.gate_cells(abilities)
        seen = set()
        q = deque(s for s in starts if self.is_stand(s, gates))
        seen.update(q)
        graph = {}
        while q:
            s = q.popleft()
            nxt = self.moves(s, gates)
            graph[s] = nxt
            for t in nxt:
                if t not in seen:
                    seen.add(t)
                    q.append(t)
        return seen, graph, gates

    def touched(self, e, stands) -> bool:
        return any((e["x"], e["y"] + k) in stands for k in range(REACH_ABOVE + 1))


def check_rooms(w: World, rep: Report) -> None:
    known = set(w.legend["tiles"]) | set(w.legend["entities"])
    for rid, room in w.rooms.items():
        for e in room.errors:
            rep.errors.append(f"{rid}: {e}")
        if room.id != rid:
            rep.errors.append(f"{rid}: header id is {room.id!r}")
        if room.width % w.cw or room.height % w.ch:
            rep.errors.append(f"{rid}: size {room.width}x{room.height} is not a multiple of {w.cw}x{w.ch}")
        if room.header.get("theme") not in w.themes:
            rep.errors.append(f"{rid}: unknown theme {room.header.get('theme')!r}")
        for y, row in enumerate(room.map_rows):
            for x, c in enumerate(row):
                if c not in known and c not in room.legend:
                    rep.errors.append(f"{rid}: unknown character {c!r} at ({x},{y})")


def check_edges(w: World, rep: Report) -> None:
    """Openings must meet openings; nothing may open onto the void (except the sky)."""
    for rid, room in w.rooms.items():
        ox, oy = w.origin[rid]
        sides = {
            "left": [((ox, oy + y), (ox - 1, oy + y)) for y in range(room.height)],
            "right": [((ox + room.width - 1, oy + y), (ox + room.width, oy + y)) for y in range(room.height)],
            "bottom": [((ox + x, oy + room.height - 1), (ox + x, oy + room.height)) for x in range(room.width)],
        }
        for side, pairs in sides.items():
            for inside, outside in pairs:
                if w.char(inside) in SOLID:
                    continue
                if outside not in w.grid:
                    rep.errors.append(f"{rid}: {side} edge opens onto nothing at world cell {inside}")
                elif w.char(outside) in SOLID:
                    other = w.grid[outside][1]
                    rep.errors.append(f"{rid}: {side} edge opening at {inside} runs into a wall in {other}")


def solve(w: World, rep: Report) -> None:
    starts = [(e["x"], e["y"]) for e in w.entities if e["kind"] == "player_start"]
    abilities: frozenset = frozenset()
    rounds = []
    while True:
        stands, graph, gates = w.reachable(starts, abilities)
        gained = set()
        for e in w.entities:
            if e["kind"] == "pickup" and w.touched(e, stands):
                ab = e["params"].get("ability", "")
                if ab and ab not in abilities:
                    gained.add(ab)
        if not gained:
            break
        rounds.append(sorted(gained))
        abilities = abilities | gained
    for i, r in enumerate(rounds, 1):
        rep.info.append(f"progression round {i}: gains {', '.join(r)}")

    # Everything that matters must be reachable with the final abilities.
    for e in w.entities:
        if e["kind"] in ("player_start", "torch", "lantern", "column", "broken_column", "olive_tree", "furnace"):
            continue
        need = w.needs(e)
        if need:
            if need not in abilities:
                rep.warnings.append(f"{e['id']}: needs {need}, which is not obtainable yet")
            continue
        if not w.touched(e, stands):
            rep.errors.append(f"{e['id']}: unreachable")
    visited_rooms = {w.grid[s][1] for s in stands}
    for rid in w.rooms:
        if rid not in visited_rooms:
            rep.errors.append(f"{rid}: no reachable floor")

    # Softlocks: from every reachable stand you must be able to get to a
    # Hearth, or to a hazard (death returns you to a Hearth).
    safe = {(e["x"], e["y"]) for e in w.entities if e["kind"] == "hearth"}
    safe = {s for s in stands if s in safe or w.touches_hazard(s, gates)}
    reverse: dict = {}
    for s, nxt in graph.items():
        for t in nxt:
            reverse.setdefault(t, []).append(s)
    can_escape = set(safe)
    q = deque(safe)
    while q:
        t = q.popleft()
        for s in reverse.get(t, []):
            if s not in can_escape:
                can_escape.add(s)
                q.append(s)
    trapped = sorted(stands - can_escape)
    if trapped:
        rooms = sorted({w.grid[s][1] for s in trapped})
        rep.errors.append(f"softlock: {len(trapped)} reachable spots cannot get back to a Hearth "
                          f"(rooms: {', '.join(rooms)}; first at world cell {trapped[0]})")
    rep.info.append(f"reachable stands: {len(stands)} across {len(visited_rooms)} rooms")


def validate(base: Path = CONTENT) -> Report:
    rep = Report()
    w = World(base)
    check_rooms(w, rep)
    if rep.errors:
        return rep
    check_edges(w, rep)
    solve(w, rep)
    return rep


def main() -> int:
    rep = validate()
    for line in rep.info:
        print("  ", line)
    for line in rep.warnings:
        print("WARN", line)
    for line in rep.errors:
        print("ERROR", line)
    print("world OK" if rep.ok() else f"{len(rep.errors)} error(s)")
    return 0 if rep.ok() else 1


if __name__ == "__main__":
    sys.exit(main())

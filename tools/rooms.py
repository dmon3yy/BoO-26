"""Python twin of game/world/room_data.gd — same grammar, same results.

    ; comment
    key = value          header (id, theme, name, ...)
    [legend]
    X = kind key=value   room-specific entity characters
    [map]                playable layer, one character per 16px tile
    [back]               optional back-wall layer, same size as [map]
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
SOLID = {"#", "%"}


@dataclass
class Room:
    id: str = ""
    header: dict = field(default_factory=dict)
    legend: dict = field(default_factory=dict)       # char -> {"kind":..., "params": {...}}
    map_rows: list[str] = field(default_factory=list)
    back_rows: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def width(self) -> int:
        return len(self.map_rows[0]) if self.map_rows else 0

    @property
    def height(self) -> int:
        return len(self.map_rows)

    def char_at(self, x: int, y: int) -> str:
        if 0 <= y < self.height and 0 <= x < self.width:
            return self.map_rows[y][x]
        return ""

    def entities(self, global_legend: dict) -> list[tuple[str, int, int, dict]]:
        """(kind, x, y, params) for every entity character on the map."""
        out = []
        for y, row in enumerate(self.map_rows):
            for x, ch in enumerate(row):
                if ch in self.legend:
                    out.append((self.legend[ch]["kind"], x, y, self.legend[ch]["params"]))
                elif ch in global_legend:
                    out.append((global_legend[ch], x, y, {}))
        return out


def parse_legend_value(value: str) -> dict:
    parts = value.split()
    params = {}
    for p in parts[1:]:
        kv = p.split("=")
        if len(kv) == 2:
            params[kv[0]] = kv[1]
    return {"kind": parts[0] if parts else "", "params": params}


def parse_room(text: str) -> Room:
    room = Room()
    section = ""
    for raw in text.split("\n"):
        line = raw.rstrip("\r")
        stripped = line.strip()
        if line.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            continue
        if section in ("map", "back"):
            if stripped == "":
                continue
            (room.map_rows if section == "map" else room.back_rows).append(line)
            continue
        if stripped == "" or stripped.startswith(";"):
            continue
        if "=" not in stripped:
            room.errors.append(f"cannot read line: {stripped}")
            continue
        key, value = stripped.split("=", 1)
        key, value = key.strip(), value.strip()
        if section == "legend":
            room.legend[key] = parse_legend_value(value)
        else:
            room.header[key] = value
    room.id = room.header.get("id", "")
    for i, row in enumerate(room.map_rows):
        if len(row) != room.width:
            room.errors.append(f"map row {i} is {len(row)} wide, expected {room.width}")
    if room.back_rows and len(room.back_rows) != room.height:
        room.errors.append(f"[back] has {len(room.back_rows)} rows, [map] has {room.height}")
    return room


def load_room(room_id: str, base: Path = CONTENT) -> Room:
    return parse_room((base / "rooms" / f"{room_id}.room").read_text())


def load_json(name: str, base: Path = CONTENT) -> dict:
    return json.loads((base / f"{name}.json").read_text())


def summary(room: Room, global_legend: dict) -> dict:
    """Canonical summary used to check both parsers agree (see tests)."""
    return {
        "id": room.id,
        "width": room.width,
        "height": room.height,
        "header": room.header,
        "legend": room.legend,
        "entities": [[k, x, y] for (k, x, y, _) in room.entities(global_legend)],
        "errors": room.errors,
    }

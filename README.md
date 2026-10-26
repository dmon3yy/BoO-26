# Ballad of Orpheus

*A spiritual successor to The Battle of Olympus (NES, 1988/89), sung in an industrial underworld.*

Orpheus crosses a frozen Greece earning the gods' help, one verse of his song at a time, then follows Eurydice down to Erebos, the company town behind the Wall. It's a fully seamless pixel-art Metroidvania with dynamic lighting, rhythm-infused combat, a Souls-lite bite and an ending you earn.

**Status:** Milestone 3, the vertical slice: Arcadia from a cold start to the road east, with Zeus, Eurydice, Hermes narrating, a journal, olives you drop when you die, the crouch strike and the Colchis Bull. How each milestone works: [M0](docs/learn/M0.md), [M1](docs/learn/M1.md), [M2](docs/learn/M2.md), [M3](docs/learn/M3.md).

## Play
- **Web:** the GitHub Pages build from CI (the threaded build; `lite/` is single-threaded). Add `?lab` to open the Beat Lab.
- **Desktop:** open the project in **Godot 4.7.2** and press Play.

| Key | Action |
|---|---|
| Arrows / WASD | Move |
| Z / Space | Jump (hold for height) |
| Down + Jump | Drop through a ledge |
| F2 | Next test room |
| F3 | Beat Lab (rhythm calibration) |
| F4 | Test dialogue |

Gamepads work too.

## Build from source

```bash
pip install -r tools/requirements.txt   # numpy, Pillow, pytest (+ ffmpeg on PATH)
python3 tools/build_all.py              # regenerate art, font and music from content/
python3 tools/validate_world.py         # check every room is reachable and nothing traps you
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit
```

## Layout

| Path | What lives there |
|---|---|
| `content/` | The source of truth, all plain text: rooms, palettes, rigs, scores, dialogue, movement |
| `tools/` | Python generators: tiles, props, backgrounds, characters, font, synthesizer; plus the world validator |
| `game/` | Godot scripts and scenes, plus generated `art/` and `audio/` |
| `tests/` | GUT engine tests, pytest content tests, web smoke test |
| `docs/` | [Design doc](docs/GDD.md) · [Style guide](docs/STYLE_GUIDE.md) · [IP rules](docs/IP_RULES.md) · [Learning notes](docs/learn/) |

## Credits and licence
All art, music and writing are original and generated in this repository. Built with [Godot](https://godotengine.org) (MIT), [GUT](https://github.com/bitwes/Gut) (MIT) and [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) (MIT). *The Battle of Olympus* and *Hadestown* belong to their owners; this project only alludes to them (see [docs/IP_RULES.md](docs/IP_RULES.md)).

Licensed under the GNU AGPL-3.0.

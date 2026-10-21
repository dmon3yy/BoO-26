class_name Autotiler
extends RefCounted
## Chooses the right tile image for each solid cell from its eight neighbours.
##
## Matches tools/build_tiles.py exactly: bit set = neighbour is solid,
## corners only count when both touching sides are solid (47 shapes), and a
## 4x4 grid of "macro variants" keeps texture detail flowing between tiles.

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128
const MACRO := 4

const OFFSETS := [
	[N, Vector2i(0, -1)], [NE, Vector2i(1, -1)], [E, Vector2i(1, 0)], [SE, Vector2i(1, 1)],
	[S, Vector2i(0, 1)], [SW, Vector2i(-1, 1)], [W, Vector2i(-1, 0)], [NW, Vector2i(-1, -1)],
]


static func canonical(mask: int) -> int:
	var m := mask
	if not (m & N and m & E):
		m &= ~NE
	if not (m & S and m & E):
		m &= ~SE
	if not (m & S and m & W):
		m &= ~SW
	if not (m & N and m & W):
		m &= ~NW
	return m


## `is_solid` takes a Vector2i and returns bool. Out-of-room cells should be
## answered by clamping to the edge, so terrain flows into the next room.
static func mask_at(cell: Vector2i, is_solid: Callable) -> int:
	var m := 0
	for o in OFFSETS:
		if is_solid.call(cell + o[1]):
			m |= o[0]
	return canonical(m)


static func atlas_coords(mask: int, world_cell: Vector2i) -> Vector2i:
	var v := posmod(world_cell.x, MACRO) + MACRO * posmod(world_cell.y, MACRO)
	return Vector2i((v % MACRO) * 16 + mask % 16, (v / MACRO) * 16 + mask / 16)

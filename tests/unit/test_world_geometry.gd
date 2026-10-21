extends GutTest
## Autotiling and surface tracing.


func _grid(rows: Array) -> Callable:
	return func(c: Vector2i) -> bool:
		return c.y >= 0 and c.y < rows.size() and c.x >= 0 and c.x < rows[c.y].length() \
			and rows[c.y][c.x] == "#"


func test_47_canonical_shapes() -> void:
	var seen := {}
	for m in 256:
		seen[Autotiler.canonical(m)] = true
	assert_eq(seen.size(), 47)


func test_corner_ignored_without_both_sides() -> void:
	assert_eq(Autotiler.canonical(Autotiler.NE), 0)
	var full := Autotiler.N | Autotiler.E | Autotiler.NE
	assert_eq(Autotiler.canonical(full), full)


func test_macro_variant_layout_matches_python() -> void:
	# variant 5 = (1, 1) in the 4x4 block grid; mask 255 -> cell (15, 15) inside it
	assert_eq(Autotiler.atlas_coords(255, Vector2i(1, 1)), Vector2i(16 + 15, 16 + 15))
	assert_eq(Autotiler.atlas_coords(0, Vector2i(4, 4)), Vector2i(0, 0))


func test_closed_block_is_one_loop() -> void:
	var rows := ["....", ".##.", ".##.", "...."]
	var surf := TileOutline.trace(Vector2i(4, 4), _grid(rows), 16)
	assert_eq(surf.size(), 1)
	assert_true(surf[0]["closed"])
	assert_eq(surf[0]["points"].size(), 4)


func test_floor_touching_edges_is_one_open_chain() -> void:
	# Regression: open surfaces used to be split and short pieces dropped,
	# which let Orpheus fall through the Temple Steps floor.
	var rows := ["....", "....", "####"]
	var surf := TileOutline.trace(Vector2i(4, 3), _grid(rows), 16)
	assert_eq(surf.size(), 1)
	assert_false(surf[0]["closed"])
	var pts: PackedVector2Array = surf[0]["points"]
	assert_eq(pts[0], Vector2(0, 32))
	assert_eq(pts[pts.size() - 1], Vector2(64, 32))


func test_every_exposed_side_is_covered() -> void:
	var rows := ["#..#....", "#..#.##.", "#......#", "########"]
	var size := Vector2i(8, 4)
	var solid := _grid(rows)
	var exposed := 0
	for y in size.y:
		for x in size.x:
			if not solid.call(Vector2i(x, y)):
				continue
			for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var n: Vector2i = Vector2i(x, y) + d
				var inside := n.x >= 0 and n.y >= 0 and n.x < size.x and n.y < size.y
				if inside and not solid.call(n):
					exposed += 1
	var length := 0.0
	for s in TileOutline.trace(size, solid, 1):
		var pts: PackedVector2Array = s["points"]
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
		if s["closed"]:
			length += pts[pts.size() - 1].distance_to(pts[0])
	assert_eq(int(length), exposed)

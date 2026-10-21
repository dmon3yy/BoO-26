class_name TileOutline
extends RefCounted
## Traces the surface of solid tiles into polylines.
##
## Used twice per room: as collision (one seamless shape per surface, so the
## player never snags on tile seams) and as light occluders (shadows).
## Walking along any polyline, the solid side is always on the right.
##
## Surfaces that run off the edge of the room are *open* chains (the next
## room continues them); surfaces fully inside the room are *closed* loops.


## `solid` is a Callable(Vector2i) -> bool; `size` is the grid size in tiles.
## Cells outside the grid count as solid, so no surface appears at room seams.
## Returns an array of {"points": PackedVector2Array, "closed": bool}.
static func trace(size: Vector2i, solid: Callable, tile: int = 16) -> Array[Dictionary]:
	var is_solid := func(c: Vector2i) -> bool:
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
			return true
		return solid.call(c)
	var edges := {}        # start vertex -> Array of end vertices
	var indegree := {}
	var add := func(a: Vector2i, b: Vector2i) -> void:
		if not edges.has(a):
			edges[a] = []
		edges[a].append(b)
		indegree[b] = indegree.get(b, 0) + 1
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not is_solid.call(c):
				continue
			if not is_solid.call(c + Vector2i(0, -1)):
				add.call(Vector2i(x, y), Vector2i(x + 1, y))
			if not is_solid.call(c + Vector2i(1, 0)):
				add.call(Vector2i(x + 1, y), Vector2i(x + 1, y + 1))
			if not is_solid.call(c + Vector2i(0, 1)):
				add.call(Vector2i(x + 1, y + 1), Vector2i(x, y + 1))
			if not is_solid.call(c + Vector2i(-1, 0)):
				add.call(Vector2i(x, y + 1), Vector2i(x, y))

	var result: Array[Dictionary] = []
	# Open chains first: they start where a vertex has outgoing but no incoming edges.
	var starts: Array = []
	for v in edges:
		if indegree.get(v, 0) == 0:
			starts.append(v)
	for s in starts:
		while edges.has(s):
			result.append(_walk(edges, s, tile))
	# Everything left is a closed loop.
	while not edges.is_empty():
		result.append(_walk(edges, edges.keys()[0], tile))
	return result


static func _walk(edges: Dictionary, start: Vector2i, tile: int) -> Dictionary:
	var pts: Array[Vector2i] = [start]
	var at := start
	var prev_dir := Vector2i.ZERO
	var closed := false
	while edges.has(at):
		var outs: Array = edges[at]
		var next: Vector2i = _choose(outs, at, prev_dir)
		outs.erase(next)
		if outs.is_empty():
			edges.erase(at)
		prev_dir = next - at
		at = next
		if at == start:
			closed = true
			break
		pts.append(at)
	var simple := _simplify(pts, closed)
	var poly := PackedVector2Array()
	for p in simple:
		poly.append(Vector2(p) * tile)
	return {"points": poly, "closed": closed}


## At a vertex shared by two diagonal tiles, turn right so surfaces stay separate.
static func _choose(outs: Array, at: Vector2i, prev_dir: Vector2i) -> Vector2i:
	if outs.size() == 1 or prev_dir == Vector2i.ZERO:
		return outs[0]
	var right := Vector2i(-prev_dir.y, prev_dir.x)
	for o in outs:
		if o - at == right:
			return o
	return outs[0]


## Drop points in the middle of straight runs (keeps open-chain endpoints).
static func _simplify(pts: Array[Vector2i], closed: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := pts.size()
	for i in n:
		if not closed and (i == 0 or i == n - 1):
			out.append(pts[i])
			continue
		var a := pts[(i - 1 + n) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		if (b - a).sign() != (c - b).sign():
			out.append(b)
	return out

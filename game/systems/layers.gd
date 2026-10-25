class_name Layers
extends RefCounted
## Physics layer bits, named. A body is ON its collision_layer and BUMPS INTO
## whatever is in its collision_mask.

const SOLID := 1        # walls and floors
const LEDGE := 2        # one-way ledges ('='), which Orpheus can drop through
const PLAYER := 4
const ENEMY := 8

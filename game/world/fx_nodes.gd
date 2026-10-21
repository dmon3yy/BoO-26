class_name FxNodes
extends RefCounted
## Small reusable effect nodes: animated sprite strips, flickering lights, glow halos.

const FLAME := "res://game/art/fx/flame.png"
const HALO := "res://game/art/fx/halo.png"
const LIGHT := "res://game/art/fx/light_banded.png"

static var _additive: CanvasItemMaterial


static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _additive


static func flame(at: Vector2) -> Sprite2D:
	var s := StripSprite.new()
	s.texture = ContentDB.texture(FLAME)
	s.hframes = 8
	s.fps = 12.0
	s.material = _unshaded()
	s.position = at + Vector2(0, -8)
	s.frame = randi() % 8
	return s


static func light(at: Vector2, spec: Dictionary) -> PointLight2D:
	var l := FlickerLight.new()
	l.texture = ContentDB.texture(LIGHT)
	l.position = at
	var c: Array = spec.get("color", [1, 1, 1])
	l.color = Color(c[0], c[1], c[2])
	l.base_energy = float(spec.get("energy", 1.0))
	l.energy = l.base_energy
	l.texture_scale = float(spec.get("scale", 1.0))
	l.flicker = float(spec.get("flicker", 0.0))
	l.shadow_enabled = bool(spec.get("shadow", false))
	l.shadow_filter = Light2D.SHADOW_FILTER_NONE
	l.height = 64.0
	return l


static func halo(at: Vector2, color: Color, radius: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = ContentDB.texture(HALO)
	s.material = additive()
	s.modulate = color
	s.position = at
	s.scale = Vector2.ONE * (radius * 2.0 / 64.0)
	return s


static var _unshaded_mat: CanvasItemMaterial


static func _unshaded() -> CanvasItemMaterial:
	if _unshaded_mat == null:
		_unshaded_mat = CanvasItemMaterial.new()
		_unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded_mat


static func unshaded() -> CanvasItemMaterial:
	return _unshaded()


class StripSprite:
	extends Sprite2D
	## Plays every frame of a horizontal strip, looping.
	var fps := 10.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 1.0 / fps:
			_t = fmod(_t, 1.0 / fps)
			frame = (frame + 1) % (hframes * vframes)


class FlickerLight:
	extends PointLight2D
	## Firelight: energy wobbles with layered sine noise (deterministic per light).
	var base_energy := 1.0
	var flicker := 0.0
	var _seed := randf() * 100.0

	func _process(_delta: float) -> void:
		if flicker <= 0.0:
			return
		var t := Time.get_ticks_msec() / 1000.0 + _seed
		var n := sin(t * 7.1) * 0.5 + sin(t * 13.3 + 1.7) * 0.3 + sin(t * 23.9 + 4.1) * 0.2
		energy = base_energy * (1.0 + n * flicker)

class_name StarsUI
extends Control

# Simple 2D star field drawn behind the 3D scene via a CanvasLayer at layer -1.
# Pre-computed on _ready so _draw is just a list of draw_circle calls.

const STAR_COUNT := 280

var _stars: Array = []   # [{pos, size, alpha}]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	var vp  := get_viewport().get_visible_rect().size
	for i in range(STAR_COUNT):
		_stars.append({
			"pos":   Vector2(rng.randf() * vp.x, rng.randf() * vp.y),
			"size":  rng.randf_range(0.4, 1.8),
			"alpha": rng.randf_range(0.25, 0.90),
			"warm":  rng.randf(),   # 0 = blue-white, 1 = warm white
		})


func _draw() -> void:
	for s in _stars:
		var col := Color(
			lerp(0.82, 1.00, s["warm"]),
			lerp(0.90, 0.97, s["warm"]),
			lerp(1.00, 0.90, s["warm"]),
			s["alpha"]
		)
		draw_circle(s["pos"], s["size"], col)

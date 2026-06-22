extends Node3D

const DEBRIS_PER_INTENSITY := 20
const FALL_BASE_DURATION   := 0.8
const TRAIL_SEGMENTS       := 16

var _planet:      Node3D
var _tile:        Object
var _meteor:      MeshInstance3D  # owned sphere mesh (normal bombardments)
var _ext_rock:    Node3D          # externally-owned rock (IMPACT ability)
var _rock_cb:     Callable        # called when external rock lands
var _intensity:   float  = 1.0
var _tile_col:    Color  = Color(0.5, 0.5, 0.5)
var _is_sea:      bool   = false
var _debris:      Array  = []
var _rings:       Array  = []   # [{mi, mat, life, max_life, speed, delay}]
var _surf_normal: Vector3

var _start_pos: Vector3
var _end_pos:   Vector3
var _t:         float = 0.0
var _phase:     int   = 0

var _trail_nodes:  Array = []
var _trail_mats:   Array = []
var _trail_hist:   Array = []
var _trail_write:  int   = 0


func setup(planet: Node3D, tile: Object, intensity: float = 1.0, tile_col: Color = Color(0.5, 0.5, 0.5)) -> void:
	_intensity   = clamp(intensity, 0.1, 3.0)
	_planet      = planet
	_tile        = tile
	_tile_col    = tile_col
	_is_sea      = not (tile as RefCounted).is_land
	_surf_normal = (tile as RefCounted).center_position.normalized()

	var land_add: float = planet.land_height if (tile as RefCounted).is_land else 0.0
	var surf_r: float   = planet.planet_radius + planet.tile_raise + land_add

	# Random offset within the tile — bigger asteroids can hit further off-centre
	var ref:       Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent:   Vector3 = _surf_normal.cross(ref).normalized()
	var bitangent: Vector3 = _surf_normal.cross(tangent).normalized()
	var max_off:   float   = 0.15 + _intensity * 0.18
	var offset:    Vector3 = (tangent * randf_range(-1.0, 1.0) + bitangent * randf_range(-1.0, 1.0)).normalized() \
	                         * randf_range(0.0, max_off)

	_end_pos   = _surf_normal * surf_r + offset
	_start_pos = _surf_normal * (surf_r + 3.5 + _intensity * 2.0)

	_build_meteor()
	_build_trail()


# Called by Main when firing the IMPACT rock — rock is already reparented to planet.
func setup_with_rock(planet: Node3D, tile: Object, intensity: float,
		tile_col: Color, rock: Node3D, cb: Callable) -> void:
	_ext_rock  = rock
	_rock_cb   = cb
	_intensity = clamp(intensity, 0.1, 5.0)
	_planet    = planet
	_tile      = tile
	_tile_col  = tile_col
	_is_sea    = not (tile as RefCounted).is_land
	_surf_normal = (tile as RefCounted).center_position.normalized()

	var land_add: float = planet.land_height if (tile as RefCounted).is_land else 0.0
	var surf_r: float   = planet.planet_radius + planet.tile_raise + land_add

	var ref:       Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent:   Vector3 = _surf_normal.cross(ref).normalized()
	var bitangent: Vector3 = _surf_normal.cross(tangent).normalized()
	var max_off:   float   = 0.15 + _intensity * 0.18
	var offset:    Vector3 = (tangent * randf_range(-1.0, 1.0) + bitangent * randf_range(-1.0, 1.0)).normalized() \
	                         * randf_range(0.0, max_off)

	_end_pos   = _surf_normal * surf_r + offset
	_start_pos = rock.position  # rock is already in planet-local space after reparent

	_build_trail()  # trail uses sphere segments; no owned meteor mesh built


func _build_meteor() -> void:
	_meteor = MeshInstance3D.new()
	var mesh    := SphereMesh.new()
	mesh.radius  = 0.12 + _intensity * 0.12
	mesh.height  = mesh.radius * 2.2
	_meteor.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.15, 0.10, 0.07)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 2.0 + _intensity
	mat.roughness                  = 0.9
	_meteor.set_surface_override_material(0, mat)
	_meteor.position = _start_pos
	add_child(_meteor)


func _build_trail() -> void:
	_trail_hist.resize(TRAIL_SEGMENTS)
	for i in range(TRAIL_SEGMENTS):
		_trail_hist[i] = _start_pos

	var base_radius: float = 0.09 + _intensity * 0.09

	for i in range(TRAIL_SEGMENTS):
		var mi   := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var frac: float          = float(TRAIL_SEGMENTS - i) / TRAIL_SEGMENTS
		mesh.radius              = base_radius * frac * 0.9
		mesh.height              = mesh.radius * 2.0
		mi.mesh                  = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode         = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency         = BaseMaterial3D.TRANSPARENCY_ALPHA
		var heat: float          = frac
		mat.albedo_color         = Color(1.0, 0.4 + heat * 0.4, heat * 0.2, heat * 0.85)
		mat.emission_enabled     = true
		mat.emission             = Color(1.0, 0.3 + heat * 0.5, 0.0) * heat
		mat.emission_energy_multiplier = heat * 2.5
		mi.position = _start_pos
		add_child(mi)
		_trail_nodes.append(mi)
		_trail_mats.append(mat)


func _active_pos() -> Vector3:
	if _ext_rock:
		return _ext_rock.position
	return _meteor.position if _meteor else _end_pos


func _update_trail() -> void:
	_trail_hist[_trail_write] = _active_pos()
	_trail_write = (_trail_write + 1) % TRAIL_SEGMENTS
	for i in range(TRAIL_SEGMENTS):
		var hist_idx: int = (_trail_write - 1 - i + TRAIL_SEGMENTS) % TRAIL_SEGMENTS
		(_trail_nodes[i] as MeshInstance3D).position = _trail_hist[hist_idx]


func _hide_trail() -> void:
	for mi in _trail_nodes:
		(mi as MeshInstance3D).visible = false


# ── Ring helpers ──────────────────────────────────────────────────────────────

func _make_ring(color: Color, thickness: float, delay: float, max_life: float, speed: float) -> void:
	var mi   := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius  = 0.01
	mesh.outer_radius  = 0.04
	mesh.rings         = 128
	mesh.ring_segments = 8
	mi.mesh = mesh

	# Build basis with Y = surf_normal so the torus lies flat on the surface
	var ref:  Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx:   Vector3 = _surf_normal.cross(ref).normalized()
	var bz:   Vector3 = bx.cross(_surf_normal).normalized()
	mi.transform.basis = Basis(bx, _surf_normal, bz)
	mi.position        = _end_pos

	var mat := StandardMaterial3D.new()
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode      = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color   = color
	if color.r > 0.8 and color.g > 0.8:   # white blast ring gets emission
		mat.emission_enabled           = true
		mat.emission                   = Color(1.0, 1.0, 0.9)
		mat.emission_energy_multiplier = 1.5
	mi.set_surface_override_material(0, mat)
	mi.visible = false
	add_child(mi)

	_rings.append({
		"mi":       mi,
		"mat":      mat,
		"life":     0.0,
		"max_life": max_life,
		"speed":    speed,
		"delay":    delay,
	})


func _spawn_rings() -> void:
	if _is_sea:
		# Three concentric water ripples, staggered
		var ripple_col := Color(0.7, 0.88, 1.0, 0.9)
		_make_ring(ripple_col, 0.025, 0.00, 1.2, 2.8 * _intensity)
		_make_ring(ripple_col, 0.018, 0.18, 1.1, 2.2 * _intensity)
		_make_ring(ripple_col, 0.012, 0.36, 1.0, 1.8 * _intensity)
	else:
		# Single fast white shockwave blast ring
		var blast_col := Color(1.0, 0.97, 0.92, 1.0)
		_make_ring(blast_col, 0.035, 0.00, 0.65, 6.0 * _intensity)


func _update_rings(delta: float) -> void:
	for r in _rings:
		r["life"] += delta
		var age: float = r["life"] - r["delay"]
		if age < 0.0:
			continue
		var mi  := r["mi"]  as MeshInstance3D
		var mat := r["mat"] as StandardMaterial3D
		mi.visible = true
		var progress: float = age / r["max_life"]
		# Expand by scaling the node uniformly
		var s: float = 1.0 + age * r["speed"]
		mi.scale    = Vector3(s, s, s)
		# Rise slightly as it expands so it stays clear of tile edges
		mi.position = _end_pos
		# Fade: ripples fade out smoothly; blast ring fades fast at end
		var alpha: float
		if _is_sea:
			alpha = (1.0 - smoothstep(0.4, 1.0, progress)) * 0.75
		else:
			alpha = (1.0 - smoothstep(0.0, 1.0, progress)) * 0.9
		mat.albedo_color.a = alpha


# ── Debris ────────────────────────────────────────────────────────────────────

func _spawn_debris() -> void:
	var ref:       Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent:   Vector3 = _surf_normal.cross(ref).normalized()
	var bitangent: Vector3 = _surf_normal.cross(tangent).normalized()
	var count: int = clamp(int(DEBRIS_PER_INTENSITY * _intensity), 8, 60)

	for i in range(count):
		var angle: float   = (float(i) / count) * TAU + randf() * 1.2
		var t_dir: Vector3 = (tangent * cos(angle) + bitangent * sin(angle)).normalized()
		var speed: float   = randf_range(4.0, 9.0) * (0.6 + _intensity * 0.7)
		var vel: Vector3   = t_dir * speed + _surf_normal * randf_range(1.0, 4.0 * _intensity)

		var mi   := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var w: float = randf_range(0.06, 0.18) * (0.7 + _intensity * 0.3)
		var h: float = randf_range(0.04, 0.14) * (0.7 + _intensity * 0.3)
		mesh.size    = Vector2(w, h)
		mi.mesh      = mesh

		var vary: float = randf_range(-0.12, 0.12)
		var piece_col := Color(
			clamp(_tile_col.r + vary, 0.0, 1.0),
			clamp(_tile_col.g + vary, 0.0, 1.0),
			clamp(_tile_col.b + vary, 0.0, 1.0)
		)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = piece_col
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.set_surface_override_material(0, mat)
		mi.position = _end_pos
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(mi)

		_debris.append({
			"mi":       mi,
			"vel":      vel,
			"spin":     Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)),
			"life":     0.0,
			"max_life": randf_range(1.2, 2.8 + _intensity * 0.6),
			"mat":      mat,
		})


# ── Main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _phase == 0:
		_t = move_toward(_t, 1.0, delta / (FALL_BASE_DURATION + _intensity * 0.1))
		var new_pos: Vector3 = _start_pos.lerp(_end_pos, _t * _t)
		if _ext_rock:
			_ext_rock.position = new_pos
			# Let external rock keep its own rotation (tumbling, set by Main._process)
		else:
			_meteor.position = new_pos
			var dir: Vector3 = (_end_pos - _meteor.position).normalized()
			if dir.length_squared() > 0.001:
				_meteor.look_at(_meteor.global_position + dir, Vector3.UP)
		_update_trail()
		if _t >= 1.0:
			_on_impact()
		return

	_update_rings(delta)

	var all_done := true
	for d in _debris:
		d["life"] += delta
		var progress: float = d["life"] / d["max_life"]
		var mi := d["mi"] as MeshInstance3D
		if progress >= 1.0:
			mi.visible = false
			continue
		all_done = false
		d["vel"] = d["vel"] + (-_surf_normal * 10.0 * delta)
		mi.position += (d["vel"] as Vector3) * delta
		mi.rotation += (d["spin"] as Vector3) * delta
		var alpha: float = 1.0 - smoothstep(0.55, 1.0, progress)
		(d["mat"] as StandardMaterial3D).albedo_color.a = alpha

	# Keep alive until rings and debris are all done
	var rings_done := _rings.all(func(r) -> bool:
		return r["life"] - r["delay"] >= r["max_life"]
	)
	if all_done and rings_done:
		queue_free()


func _on_impact() -> void:
	_phase = 1
	_hide_trail()
	if _ext_rock:
		_ext_rock.visible = false
		if _rock_cb.is_valid():
			_rock_cb.call()
	else:
		_meteor.queue_free()
	_spawn_rings()
	_spawn_debris()
	if _planet.has_method("apply_impact"):
		_planet.apply_impact((_tile as RefCounted).tile_id, _end_pos, _intensity)

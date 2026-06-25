extends Node3D

const DEBRIS_PER_INTENSITY := 120
const FALL_BASE_DURATION   := 1.2
const TRAIL_SEGMENTS       := 20

# Fire palette — head (hot) to tail (cooling)
const FIRE_COLORS := [
	Color(1.00, 0.95, 0.60),  # white-yellow core
	Color(1.00, 0.72, 0.10),  # bright orange
	Color(1.00, 0.45, 0.05),  # deep orange
	Color(0.90, 0.20, 0.02),  # red
	Color(0.55, 0.08, 0.01),  # dark red ember
]
const ICE_COLORS := [
	Color(1.00, 1.00, 1.00),  # white ice core
	Color(0.82, 0.96, 1.00),  # light cyan
	Color(0.55, 0.82, 1.00),  # ice blue
	Color(0.35, 0.65, 0.95),  # deep blue
	Color(0.22, 0.48, 0.82),  # dark ice
]
const METAL_COLORS := [
	Color(1.00, 1.00, 0.95),  # white-hot
	Color(1.00, 0.98, 0.60),  # searing yellow
	Color(1.00, 0.72, 0.10),  # bright orange
	Color(0.90, 0.40, 0.05),  # orange-red
	Color(0.60, 0.20, 0.02),  # cooling red
]

var _planet:      Node3D
var _tile:        Object
var _meteor:      MeshInstance3D
var _ext_rock:    Node3D
var _rock_cb:     Callable
var _intensity:   float  = 1.0
var _tile_col:    Color  = Color(0.5, 0.5, 0.5)
var _is_sea:      bool   = false
var _ast_type:    String = "c_type"
var _debris:      Array  = []
var _rings:       Array  = []
var _surf_normal: Vector3

var _start_pos:   Vector3
var _end_pos:     Vector3
var _t:           float = 0.0
var _phase:       int   = 0
var _flight_dir:  Vector3  # unit vector start→end, for fire particle drift

var _trail_nodes: Array = []
var _trail_mats:  Array = []
var _trail_hist:  Array = []
var _trail_write: int   = 0

var _fire_pixels:     Array = []  # [{mi, mat, vel, life, max_life}]
var _fire_accum:      float = 0.0
var _irregular_core:  bool  = false  # true for player impacts, false for bombardment


func _offscreen_start(surf_normal: Vector3) -> Vector3:
	# Start from off-screen in a diagonal direction relative to the surface normal.
	# Distance is capped so the Z component stays below 12: camera is at world Z=17,
	# ImpactEffect origin is at planet Z=0, so Z>12 would put the start near/behind camera.
	var ref:    Vector3 = Vector3.UP if abs(surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tang:   Vector3 = surf_normal.cross(ref).normalized()
	var bitang: Vector3 = tang.cross(surf_normal).normalized()
	var lat:  float = randf_range(0.6, 1.4)
	var vert: float = randf_range(0.2, 0.7)
	var side: Vector3 = (tang * randf_range(-1.0, 1.0) + bitang * randf_range(-1.0, 1.0)).normalized()
	var approach: Vector3 = (surf_normal + side * lat + Vector3.UP * vert).normalized()
	# Clamp distance so approach.z * dist <= 12 (keeps start in front of camera)
	var max_z_contrib := 12.0
	var dist := minf(18.0, max_z_contrib / maxf(approach.z, 0.25))
	return approach * dist


func setup(planet: Node3D, tile: Object, intensity: float = 1.0,
		tile_col: Color = Color(0.5, 0.5, 0.5), asteroid_type: String = "c_type") -> void:
	print("[ImpactEffect] setup() type=", asteroid_type, " intensity=", intensity)
	_ast_type    = asteroid_type
	_intensity   = clamp(intensity, 0.1, 3.0)
	_planet      = planet
	_tile        = tile
	_tile_col    = tile_col
	# Apply planet's current rotation so normals/positions are in ImpactEffect's world-oriented space.
	# (ImpactEffect is parented to the scene root at planet.global_position with identity rotation.)
	var local_normal: Vector3 = (tile as RefCounted).center_position.normalized()
	_surf_normal = (planet as Node3D).global_transform.basis * local_normal
	_is_sea      = not (tile as PlanetTile).is_land

	var land_add: float = 0.0 if _is_sea else planet.land_height
	var surf_r:   float = planet.planet_radius + planet.tile_raise + land_add

	var ref:       Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent:   Vector3 = _surf_normal.cross(ref).normalized()
	var bitangent: Vector3 = _surf_normal.cross(tangent).normalized()
	var max_off:   float   = 0.15 + _intensity * 0.18
	var offset:    Vector3 = (tangent * randf_range(-1.0, 1.0) + bitangent * randf_range(-1.0, 1.0)).normalized() \
	                         * randf_range(0.0, max_off)

	_end_pos     = _surf_normal * surf_r + offset
	_start_pos   = _offscreen_start(_surf_normal)
	_flight_dir  = (_end_pos - _start_pos).normalized()

	_build_meteor()
	_build_trail()


func setup_with_rock(planet: Node3D, tile: Object, intensity: float,
		tile_col: Color, rock: Node3D, cb: Callable,
		asteroid_type: String = "c_type") -> void:
	_ast_type       = asteroid_type
	_irregular_core = true  # player-aimed rock → irregular black center
	_ext_rock    = rock
	_rock_cb     = cb
	_intensity   = clamp(intensity, 0.1, 5.0)
	_planet      = planet
	_tile        = tile
	_tile_col    = tile_col
	var local_normal: Vector3 = (tile as RefCounted).center_position.normalized()
	_surf_normal = (planet as Node3D).global_transform.basis * local_normal
	_is_sea      = not (tile as PlanetTile).is_land

	var land_add: float = 0.0 if _is_sea else planet.land_height
	var surf_r:   float = planet.planet_radius + planet.tile_raise + land_add

	var ref:       Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent:   Vector3 = _surf_normal.cross(ref).normalized()
	var bitangent: Vector3 = _surf_normal.cross(tangent).normalized()
	var max_off:   float   = 0.15 + _intensity * 0.18
	var offset:    Vector3 = (tangent * randf_range(-1.0, 1.0) + bitangent * randf_range(-1.0, 1.0)).normalized() \
	                         * randf_range(0.0, max_off)

	_end_pos    = _surf_normal * surf_r + offset
	# rock.position is in camera-local space; convert to ImpactEffect-local (world - planet_pos)
	_start_pos  = rock.global_position - (planet as Node3D).global_position
	_flight_dir = (_end_pos - _start_pos).normalized()

	_build_trail()


func _build_meteor() -> void:
	_meteor      = MeshInstance3D.new()
	var mesh     := SphereMesh.new()
	mesh.radius          = 0.24 + _intensity * 0.24  # large enough to see
	mesh.height          = mesh.radius * 2.0
	mesh.radial_segments = 8
	mesh.rings           = 4
	_meteor.mesh = mesh

	# Bright fireball — visible from any camera distance
	var hot: Color = _trail_palette()[0] as Color
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = hot
	mat.emission_enabled          = true
	mat.emission                  = hot
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
	_meteor.set_surface_override_material(0, mat)
	_meteor.position = _start_pos
	add_child(_meteor)


func _trail_palette() -> Array:
	match _ast_type:
		"comet":   return ICE_COLORS.duplicate()
		"m_type":  return METAL_COLORS.duplicate()
		"s_type":  return [Color(1.00,0.97,0.70), Color(1.00,0.78,0.15),
		                   Color(1.00,0.50,0.05), Color(0.88,0.22,0.02), Color(0.50,0.08,0.01)]
		_:         return FIRE_COLORS.duplicate()


func _build_trail() -> void:
	_trail_hist.resize(TRAIL_SEGMENTS)
	for i in range(TRAIL_SEGMENTS):
		_trail_hist[i] = _start_pos

	var base_radius: float = 0.16 + _intensity * 0.12
	var palette: Array = _trail_palette()

	for i in range(TRAIL_SEGMENTS):
		var mi   := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		# frac: 1.0 at head (newest), 0.0 at tail (oldest)
		var frac: float          = float(TRAIL_SEGMENTS - i) / TRAIL_SEGMENTS
		mesh.radius              = base_radius * frac
		mesh.height              = mesh.radius * 2.0
		mesh.radial_segments     = 6
		mesh.rings               = 3
		mi.mesh                  = mesh

		var fire_idx: int   = int(frac * (palette.size() - 1))
		var fire_t:   float = frac * (palette.size() - 1) - fire_idx
		var fire_col: Color = (palette[fire_idx] as Color).lerp(
			palette[mini(fire_idx + 1, palette.size() - 1)] as Color, fire_t)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = fire_col
		mat.emission_enabled = true
		mat.emission         = fire_col
		mat.emission_energy_multiplier = 3.0 * frac
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = frac * 0.9

		mi.set_surface_override_material(0, mat)
		mi.position = _start_pos
		add_child(mi)
		_trail_nodes.append(mi)
		_trail_mats.append(mat)


func _active_pos() -> Vector3:
	if _ext_rock:
		# ext_rock is a camera child; convert its world position to ImpactEffect-local
		return _ext_rock.global_position - (_planet as Node3D).global_position
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


# ── Fire pixel particles ───────────────────────────────────────────────────────

func _spawn_fire_pixel(origin: Vector3) -> void:
	var mi   := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var sz: float = randf_range(0.09, 0.26)
	mesh.size = Vector2(sz, sz)
	mi.mesh   = mesh

	var _pal: Array = _trail_palette()
	var col: Color = _pal[randi() % _pal.size()]

	var mat := StandardMaterial3D.new()
	mat.albedo_color             = col
	mat.emission_enabled         = true
	mat.emission                 = col
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	mi.set_surface_override_material(0, mat)

	# Drift mostly backward along flight path with random spread
	var spread: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	var vel: Vector3    = -_flight_dir * randf_range(2.0, 5.0) + spread * randf_range(0.3, 1.2)

	mi.position = origin + spread * randf_range(0.0, 0.15)
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	add_child(mi)

	_fire_pixels.append({
		"mi":       mi,
		"mat":      mat,
		"vel":      vel,
		"life":     0.0,
		"max_life": randf_range(0.18, 0.45),
	})


func _update_fire_pixels(delta: float) -> void:
	for p in _fire_pixels:
		p["life"] += delta
		var progress: float = p["life"] / p["max_life"]
		var mi := p["mi"] as MeshInstance3D
		if progress >= 1.0:
			mi.visible = false
			continue
		mi.position += (p["vel"] as Vector3) * delta
		var alpha: float = 1.0 - smoothstep(0.5, 1.0, progress)
		(p["mat"] as StandardMaterial3D).albedo_color.a = alpha


# ── Ring helpers ──────────────────────────────────────────────────────────────

func _build_sphere_cap_disk(mesh: ArrayMesh, max_r: float, planet_r: float) -> void:
	var theta_max: float = asin(clamp(max_r / planet_r, 0.0, 0.9999))
	var ref: Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var bx: Vector3  = _surf_normal.cross(ref).normalized()
	var bz: Vector3  = bx.cross(_surf_normal).normalized()

	const N_PHI := 24
	const N_R   := 8
	var verts   := PackedVector3Array()
	var indices := PackedInt32Array()

	verts.append(_surf_normal * planet_r)

	for r_i in range(1, N_R + 1):
		var theta: float = theta_max * r_i / N_R
		for phi_i in range(N_PHI):
			var phi:  float   = phi_i * TAU / N_PHI
			var tang: Vector3 = bx * cos(phi) + bz * sin(phi)
			verts.append(planet_r * (cos(theta) * _surf_normal + sin(theta) * tang))

	for phi_i in range(N_PHI):
		indices.append_array([0, 1 + phi_i, 1 + (phi_i + 1) % N_PHI])

	for r_i in range(N_R - 1):
		var rs: int = 1 + r_i * N_PHI
		var re: int = rs + N_PHI
		for phi_i in range(N_PHI):
			var a0: int = rs + phi_i;          var a1: int = rs + (phi_i + 1) % N_PHI
			var b0: int = re + phi_i;          var b1: int = re + (phi_i + 1) % N_PHI
			indices.append_array([a0, b0, a1, a1, b0, b1])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX]  = indices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _make_ring(color: Color, start_r: float, delay: float, max_life: float, expand_to: float) -> void:
	var mi      := MeshInstance3D.new()
	var mesh    := ArrayMesh.new()
	var pln     := _planet as Planet
	# Use actual rendered surface radius so rings appear ON the surface, not inside it
	var land_add: float = 0.0 if _is_sea else pln.land_height
	var surf_r:  float  = pln.planet_radius + pln.tile_raise + land_add + 0.02
	var center: Vector3 = _surf_normal * surf_r
	_build_sphere_cap_disk(mesh, expand_to * 1.15, surf_r)
	mi.mesh     = mesh
	mi.position = Vector3.ZERO
	mi.scale    = Vector3.ONE

	var tube: float = start_r * 0.06
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_ring.gdshader") as Shader
	mat.set_shader_parameter("ring_color",  color)
	mat.set_shader_parameter("alpha",       1.0)
	mat.set_shader_parameter("pixel_size",  0.10)
	mat.set_shader_parameter("ring_center", center)
	mat.set_shader_parameter("inner_r",     start_r - tube)
	mat.set_shader_parameter("outer_r",     start_r + tube)
	mi.set_surface_override_material(0, mat)
	mi.visible = false
	add_child(mi)

	_rings.append({
		"mi":        mi,
		"mat":       mat,
		"life":      0.0,
		"max_life":  max_life,
		"start_r":   start_r,
		"expand_to": expand_to,
		"delay":     delay,
	})


func _spawn_rings() -> void:
	var cr: float = 0.45 + _intensity * 0.55
	match _ast_type:
		"comet":
			if _is_sea:
				# Comet ocean hit — 5 massive ice-blue tidal waves + trailing steam
				var ice1  := Color(0.60, 0.92, 1.00, 0.95)
				var ice2  := Color(0.45, 0.78, 0.98, 0.85)
				var steam := Color(0.88, 0.96, 1.00, 0.55)
				_make_ring(ice1,  cr * 1.3, 0.00, 2.4, cr * 8.0)
				_make_ring(ice2,  cr * 1.1, 0.22, 2.1, cr * 6.8)
				_make_ring(ice1,  cr * 1.0, 0.44, 1.9, cr * 5.8)
				_make_ring(ice2,  cr * 0.9, 0.65, 1.7, cr * 4.8)
				_make_ring(steam, cr * 0.7, 0.90, 2.0, cr * 7.0)
			else:
				# Comet land — pale ice burst then slow steam spread
				var burst := Color(0.78, 0.94, 1.00, 0.92)
				var steam2 := Color(0.92, 0.97, 1.00, 0.60)
				_make_ring(burst,  cr * 1.0, 0.00, 0.70, cr * 5.0)
				_make_ring(steam2, cr * 0.8, 0.10, 2.20, cr * 7.5)
				_make_ring(burst,  cr * 0.6, 0.38, 1.10, cr * 3.5)
		"m_type":
			if _is_sea:
				# Metallic ocean — violent, fast, near-white then steel
				var white := Color(0.94, 0.97, 1.00, 0.96)
				var steel := Color(0.68, 0.80, 0.92, 0.80)
				var grey  := Color(0.52, 0.64, 0.78, 0.55)
				_make_ring(white, cr * 1.4, 0.00, 0.80, cr * 9.0)  # explosive leading wave
				_make_ring(steel, cr * 1.1, 0.14, 1.50, cr * 7.0)
				_make_ring(grey,  cr * 0.8, 0.50, 2.00, cr * 5.0)
			else:
				# Metallic land — massive yellow-white shockwave + molten splatter
				var shock  := Color(1.00, 0.94, 0.55, 1.00)
				var molten := Color(1.00, 0.55, 0.08, 0.92)
				var settle := Color(0.46, 0.38, 0.28, 0.70)
				_make_ring(shock,  cr * 1.3, 0.00, 0.55, cr * 8.0)  # ultra-fast shockwave
				_make_ring(molten, cr * 1.0, 0.04, 0.85, cr * 4.5)
				_make_ring(settle, cr * 0.9, 0.22, 2.10, cr * 6.0)
				_make_ring(molten, cr * 0.6, 0.45, 1.30, cr * 3.2)
		"s_type":
			if _is_sea:
				# Stony ocean — 3 waves + mud ring
				var ripple := Color(0.70, 0.88, 1.00, 0.90)
				var mud    := Color(0.58, 0.66, 0.52, 0.65)
				_make_ring(ripple, cr * 1.2, 0.00, 1.5, cr * 5.5)
				_make_ring(ripple, cr * 1.0, 0.28, 1.4, cr * 4.5)
				_make_ring(mud,    cr * 0.8, 0.55, 1.6, cr * 3.8)
			else:
				# Stony land — bigger shockwave + stronger fire accent
				var dust  := Color(0.72, 0.52, 0.26, 1.00)
				var fire  := Color(1.00, 0.55, 0.05, 0.82)
				var dust2 := Color(0.58, 0.42, 0.20, 0.78)
				_make_ring(dust,  cr * 1.1, 0.00, 1.00, cr * 6.0)
				_make_ring(fire,  cr * 0.8, 0.05, 0.72, cr * 3.8)
				_make_ring(dust2, cr * 0.9, 0.25, 1.40, cr * 5.2)
				_make_ring(dust2, cr * 0.7, 0.52, 1.60, cr * 4.0)
		_:  # c_type and default
			if _is_sea:
				var ripple_col := Color(0.65, 0.85, 1.0, 0.90)
				_make_ring(ripple_col, cr * 1.1, 0.00, 1.6, cr * 5.5)
				_make_ring(ripple_col, cr * 1.0, 0.28, 1.5, cr * 4.8)
				_make_ring(ripple_col, cr * 0.9, 0.55, 1.4, cr * 4.0)
				_make_ring(ripple_col, cr * 0.8, 0.80, 1.3, cr * 3.2)
			else:
				var dust  := Color(0.76, 0.55, 0.28, 1.00)
				var dust2 := Color(0.62, 0.44, 0.22, 0.85)
				var dust3 := Color(0.52, 0.36, 0.18, 0.65)
				var fire  := Color(1.00, 0.45, 0.05, 0.70)
				_make_ring(dust,  cr * 1.0, 0.00, 1.10, cr * 5.5)
				_make_ring(fire,  cr * 0.7, 0.06, 0.65, cr * 3.0)
				_make_ring(dust2, cr * 0.9, 0.22, 1.30, cr * 4.5)
				_make_ring(dust3, cr * 0.8, 0.45, 1.50, cr * 3.8)


func _update_rings(delta: float) -> void:
	for r in _rings:
		r["life"] += delta
		var age: float = r["life"] - r["delay"]
		if age < 0.0:
			continue
		var mi  := r["mi"]  as MeshInstance3D
		var mat := r["mat"] as ShaderMaterial
		mi.visible = true
		var progress: float  = clamp(age / r["max_life"], 0.0, 1.0)
		var current_r: float = lerp(r["start_r"], r["expand_to"], progress)
		var tube: float      = current_r * 0.06
		mat.set_shader_parameter("inner_r", current_r - tube)
		mat.set_shader_parameter("outer_r", current_r + tube)
		var alpha: float
		if _is_sea:
			alpha = (1.0 - smoothstep(0.35, 1.0, progress)) * 0.80
		else:
			alpha = (1.0 - smoothstep(0.10, 1.0, progress)) * 0.92
		mat.set_shader_parameter("alpha", alpha)


# ── Debris ────────────────────────────────────────────────────────────────────

func _spawn_debris() -> void:
	var ref:       Vector3 = Vector3.UP if abs(_surf_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent:   Vector3 = _surf_normal.cross(ref).normalized()
	var bitangent: Vector3 = _surf_normal.cross(tangent).normalized()
	var count: int = clamp(int(DEBRIS_PER_INTENSITY * _intensity), 40, 200)

	var rock_cols: Array
	var emit_palette: Array
	var emit_threshold: float
	match _ast_type:
		"comet":
			rock_cols = [Color(0.90,0.95,1.00), Color(0.75,0.88,0.98),
			             Color(0.85,0.90,0.96), Color(0.65,0.80,0.95), Color(0.95,0.97,1.00)]
			emit_palette = [ICE_COLORS[0], ICE_COLORS[1]]
			emit_threshold = 0.18
		"m_type":
			rock_cols = [Color(0.72,0.72,0.76), Color(0.82,0.82,0.86),
			             Color(0.88,0.84,0.70), Color(0.65,0.65,0.68), Color(0.55,0.55,0.60)]
			emit_palette = [METAL_COLORS[0], METAL_COLORS[1]]
			emit_threshold = 0.28
		"s_type":
			rock_cols = [Color(0.60,0.48,0.30), Color(0.72,0.58,0.36),
			             Color(0.80,0.65,0.42), Color(0.48,0.38,0.22), Color(0.66,0.52,0.32)]
			emit_palette = [FIRE_COLORS[0], FIRE_COLORS[1]]
			emit_threshold = 0.18
		_:  # c_type
			rock_cols = [Color(0.36,0.28,0.20), Color(0.50,0.40,0.28),
			             Color(0.62,0.52,0.36), Color(0.28,0.24,0.18), Color(0.45,0.35,0.22)]
			emit_palette = [FIRE_COLORS[0], FIRE_COLORS[1]]
			emit_threshold = 0.12

	for i in range(count):
		var angle: float   = (float(i) / count) * TAU + randf() * 1.2
		var t_dir: Vector3 = (tangent * cos(angle) + bitangent * sin(angle)).normalized()
		var speed: float   = randf_range(1.5, 4.0) * (0.5 + _intensity * 0.5)
		var lift: float    = randf_range(2.5, 7.0 * _intensity)
		var vel: Vector3   = t_dir * speed + _surf_normal * lift

		var return_time: float = 2.0 * lift / 6.5
		var piece_life: float  = return_time + randf_range(0.4, 0.9)
		var spin: Vector3      = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))

		var base_col: Color
		if randf() < emit_threshold:
			base_col = emit_palette[randi() % emit_palette.size()]
		elif randf() < 0.5:
			base_col = rock_cols[randi() % rock_cols.size()]
		else:
			var vary: float = randf_range(-0.08, 0.08)
			base_col = Color(clamp(_tile_col.r + vary, 0.0, 1.0),
			                 clamp(_tile_col.g + vary, 0.0, 1.0),
			                 clamp(_tile_col.b + vary, 0.0, 1.0))

		# 2-4 quads per cluster, each tracked independently with shared velocity
		var cluster_size: int = 2 + randi() % 3
		for _c in range(cluster_size):
			var mi   := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			var sz: float = randf_range(0.03, 0.07) * (0.7 + _intensity * 0.3)
			mesh.size = Vector2(sz, sz)
			mi.mesh   = mesh

			var vary2: float = randf_range(-0.06, 0.06)
			var piece_col := Color(clamp(base_col.r + vary2, 0.0, 1.0),
			                       clamp(base_col.g + vary2, 0.0, 1.0),
			                       clamp(base_col.b + vary2, 0.0, 1.0))
			var mat := StandardMaterial3D.new()
			mat.albedo_color = piece_col
			var is_hot: bool = _ast_type == "comet" \
					and piece_col.b > 0.85 and piece_col.r > 0.75
			mat.emission_enabled = piece_col.r > 0.7 or is_hot
			if mat.emission_enabled:
				mat.emission = piece_col
				mat.emission_energy_multiplier = 1.2 if _ast_type == "m_type" else 1.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.set_surface_override_material(0, mat)

			# Tight positional offset so pieces read as one chunk
			var spread: Vector3 = (tangent * randf_range(-1.0, 1.0)
			                     + bitangent * randf_range(-1.0, 1.0)).normalized()
			mi.position = _end_pos + spread * randf_range(0.0, 0.05)
			mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			add_child(mi)

			# Slight per-piece velocity variation to make cluster drift apart over time
			var piece_vel: Vector3 = vel + spread * randf_range(0.0, 0.4)
			_debris.append({
				"mi":       mi,
				"vel":      piece_vel,
				"spin":     spin,
				"life":     0.0,
				"max_life": piece_life,
				"mat":      mat,
			})


# ── Main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _phase == 0:
		_t = move_toward(_t, 1.0, delta / (FALL_BASE_DURATION + _intensity * 0.1))
		var new_pos: Vector3 = _start_pos.lerp(_end_pos, _t * _t)
		if _ext_rock:
			# Drive the camera-child rock via world position so it tracks the arc correctly
			_ext_rock.global_position = new_pos + (_planet as Node3D).global_position
		else:
			_meteor.position = new_pos
			var dir: Vector3 = (_end_pos - _meteor.position).normalized()
			if dir.length_squared() > 0.001:
				var up: Vector3 = Vector3.RIGHT if abs(dir.dot(Vector3.UP)) > 0.95 else Vector3.UP
				_meteor.look_at(_meteor.global_position + dir, up)
		_update_trail()

		# Spawn fire pixels — more frequent as asteroid gets closer
		var rate: float = lerp(8.0, 22.0, _t)  # pixels per second
		_fire_accum += delta * rate
		while _fire_accum >= 1.0:
			_spawn_fire_pixel(_active_pos())
			_fire_accum -= 1.0

		_update_fire_pixels(delta)

		if _t >= 1.0:
			_on_impact()
		return

	_update_rings(delta)
	_update_fire_pixels(delta)

	var all_done := true
	for d in _debris:
		d["life"] += delta
		var progress: float = d["life"] / d["max_life"]
		var mi := d["mi"] as MeshInstance3D
		if progress >= 1.0:
			mi.visible = false
			continue
		all_done = false
		d["vel"] = d["vel"] + (-_surf_normal * 6.5 * delta)
		mi.position += (d["vel"] as Vector3) * delta
		mi.rotation += (d["spin"] as Vector3) * delta
		var alpha: float = 1.0 - smoothstep(0.80, 1.0, progress)
		(d["mat"] as StandardMaterial3D).albedo_color.a = alpha

	var rings_done := _rings.all(func(r) -> bool:
		return r["life"] - r["delay"] >= r["max_life"]
	)
	var fire_done := _fire_pixels.all(func(p) -> bool:
		return p["life"] >= p["max_life"]
	)
	if all_done and rings_done and fire_done:
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
	print("[ImpactEffect] _on_impact() rings=", _rings.size(), " debris=", _debris.size(),
		" is_sea=", _is_sea, " type=", _ast_type, " end_pos=", _end_pos)

	# DIAGNOSTIC: big glowing sphere at impact point so we know Child meshes CAN render
	var dbg := MeshInstance3D.new()
	var dbg_m := SphereMesh.new()
	dbg_m.radius = 0.5
	dbg.mesh = dbg_m
	var dbg_mat := StandardMaterial3D.new()
	dbg_mat.albedo_color = Color(1.0, 0.0, 1.0)
	dbg_mat.emission_enabled = true
	dbg_mat.emission = Color(1.0, 0.0, 1.0)
	dbg_mat.emission_energy_multiplier = 12.0
	dbg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dbg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dbg.set_surface_override_material(0, dbg_mat)
	dbg.position = _end_pos + _surf_normal * 0.5
	add_child(dbg)

	if _planet.has_method("apply_impact"):
		_planet.apply_impact((_tile as RefCounted).tile_id, _end_pos, _intensity, _irregular_core)

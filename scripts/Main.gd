extends Node3D

const EPOCH_NAMES := ["Cambrian", "Carboniferous", "Permian", "Jurassic",
		"Cretaceous", "Eocene", "Pleistocene", "Holocene"]
const EPOCH_KEYS  := ["cambrian", "carboniferous", "permian", "jurassic",
		"cretaceous", "eocene", "pleistocene", "holocene"]
# Additive linear-space tint applied to the space background per epoch
const EPOCH_GHOST_COLORS := {
	"cambrian":      Vector3(0.28, 0.50, 0.56),
	"carboniferous": Vector3(0.42, 0.52, 0.28),
	"permian":       Vector3(0.52, 0.36, 0.22),
	"jurassic":      Vector3(0.28, 0.50, 0.30),
	"cretaceous":    Vector3(0.40, 0.42, 0.46),
	"eocene":        Vector3(0.28, 0.40, 0.60),
	"pleistocene":   Vector3(0.28, 0.38, 0.65),
	"holocene":      Vector3(0.44, 0.44, 0.38),
}

const EPOCH_TINTS := {
	"cambrian":      Vector3(0.001,  0.002,  0.003),
	"carboniferous": Vector3(0.0025, 0.0025, 0.0),
	"permian":       Vector3(0.003,  0.0015, 0.0005),
	"jurassic":      Vector3(0.002,  0.0025, 0.0005),
	"cretaceous":    Vector3(0.0005, 0.0005, 0.0005),
	"eocene":        Vector3(0.001,  0.0015, 0.003),
	"pleistocene":   Vector3(0.0005, 0.001,  0.0035),
	"holocene":      Vector3(0.002,  0.002,  0.0015),
}

# Belt configuration
const SLOT_COUNT    := 3
const SLOT_COOLDOWN := 20.0   # seconds per slot
const SLOT_DRAG_DEPTH := 6.0  # units from camera while dragging
const SLOT_HIT_RADIUS := 60.0 # screen-pixel radius for drag pickup
const SLOT_HOME_POS := [
	Vector3(-4.0, -4.81, -9.0),
	Vector3( 0.0, -4.83, -9.0),
	Vector3( 4.0, -4.81, -9.0),
]

var planet:           Planet
var _smooth_planet:   EarthPlanet
var _sky_mat:         ShaderMaterial
var _dev_label:       Label
var _cam:             Camera3D
var _cam_base:        Vector3
var _shake_intensity: float = 0.0
var _shake_decay:     float = 0.0

# Belt state — one entry per slot
var _slot_rocks:   Array[Node3D] = []   # MeshInstance3D parented to camera
var _slot_cd:      Array[float]  = []   # cooldown remaining (0 = ready)
var _slot_flying:  Array[bool]   = []   # impact in flight
var _slot_hidden:  Array[bool]   = []   # hidden post-impact, counting down

var _belt_ui:     BeltUI
var _bombard_ui:  BombardmentUI
var _epoch_rock:  Asteroid      # 3D ghost asteroid on the belt arc
var _epoch_frags: int = 0
var _epoch_frags_total: int = 4

const BOMBARD_INTERVAL := 10.0   # seconds between auto impacts in gameplay
var _bombard_timer: float = 1.0  # first auto strike after 1 s (diagnostic)

# Drag state
var _drag_slot:  int     = -1     # slot being dragged (-1 = none)
var _last_mouse: Vector2 = Vector2.ZERO

# Top bar labels
var _label_current: Label
var _label_alltime: Label


func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_camera()

	planet = $Planet if has_node("Planet") else Planet.new()
	if not planet.is_inside_tree():
		add_child(planet)

	planet.impact_landed.connect(func(tile_id: int, intensity: float) -> void:
		screen_shake(intensity)
		GameState.add_dust(maxf(50.0, intensity * 250.0))
	)

	_setup_star_field()
	_setup_smooth_planet()
	_setup_belt()  # cloud is now owned by BeltUI._draw() — no Sprite3D needed
	_setup_epoch_rock()
	_setup_top_bar()
	_setup_dev_ui()
	_setup_bombardment_ui()

	GameState.dust_changed.connect(_on_dust_changed)


# ---------------------------------------------------------------------------
# Belt setup
# ---------------------------------------------------------------------------

func _setup_belt() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	# BeltUI — drawn Control covering full viewport
	_belt_ui = BeltUI.new()
	_belt_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_belt_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_belt_ui)

	const SLOT_TYPES := ["c_type", "s_type", "m_type"]
	for s in SLOT_COUNT:
		var rock := Asteroid.new()
		rock.asteroid_type = SLOT_TYPES[s] if s < SLOT_TYPES.size() else "c_type"
		rock.variation     = s
		rock.scale         = Vector3.ONE * 1.3
		rock.position      = SLOT_HOME_POS[s]
		_cam.add_child(rock)
		_slot_rocks.append(rock)
		_slot_cd.append(0.0)
		_slot_flying.append(false)
		_slot_hidden.append(false)

	# Initialise BeltUI arrays
	_belt_ui.slot_screen_pos.resize(SLOT_COUNT)
	_belt_ui.slot_cd_frac.resize(SLOT_COUNT)
	_belt_ui.slot_ready.resize(SLOT_COUNT)
	_belt_ui.slot_flying.resize(SLOT_COUNT)
	for s in SLOT_COUNT:
		_belt_ui.slot_screen_pos[s] = Vector2.ZERO
		_belt_ui.slot_cd_frac[s]   = 1.0
		_belt_ui.slot_ready[s]     = true
		_belt_ui.slot_flying[s]    = false


func _setup_bombardment_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 6
	add_child(canvas)
	_bombard_ui = BombardmentUI.new()
	canvas.add_child(_bombard_ui)


# ---------------------------------------------------------------------------
# Top bar UI
# ---------------------------------------------------------------------------

func _setup_smooth_planet() -> void:
	# Star sphere from _setup_star_field() conflicts with the sky shader — hide it
	if _star_sphere:
		_star_sphere.visible = false

	# Shift planet node up so the planet sits in the upper third of the screen.
	# Tile planet moves too so hitboxes and visuals stay aligned.
	const PLANET_Y    := 2.8
	const PLANET_SCALE := 12.35
	planet.position.y = PLANET_Y

	_smooth_planet = EarthPlanet.new()
	_smooth_planet.position   = Vector3(0.0, PLANET_Y, 0.0)
	_smooth_planet.scale      = Vector3.ONE * PLANET_SCALE
	_smooth_planet.ring_scale    = PLANET_SCALE
	# Shift the ring billboard upward so its UV centre aligns with the sphere's apparent
	# visual centre under perspective. At PLANET_Y=2.8, camera z=17: the silhouette
	# extends ~296 px above and ~261 px below the projected sphere centre, so the visual
	# centre is ~17.5 px (≈0.42 world units) above the geometric centre.
	# In EarthPlanet local space (÷ PLANET_SCALE): 0.42 / 12.35 ≈ 0.034.
	_smooth_planet.ring_y_offset = 0.034
	add_child(_smooth_planet)
	# Set properties after add_child so _refresh() runs with the node in the tree
	_smooth_planet.show_clouds      = true
	_smooth_planet.show_shadow      = true
	_smooth_planet.atmosphere_ring  = true
	_smooth_planet.epoch            = _epoch_key()
	_fix_smooth_planet_spin()
	# Hide the tile planet mesh — mechanics stay active, visuals replaced
	planet.visible = false
	_sky_mat.set_shader_parameter("epoch_tint", EPOCH_TINTS.get(_epoch_key(), Vector3.ZERO))


func _fix_smooth_planet_spin() -> void:
	# JSON spin_speed (0.65) is fast for the generator; match the tile planet (TAU/90 s).
	# sun_dir default is side-lit; match main_smooth.gd (mostly camera-facing).
	var smat := _smooth_planet.material_override as ShaderMaterial
	if smat:
		smat.set_shader_parameter("spin_speed", 0.030)
		smat.set_shader_parameter("sun_dir", Vector3(0.3, 0.25, 0.92))


func _apply_epoch_ghost_color(_key: String) -> void:
	# Derive the ghost hue from the planet's atmosphere colour so the ghostly shell
	# reads as being lit by — and continuous with — the atmosphere ring glow.
	var ac := Color(0.28, 0.40, 0.65)  # fallback blue-grey
	if _smooth_planet:
		var mat := _smooth_planet.material_override as ShaderMaterial
		if mat:
			var v = mat.get_shader_parameter("atmosphere_color")
			if v is Color:
				ac = v
			elif v is Vector3:
				ac = Color((v as Vector3).x, (v as Vector3).y, (v as Vector3).z)
	var gv := Vector3(ac.r, ac.g, ac.b)
	if _epoch_rock:
		var mat := _epoch_rock.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("ghost_color", gv)
	if _belt_ui:
		_belt_ui.epoch_ghost_color = Color(gv.x, gv.y, gv.z)


func _epoch_key() -> String:
	return EPOCH_KEYS[planet.current_age]


func _setup_epoch_rock() -> void:
	_epoch_rock = Asteroid.new()
	_epoch_rock.asteroid_type = "c_type"
	_epoch_rock.ghost_fill    = 0.0       # starts as pure ghost
	_epoch_rock.tumble_x      = 0.04
	_epoch_rock.tumble_y      = 0.09
	_epoch_rock.tumble_z      = 0.02
	# Far right of belt arc — y=-4.72 puts centre on the arc at camera-local x=8
	_epoch_rock.position = Vector3(8.0, -4.72, -9.0)
	_epoch_rock.scale    = Vector3.ONE * 1.45
	_cam.add_child(_epoch_rock)
	_apply_epoch_ghost_color(_epoch_key())


func _setup_top_bar() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 60)
	canvas.add_child(bar)

	# Left — current dust
	var left := _make_dust_block("COSMIC DUST", Color(0.95, 0.85, 0.4))
	bar.add_child(left)
	_label_current = left.get_child(1) as Label

	# Centre spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# Right — all-time dust
	var right := _make_dust_block("ALL-TIME DUST", Color(0.6, 0.8, 1.0))
	bar.add_child(right)
	_label_alltime = right.get_child(1) as Label

	_refresh_dust_labels(0.0, 0.0)


func _make_dust_block(header: String, col: Color) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(260, 0)

	var hdr := Label.new()
	hdr.text = header
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", col.darkened(0.25))
	vbox.add_child(hdr)

	var val := Label.new()
	val.text = "0"
	val.add_theme_font_size_override("font_size", 28)
	val.add_theme_color_override("font_color", col)
	val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	val.add_theme_constant_override("shadow_offset_x", 1)
	val.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(val)

	return vbox


func _on_dust_changed(current: float, alltime: float) -> void:
	_refresh_dust_labels(current, alltime)


func _refresh_dust_labels(current: float, alltime: float) -> void:
	if _label_current:
		_label_current.text = _fmt_dust(current)
	if _label_alltime:
		_label_alltime.text = _fmt_dust(alltime)


func _fmt_dust(v: float) -> String:
	if v >= 1_000_000_000.0:
		return "%.2fB" % (v / 1_000_000_000.0)
	if v >= 1_000_000.0:
		return "%.2fM" % (v / 1_000_000.0)
	if v >= 1_000.0:
		return "%.1fK" % (v / 1_000.0)
	return "%d" % int(v)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not (event as InputEventKey).pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_1: planet.subdivision_depth = 1
		KEY_2: planet.subdivision_depth = 2
		KEY_3: planet.subdivision_depth = 3
		KEY_4: planet.subdivision_depth = 4
		KEY_LEFT:  _cycle_epoch(-1)
		KEY_RIGHT: _cycle_epoch(1)
		KEY_SPACE: _test_impact()
		KEY_E:     _try_fire_slot(0)   # dev shortcut — fire slot 0 at random tile
		KEY_F:     _add_epoch_fragment()      # dev shortcut — add fragment


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		_last_mouse = pos
		_on_mouse_move(pos)
		if _drag_slot >= 0:
			_update_drag_position(pos)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_begin_drag(mb.position)
			else:
				_end_drag(mb.position)


# ---------------------------------------------------------------------------
# Belt drag
# ---------------------------------------------------------------------------

func _try_begin_drag(screen_pos: Vector2) -> void:
	for s in SLOT_COUNT:
		if not _slot_is_ready(s):
			continue
		var proj := _slot_screen_pos(s)
		if screen_pos.distance_to(proj) <= SLOT_HIT_RADIUS:
			_drag_slot = s
			return
	# No belt slot hit — pass through to planet click
	_on_mouse_click(screen_pos)


func _update_drag_position(screen_pos: Vector2) -> void:
	if _drag_slot < 0:
		return
	var world_pos := _screen_to_world_at_depth(screen_pos, SLOT_DRAG_DEPTH)
	_slot_rocks[_drag_slot].position = _cam.to_local(world_pos)


func _end_drag(screen_pos: Vector2) -> void:
	if _drag_slot < 0:
		return
	var slot := _drag_slot
	_drag_slot = -1

	# Try to hit a planet tile at cursor position
	var tile := planet.get_tile_at_screen_pos(screen_pos, _cam)
	if tile != null:
		_fire_slot(slot, tile)
	else:
		# Snap rock back to home position
		_slot_rocks[slot].position = SLOT_HOME_POS[slot]


func _try_fire_slot(slot: int) -> void:
	if not _slot_is_ready(slot):
		return
	var tile := planet.get_selected_tile()
	if tile == null:
		var visible := _random_visible_tile()
		if visible == null:
			return
		tile = visible
	_fire_slot(slot, tile)


func _fire_slot(slot: int, target_tile: Object) -> void:
	_slot_flying[slot] = true
	var rock := _slot_rocks[slot]
	rock.reparent(planet, true)
	var ast_type: String = "c_type"
	if rock.has_method("get") and "asteroid_type" in rock:
		ast_type = str(rock.get("asteroid_type"))
	planet.trigger_impact_with_rock(
		target_tile.tile_id,
		planet.impact_meteor_intensity,
		rock,
		func() -> void: _on_slot_landed(slot),
		ast_type
	)


func _on_slot_landed(slot: int) -> void:
	_slot_flying[slot] = false
	_slot_hidden[slot] = true
	_slot_cd[slot]     = SLOT_COOLDOWN


func _add_epoch_fragment() -> void:
	if _epoch_frags >= _epoch_frags_total:
		return
	_epoch_frags += 1
	_epoch_rock.ghost_fill = float(_epoch_frags) / float(_epoch_frags_total)


func _slot_is_ready(slot: int) -> bool:
	return not _slot_flying[slot] and not _slot_hidden[slot] and _slot_cd[slot] <= 0.0


func _slot_screen_pos(slot: int) -> Vector2:
	var world := _cam.to_global(_slot_rocks[slot].position)
	return _cam.unproject_position(world)


# ---------------------------------------------------------------------------
# Process
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Star sphere slow drift — very subtle parallax
	if _star_sphere:
		_star_sphere.rotation_degrees.y += delta * 2.5
		_star_sphere.rotation_degrees.x += delta * 0.6

	# Screen shake
	if _shake_intensity > 0.0:
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0
		) * _shake_intensity * 0.20
		_cam.position    = _cam_base + offset
		_shake_intensity = move_toward(_shake_intensity, 0.0, delta * _shake_decay)
	elif _cam.position != _cam_base:
		_cam.position = _cam_base

	# Per-slot updates
	for s in SLOT_COUNT:
		var rock := _slot_rocks[s]

		if not _slot_flying[s] and not _slot_hidden[s]:
			pass  # Asteroid._process() handles tumble

		if _slot_hidden[s]:
			_slot_cd[s] -= delta
			if _slot_cd[s] <= 0.0:
				_slot_cd[s]     = 0.0
				_slot_hidden[s] = false
				rock.reparent(_cam, false)
				rock.position = SLOT_HOME_POS[s]
				rock.visible  = true

	# Feed BeltUI — project slot positions and push state
	for s in SLOT_COUNT:
		var home := SLOT_HOME_POS[s] as Vector3
		_belt_ui.slot_screen_pos[s] = _cam.unproject_position(_cam.to_global(home))
		_belt_ui.slot_flying[s]     = _slot_flying[s]
		_belt_ui.slot_ready[s]      = _slot_is_ready(s)
		if _slot_hidden[s]:
			_belt_ui.slot_cd_frac[s] = 1.0 - (_slot_cd[s] / SLOT_COOLDOWN)
		else:
			_belt_ui.slot_cd_frac[s] = 1.0

	# Push epoch rock position and state
	if _epoch_rock:
		_belt_ui.epoch_screen_pos  = _cam.unproject_position(_cam.to_global(_epoch_rock.position))
		_belt_ui.epoch_ghost_fill  = _epoch_rock.ghost_fill
		_belt_ui.epoch_frag_count  = _epoch_frags
		_belt_ui.epoch_ready       = (_epoch_frags >= _epoch_frags_total)

	_belt_ui.queue_redraw()

	_bombard_ui.dust_total    = int(GameState.alltime_dust)
	_bombard_ui.current_epoch = EPOCH_NAMES[planet.current_age]
	_bombard_ui.queue_redraw()

	# Auto bombardment — constant background barrage
	_bombard_timer -= delta
	if _bombard_timer <= 0.0:
		_bombard_timer = BOMBARD_INTERVAL
		_auto_bombard()


# ---------------------------------------------------------------------------
# Planet helpers
# ---------------------------------------------------------------------------

func _random_ast_type() -> String:
	var r := randf()
	if r < 0.38: return "c_type"
	if r < 0.70: return "s_type"
	if r < 0.88: return "m_type"
	return "comet"


func _test_impact() -> void:
	var tile := _random_visible_tile()
	if tile == null:
		return
	var intensity: float = randf_range(planet.impact_intensity_min, planet.impact_intensity_max)
	planet.trigger_impact(tile.tile_id, intensity, _random_ast_type())


func _auto_bombard() -> void:
	var tile := _random_visible_tile()
	if tile == null:
		return
	var ast_type := _random_ast_type()
	var base_intensity: float = 0.3 + float(planet.current_age) * 0.08
	var intensity: float = clamp(base_intensity + randf_range(-0.15, 0.15), 0.15, 1.5)
	planet.trigger_impact(tile.tile_id, intensity, ast_type)


func _random_visible_tile() -> Object:
	if planet._geo_tiles.is_empty():
		return null
	var planet_to_cam := (_cam.global_position - planet.global_position).normalized()
	var basis := planet.global_transform.basis
	var visible: Array = planet._geo_tiles.filter(func(t) -> bool:
		return (basis * (t as Object).center_position as Vector3).normalized().dot(planet_to_cam) > 0.2
	)
	if visible.is_empty():
		return null
	return visible[randi() % visible.size()]


func _cycle_epoch(dir: int) -> void:
	planet.current_age = (planet.current_age + dir + 8) % 8
	var key := _epoch_key()
	if _smooth_planet:
		_smooth_planet.epoch = key
		_fix_smooth_planet_spin()
	if _sky_mat:
		_sky_mat.set_shader_parameter("epoch_tint", EPOCH_TINTS.get(key, Vector3.ZERO))
	_apply_epoch_ghost_color(key)
	_dev_label.text = _dev_label_text()


# ---------------------------------------------------------------------------
# Screen and camera helpers
# ---------------------------------------------------------------------------

func screen_shake(intensity: float) -> void:
	_shake_intensity = clamp(intensity, 0.0, 8.0)
	_shake_decay     = 2.5 + intensity * 0.8


func _screen_to_world_at_depth(screen_pos: Vector2, depth: float) -> Vector3:
	return _cam.project_ray_origin(screen_pos) + _cam.project_ray_normal(screen_pos) * depth


func _on_mouse_move(screen_pos: Vector2) -> void:
	var tile := planet.get_tile_at_screen_pos(screen_pos, _cam)
	planet.set_tile_hover(tile.tile_id if tile != null else -1)


func _on_mouse_click(screen_pos: Vector2) -> void:
	var tile := planet.get_tile_at_screen_pos(screen_pos, _cam)
	planet.set_tile_selected(tile.tile_id if tile != null else -1)


# ---------------------------------------------------------------------------
# Scene setup
# ---------------------------------------------------------------------------

func _setup_dev_ui() -> void:
	var canvas := CanvasLayer.new()
	_dev_label  = Label.new()
	_dev_label.position = Vector2(10, 70)
	_dev_label.add_theme_font_size_override("font_size", 14)
	_dev_label.add_theme_color_override("font_color",        Color(1, 1, 0))
	_dev_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_dev_label.add_theme_constant_override("shadow_offset_x", 1)
	_dev_label.add_theme_constant_override("shadow_offset_y", 1)
	_dev_label.text = _dev_label_text()
	canvas.add_child(_dev_label)
	add_child(canvas)


func _dev_label_text() -> String:
	return "[DEV] ◀ ▶ cycle epochs    ← %s →\n1–4 = tile grid size    E = fire slot 0" \
		% EPOCH_NAMES[planet.current_age]


func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env      := Environment.new()

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://planet_smooth/space_background.gdshader") as Shader
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.20, 0.25, 0.35)
	env.ambient_light_energy = 0.4
	env.glow_enabled       = true
	env.glow_intensity     = 1.1
	env.glow_strength      = 1.0
	env.glow_bloom         = 0.15
	env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.85

	env_node.environment = env
	add_child(env_node)


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	sun.light_energy     = 1.8
	sun.light_color      = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled   = false
	add_child(sun)


func _setup_camera() -> void:
	_cam          = Camera3D.new()
	_cam_base     = Vector3(0.0, 0.0, 17.0)
	_cam.position = _cam_base
	_cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	_cam.fov      = 75.0
	_cam.current  = true
	add_child(_cam)


var _star_sphere: MeshInstance3D

func _setup_star_field() -> void:
	var sphere    := SphereMesh.new()
	sphere.radius = 200.0
	sphere.height = 400.0

	var mat       := ShaderMaterial.new()
	mat.shader     = load("res://shaders/stars.gdshader") as Shader

	_star_sphere              = MeshInstance3D.new()
	_star_sphere.mesh          = sphere
	_star_sphere.material_override = mat
	_star_sphere.cast_shadow   = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_star_sphere)


func _setup_tilt_shift() -> void:
	pass  # disabled temporarily — re-enable to restore post-process blur

extends Node3D

const EPOCH_NAMES := ["Cambrian", "Carboniferous", "Permian", "Jurassic", "Cretaceous", "Eocene", "Pleistocene", "Holocene"]

var planet:        Planet
var _dev_label:    Label
var _cam:          Camera3D
var _cam_base:     Vector3
var _shake_intensity: float = 0.0
var _shake_decay:     float = 0.0
var _impact_btn:      Control   # ImpactMeterUI ring overlay
var _impact_rock:     Node3D    # 3D stone model
var _rock_home_pos:   Vector3   = Vector3(-6.2, -4.8, -9.0)  # camera-local home — bottom-left corner
var _rock_in_flight:  bool      = false
var _rock_hidden:     bool      = false
var _drag_active:   bool  = false
var _drag_node:     Control = null


func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_camera()
	_setup_tilt_shift()

	planet = $Planet if has_node("Planet") else Planet.new()
	if not planet.is_inside_tree():
		add_child(planet)
	planet.impact_landed.connect(func(tile_id: int, intensity: float) -> void:
		screen_shake(intensity)
	)

	_setup_dev_ui()
	_setup_impact_ui()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_1: planet.subdivision_depth = 1
		KEY_2: planet.subdivision_depth = 2
		KEY_3: planet.subdivision_depth = 3
		KEY_4: planet.subdivision_depth = 4
		KEY_LEFT:  _cycle_epoch(-1)
		KEY_RIGHT: _cycle_epoch(1)
		KEY_SPACE: _test_impact()
		KEY_E:     _fire_impact_meteor()


func _test_impact() -> void:
	if planet._geo_tiles.is_empty():
		return
	# Only hit tiles facing the camera (visible hemisphere)
	# Transform tile normals into world space to account for planet rotation
	var planet_to_cam: Vector3 = (_cam.global_position - planet.global_position).normalized()
	var basis: Basis = planet.global_transform.basis
	var visible: Array = planet._geo_tiles.filter(func(t) -> bool:
		var world_normal: Vector3 = (basis * (t as PlanetTile).center_position).normalized()
		return world_normal.dot(planet_to_cam) > 0.2
	)
	if visible.is_empty():
		return
	var tile           := visible[randi() % visible.size()] as PlanetTile
	var intensity: float = randf_range(planet.impact_intensity_min, planet.impact_intensity_max)
	planet.trigger_impact(tile.tile_id, intensity)


func _fire_impact_meteor() -> void:
	(_impact_btn as Node).call("fire")


func _do_impact_strike() -> void:
	if _rock_in_flight or _rock_hidden or _impact_rock == null:
		return

	# Pick target tile
	var target_tile: PlanetTile = planet.get_selected_tile()
	if target_tile == null:
		var planet_to_cam: Vector3 = (_cam.global_position - planet.global_position).normalized()
		var basis: Basis = planet.global_transform.basis
		var visible: Array = planet._geo_tiles.filter(func(t) -> bool:
			return (basis * (t as PlanetTile).center_position).normalized().dot(planet_to_cam) > 0.2
		)
		if visible.is_empty():
			return
		target_tile = visible[randi() % visible.size()] as PlanetTile

	# Detach rock from camera into planet-local space (keeps world transform)
	_impact_rock.reparent(planet, true)
	_rock_in_flight = true

	planet.trigger_impact_with_rock(
		target_tile.tile_id,
		planet.impact_meteor_intensity,
		_impact_rock,
		_on_rock_landed
	)


func _on_rock_landed() -> void:
	# Rock is now hidden (done by ImpactEffect). Start cooldown.
	_rock_in_flight = false
	_rock_hidden    = true
	(_impact_btn as Node).call("start_cooldown")  # starts timer without re-firing


func screen_shake(intensity: float) -> void:
	_shake_intensity = clamp(intensity, 0.0, 8.0)
	_shake_decay     = 2.5 + intensity * 0.8  # stronger = slower decay, longer shake


func _process(delta: float) -> void:
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

	# Rotate the rock — tumbles fast in flight, slow while waiting
	if _impact_rock and not _rock_hidden:
		var spin: float = 180.0 if _rock_in_flight else 14.0
		_impact_rock.rotation_degrees.y += delta * spin
		_impact_rock.rotation_degrees.x += delta * spin * 0.55

	# Respawn the rock once cooldown is done
	if _rock_hidden:
		var cd: float = (_impact_btn as Node).get("cooldown_remaining") as float
		if cd <= 0.0:
			_rock_hidden = false
			_impact_rock.reparent(_cam, false)
			_impact_rock.position = _rock_home_pos
			_impact_rock.visible  = true


func _cycle_epoch(dir: int) -> void:
	planet.current_age = (planet.current_age + dir + 8) % 8
	_dev_label.text = _dev_label_text()


func _dev_label_text() -> String:
	var age := planet.current_age
	return "[DEV] ◀ ▶ cycle epochs    ← %s →\n1–4 = tile grid size" \
		% EPOCH_NAMES[age]


func _setup_dev_ui() -> void:
	var canvas    := CanvasLayer.new()
	_dev_label     = Label.new()
	_dev_label.position = Vector2(10, 10)
	_dev_label.add_theme_font_size_override("font_size", 14)
	_dev_label.add_theme_color_override("font_color",        Color(1, 1, 0))
	_dev_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_dev_label.add_theme_constant_override("shadow_offset_x", 1)
	_dev_label.add_theme_constant_override("shadow_offset_y", 1)
	_dev_label.text = _dev_label_text()
	canvas.add_child(_dev_label)
	add_child(canvas)


func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env      := Environment.new()

	env.background_mode  = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)

	# Clay needs real ambient — not flat like Dorfromantik, not dark like space.
	# This level gives clear shape definition while keeping the soft putty feel.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.20, 0.25, 0.35)
	env.ambient_light_energy = 0.4

	env_node.environment = env
	add_child(env_node)


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	# Steep enough (-35°) to show hex facet differences, Y=10° so shadow falls behind
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


func _setup_impact_ui() -> void:
	# 3D rock parented to camera — sits in the bottom-left corner of the view
	var rock_scene = load("res://assets/Kenny nature pack/stone_largeC.glb")
	if rock_scene:
		_impact_rock          = rock_scene.instantiate() as Node3D
		_impact_rock.scale    = Vector3(1.1, 1.1, 1.1)
		# Camera-local position: left, down, forward
		_impact_rock.position = Vector3(-4.8, -3.6, -9.0)
		_cam.add_child(_impact_rock)
		# Apply pixel art shader to all mesh surfaces in the GLB
		var rock_mat := ShaderMaterial.new()
		rock_mat.shader = load("res://shaders/pixel_rock.gdshader") as Shader
		for child in _impact_rock.find_children("*", "MeshInstance3D", true):
			var mi := child as MeshInstance3D
			for s in range(mi.get_surface_override_material_count()):
				mi.set_surface_override_material(s, rock_mat)

	# ImpactMeterUI kept for cooldown logic but ring is hidden
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	_impact_btn = load("res://scripts/ImpactMeterUI.gd").new()
	(_impact_btn as Node).set("cooldown_max", 30.0)
	(_impact_btn as Node).connect("fired", _do_impact_strike)
	(_impact_btn as Control).visible = false
	canvas.add_child(_impact_btn)


func _setup_tilt_shift() -> void:
	pass  # disabled temporarily — re-enable to restore post-process blur



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_move((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Check if click is on the impact rock first
			if _impact_rock:
				var rock_screen: Vector2 = _cam.unproject_position(_impact_rock.global_position)
				if mb.position.distance_to(rock_screen) < 52.0:
					_fire_impact_meteor()
					return
			_on_mouse_click(mb.position)


func _on_mouse_move(screen_pos: Vector2) -> void:
	var tile := planet.get_tile_at_screen_pos(screen_pos, _cam)
	planet.set_tile_hover(tile.tile_id if tile != null else -1)


func _on_mouse_click(screen_pos: Vector2) -> void:
	var tile := planet.get_tile_at_screen_pos(screen_pos, _cam)
	planet.set_tile_selected(tile.tile_id if tile != null else -1)

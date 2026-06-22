@tool
extends EditorPlugin

# Current paint type — a terrain type string ("FOREST_DENSE", etc.) or "ASSET"
var _paint_type:  String  = "BARE_ROCK"
var _asset_path:  String  = ""

var _panel:           Control     = null
var _type_row:        HBoxContainer = null   # rebuilt when epoch changes
var _last_age:        int         = -1
var _last_planet:     Planet      = null


func _enter_tree() -> void:
	_panel = _build_panel()
	add_control_to_bottom_panel(_panel, "Planet Editor")
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	var sel := get_editor_interface().get_selection()
	if sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)


func _handles(object: Object) -> bool:
	return object is Planet


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not event is InputEventMouseButton:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var planet := _get_selected_planet()
	if planet == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Refresh palette if epoch changed
	_maybe_refresh_palette(planet)

	var tile_id := _pick_tile(viewport_camera, mb.position, planet)
	if tile_id < 0:
		# Consume click so the editor does not deselect the planet node
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if _paint_type == "ASSET":
		if _asset_path != "":
			_place_asset(planet, tile_id, _asset_path)
			get_editor_interface().mark_scene_as_unsaved()
	else:
		_paint_tile(planet, tile_id, _paint_type)

	return EditorPlugin.AFTER_GUI_INPUT_STOP


# ── Paint with undo/redo ──────────────────────────────────────────────────────

func _paint_tile(planet: Planet, tile_id: int, terrain_type: String) -> void:
	var ur := get_undo_redo()
	var had_override: bool   = planet.tile_overrides.has(tile_id)
	var old_value            = planet.tile_overrides.get(tile_id, "")

	ur.create_action("Paint Tile %s" % terrain_type)
	ur.add_do_method(planet, "set_tile_override", tile_id, terrain_type)
	if had_override:
		ur.add_undo_method(planet, "set_tile_override", tile_id, old_value)
	else:
		ur.add_undo_method(planet, "clear_tile_override", tile_id)
	ur.commit_action()

	get_editor_interface().mark_scene_as_unsaved()


# ── Tile picking ──────────────────────────────────────────────────────────────

func _get_selected_planet() -> Planet:
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is Planet:
			return node
	return null


func _pick_tile(camera: Camera3D, mouse_pos: Vector2, planet: Planet) -> int:
	if planet._geo_tiles.is_empty():
		return -1

	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)

	var planet_pos := planet.global_position
	var oc         := ray_origin - planet_pos
	var r          := planet.planet_radius + planet.tile_raise + planet.land_height
	var b          := oc.dot(ray_dir)
	var c          := oc.dot(oc) - r * r
	var disc       := b * b - c
	if disc < 0.0:
		return -1
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	if t < 0.0:
		return -1

	var hit       := ray_origin + ray_dir * t
	var local_hit := planet.global_transform.affine_inverse() * hit
	var local_dir := local_hit.normalized()

	var best_id  := -1
	var best_dot := -1.0
	for tile in planet._geo_tiles:
		var d: float = (tile as PlanetTile).center_position.dot(local_dir)
		if d > best_dot:
			best_dot = d
			best_id  = (tile as PlanetTile).tile_id

	return best_id


# ── Asset placement ───────────────────────────────────────────────────────────

func _place_asset(planet: Planet, tile_id: int, scene_path: String) -> void:
	var tile: PlanetTile = null
	for t in planet._geo_tiles:
		if (t as PlanetTile).tile_id == tile_id:
			tile = t
			break
	if tile == null:
		return

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Planet Editor: could not load scene '%s'" % scene_path)
		return

	var instance := packed.instantiate() as Node3D
	instance.name = "Asset_tile%d" % tile_id
	instance.set_meta("planet_tile_id", tile_id)

	var up     := tile.center_position.normalized()
	var surf_r := planet.planet_radius + planet.tile_raise + planet.land_height + 0.05
	var ref    := Vector3.RIGHT if abs(up.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var right  := up.cross(ref).normalized()
	var fwd    := right.cross(up)
	instance.transform = Transform3D(Basis(right, up, fwd), up * surf_r)

	planet.add_child(instance)
	instance.owner = get_tree().get_edited_scene_root()


# ── Palette building ──────────────────────────────────────────────────────────

func _on_selection_changed() -> void:
	var planet := _get_selected_planet()
	if planet:
		_rebuild_palette_buttons(planet)
		_last_planet = planet
		_last_age    = planet.current_age


func _maybe_refresh_palette(planet: Planet) -> void:
	if planet != _last_planet or planet.current_age != _last_age:
		_rebuild_palette_buttons(planet)
		_last_planet = planet
		_last_age    = planet.current_age


func _rebuild_palette_buttons(planet: Planet) -> void:
	if _type_row == null:
		return
	# Clear old buttons
	for child in _type_row.get_children():
		child.queue_free()

	var palette: Dictionary = planet.get_epoch_data().get("palette", {})
	var epoch_name: String  = planet.get_epoch_data().get("name", "?")

	var lbl := Label.new()
	lbl.text = "Epoch %d – %s   Paint:" % [planet.current_age, epoch_name]
	_type_row.add_child(lbl)

	var first_type: String = ""
	for terrain_type in palette.keys():
		if first_type == "":
			first_type = terrain_type
		var col: Color = palette[terrain_type]
		var btn        := _make_type_button(terrain_type, col)
		_type_row.add_child(btn)

	_type_row.add_child(VSeparator.new())

	var asset_btn := Button.new()
	asset_btn.text          = "Place Asset"
	asset_btn.toggle_mode   = true
	asset_btn.button_pressed = (_paint_type == "ASSET")
	asset_btn.pressed.connect(func() -> void:
		_paint_type = "ASSET"
		_sync_type_buttons()
	)
	_type_row.add_child(asset_btn)

	# Default to first available type if current type not in new palette
	if not palette.has(_paint_type) and _paint_type != "ASSET":
		_paint_type = first_type if first_type != "" else "BARE_ROCK"

	_sync_type_buttons()


func _make_type_button(terrain_type: String, col: Color) -> Button:
	var btn := Button.new()
	btn.text        = terrain_type.replace("_", " ").capitalize()
	btn.toggle_mode = true
	btn.custom_minimum_size.x = 90

	# Colour the button background
	var style := StyleBoxFlat.new()
	style.bg_color      = col
	style.border_width_bottom = 3
	style.border_color  = Color(1, 1, 1, 0.0)
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal",   style)
	var style_pressed := style.duplicate()
	style_pressed.border_color = Color.WHITE
	style_pressed.border_width_bottom = 3
	btn.add_theme_stylebox_override("pressed", style_pressed)

	# Pick readable text colour (light or dark) based on luminance
	var lum: float = col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	var txt_col    := Color.BLACK if lum > 0.5 else Color.WHITE
	btn.add_theme_color_override("font_color",          txt_col)
	btn.add_theme_color_override("font_pressed_color",  txt_col)
	btn.add_theme_color_override("font_hover_color",    txt_col)

	btn.set_meta("terrain_type", terrain_type)
	btn.pressed.connect(func() -> void:
		_paint_type = terrain_type
		_sync_type_buttons()
	)
	return btn


func _sync_type_buttons() -> void:
	if _type_row == null:
		return
	for child in _type_row.get_children():
		if child is Button and child.has_meta("terrain_type"):
			child.button_pressed = (child.get_meta("terrain_type") == _paint_type)
		elif child is Button and child.text == "Place Asset":
			child.button_pressed = (_paint_type == "ASSET")


# ── Bottom panel ──────────────────────────────────────────────────────────────

func _build_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Top row: palette type buttons (rebuilt per epoch)
	_type_row = HBoxContainer.new()
	_type_row.add_theme_constant_override("separation", 4)
	vbox.add_child(_type_row)

	# Default placeholder until a planet is selected
	var placeholder := Label.new()
	placeholder.text = "Select a Planet node to paint tiles."
	_type_row.add_child(placeholder)

	# Bottom row: asset placement + utilities
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 6)

	var asset_lbl := Label.new()
	asset_lbl.text = "Asset scene:"
	bot.add_child(asset_lbl)

	var asset_edit := LineEdit.new()
	asset_edit.placeholder_text    = "res://scenes/my_tree.tscn"
	asset_edit.custom_minimum_size.x = 280
	asset_edit.text_changed.connect(func(t: String) -> void: _asset_path = t)
	bot.add_child(asset_edit)

	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(func() -> void: _open_file_dialog(asset_edit))
	bot.add_child(browse)

	bot.add_child(VSeparator.new())

	var clear := Button.new()
	clear.text = "Clear All Overrides"
	clear.pressed.connect(_clear_overrides)
	bot.add_child(clear)

	vbox.add_child(bot)
	return vbox


func _open_file_dialog(edit: LineEdit) -> void:
	var dlg := EditorFileDialog.new()
	dlg.access    = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.add_filter("*.tscn,*.scn", "Scenes")
	dlg.file_selected.connect(func(path: String) -> void:
		edit.text   = path
		_asset_path = path
		dlg.queue_free()
	)
	get_editor_interface().get_base_control().add_child(dlg)
	dlg.popup_centered_ratio(0.6)


func _clear_overrides() -> void:
	var planet := _get_selected_planet()
	if planet == null:
		return
	var snapshot: Dictionary = planet.tile_overrides.duplicate()
	var ur := get_undo_redo()
	ur.create_action("Clear All Tile Overrides")
	ur.add_do_method(planet, "_apply_overrides_dict", {})
	ur.add_undo_method(planet, "_apply_overrides_dict", snapshot)
	ur.commit_action()
	get_editor_interface().mark_scene_as_unsaved()

extends Node3D

# In-game planet generator: design ONE epoch at a time with live sliders + colour pickers,
# preview exactly as it will look in-game (procedural, lit, atmosphere ring + bloom), then
# "LOCK IN" (Save) -> writes that epoch into earth_epochs.json, which main_smooth.tscn loads.

const EPOCHS := ["cambrian", "carboniferous", "permian", "jurassic", "cretaceous", "eocene", "pleistocene", "holocene"]
const FLOATS := [
	["earth_sea_level", -0.25, 0.25, 0.005],
	["ice_north", 0.0, 1.0, 0.01],
	["ice_south", 0.0, 1.0, 0.01],
	["land_cutoff", 0.2, 0.8, 0.005],
	["continent_scale", 0.8, 4.0, 0.05],
	["continent_mix", 0.0, 1.0, 0.01],
	["ocean_depth", 0.0, 1.0, 0.02],
	["ocean_shallow_amt", 0.0, 1.0, 0.02],
	["wave_flecks", 0.0, 1.0, 0.02],
	["coast_strength", 0.0, 1.0, 0.05],
	["cloud_cover", 0.0, 1.0, 0.01],
	["cloud_size", 2.0, 12.0, 0.25],
	["cloud_wispy", 0.0, 1.0, 0.02],
	["atmosphere_strength", 0.0, 1.0, 0.02],
	["band_smoothness", 0.0, 1.0, 0.02],
	["outline_strength", 0.0, 1.0, 0.05],
	["outline_width", 1.0, 10.0, 0.25],
	["edge_softness", 0.0, 3.0, 0.05],
	["spin_speed", 0.0, 0.3, 0.005],
]
const COLORS := ["color1", "color2", "color3", "landColor1", "landColor2", "landColor3", "landColor4",
				 "ice_color", "ice_color2", "atmosphere_color", "cloud_color", "outline_color",
				 "ocean_shallow_color", "fleck_color"]
const JSON_PATH := "res://planet_smooth/earth_epochs.json"
const EPOCH_TINTS := {
	"cambrian":      Vector3(0.0010, 0.0020, 0.0030),
	"carboniferous": Vector3(0.0025, 0.0025, 0.0000),
	"permian":       Vector3(0.0030, 0.0015, 0.0005),
	"jurassic":      Vector3(0.0020, 0.0025, 0.0005),
	"cretaceous":    Vector3(0.0005, 0.0005, 0.0005),
	"eocene":        Vector3(0.0010, 0.0015, 0.0030),
	"pleistocene":   Vector3(0.0005, 0.0010, 0.0035),
	"holocene":      Vector3(0.0020, 0.0020, 0.0015),
}

var planet: MeshInstance3D
var mat: ShaderMaterial
var current_epoch := "holocene"
var _syncing := false
var _sliders := {}
var _slider_labels := {}
var _color_btns := {}
var _status: Label
var _epoch_opt: OptionButton
var _sky_tint_strength := 1.0
var _ring_strength := 2.5
var _ring_falloff  := 4.0
var _ring_size     := 1.12
var _ring_gradient := 0.5
var _belt_prev: Control

func _ready() -> void:
	planet = $Planet
	mat = planet.material_override
	_build_ui()
	_load_epoch("holocene")

func _build_ui() -> void:
	var panel := Panel.new()
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.anchor_top = 0.0; panel.anchor_bottom = 1.0
	panel.offset_left = -370.0
	$UI.add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 10)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	scroll.add_child(vb)

	_add_title(vb, "PLANET GENERATOR")
	var ep_row := HBoxContainer.new()
	var ep_lbl := Label.new(); ep_lbl.text = "Epoch"; ep_lbl.custom_minimum_size.x = 120
	var ep_opt := OptionButton.new()
	ep_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in EPOCHS:
		ep_opt.add_item(e.capitalize())
	ep_opt.item_selected.connect(func(i): _load_epoch(EPOCHS[i]))
	ep_row.add_child(ep_lbl); ep_row.add_child(ep_opt)
	vb.add_child(ep_row)
	_epoch_opt = ep_opt

	_add_toggle(vb, "Show clouds", true, func(on): mat.set_shader_parameter("clouds_enabled", on))
	_add_toggle(vb, "Show shadow", true, func(on): mat.set_shader_parameter("shadow_enabled", on))

	_add_sep(vb)
	for f in FLOATS:
		_add_float_row(vb, f[0], f[1], f[2], f[3])
	# atmosphere ring strength (drives the ring child material, not the planet material)
	_add_ring_row(vb)

	_add_sep(vb)
	_add_sky_tint_row(vb)
	_add_sep(vb)
	for c in COLORS:
		_add_color_row(vb, c)

	_add_sep(vb)
	_add_belt_section(vb)

	_setup_belt_preview()

	_add_sep(vb)
	var save_btn := Button.new(); save_btn.text = "★ LOCK IN this epoch (Save)"
	save_btn.pressed.connect(_save_epoch)
	vb.add_child(save_btn)
	var reload_btn := Button.new(); reload_btn.text = "Reload (discard edits)"
	reload_btn.pressed.connect(func(): _load_epoch(current_epoch))
	vb.add_child(reload_btn)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_status)

func _add_title(vb, text) -> void:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 16)
	vb.add_child(l)

func _add_sep(vb) -> void:
	vb.add_child(HSeparator.new())

func _add_toggle(vb, text, default, cb) -> void:
	var c := CheckButton.new(); c.text = text; c.button_pressed = default
	c.toggled.connect(func(on): if not _syncing: cb.call(on))
	vb.add_child(c)

func _add_float_row(vb, pname, mn, mx, step) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new(); lbl.text = pname; lbl.custom_minimum_size.x = 120
	var sl := HSlider.new()
	sl.min_value = mn; sl.max_value = mx; sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new(); val.custom_minimum_size.x = 46
	sl.value_changed.connect(func(v):
		if _syncing: return
		mat.set_shader_parameter(pname, v)
		_sync_ring()
		val.text = "%.3f" % v)
	row.add_child(lbl); row.add_child(sl); row.add_child(val)
	vb.add_child(row)
	_sliders[pname] = sl
	_slider_labels[pname] = val

func _add_ring_row(vb) -> void:
	var RING := [
		["atmo_ring_strength",    0.0, 8.0,  0.05],
		["atmo_ring_falloff",     0.3, 10.0, 0.1],
		["atmo_ring_size",        1.0, 1.5,  0.005],
		["atmo_gradient_strength",0.0, 2.0,  0.05],
	]
	for rdef in RING:
		var pname: String = rdef[0]
		var row := HBoxContainer.new()
		var lbl := Label.new(); lbl.text = pname; lbl.custom_minimum_size.x = 120
		var sl := HSlider.new()
		sl.min_value = rdef[1]; sl.max_value = rdef[2]; sl.step = rdef[3]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Label.new(); val.custom_minimum_size.x = 46
		sl.value_changed.connect(func(v, p = pname, lv = val):
			if _syncing: return
			if   p == "atmo_ring_strength":    _ring_strength = v
			elif p == "atmo_ring_falloff":     _ring_falloff  = v
			elif p == "atmo_ring_size":        _ring_size     = v
			elif p == "atmo_gradient_strength":_ring_gradient = v
			_sync_ring()
			lv.text = "%.3f" % v)
		row.add_child(lbl); row.add_child(sl); row.add_child(val)
		vb.add_child(row)
		_sliders[pname] = sl
		_slider_labels[pname] = val

func _add_color_row(vb, pname) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new(); lbl.text = pname; lbl.custom_minimum_size.x = 120
	var btn := ColorPickerButton.new()
	btn.edit_alpha = false
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 24
	btn.color_changed.connect(func(col):
		if _syncing: return
		mat.set_shader_parameter(pname, col)
		_sync_ring())
	row.add_child(lbl); row.add_child(btn)
	vb.add_child(row)
	_color_btns[pname] = btn

func _add_sky_tint_row(vb) -> void:
	_add_title(vb, "Space Background")
	var row := HBoxContainer.new()
	var lbl := Label.new(); lbl.text = "tint_strength"; lbl.custom_minimum_size.x = 120
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 5.0; sl.step = 0.05
	sl.value = _sky_tint_strength
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new(); val.text = "%.2f" % _sky_tint_strength; val.custom_minimum_size.x = 46
	sl.value_changed.connect(func(v):
		if _syncing: return
		_sky_tint_strength = v
		_set_sky_tint(current_epoch)
		val.text = "%.2f" % v)
	row.add_child(lbl); row.add_child(sl); row.add_child(val)
	vb.add_child(row)
	_sliders["sky_tint_strength"] = sl
	_slider_labels["sky_tint_strength"] = val

func _set_sky_tint(epoch: String) -> void:
	var we := $WorldEnvironment as WorldEnvironment
	if we == null or we.environment == null or we.environment.sky == null:
		return
	var sm := we.environment.sky.sky_material as ShaderMaterial
	if sm:
		sm.set_shader_parameter("epoch_tint", EPOCH_TINTS.get(epoch, Vector3.ZERO))
		sm.set_shader_parameter("tint_strength", _sky_tint_strength)

func _sync_ring() -> void:
	var rm = planet.call("ring_mat")
	if rm == null:
		return
	planet.call("set_ring_size_live", _ring_size)   # resize the quad mesh
	var ac = mat.get_shader_parameter("atmosphere_color")
	if ac is Color:
		rm.set_shader_parameter("ring_color", ac)
	rm.set_shader_parameter("ring_strength",     _ring_strength)
	rm.set_shader_parameter("ring_falloff",      _ring_falloff)
	rm.set_shader_parameter("ring_size",         _ring_size)
	rm.set_shader_parameter("gradient_strength", _ring_gradient)

func _load_epoch(epoch: String) -> void:
	current_epoch = epoch
	if _epoch_opt:
		_epoch_opt.selected = EPOCHS.find(epoch)
	planet.set("epoch", epoch)            # component applies the preset to the material
	mat = planet.material_override
	# preview exactly like the game (main_smooth): procedural + lit toward camera
	mat.set_shader_parameter("use_earth_map", false)
	mat.set_shader_parameter("spin_speed", 0.0)
	mat.set_shader_parameter("sun_dir", Vector3(0.3, 0.25, 0.92))
	_ring_strength = 2.5; _ring_falloff = 4.0; _ring_size = 1.12; _ring_gradient = 0.5
	var rd = _load_json().get(epoch, {})
	if rd.has("atmo_ring_strength"):    _ring_strength = float(rd["atmo_ring_strength"])
	if rd.has("atmo_ring_falloff"):     _ring_falloff  = float(rd["atmo_ring_falloff"])
	if rd.has("atmo_ring_size"):        _ring_size     = float(rd["atmo_ring_size"])
	if rd.has("atmo_gradient_strength"):_ring_gradient = float(rd["atmo_gradient_strength"])
	_set_sky_tint(epoch)
	_sync_ui_from_material()
	_sync_ring()

# small helpers to read the JSON value for ring strength (planet keeps the dict private)
func _epochs_has(epoch, key) -> bool:
	var d := _load_json()
	return d.has(epoch) and d[epoch].has(key)
func _epoch_val(epoch, key):
	return _load_json()[epoch][key]
func _load_json() -> Dictionary:
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _sync_ui_from_material() -> void:
	_syncing = true
	for pname in _sliders.keys():
		if pname == "atmo_ring_strength":
			_sliders[pname].value = _ring_strength
			_slider_labels[pname].text = "%.3f" % _ring_strength
			continue
		if pname == "atmo_ring_falloff":
			_sliders[pname].value = _ring_falloff
			_slider_labels[pname].text = "%.3f" % _ring_falloff
			continue
		if pname == "atmo_ring_size":
			_sliders[pname].value = _ring_size
			_slider_labels[pname].text = "%.3f" % _ring_size
			continue
		if pname == "atmo_gradient_strength":
			_sliders[pname].value = _ring_gradient
			_slider_labels[pname].text = "%.3f" % _ring_gradient
			continue
		if pname == "sky_tint_strength":
			_sliders[pname].value = _sky_tint_strength
			_slider_labels[pname].text = "%.2f" % _sky_tint_strength
			continue
		var v = mat.get_shader_parameter(pname)
		if v == null:
			v = _sliders[pname].min_value
		_sliders[pname].value = v
		_slider_labels[pname].text = "%.3f" % float(v)
	for pname in _color_btns.keys():
		var c = mat.get_shader_parameter(pname)
		if c is Color:
			_color_btns[pname].color = c
	_syncing = false

func _save_epoch() -> void:
	var data := _load_json()
	if not data.has(current_epoch):
		_status.text = "ERROR: epoch missing in JSON"
		return
	var ep: Dictionary = data[current_epoch]
	for fdef in FLOATS:
		var p: String = fdef[0]
		ep[p] = snappedf(float(mat.get_shader_parameter(p)), 0.001)
	for c in COLORS:
		var col = mat.get_shader_parameter(c)
		if col is Color:
			ep[c] = [snappedf(col.r, 0.001), snappedf(col.g, 0.001), snappedf(col.b, 0.001)]
	ep["atmo_ring_strength"]    = snappedf(_ring_strength, 0.01)
	ep["atmo_ring_falloff"]     = snappedf(_ring_falloff,  0.01)
	ep["atmo_ring_size"]        = snappedf(_ring_size,     0.001)
	ep["atmo_gradient_strength"]= snappedf(_ring_gradient, 0.01)
	data[current_epoch] = ep
	var w := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	w.store_string(JSON.stringify(data, "  "))
	w.close()
	planet.call("reload_epochs")   # flush the in-memory cache so switching epochs picks up new values
	_status.text = "✔ Locked in '%s' — main_smooth will use it." % current_epoch


func _setup_belt_preview() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 0
	add_child(cl)
	var bp := BeltPreviewUI.new()
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(bp)
	_belt_prev = bp


func _add_belt_section(vb: VBoxContainer) -> void:
	_add_title(vb, "Asteroid Belt")
	_add_toggle(vb, "Show belt", true, func(on):
		if _belt_prev: _belt_prev.call("set_show", on))

	var defs: Array = [
		["Belt width",  20.0,  200.0,  5.0,   "set_sigma",      80.0],
		["Density",     0.02,  0.50,   0.01,   "set_peak",       0.15],
		["Dust size",   0.5,   8.0,    0.1,    "set_dust_sz",    2.5],
		["Dust alpha",  0.1,   2.0,    0.05,   "set_dust_alpha", 1.0],
		["Dust speed",  0.0,   4.0,    0.1,    "set_speed_mul",  1.0],
		["Dust count",  50.0,  800.0,  10.0,   "set_dust_n_f",   300.0],
	]
	for d in defs:
		var lname:  String = d[0]
		var mn:     float  = d[1]
		var mx:     float  = d[2]
		var step:   float  = d[3]
		var setter: String = d[4]
		var def:    float  = d[5]
		var row := HBoxContainer.new()
		var lbl := Label.new(); lbl.text = lname; lbl.custom_minimum_size.x = 120
		var sl := HSlider.new()
		sl.min_value = mn; sl.max_value = mx; sl.step = step; sl.value = def
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Label.new()
		val.text = "%.2f" % def
		val.custom_minimum_size.x = 46
		sl.value_changed.connect(func(v, s = setter, lv = val):
			if _belt_prev: _belt_prev.call(s, v)
			lv.text = "%.2f" % v)
		row.add_child(lbl); row.add_child(sl); row.add_child(val)
		vb.add_child(row)

	var crow := HBoxContainer.new()
	var clbl := Label.new(); clbl.text = "Belt color"; clbl.custom_minimum_size.x = 120
	var cbtn := ColorPickerButton.new()
	cbtn.edit_alpha = false
	cbtn.color = Color(0.94, 0.91, 0.86)
	cbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbtn.custom_minimum_size.y = 24
	cbtn.color_changed.connect(func(c):
		if _belt_prev: _belt_prev.call("set_belt_color", c))
	crow.add_child(clbl); crow.add_child(cbtn)
	vb.add_child(crow)

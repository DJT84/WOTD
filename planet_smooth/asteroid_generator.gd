extends Node3D

# Asteroid generator: tweak one type at a time, Lock In to save to asteroid_types.json.
# Mirrors the planet generator pattern exactly.

const TYPES    := ["c_type", "s_type", "m_type", "comet", "volcanic"]
const JSON_PATH := "res://planet_smooth/asteroid_types.json"

const FLOATS := [
	["displacement",   0.0,  0.45, 0.005],
	["shape_scale",    0.5,  4.0,  0.05],
	["surface_scale",  1.0,  10.0, 0.1],
	["band_smoothness",0.0,  1.0,  0.01],
	["edge_softness",  0.0,  3.0,  0.05],
	["crater_scale",   1.0,  8.0,  0.1],
	["crater_density", 0.0,  1.0,  0.01],
	["crater_depth",   0.0,  1.0,  0.01],
	["metallic",       0.0,  1.0,  0.01],
	["rim_strength",   0.0,  2.0,  0.02],
	["rim_falloff",    1.0,  8.0,  0.1],
	["outline_strength",0.0, 1.0,  0.02],
	["outline_width",  1.0,  10.0, 0.25],
]
const COLORS := [
	"rock_color1", "rock_color2", "rock_color3", "rock_color4",
	"specular_color", "rim_color", "outline_color",
]

var asteroid: MeshInstance3D
var mat: ShaderMaterial
var current_type := "s_type"
var _syncing := false
var _sliders := {}
var _slider_labels := {}
var _color_btns := {}
var _status: Label
var _type_opt: OptionButton

func _ready() -> void:
	asteroid = $Asteroid
	mat = asteroid.material_override
	_build_ui()
	_load_type("s_type")

func _build_ui() -> void:
	var panel := Panel.new()
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.anchor_top = 0.0;  panel.anchor_bottom = 1.0
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

	_add_title(vb, "ASTEROID GENERATOR")

	var ep_row := HBoxContainer.new()
	var ep_lbl := Label.new(); ep_lbl.text = "Type"; ep_lbl.custom_minimum_size.x = 120
	var ep_opt := OptionButton.new()
	ep_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in TYPES:
		ep_opt.add_item(t.replace("_", " ").capitalize())
	ep_opt.item_selected.connect(func(i): _load_type(TYPES[i]))
	ep_row.add_child(ep_lbl); ep_row.add_child(ep_opt)
	vb.add_child(ep_row)
	_type_opt = ep_opt

	_add_toggle(vb, "Show shadow", true, func(on): mat.set_shader_parameter("shadow_enabled", on))

	_add_sep(vb)
	_add_title(vb, "Shape")
	for f in FLOATS:
		_add_float_row(vb, f[0], f[1], f[2], f[3])

	_add_sep(vb)
	_add_title(vb, "Colors")
	for c in COLORS:
		_add_color_row(vb, c)

	_add_sep(vb)
	var save_btn := Button.new(); save_btn.text = "★ LOCK IN this type (Save)"
	save_btn.pressed.connect(_save_type)
	vb.add_child(save_btn)
	var reload_btn := Button.new(); reload_btn.text = "Reload (discard edits)"
	reload_btn.pressed.connect(func(): _load_type(current_type))
	vb.add_child(reload_btn)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_status)

func _add_title(vb, text) -> void:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 14)
	vb.add_child(l)

func _add_sep(vb) -> void:
	vb.add_child(HSeparator.new())

func _add_toggle(vb, text, default, cb) -> void:
	var c := CheckButton.new(); c.text = text; c.button_pressed = default
	c.toggled.connect(func(on): if not _syncing: cb.call(on))
	vb.add_child(c)

func _add_float_row(vb, pname, mn, mx, step) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new(); lbl.text = pname; lbl.custom_minimum_size.x = 130
	var sl  := HSlider.new()
	sl.min_value = mn; sl.max_value = mx; sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new(); val.custom_minimum_size.x = 46
	sl.value_changed.connect(func(v):
		if _syncing: return
		mat.set_shader_parameter(pname, v)
		val.text = "%.3f" % v)
	row.add_child(lbl); row.add_child(sl); row.add_child(val)
	vb.add_child(row)
	_sliders[pname] = sl
	_slider_labels[pname] = val

func _add_color_row(vb, pname) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new(); lbl.text = pname; lbl.custom_minimum_size.x = 130
	var btn := ColorPickerButton.new()
	btn.edit_alpha = false
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 24
	btn.color_changed.connect(func(col):
		if _syncing: return
		mat.set_shader_parameter(pname, col))
	row.add_child(lbl); row.add_child(btn)
	vb.add_child(row)
	_color_btns[pname] = btn

func _load_type(type: String) -> void:
	current_type = type
	if _type_opt:
		_type_opt.selected = TYPES.find(type)
	asteroid.set("asteroid_type", type)
	mat = asteroid.material_override
	mat.set_shader_parameter("sun_dir", Vector3(0.3, 0.25, 0.92))
	_sync_ui_from_material()
	_status.text = ""

func _sync_ui_from_material() -> void:
	_syncing = true
	for pname in _sliders.keys():
		var v = mat.get_shader_parameter(pname)
		if v == null:
			v = _sliders[pname].min_value
		_sliders[pname].value = float(v)
		_slider_labels[pname].text = "%.3f" % float(v)
	for pname in _color_btns.keys():
		var c = mat.get_shader_parameter(pname)
		if c is Color:
			_color_btns[pname].color = c
	_syncing = false

func _load_json() -> Dictionary:
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _save_type() -> void:
	var data := _load_json()
	if not data.has(current_type):
		_status.text = "ERROR: type missing in JSON"
		return
	var tp: Dictionary = data[current_type]
	for fdef in FLOATS:
		var p: String = fdef[0]
		tp[p] = snappedf(float(mat.get_shader_parameter(p)), 0.001)
	for c in COLORS:
		var col = mat.get_shader_parameter(c)
		if col is Color:
			tp[c] = [snappedf(col.r, 0.001), snappedf(col.g, 0.001), snappedf(col.b, 0.001)]
	data[current_type] = tp
	var w := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if w == null:
		_status.text = "ERROR: cannot write " + JSON_PATH
		return
	w.store_string(JSON.stringify(data, "\t"))
	w.close()
	asteroid.call("reload_types")
	_status.text = "Saved %s" % current_type

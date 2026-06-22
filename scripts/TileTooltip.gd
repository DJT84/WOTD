extends Control

const FEATURE_ICONS := {
	"fish":             ["🐟", Color(0.15, 0.35, 0.65)],
	"crab":             ["🦀", Color(0.70, 0.22, 0.10)],
	"whale":            ["🐋", Color(0.15, 0.30, 0.60)],
	"shark":            ["🦈", Color(0.25, 0.35, 0.55)],
	"octopus":          ["🐙", Color(0.55, 0.15, 0.35)],
	"coral":            ["🪸", Color(0.80, 0.35, 0.20)],
	"jellyfish":        ["🪼", Color(0.60, 0.40, 0.75)],
	"turtle":           ["🐢", Color(0.20, 0.50, 0.20)],
	"pterodactyl":      ["🦅", Color(0.45, 0.38, 0.25)],
	"mammoth":          ["🦣", Color(0.40, 0.35, 0.30)],
	"fern":             ["🌿", Color(0.20, 0.48, 0.18)],
	"insect":           ["🦗", Color(0.35, 0.40, 0.18)],
	"lizard":           ["🦎", Color(0.30, 0.45, 0.20)],
	"giant_fern":       ["🌱", Color(0.18, 0.52, 0.22)],
	"megalodon":        ["⚠ MEGALODON", Color(0.55, 0.10, 0.10)],
	"giant_sloth":      ["⚠ GIANT SLOTH", Color(0.50, 0.12, 0.42)],
	"submarine_vents":  ["♨ VENTS", Color(0.55, 0.28, 0.10)],
	"volcano":          ["🌋 VOLCANO", Color(0.60, 0.18, 0.08)],
}

var _icon_label:    Label
var _feature_label: Label
var _terrain_label: Label
var _rare_badge:    Panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160.0, 80.0)

	var bg := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color              = Color(0.05, 0.05, 0.10, 0.88)
	style.border_color          = Color(0.4, 0.4, 0.5, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left   = 10.0
	style.content_margin_right  = 10.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	_icon_label = Label.new()
	_icon_label.add_theme_font_size_override("font_size", 22)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_icon_label)

	_feature_label = Label.new()
	_feature_label.add_theme_font_size_override("font_size", 13)
	_feature_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_feature_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_feature_label)

	_terrain_label = Label.new()
	_terrain_label.add_theme_font_size_override("font_size", 11)
	_terrain_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	_terrain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_terrain_label)


func show_tile(tile: PlanetTile, screen_pos: Vector2) -> void:
	visible = true
	var feature: String = tile.feature

	if feature != "" and FEATURE_ICONS.has(feature):
		var info: Array = FEATURE_ICONS[feature]
		_icon_label.text = info[0]
		_icon_label.add_theme_color_override("font_color", Color.WHITE)
		_feature_label.text = feature.replace("_", " ").to_upper()
		var is_rare: bool = feature == "megalodon" or feature == "giant_sloth"
		_feature_label.add_theme_color_override("font_color",
			Color(1.0, 0.4, 0.4) if is_rare else Color(1.0, 1.0, 1.0))
	else:
		_icon_label.text    = "·"
		_feature_label.text = "NO ACTIVITY"
		_feature_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))

	var terrain_str: String = tile.terrain_type.replace("_", " ").to_upper()
	var sea_str:     String = "SEA" if not tile.is_land else "LAND"
	_terrain_label.text = "%s  ·  %s" % [sea_str, terrain_str]

	# Refit panel size
	custom_minimum_size = Vector2(max(160.0, _feature_label.get_minimum_size().x + 24.0), 80.0)
	size = custom_minimum_size

	# Position tooltip — offset so it doesn't sit under the cursor
	var vp_size: Vector2 = get_viewport_rect().size
	var tx: float = screen_pos.x + 14.0
	var ty: float = screen_pos.y - size.y - 8.0
	if tx + size.x > vp_size.x - 8.0:
		tx = screen_pos.x - size.x - 8.0
	if ty < 8.0:
		ty = screen_pos.y + 18.0
	position = Vector2(tx, ty)


func hide_tile() -> void:
	visible = false

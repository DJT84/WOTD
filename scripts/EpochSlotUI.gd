class_name EpochSlotUI
extends Control

# Epoch asteroid assembly display — bottom-left corner.
# Shows the named epoch asteroid as an irregular polygon silhouette.
# Fragment pieces appear as small diamonds that fill in as collected.
# When all fragments collected the asteroid glows ready-to-fire.

var epoch_name:         String = "Gondwana's Bane"
var fragment_total:     int    = 4
var fragment_collected: int    = 0

const WIDGET_W    := 190.0
const WIDGET_H    := 220.0

const AST_CENTER  := Vector2(95, 95)
const AST_RADIUS  := 52.0

const FRAG_Y      := 168.0    # y of fragment row
const FRAG_SIZE   := 11.0     # half-size of each diamond
const FRAG_GAP    := 28.0     # centre-to-centre spacing

const C_BG            := Color(0.04, 0.04, 0.07, 0.70)
const C_AST_BODY      := Color(0.09, 0.09, 0.13, 1.0)
const C_AST_RIM       := Color(0.30, 0.28, 0.24, 0.85)
const C_AST_FULL_BODY := Color(0.50, 0.38, 0.12, 0.90)
const C_AST_FULL_GLOW := Color(0.85, 0.68, 0.28, 0.22)
const C_FRAG_EMPTY    := Color(0.14, 0.14, 0.18, 1.0)
const C_FRAG_RIM      := Color(0.28, 0.26, 0.32, 1.0)
const C_FRAG_FILLED   := Color(0.82, 0.66, 0.28, 1.0)
const C_FRAG_GLOW     := Color(0.90, 0.72, 0.32, 0.25)
const C_LABEL         := Color(0.50, 0.47, 0.40, 1.0)
const C_LABEL_NAME    := Color(0.75, 0.70, 0.55, 1.0)

var _ast_poly:   PackedVector2Array
var _frag_polys: Array[PackedVector2Array]  # one per possible fragment (max 5)


func _ready() -> void:
	custom_minimum_size = Vector2(WIDGET_W, WIDGET_H)
	_build_asteroid_shape()
	_build_fragment_shapes()


func _build_asteroid_shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9271
	_ast_poly = PackedVector2Array()
	var sides := 12
	for i in range(sides):
		var a := (TAU / sides) * i - PI * 0.5
		var r := AST_RADIUS * rng.randf_range(0.65, 1.0)
		_ast_poly.append(AST_CENTER + Vector2(cos(a), sin(a)) * r)


func _build_fragment_shapes() -> void:
	_frag_polys.clear()
	for f in range(5):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4400 + f * 77
		var sides := 5
		var cx    := _frag_center_x(f, 4)  # default spacing for 4; overridden in draw
		var cy    := FRAG_Y
		var pts   := PackedVector2Array()
		for i in range(sides):
			var a := (TAU / sides) * i - PI * 0.5
			var r := FRAG_SIZE * rng.randf_range(0.72, 1.0)
			pts.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r)
		_frag_polys.append(pts)


func _frag_center_x(idx: int, total: int) -> float:
	var row_w := (total - 1) * FRAG_GAP
	return (WIDGET_W - row_w) * 0.5 + idx * FRAG_GAP


# ---------------------------------------------------------------------------
# Draw
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Background panel
	draw_rect(Rect2(0, 0, WIDGET_W, WIDGET_H), C_BG)

	_draw_label_header()
	_draw_asteroid()
	_draw_fragments()


func _draw_label_header() -> void:
	var font := ThemeDB.fallback_font
	var fs_header := 9
	var fs_name   := 12

	draw_string(font, Vector2(8, 14), "EPOCH ASTEROID",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_header, C_LABEL)

	var name_display := epoch_name
	if name_display.length() > 18:
		name_display = name_display.substr(0, 17) + "…"
	draw_string(font, Vector2(8, 30), name_display,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_name, C_LABEL_NAME)


func _draw_asteroid() -> void:
	var complete := fragment_collected >= fragment_total and fragment_total > 0

	if complete:
		var glow_poly := _scaled_poly(_ast_poly, AST_CENTER, 1.18)
		draw_colored_polygon(glow_poly, C_AST_FULL_GLOW)
		draw_colored_polygon(_ast_poly, C_AST_FULL_BODY)
	else:
		draw_colored_polygon(_ast_poly, C_AST_BODY)

	# Rim outline — close the polygon
	for i in range(_ast_poly.size()):
		var a := _ast_poly[i]
		var b := _ast_poly[(i + 1) % _ast_poly.size()]
		draw_line(a, b, C_AST_RIM, 1.5, true)

	# Fragment count label inside
	var font   := ThemeDB.fallback_font
	var count_str := "%d / %d" % [fragment_collected, fragment_total]
	draw_string(font, AST_CENTER + Vector2(-14, 5), count_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(C_LABEL, 0.7 if not complete else 0.0))


func _draw_fragments() -> void:
	for f in range(fragment_total):
		if f >= _frag_polys.size():
			break

		# Reposition fragment shape for the current total
		var cx   := _frag_center_x(f, fragment_total)
		var base := _frag_polys[f]
		# Shift the pre-built poly to the correct x for this total
		var old_cx := _frag_center_x(f, 4)
		var shift  := Vector2(cx - old_cx, 0.0)
		var pts    := PackedVector2Array()
		for p in base:
			pts.append(p + shift)

		var filled := f < fragment_collected

		if filled:
			var glow_pts := _scaled_poly(pts, pts[0].lerp(pts[2], 0.5), 1.5)
			draw_colored_polygon(glow_pts, C_FRAG_GLOW)
			draw_colored_polygon(pts, C_FRAG_FILLED)
		else:
			draw_colored_polygon(pts, C_FRAG_EMPTY)
			for i in range(pts.size()):
				draw_line(pts[i], pts[(i + 1) % pts.size()], C_FRAG_RIM, 1.0, true)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _scaled_poly(poly: PackedVector2Array, center: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(center + (p - center) * scale)
	return out


# ---------------------------------------------------------------------------
# Public API — called when game state changes
# ---------------------------------------------------------------------------

func set_epoch(name: String, total_fragments: int) -> void:
	epoch_name         = name
	fragment_total     = total_fragments
	fragment_collected = 0
	queue_redraw()


func add_fragment() -> void:
	fragment_collected = mini(fragment_collected + 1, fragment_total)
	queue_redraw()

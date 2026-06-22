extends Control

# Just the cooldown ring + countdown label — the rock is a 3D model in Main.gd
const SIZE := 96.0

var cooldown_max:       float = 30.0
var cooldown_remaining: float = 0.0

signal fired

var _cd_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 20.0)
	mouse_filter        = Control.MOUSE_FILTER_IGNORE  # clicks pass through to 3D

	_cd_label = Label.new()
	_cd_label.add_theme_font_size_override("font_size", 11)
	_cd_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_cd_label.position             = Vector2(0.0, SIZE + 2.0)
	_cd_label.size                 = Vector2(SIZE, 16.0)
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.text                 = "READY"
	add_child(_cd_label)


func _process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
		_cd_label.text = "%.0fs" % cooldown_remaining if cooldown_remaining > 0.0 else "READY"
		queue_redraw()


func fire() -> void:
	if cooldown_remaining > 0.0:
		return
	cooldown_remaining = cooldown_max
	_cd_label.text = "%.0fs" % cooldown_remaining
	fired.emit()
	queue_redraw()


# Start cooldown without emitting fired (called after rock lands)
func start_cooldown() -> void:
	cooldown_remaining = cooldown_max
	_cd_label.text     = "%.0fs" % cooldown_remaining
	queue_redraw()


func _draw() -> void:
	var c:     Vector2 = Vector2(SIZE * 0.5, SIZE * 0.5)
	var ready: bool    = cooldown_remaining <= 0.0
	var ring_r: float  = SIZE * 0.5 - 4.0

	# Dark backdrop circle
	draw_circle(c, ring_r - 2.0, Color(0.0, 0.0, 0.0, 0.30))

	# Ring track
	draw_arc(c, ring_r, 0.0, TAU, 80, Color(0.15, 0.15, 0.18, 0.85), 5.0, true)

	# Filled arc
	var filled: float = 1.0 - clamp(cooldown_remaining / cooldown_max, 0.0, 1.0)
	if filled > 0.001:
		var arc_col: Color = Color(1.0, 0.68, 0.08) if ready else Color(0.75, 0.42, 0.08, 0.85)
		draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * filled,
			maxi(int(filled * 80.0), 2), arc_col, 5.0, true)

	# Outer glow when ready
	if ready:
		draw_arc(c, ring_r + 3.0, 0.0, TAU, 80, Color(1.0, 0.82, 0.3, 0.25), 2.5, true)

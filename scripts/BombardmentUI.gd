class_name BombardmentUI
extends Control

# Left-edge slide-in panel.
# Tab (52px) always visible – shows dust score. Click to expand full panel.
# Panel contains: cosmic dust total | bombardment profile | epoch species.

const TAB_W     := 52.0
const PANEL_W   := 320.0
const TOP_BAR_H := 60.0    # offset below Main's top bar

const HDR_H  := 28.0
const ROW_H  := 22.0
const PAD    := 11.0

const C_BG      := Color(0.07, 0.08, 0.14, 0.94)
const C_TAB_BG  := Color(0.05, 0.06, 0.11, 0.97)
const C_ACCENT  := Color(0.72, 0.50, 0.15, 0.60)
const C_DIV     := Color(0.90, 0.90, 1.00, 0.09)
const C_SEC_HDR := Color(0.70, 0.65, 0.42, 0.75)
const C_TEXT    := Color(0.88, 0.87, 0.92, 0.92)
const C_DIM     := Color(0.50, 0.50, 0.55, 0.55)
const C_DUST    := Color(0.96, 0.84, 0.36, 1.00)

const TYPE_NAMES: Array = ["C-type", "S-type", "M-type", "Comet"]
const TYPE_FREQS: Array = [0.38, 0.32, 0.18, 0.12]
const TYPE_DUSTS: Array = [2, 3, 4, 1]
const TYPE_COLS: Array = [
	Color(0.54, 0.52, 0.50),
	Color(0.73, 0.47, 0.13),
	Color(0.33, 0.30, 0.72),
	Color(0.10, 0.37, 0.65),
]

const EPOCH_SPECIES: Dictionary = {
	"Cambrian":      ["Anomalocaris", "Trilobite", "Hallucigenia", "Opabinia", "Pikaia"],
	"Carboniferous": ["Meganeura", "Arthropleura", "Eryops", "Hylonomus", "Westlothiana"],
	"Permian":       ["Dimetrodon", "Gorgonopsia", "Moschops", "Lystrosaurus", "Edaphosaurus"],
	"Jurassic":      ["Brachiosaurus", "Allosaurus", "Stegosaurus", "Pterodactylus", "Apatosaurus"],
	"Cretaceous":    ["Tyrannosaurus", "Triceratops", "Velociraptor", "Mosasaurus", "Pteranodon"],
	"Eocene":        ["Ambulocetus", "Basilosaurus", "Andrewsarchus", "Hyracotherium", "Brontotherium"],
	"Pleistocene":   ["Woolly Mammoth", "Sabre-Tooth", "Dire Wolf", "Ground Sloth", "Glyptodon"],
	"Holocene":      ["Homo Sapiens", "Blue Whale", "African Elephant", "Snow Leopard", "Giant Panda"],
}

# Set by Main._process() each frame
var dust_total:    int    = 0
var current_epoch: String = ""

var _open:  bool  = false
var _tween: Tween = null

# Fonts – loaded from downloaded assets
var _fnt_hdr:  Font = null   # Rajdhani-Bold  (section headers, tab label)
var _fnt_num:  Font = null   # JetBrainsMono  (dust counter)
var _fnt_body: Font = null   # SpaceGrotesk   (species, type names)


func _ready() -> void:
	_fnt_hdr  = _load_font("res://assets/fonts/Rajdhani-Bold.woff")
	_fnt_num  = _load_font("res://assets/fonts/JetBrainsMono-Regular.woff")
	_fnt_body = _load_font("res://assets/fonts/SpaceGrotesk-Regular.woff")

	mouse_filter = Control.MOUSE_FILTER_STOP

	# Full-height left-edge strip, starting below the top bar
	anchor_left   = 0.0;  anchor_top    = 0.0
	anchor_right  = 0.0;  anchor_bottom = 1.0
	offset_left   = 0.0;  offset_top    = TOP_BAR_H
	offset_right  = TAB_W; offset_bottom = 0.0
	clip_contents = true


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is Font:
			return res as Font
	return ThemeDB.fallback_font


func _set_width(w: float) -> void:
	offset_right = w
	queue_redraw()


func _toggle() -> void:
	_open = not _open
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target := TAB_W + (PANEL_W if _open else 0.0)
	_tween.tween_method(_set_width, offset_right, target, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.position.x <= TAB_W:
				_toggle()
			accept_event()


func _fmt(n: int) -> String:
	if n >= 1000000: return str(n / 1000000) + "M"
	if n >= 1000:    return str(n / 1000) + "k"
	return str(n)


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var W := size.x
	var H := size.y
	if W < 1.0 or H < 1.0:
		return
	_draw_tab(H)
	if W > TAB_W + 4.0:
		_draw_panel(H, W)


func _draw_tab(H: float) -> void:
	draw_rect(Rect2(0.0, 0.0, TAB_W, H), C_TAB_BG, true)

	_str(0.0, 14.0, "COSMIC DUST", _fnt_hdr, 7,
			Color(C_DUST, 0.60), HORIZONTAL_ALIGNMENT_CENTER, TAB_W)
	_str(0.0, 32.0, _fmt(dust_total), _fnt_num, 16,
			Color(C_DUST, 0.95), HORIZONTAL_ALIGNMENT_CENTER, TAB_W)

	draw_line(Vector2(6.0, 40.0), Vector2(TAB_W - 8.0, 40.0), C_DIV, 1.0)
	draw_line(Vector2(6.0, H - 34.0), Vector2(TAB_W - 8.0, H - 34.0), C_DIV, 1.0)

	var arrow := ">" if not _open else "<"
	_str(0.0, H - 12.0, arrow, _fnt_hdr, 13,
			Color(C_ACCENT, 0.90), HORIZONTAL_ALIGNMENT_CENTER, TAB_W)


func _draw_panel(H: float, W: float) -> void:
	var px := TAB_W
	var pw := W - TAB_W
	draw_rect(Rect2(px, 0.0, pw, H), C_BG, true)

	var y := PAD * 0.5

	# ── Cosmic Dust ──────────────────────────────────────────────────────────
	y = _sec_hdr(px, pw, y, "COSMIC DUST")
	_str(px + PAD, y + 28.0, _fmt(dust_total), _fnt_num, 26, C_DUST,
			HORIZONTAL_ALIGNMENT_LEFT, -1)
	_str(px + pw - PAD, y + 29.0, "total", _fnt_body, 10, C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, pw - PAD)
	y += 38.0
	_divider(px, pw, y);  y += 13.0

	# ── Bombardment Profile ───────────────────────────────────────────────────
	y = _sec_hdr(px, pw, y, "BOMBARDMENT PROFILE")
	var ri: int = 0
	while ri < TYPE_NAMES.size():
		_type_row(px, pw, y, ri)
		y += ROW_H
		ri += 1
	y += 5.0
	_divider(px, pw, y);  y += 13.0

	# ── Epoch Species ─────────────────────────────────────────────────────────
	var era := (current_epoch.to_upper() + " ERA") if current_epoch != "" else "CURRENT ERA"
	y = _sec_hdr(px, pw, y, era)
	var raw = EPOCH_SPECIES.get(current_epoch, [])
	var species: Array = raw if raw is Array else []
	if species.is_empty():
		_str(px + PAD, y + 14.0, "Unknown era", _fnt_body, 10, C_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, -1)
	else:
		var si: int = 0
		while si < species.size():
			draw_circle(Vector2(px + PAD + 4.0, y + 10.0), 2.5, Color(C_ACCENT, 0.65))
			_str(px + PAD + 14.0, y + 15.0, species[si] as String, _fnt_body, 11,
					C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, pw - PAD * 2.0 - 14.0)
			y += ROW_H
			si += 1


# ── Helpers ───────────────────────────────────────────────────────────────────

func _str(x: float, y: float, text: String, font: Font, size: int,
		col: Color, align: HorizontalAlignment, width: float) -> void:
	if not font:
		return
	draw_string(font, Vector2(x, y), text, align, width, size, col)


func _sec_hdr(px: float, pw: float, y: float, title: String) -> float:
	_str(px + PAD, y + 16.0, title, _fnt_hdr, 10, C_SEC_HDR,
			HORIZONTAL_ALIGNMENT_LEFT, -1)
	draw_line(Vector2(px, y + HDR_H), Vector2(px + pw, y + HDR_H), C_DIV, 1.0)
	return y + HDR_H + 5.0


func _divider(px: float, pw: float, y: float) -> void:
	draw_line(Vector2(px, y), Vector2(px + pw, y), C_DIV, 1.0)


func _type_row(px: float, pw: float, y: float, i: int) -> void:
	var col := TYPE_COLS[i] as Color
	draw_circle(Vector2(px + PAD + 5.0, y + 10.0), 4.5, col)

	_str(px + PAD + 17.0, y + 15.0, TYPE_NAMES[i] as String, _fnt_body, 11,
			C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 68.0)

	var d: int = 0
	while d < 4:
		draw_circle(Vector2(px + PAD + 106.0 + float(d) * 10.0, y + 10.0), 3.0,
				Color(col, 0.78) if d < int(TYPE_DUSTS[i]) else Color(0.22, 0.22, 0.26, 0.45))
		d += 1

	var bx := px + PAD + 152.0
	var bw := pw - (bx - px) - PAD
	if bw > 2.0:
		draw_rect(Rect2(bx, y + 9.0, bw, 4.0), Color(0.20, 0.20, 0.25, 0.40), true)
		draw_rect(Rect2(bx, y + 9.0, bw * float(TYPE_FREQS[i]), 4.0),
				Color(col, 0.72), true)

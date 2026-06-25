class_name BeltPreviewUI
extends Control

# Live-adjustable belt preview for the planet generator.
# Parameters are set via set_*() methods called from generator.gd sliders.
# The Gaussian cloud texture is re-baked (via BeltBaker) whenever sigma/peak/color change,
# with a short debounce so rapid slider drags don't stall every frame.

const ROCK_TPLS  := 14
const X_LO_FRAC  := -0.14
const X_HI_FRAC  :=  1.14

var _sigma:      float = 80.0
var _peak:       float = 0.15
var _dust_n:     int   = 300
var _dust_sz:    float = 2.5
var _dust_alpha: float = 1.0
var _speed_mul:  float = 1.0
var _belt_color: Color = Color(0.94, 0.91, 0.86)
var _show:       bool  = true

var _dt:      PackedFloat32Array
var _dspeed:  PackedFloat32Array
var _doy:     PackedFloat32Array
var _doy_vel: PackedFloat32Array
var _dsz:     PackedFloat32Array
var _da:      PackedFloat32Array
var _dang:    PackedFloat32Array
var _dtpl:    PackedInt32Array
var _rock_tpls: Array[PackedVector2Array] = []

var _cloud_tex:   ImageTexture
var _cloud_dirty: bool  = true
var _dirty_timer: float = 0.0
const DIRTY_DELAY := 0.35


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_rock_templates()
	_init_particles()
	call_deferred("_rebuild_cloud")


func _build_rock_templates() -> void:
	_rock_tpls.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9943
	var t: int = 0
	while t < ROCK_TPLS:
		var n_verts: int = rng.randi_range(5, 7)
		var pts := PackedVector2Array()
		pts.resize(n_verts)
		var v: int = 0
		while v < n_verts:
			var base_ang := float(v) / float(n_verts) * TAU
			var jitter   := rng.randf_range(-0.25, 0.25)
			var r        := rng.randf_range(0.40, 1.0)
			pts[v] = Vector2(cos(base_ang + jitter), sin(base_ang + jitter)) * r
			v += 1
		_rock_tpls.append(pts)
		t += 1


func _init_particles() -> void:
	_dt.resize(_dust_n);      _dspeed.resize(_dust_n)
	_doy.resize(_dust_n);     _doy_vel.resize(_dust_n)
	_dsz.resize(_dust_n);     _da.resize(_dust_n)
	_dang.resize(_dust_n);    _dtpl.resize(_dust_n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var i: int = 0
	while i < _dust_n:
		_dt[i]      = rng.randf()
		_dspeed[i]  = rng.randf_range(0.002, 0.006)
		_doy[i]     = (rng.randf_range(-60.0, 60.0) + rng.randf_range(-60.0, 60.0)) * 0.5
		_doy_vel[i] = rng.randf_range(-3.0, 3.0)
		_dsz[i]     = rng.randf_range(0.4, 2.5)
		_da[i]      = rng.randf_range(0.12, 0.72)
		_dang[i]    = rng.randf() * TAU
		_dtpl[i]    = rng.randi_range(0, ROCK_TPLS - 1)
		i += 1


func _rebuild_cloud() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	if vp.x < 10.0:
		return
	var img := BeltBaker.bake(vp, _sigma, _peak, _belt_color)
	if _cloud_tex == null:
		_cloud_tex = ImageTexture.create_from_image(img)
	else:
		_cloud_tex.update(img)
	queue_redraw()


func _process(delta: float) -> void:
	if not _show:
		return
	var i: int = 0
	while i < _dust_n:
		_dt[i]  = fmod(_dt[i] + _dspeed[i] * _speed_mul * delta, 1.0)
		_doy[i] = _doy[i] + _doy_vel[i] * delta
		if absf(_doy[i]) > 62.0:
			_doy_vel[i] = -_doy_vel[i]
		i += 1
	if _cloud_dirty:
		_dirty_timer -= delta
		if _dirty_timer <= 0.0:
			_cloud_dirty = false
			_rebuild_cloud()
			return
	queue_redraw()


func _draw() -> void:
	if not _show:
		return
	if _cloud_tex:
		draw_texture(_cloud_tex, Vector2.ZERO)
	_draw_particles()


func _draw_particles() -> void:
	var vp       := get_viewport_rect().size
	var x_lo     := vp.x * X_LO_FRAC
	var x_hi     := vp.x * X_HI_FRAC
	var arc_span := x_hi - x_lo
	var i: int = 0
	while i < _dust_n:
		var t   := _dt[i]
		var x   := x_lo + t * arc_span
		var yp  := _arc_y(x, vp) + _doy[i]
		var ea  := _edge_alpha(t)
		if ea < 0.015:
			i += 1
			continue
		var col := Color(_belt_color, _da[i] * ea * _dust_alpha)
		var sz  := _dsz[i] * _dust_sz
		var ang := _dang[i]
		var ca  := cos(ang)
		var sa  := sin(ang)
		var pos := Vector2(x, yp)
		var tpl: PackedVector2Array = _rock_tpls[_dtpl[i]]
		var n_v: int = tpl.size()
		var xf  := PackedVector2Array()
		xf.resize(n_v)
		var vi: int = 0
		while vi < n_v:
			var lx: float = tpl[vi].x * sz
			var ly: float = tpl[vi].y * sz
			xf[vi] = Vector2(pos.x + lx * ca - ly * sa, pos.y + lx * sa + ly * ca)
			vi += 1
		draw_colored_polygon(xf, col)
		i += 1


func _arc_y(x: float, vp: Vector2) -> float:
	var norm := (x - vp.x * 0.5) / (vp.x * 0.5)
	return vp.y * 0.85 - norm * norm * 20.0


func _edge_alpha(t: float) -> float:
	var fade := 0.15
	return clamp(smoothstep(0.0, fade, t) * smoothstep(1.0, 1.0 - fade, t), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Setters — called via .call() from generator.gd slider callbacks
# ---------------------------------------------------------------------------

func set_show(on: bool) -> void:
	_show = on
	queue_redraw()

func set_sigma(v: float) -> void:
	_sigma = v
	_cloud_dirty = true
	_dirty_timer = DIRTY_DELAY

func set_peak(v: float) -> void:
	_peak = v
	_cloud_dirty = true
	_dirty_timer = DIRTY_DELAY

func set_dust_sz(v: float) -> void:
	_dust_sz = v
	queue_redraw()

func set_dust_alpha(v: float) -> void:
	_dust_alpha = v
	queue_redraw()

func set_speed_mul(v: float) -> void:
	_speed_mul = v

func set_belt_color(c: Color) -> void:
	_belt_color = c
	_cloud_dirty = true
	_dirty_timer = DIRTY_DELAY

func set_dust_n_f(v: float) -> void:
	_dust_n = int(v)
	_init_particles()

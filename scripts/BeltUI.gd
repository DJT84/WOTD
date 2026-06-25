class_name BeltUI
extends Control

# Belt visual — dynamic elements of the asteroid belt arc.
# The static Gaussian dust cloud is baked to a texture by BeltBaker (see Main._setup_belt_texture).
# This node handles only: animated dust particles, slot cooldown bars, epoch marker ring.

var slot_screen_pos:   Array[Vector2] = []
var slot_cd_frac:      Array[float]   = []
var slot_ready:        Array[bool]    = []
var slot_flying:       Array[bool]    = []
var epoch_screen_pos:  Vector2        = Vector2.ZERO
var epoch_ghost_fill:  float          = 0.0
var epoch_ready:       bool           = false
var epoch_frag_count:  int            = 0
var epoch_ghost_color: Color          = Color(0.28, 0.40, 0.65)

const RING_R      := 30.0
const FRAG_RING_R := 46.0
const ELEC_RING_R := 62.0
const FRAG_TOTAL  := 4

const C_DUST       := Color(0.94, 0.91, 0.86, 1.0)
const C_RING_TRACK := Color(0.85, 0.85, 0.85, 0.07)
const C_RING_LOW   := Color(0.72, 0.46, 0.10, 0.80)
const C_RING_HIGH  := Color(0.94, 0.75, 0.28, 0.90)
const C_RING_READY := Color(0.94, 0.62, 0.18, 0.82)
const C_FRAG_FULL  := Color(0.50, 0.46, 0.86, 0.92)
const C_FRAG_EMPTY := Color(0.50, 0.46, 0.86, 0.15)
const C_ELEC_GLOW  := Color(0.72, 0.46, 0.10, 1.0)
const C_ELEC_CORE  := Color(0.98, 0.80, 0.28, 1.0)

const DUST_N    := 240
const ROCK_TPLS := 14

var _dt:      PackedFloat32Array
var _dspeed:  PackedFloat32Array
var _doy:     PackedFloat32Array
var _doy_vel: PackedFloat32Array
var _dsz:     PackedFloat32Array
var _da:      PackedFloat32Array
var _dang:    PackedFloat32Array
var _dtpl:    PackedInt32Array              # rock template index per particle
var _rock_tpls: Array[PackedVector2Array] = []

var _elec_tick:  int   = 0
var _elec_timer: float = 0.0
var _cloud_tex:  ImageTexture = null


func _build_cloud() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	if vp.x < 10.0:
		return
	# "b6" forces a fresh bake – cloud now lives on the 2D canvas, not a Sprite3D.
	var cache := "user://belt_b6_" + str(int(vp.x)) + "x" + str(int(vp.y)) + ".png"
	var img: Image
	if FileAccess.file_exists(cache):
		img = Image.load_from_file(cache)
	else:
		img = BeltBaker.bake(vp)
		img.save_png(cache)
	if _cloud_tex == null:
		_cloud_tex = ImageTexture.create_from_image(img)
	else:
		_cloud_tex.update(img)
	queue_redraw()


func _build_rock_templates() -> void:
	_rock_tpls.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3317
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


func _ready() -> void:
	call_deferred("_build_cloud")
	_build_rock_templates()
	_dt.resize(DUST_N);      _dspeed.resize(DUST_N)
	_doy.resize(DUST_N);     _doy_vel.resize(DUST_N)
	_dsz.resize(DUST_N);     _da.resize(DUST_N)
	_dang.resize(DUST_N);    _dtpl.resize(DUST_N)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5513
	for i in range(DUST_N):
		var oy := (rng.randf_range(-60.0, 60.0) + rng.randf_range(-60.0, 60.0)) * 0.5
		_dt[i]      = rng.randf()
		_dspeed[i]  = rng.randf_range(0.0008, 0.0024)
		_doy[i]     = oy
		_doy_vel[i] = rng.randf_range(-3.0, 3.0)
		_dsz[i]     = rng.randf_range(0.4, 2.5)
		_da[i]      = rng.randf_range(0.12, 0.72)
		_dang[i]    = rng.randf() * TAU
		_dtpl[i]    = rng.randi_range(0, ROCK_TPLS - 1)


func _process(delta: float) -> void:
	for i in range(DUST_N):
		_dt[i]  = fmod(_dt[i] + _dspeed[i] * delta, 1.0)
		_doy[i] = _doy[i] + _doy_vel[i] * delta
		if absf(_doy[i]) > 62.0:
			_doy_vel[i] = -_doy_vel[i]
	_elec_timer += delta
	if _elec_timer >= 0.065:
		_elec_timer -= 0.065
		_elec_tick  += 1


func _draw() -> void:
	if _cloud_tex:
		draw_texture(_cloud_tex, Vector2.ZERO)
	_draw_belt_arc()
	for s in slot_screen_pos.size():
		_draw_cooldown_ring(s)
	if epoch_screen_pos.x > 0.0:
		_draw_epoch_rings()


# ---------------------------------------------------------------------------
# Arc
# ---------------------------------------------------------------------------

func _arc_y(x: float, vp: Vector2) -> float:
	var norm := (x - vp.x * 0.5) / (vp.x * 0.5)
	return vp.y * 0.85 - norm * norm * 20.0


func _edge_alpha(t: float, tightness: float) -> float:
	var fade: float = lerp(0.07, 0.28, tightness)
	return clamp(smoothstep(0.0, fade, t) * smoothstep(1.0, 1.0 - fade, t), 0.0, 1.0)


func _occlusion(x: float, y: float) -> float:
	var a := 1.0
	for s in slot_screen_pos.size():
		if slot_flying[s]:
			continue
		var dx := x - slot_screen_pos[s].x
		var dy := y - slot_screen_pos[s].y
		a *= smoothstep(0.0, 72.0, sqrt(dx * dx + dy * dy))
	if epoch_screen_pos.x > 100.0:
		var dx := x - epoch_screen_pos.x
		var dy := y - epoch_screen_pos.y
		a *= smoothstep(0.0, 80.0, sqrt(dx * dx + dy * dy))
	return a


func _draw_belt_arc() -> void:
	var vp       := get_viewport_rect().size
	var x_lo     := -vp.x * 0.14
	var x_hi     :=  vp.x * 1.14
	var arc_span := x_hi - x_lo

	# Static belt cloud is rendered by a baked TextureRect (see BeltBaker.gd / Main._setup_belt_texture).

	# Epoch ghost glow around the far-right asteroid
	if epoch_screen_pos.x > 100.0 and epoch_ghost_fill > 0.005:
		var ga  := epoch_ghost_fill * 0.07
		var ex  := epoch_screen_pos.x
		var gpt := PackedVector2Array()
		for i in range(13):
			var x := ex - 80.0 + float(i) / 12.0 * 145.0
			gpt.append(Vector2(x, _arc_y(x, vp)))
		var gc := epoch_ghost_color
		draw_polyline(gpt, Color(gc, ga * 0.10), 65.0, true)
		draw_polyline(gpt, Color(gc, ga * 0.16), 26.0, true)
		draw_polyline(gpt, Color(gc, ga * 0.22),  9.0, true)

	# Drifting dust cloud particles — rotated diamonds for irregular silhouettes
	for i in range(DUST_N):
		var t   := _dt[i]
		var x   := x_lo + t * arc_span
		var yp  := _arc_y(x, vp) + _doy[i]
		var ea  := _edge_alpha(t, 0.40) * _occlusion(x, yp)
		if ea < 0.015:
			continue
		var col := Color(C_DUST, _da[i] * ea * 0.25)
		var sz  := _dsz[i] * 2.6
		var ang := _dang[i]
		var pos := Vector2(x, yp)
		var ca  := cos(ang)
		var sa  := sin(ang)
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


# ---------------------------------------------------------------------------
# Epoch rock rings — fragment collection (inner) + cosmic energy (outer)
# ---------------------------------------------------------------------------

func _draw_epoch_rings() -> void:
	var pos := epoch_screen_pos
	_draw_frag_ring(pos, epoch_frag_count, FRAG_TOTAL)
	_draw_electric_ring(pos, ELEC_RING_R, epoch_ghost_fill)
	if epoch_ready:
		draw_arc(pos, ELEC_RING_R + 8.0, 0.0, TAU, 48, Color(C_RING_READY, 0.30), 5.0, true)


func _draw_frag_ring(center: Vector2, filled: int, total: int) -> void:
	if total <= 0:
		return
	var seg := TAU / float(total)
	var gap := 0.08
	var i: int = 0
	while i < total:
		var sa  := float(i) * seg - PI * 0.5 + gap
		var ea  := float(i + 1) * seg - PI * 0.5 - gap
		var col := C_FRAG_FULL if i < filled else C_FRAG_EMPTY
		var lw  := 3.5 if i < filled else 2.0
		draw_arc(center, FRAG_RING_R, sa, ea, 16, col, lw, true)
		i += 1


func _draw_electric_ring(center: Vector2, radius: float, fill: float) -> void:
	if fill <= 0.005:
		return
	var N     := 80
	var end_i := int(float(N) * fill)
	if end_i < 2:
		return
	var lw_arr    := PackedFloat32Array([16.0, 6.0, 1.5])
	var alpha_arr := PackedFloat32Array([0.10, 0.28, 0.90])
	var pass_i: int = 0
	while pass_i < 3:
		var lw       : float = lw_arr[pass_i]
		var alpha    : float = alpha_arr[pass_i]
		var base_col := C_ELEC_GLOW if pass_i < 2 else C_ELEC_CORE
		var rng := RandomNumberGenerator.new()
		rng.seed = (_elec_tick * 9973 + pass_i * 53129) & 0x7FFFFFFF
		var pts := PackedVector2Array()
		pts.resize(end_i + 1)
		var vi: int = 0
		while vi <= end_i:
			var ang   := float(vi) / float(N) * TAU - PI * 0.5
			var spike := 0.0
			if rng.randf() < 0.08:
				spike = rng.randf() * 11.0
			var j := (rng.randf() - 0.5) * 6.5 + spike
			pts[vi] = Vector2(center.x + cos(ang) * (radius + j),
					center.y + sin(ang) * (radius + j))
			vi += 1
		draw_polyline(pts, Color(base_col, alpha), lw, true)
		pass_i += 1
	# Sparks at the live arc tip when not fully charged
	if fill < 0.99:
		var tip_ang := float(end_i) / float(N) * TAU - PI * 0.5
		var tx := center.x + cos(tip_ang) * radius
		var ty := center.y + sin(tip_ang) * radius
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = (_elec_tick * 7919 + 5) & 0x7FFFFFFF
		var sp: int = 0
		while sp < 5:
			var sa  := tip_ang + (rng2.randf() - 0.5) * 0.8
			var sl  := rng2.randf() * 12.0 + 3.0
			var spa := rng2.randf() * 0.85 + 0.15
			draw_line(Vector2(tx, ty),
					Vector2(tx + cos(sa) * sl, ty + sin(sa) * sl),
					Color(C_ELEC_CORE, spa), 1.2, true)
			sp += 1


# ---------------------------------------------------------------------------
# Cooldown ring (replaces flat bar)
# ---------------------------------------------------------------------------

func _draw_cooldown_ring(s: int) -> void:
	var pos := slot_screen_pos[s]
	# Track
	draw_arc(pos, RING_R, 0.0, TAU, 48, C_RING_TRACK, 4.5, true)
	if slot_flying[s]:
		return
	if slot_ready[s]:
		draw_arc(pos, RING_R, 0.0, TAU, 48, Color(C_RING_READY, 0.20), 12.0, true)
		draw_arc(pos, RING_R, 0.0, TAU, 48, C_RING_READY, 4.5, true)
		return
	if slot_cd_frac[s] > 0.01:
		var sa := -PI * 0.5
		var ea := sa + slot_cd_frac[s] * TAU
		draw_arc(pos, RING_R, sa, ea, 48, C_RING_LOW.lerp(C_RING_HIGH, slot_cd_frac[s]), 4.5, true)

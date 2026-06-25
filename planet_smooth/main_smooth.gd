extends Node3D

# Parallel game scene using the smooth EarthSphere planet.
#  - Left-click the planet to call a meteor strike there.
#       land/ice -> fiery crater + shockwave ;  ocean -> splash + foam rings (proto-tsunami)
#  - Left / Right arrows cycle epochs.
# Uses the validated land/sea query (PlanetRegion) so impacts react to the terrain.
const EarthPlanetScript = preload("res://planet_smooth/earth_planet.gd")
const CraterFieldScript = preload("res://planet_smooth/CraterField.gd")
const ORDER := ["cambrian", "carboniferous", "permian", "jurassic", "cretaceous", "eocene", "pleistocene", "holocene"]
const MAX := 64
# Additive linear-space colour shift per epoch (values are tiny by design — subliminal tint only).
const EPOCH_TINTS := {
	"cambrian":      Vector3(0.0010, 0.0020, 0.0030),  # blue-teal
	"carboniferous": Vector3(0.0025, 0.0025, 0.0000),  # yellow-green
	"permian":       Vector3(0.0030, 0.0015, 0.0005),  # warm amber
	"jurassic":      Vector3(0.0020, 0.0025, 0.0005),  # warm green
	"cretaceous":    Vector3(0.0005, 0.0005, 0.0005),  # near-neutral
	"eocene":        Vector3(0.0010, 0.0015, 0.0030),  # warm blue
	"pleistocene":   Vector3(0.0005, 0.0010, 0.0035),  # icy blue (coldest)
	"holocene":      Vector3(0.0020, 0.0020, 0.0015),  # warm grey
}

var craters   # CraterField (persistent scar map)

@onready var planet: MeshInstance3D = $Planet
@onready var cam: Camera3D = $Camera3D
var mat: ShaderMaterial
var dirs := PackedVector3Array()
var radii := PackedFloat32Array()
var ages := PackedFloat32Array()
var water := PackedFloat32Array()
var spin := 0.0
var epoch_idx := 4   # start on a procedural epoch (Cretaceous) so land/sea query matches visuals
var _label: Label

func _ready() -> void:
	dirs.resize(MAX); radii.resize(MAX); ages.resize(MAX); water.resize(MAX)
	for i in MAX:
		ages[i] = 999.0
		dirs[i] = Vector3.UP
	_apply_epoch()
	_build_ui()

func _set_sky_tint(epoch: String) -> void:
	var we := $WorldEnvironment as WorldEnvironment
	if we == null or we.environment == null or we.environment.sky == null:
		return
	var sm := we.environment.sky.sky_material as ShaderMaterial
	if sm:
		sm.set_shader_parameter("epoch_tint", EPOCH_TINTS.get(epoch, Vector3.ZERO))

func _apply_epoch() -> void:
	planet.set("epoch", ORDER[epoch_idx])
	_set_sky_tint(ORDER[epoch_idx])
	mat = planet.material_override
	mat.set_shader_parameter("spin_speed", 0.0)   # spin via node rotation
	mat.set_shader_parameter("use_earth_map", false)  # force procedural so the land/sea query is exact
	mat.set_shader_parameter("sun_dir", Vector3(0.3, 0.25, 0.92))  # light the camera-facing side
	# Crater scar map: each epoch is a FRESH, pristine planet, so wipe craters on every
	# epoch start. Craters accumulate only within the current epoch.
	if craters == null:
		craters = CraterFieldScript.new(1024, 512)
	craters.clear()
	# also clear any in-flight explosion animations from the previous epoch
	for i in MAX:
		ages[i] = 999.0
		radii[i] = 0.0
	mat.set_shader_parameter("use_scar_map", true)
	mat.set_shader_parameter("scar_map", craters.tex)
	_push()
	if _label:
		_label.text = _hud_text()

func _hud_text() -> String:
	return "Epoch: %s   (Left/Right to change)\nClick planet:  land = crater/shockwave,  sea = splash/tsunami" % ORDER[epoch_idx].capitalize()

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.text = _hud_text()
	cl.add_child(_label)

func _process(delta: float) -> void:
	spin += delta * 0.05
	planet.rotation.y = spin
	for i in MAX:
		ages[i] += delta
	_push()

func _push() -> void:
	mat.set_shader_parameter("impact_count", MAX)
	mat.set_shader_parameter("impact_dir", dirs)
	mat.set_shader_parameter("impact_radius", radii)
	mat.set_shader_parameter("impact_age", ages)
	mat.set_shader_parameter("impact_water", water)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _ray_sphere(event.position)
		if hit != Vector3.INF:
			var local: Vector3 = planet.call("to_local_dir", hit)
			var stype: String = planet.call("surface_type", local)
			_strike(local, stype)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			epoch_idx = wrapi(epoch_idx + 1, 0, ORDER.size()); _apply_epoch()
		elif event.keycode == KEY_LEFT:
			epoch_idx = wrapi(epoch_idx - 1, 0, ORDER.size()); _apply_epoch()

func _strike(local_dir: Vector3, stype: String) -> void:
	var slot := 0
	var oldest := -1.0
	for i in MAX:
		if ages[i] > oldest:
			oldest = ages[i]; slot = i
	var r := randf_range(0.12, 0.22)
	dirs[slot] = local_dir.normalized()
	radii[slot] = r
	ages[slot] = 0.0
	water[slot] = 1.0 if stype == "ocean" else 0.0
	# Land strikes leave a PERMANENT crater baked into the scar map.
	if stype != "ocean" and craters != null:
		craters.stamp(local_dir.normalized(), r, 1.0, randf() * 100.0)

func _ray_sphere(screen_pos: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var c := planet.global_position
	var oc := o - c
	var b := oc.dot(dir)
	var cc := oc.dot(oc) - 0.25   # radius 0.5
	var disc := b * b - cc
	if disc < 0.0:
		return Vector3.INF
	var t := -b - sqrt(disc)
	if t < 0.0:
		return Vector3.INF
	return o + dir * t

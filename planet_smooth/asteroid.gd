class_name Asteroid
extends MeshInstance3D

# Drop-in cel-shaded asteroid. Add to a scene, pick a type in the Inspector.
# The node rotates each frame to simulate tumbling — set tumble_* to 0 to disable.

const SHADER       := preload("res://planet_smooth/AsteroidSphere.gdshader")
const LoaderScript := preload("res://planet_smooth/PlanetLoader.gd")
const JSON_PATH    := "res://planet_smooth/asteroid_types.json"

@export_enum("c_type", "s_type", "m_type", "comet", "volcanic") var asteroid_type: String = "s_type":
	set(v): asteroid_type = v; _refresh()

@export_range(0, 4) var variation: int = 0:
	set(v): variation = v; _refresh()

@export_range(0.0, 1.0) var ghost_fill: float = 1.0:
	set(v):
		ghost_fill = v
		if material_override is ShaderMaterial:
			(material_override as ShaderMaterial).set_shader_parameter("ghost_fill", v)

@export_group("Tumble (rad/s)")
@export var tumble_x: float = 0.07
@export var tumble_y: float = 0.13
@export var tumble_z: float = 0.04

var _types: Dictionary

func _ready() -> void:
	_ensure_mesh()
	_refresh()

func _process(delta: float) -> void:
	rotation.x += tumble_x * delta
	rotation.y += tumble_y * delta
	rotation.z += tumble_z * delta

func _ensure_mesh() -> void:
	if mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 96
		sm.rings = 48
		mesh = sm
	cast_shadow = SHADOW_CASTING_SETTING_OFF

func _refresh() -> void:
	if not is_inside_tree():
		return
	_ensure_mesh()
	if _types.is_empty():
		_types = LoaderScript.load_file(JSON_PATH)
	var mat := material_override as ShaderMaterial
	if mat == null or mat.shader != SHADER:
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		material_override = mat
	if _types.has(asteroid_type):
		LoaderScript.apply(mat, _types[asteroid_type], 0)
		_apply_variation(mat, _types[asteroid_type])
	# ghost_fill is runtime-only — re-apply after JSON load
	mat.set_shader_parameter("ghost_fill", ghost_fill)

func _apply_variation(mat: ShaderMaterial, preset: Dictionary) -> void:
	if variation == 0:
		return
	var off := float(variation) * 3.17
	for sk in ["shape_seed", "surface_seed", "crater_seed"]:
		if preset.has(sk):
			mat.set_shader_parameter(sk, fmod(float(preset[sk]) + off, 10.0))

func reload_types() -> void:
	_types = LoaderScript.load_file(JSON_PATH)
	_refresh()

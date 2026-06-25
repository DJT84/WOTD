@tool
class_name EarthPlanet
extends MeshInstance3D

# Drop-in Earth-epoch planet. Add this node to a scene, pick an epoch + variation in the
# Inspector, and it builds the EarthSphere material for you. Updates live in the editor.

@export_enum("cambrian", "carboniferous", "permian", "jurassic", "cretaceous", "eocene", "pleistocene", "holocene")
var epoch: String = "holocene":
	set(v): epoch = v; _refresh()

@export_range(0, 2) var variation: int = 0:
	set(v): variation = v; _refresh()

# Use the real Earth map for holocene/pleistocene (recognizable modern continents).
@export var use_real_earth_map: bool = true:
	set(v): use_real_earth_map = v; _refresh()

# Use baked research-based paleogeography (Pangaea, Gondwana, ...) for deep-time epochs.
# Off by default: the organic procedural continents read better / have more charm.
@export var use_paleo_map: bool = false:
	set(v): use_paleo_map = v; _refresh()

@export var show_shadow: bool = true:
	set(v): show_shadow = v; _refresh()

@export var show_clouds: bool = true:
	set(v): show_clouds = v; _refresh()

@export var atmosphere_ring: bool = true:
	set(v): atmosphere_ring = v; _refresh()

@export_range(0.0, 8.0) var atmo_ring_strength: float = 2.5:
	set(v): atmo_ring_strength = v; _refresh()

@export_range(0.3, 10.0) var atmo_ring_falloff: float = 4.0:
	set(v): atmo_ring_falloff = v; _refresh()

@export_range(1.0, 1.5) var atmo_ring_size: float = 1.12:
	set(v): atmo_ring_size = v; _refresh()

@export_range(0.0, 2.0) var atmo_gradient_strength: float = 0.5:
	set(v): atmo_gradient_strength = v; _refresh()

# Multiplies the ring quad billboard size to match a parent planet scale > 1.
# Set this to match the MeshInstance3D scale applied to EarthPlanet (e.g. 13.0).
# Defaults to 1.0 so the generator and any scale-1 usage is unaffected.
var ring_scale: float = 1.0

# Vertical offset of the ring node in EarthPlanet LOCAL space.
# When the planet is above the camera's look-at point, the sphere's perspective silhouette
# extends further above its projected center than below.  Shifting the ring billboard
# upward by this amount re-centres the UV(0.5,0.5) mask on the sphere's visual centre.
# Leave at 0.0 in the generator (planet is centred on screen).
var ring_y_offset: float = 0.0:
	set(v):
		ring_y_offset = v
		if _ring != null:
			_ring.position = Vector3(0.0, v, 0.0)

const SHADER := preload("res://planet_smooth/EarthSphere.gdshader")
const RING_SHADER := preload("res://planet_smooth/atmosphere_ring.gdshader")
const PaleoMapScript := preload("res://planet_smooth/PaleoMap.gd")
const PlanetLoaderScript := preload("res://planet_smooth/PlanetLoader.gd")
var _epochs: Dictionary
var _ring: MeshInstance3D
var _ring_quad: QuadMesh

func _ready() -> void:
	_ensure_mesh()
	_refresh()

func _ensure_mesh() -> void:
	if mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 96
		sm.rings = 48
		mesh = sm
	cast_shadow = SHADOW_CASTING_SETTING_OFF

func reload_epochs() -> void:
	_epochs = PlanetLoaderScript.load_file("res://planet_smooth/earth_epochs.json")
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	_ensure_mesh()
	if _epochs.is_empty():
		_epochs = PlanetLoaderScript.load_file("res://planet_smooth/earth_epochs.json")
	var mat := material_override as ShaderMaterial
	if mat == null or mat.shader != SHADER:
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		material_override = mat
	if _epochs.has(epoch):
		PlanetLoaderScript.apply(mat, _epochs[epoch], variation)
	mat.set_shader_parameter("shadow_enabled", show_shadow)
	mat.set_shader_parameter("clouds_enabled", show_clouds)
	# Pick the right continent source for the epoch:
	#  - holocene/pleistocene -> real Earth map
	#  - deep-time epochs      -> baked research-based paleogeography
	#  - otherwise             -> procedural
	var tex: Texture2D = null
	if use_real_earth_map and (epoch == "holocene" or epoch == "pleistocene"):
		tex = _load_earth_tex()
	elif use_paleo_map and PaleoMapScript.has_epoch(epoch):
		tex = PaleoMapScript.bake(epoch)
	mat.set_shader_parameter("use_earth_map", tex != null)
	if tex != null:
		mat.set_shader_parameter("earth_map", tex)
	_update_ring(mat)

func _update_ring(mat: ShaderMaterial) -> void:
	if not atmosphere_ring:
		if _ring != null:
			_ring.visible = false
		return
	var ep := _epochs.get(epoch, {}) as Dictionary
	var rs := float(ep.get("atmo_ring_size", atmo_ring_size))
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring_quad = QuadMesh.new()
		_ring.mesh = _ring_quad
		_ring.cast_shadow = SHADOW_CASTING_SETTING_OFF
		var rm0 := ShaderMaterial.new()
		rm0.shader = RING_SHADER
		_ring.material_override = rm0
		add_child(_ring)
	# Scale the quad with ring_size so the glow extent grows; planet_edge stays fixed at 0.588.
	# ring_scale compensates when the EarthPlanet node itself is scaled (e.g. 13x in main scene).
	_ring_quad.size = Vector2(1.7 * rs * ring_scale, 1.7 * rs * ring_scale)
	_ring.position = Vector3(0.0, ring_y_offset, 0.0)
	_ring.visible = true
	var rm := _ring.material_override as ShaderMaterial
	var ac = mat.get_shader_parameter("atmosphere_color")
	if ac == null:
		ac = Color(0.3, 0.65, 1.0)
	rm.set_shader_parameter("ring_color", ac)
	rm.set_shader_parameter("ring_strength",     float(ep.get("atmo_ring_strength",     atmo_ring_strength)))
	rm.set_shader_parameter("ring_falloff",      float(ep.get("atmo_ring_falloff",      atmo_ring_falloff)))
	rm.set_shader_parameter("ring_size",         rs)
	rm.set_shader_parameter("gradient_strength", float(ep.get("atmo_gradient_strength", atmo_gradient_strength)))

# Lets the generator resize the ring quad live (ring_size changes the physical quad extent).
func set_ring_size_live(sz: float) -> void:
	if _ring_quad != null:
		_ring_quad.size = Vector2(1.7 * sz * ring_scale, 1.7 * sz * ring_scale)

# Lets the generator tune the ring live without triggering a full _refresh.
func ring_mat() -> ShaderMaterial:
	if _ring == null:
		return null
	return _ring.material_override as ShaderMaterial

func _load_earth_tex() -> Texture2D:
	var f := FileAccess.open("res://planet_smooth/earth_map.jpg", FileAccess.READ)
	if f == null:
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(f.get_buffer(f.get_length())) != OK:
		return null
	img.generate_mipmaps()   # needed so the shader can sample a blurred LOD for cel coloring
	return ImageTexture.create_from_image(img)

# ---- Gameplay region queries (match the procedural visuals) ----
const PlanetRegionScript := preload("res://planet_smooth/PlanetRegion.gd")

func _gp(pname: String, def: float) -> float:
	var v = (material_override as ShaderMaterial).get_shader_parameter(pname)
	return float(v) if v != null else def

func _region_params() -> Dictionary:
	return {
		"land_size": _gp("land_size", 4.0),
		"land_seed": _gp("land_seed", 8.0),
		"land_octaves": int(_gp("land_octaves", 5.0)),
		"continent_scale": _gp("continent_scale", 1.8),
		"continent_mix": _gp("continent_mix", 0.5),
		"land_cutoff": _gp("land_cutoff", 0.5),
		"ice_north": _gp("ice_north", 0.0),
		"ice_south": _gp("ice_south", 0.0),
	}

# local_dir = unit direction in the planet's LOCAL space (use to_local on a world hit, then normalize).
func surface_type(local_dir: Vector3) -> String:
	return PlanetRegionScript.classify(local_dir, _region_params())

func is_land(local_dir: Vector3) -> bool:
	return surface_type(local_dir) != "ocean"

# Convert a world-space point/dir on the planet to a local unit direction for the queries above.
func to_local_dir(world_point: Vector3) -> Vector3:
	return (global_transform.affine_inverse() * world_point).normalized()

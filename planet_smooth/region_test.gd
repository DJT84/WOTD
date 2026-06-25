extends Node3D

# Validates that the GDScript region query matches the shader's procedural continents.
# Left: procedural visual. Right: a sphere fed a map BAKED FROM PlanetRegion.classify().
# If the port is correct, the continents line up.
const EarthPlanetScript = preload("res://planet_smooth/earth_planet.gd")
const PlanetRegionScript = preload("res://planet_smooth/PlanetRegion.gd")

func _bake_query_map(params: Dictionary, w := 256, h := 128) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var vv := (float(y) + 0.5) / float(h)
		var sy := cos(vv * PI)
		var r := sqrt(max(0.0, 1.0 - sy * sy))
		for x in w:
			var uu := (float(x) + 0.5) / float(w)
			var phi := (uu - 0.5) * TAU
			var dir := Vector3(r * sin(phi), sy, r * cos(phi))
			var t: String = PlanetRegionScript.classify(dir, params)
			var lv := 0.0 if t == "ocean" else 1.0
			img.set_pixel(x, y, Color(lv, lv, 1.0 - lv))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make(epoch: String, pos: Vector3) -> MeshInstance3D:
	var ep: MeshInstance3D = EarthPlanetScript.new()
	ep.set("epoch", epoch)
	ep.set("show_clouds", false)
	ep.set("show_shadow", true)
	ep.set("use_paleo_map", false)
	add_child(ep)
	ep.position = pos
	(ep.material_override as ShaderMaterial).set_shader_parameter("spin_speed", 0.0)
	return ep

func _ready() -> void:
	var left := _make("permian", Vector3(-0.62, 0, 0))           # procedural visual
	var params: Dictionary = left.call("_region_params")
	var tex := _bake_query_map(params)
	var right := _make("permian", Vector3(0.62, 0, 0))           # fed the query-baked map
	var rmat := right.material_override as ShaderMaterial
	rmat.set_shader_parameter("use_earth_map", true)
	rmat.set_shader_parameter("earth_map", tex)
	rmat.set_shader_parameter("earth_sea_level", 0.0)

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0, 0, 2.5)
	add_child(cam)
	cam.make_current()
	for f in range(8):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://planet_smooth/region_test.png")
	get_tree().quit()

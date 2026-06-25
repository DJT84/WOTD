extends Node3D

# All 8 epochs: top row = procedural continents, bottom row = baked from game land-polygons.
# Columns left->right: Cambrian, Carboniferous, Permian, Jurassic, Cretaceous, Eocene, Pleistocene, Holocene.
const EarthPlanetScript = preload("res://planet_smooth/earth_planet.gd")
const ORDER := ["cambrian", "carboniferous", "permian", "jurassic", "cretaceous", "eocene", "pleistocene", "holocene"]

func _bake_region(P, age: int, w: int = 200, h: int = 100) -> ImageTexture:
	var cfg: Dictionary = P._age_cfg[age]
	var lands: Array = cfg["land_polygons"]
	var seas: Array = cfg.get("sea_polygons", [])
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var lat := 90.0 - (float(y) + 0.5) / float(h) * 180.0
		for x in w:
			var lon := ((float(x) + 0.5) / float(w) - 0.5) * 360.0
			var is_land := false
			for poly in lands:
				if P._point_in_polygon(lat, lon, poly):
					is_land = true
					break
			if is_land:
				for sp in seas:
					if P._point_in_polygon(lat, lon, sp["poly"]):
						is_land = false
						break
			var lv := 1.0 if is_land else 0.0
			img.set_pixel(x, y, Color(lv, lv, 1.0 - lv))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_planet(epoch: String, pos: Vector3, region_tex: ImageTexture) -> void:
	var ep: MeshInstance3D = EarthPlanetScript.new()
	ep.set("epoch", epoch)
	ep.set("show_clouds", false)
	ep.set("show_shadow", true)
	add_child(ep)
	ep.position = pos
	var mat := ep.material_override as ShaderMaterial
	mat.set_shader_parameter("spin_speed", 0.0)
	if region_tex != null:
		mat.set_shader_parameter("use_earth_map", true)
		mat.set_shader_parameter("earth_map", region_tex)
		mat.set_shader_parameter("earth_sea_level", 0.0)

func _ready() -> void:
	var P = load("res://scripts/Planet.gd").new()
	var spacing := 0.95
	for i in ORDER.size():
		var x := (float(i) - 3.5) * spacing
		_make_planet(ORDER[i], Vector3(x, 0.52, 0), null)              # procedural (top)
		_make_planet(ORDER[i], Vector3(x, -0.52, 0), _bake_region(P, i))  # polygons (bottom)
	P.free()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.4
	cam.position = Vector3(0, 0, 6)
	add_child(cam)
	cam.make_current()
	if "--capture" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_args():
		for f in range(10):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://planet_smooth/all_epochs.png")
		get_tree().quit()

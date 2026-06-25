extends Node3D

# Compares procedural continents vs the game's real epoch land-polygons, both rendered with
# EarthSphere. Bakes a region map from Planet.gd's _age_cfg land/sea polygons.
const EarthPlanetScript = preload("res://planet_smooth/earth_planet.gd")

func _bake_region(age: int, w: int = 256, h: int = 128) -> ImageTexture:
	var P = load("res://scripts/Planet.gd").new()
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
	P.free()
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
	var age := 2  # Permian (Pangaea)
	var tex := _bake_region(age)
	_make_planet("permian", Vector3(-0.62, 0, 0), null)   # left: procedural
	_make_planet("permian", Vector3(0.62, 0, 0), tex)     # right: game polygons
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0, 0, 2.5)
	add_child(cam)
	cam.make_current()
	# Optional screenshot for tooling; otherwise stays open so you can view it live.
	if "--capture" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_args():
		for f in range(8):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://planet_smooth/compare.png")
		get_tree().quit()

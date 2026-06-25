class_name PlanetLoader
extends RefCounted

# Loads epoch presets from earth_epochs.json and applies them to an EarthSphere ShaderMaterial.
#
# Usage:
#   var epochs := PlanetLoader.load_file("res://planet_smooth/earth_epochs.json")
#   PlanetLoader.apply(my_material, epochs["cretaceous"], 0)   # variation 0/1/2
#
# Any key in the preset that matches a shader uniform is set; unknown keys are ignored,
# so the same loader works for hand-authored JSON exported from the generator too.

static func load_file(path: String = "res://planet_smooth/earth_epochs.json") -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("PlanetLoader: cannot open " + path)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("PlanetLoader: invalid JSON in " + path)
		return {}
	return data

static func apply(mat: ShaderMaterial, preset: Dictionary, variation: int = 0) -> void:
	for key in preset.keys():
		if String(key).begins_with("_"):
			continue
		var v: Variant = preset[key]
		if v is Array:
			if v.size() == 3:
				mat.set_shader_parameter(key, Color(v[0], v[1], v[2]))
			elif v.size() == 4:
				mat.set_shader_parameter(key, Color(v[0], v[1], v[2], v[3]))
		else:
			mat.set_shader_parameter(key, v)

	# Variations: deterministically offset every seed so each gives a different
	# continent/cloud/ice layout while keeping the epoch's palette and climate.
	if variation != 0:
		var off := float(variation) * 3.17
		for sk in ["seed", "land_seed", "seedClouds", "ice_seed"]:
			if preset.has(sk):
				mat.set_shader_parameter(sk, fmod(float(preset[sk]) + off, 10.0))

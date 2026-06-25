extends RefCounted
class_name PlanetRegion

# GDScript port of EarthSphere.gdshader's procedural land function, so gameplay can ask
# "is this point land, ocean, or ice?" and get an answer that MATCHES the rendered planet.
# Pass a params dict (read from the planet material). Directions are LOCAL-space unit vectors.

static func _hash3(p: Vector3, sd: float) -> float:
	p = p * Vector3(0.1031, 0.1030, 0.0973) + Vector3.ONE * (sd * 0.123)
	p = p - p.floor()
	var a := p.dot(Vector3(p.y, p.x, p.z) + Vector3.ONE * 33.33)
	p += Vector3.ONE * a
	var f := (p.x + p.y) * p.z
	return f - floor(f)

static func _vnoise3(x: Vector3, sd: float) -> float:
	var i := x.floor()
	var f := x - i
	var u := Vector3(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y), f.z * f.z * (3.0 - 2.0 * f.z))
	var n000 := _hash3(i + Vector3(0, 0, 0), sd)
	var n100 := _hash3(i + Vector3(1, 0, 0), sd)
	var n010 := _hash3(i + Vector3(0, 1, 0), sd)
	var n110 := _hash3(i + Vector3(1, 1, 0), sd)
	var n001 := _hash3(i + Vector3(0, 0, 1), sd)
	var n101 := _hash3(i + Vector3(1, 0, 1), sd)
	var n011 := _hash3(i + Vector3(0, 1, 1), sd)
	var n111 := _hash3(i + Vector3(1, 1, 1), sd)
	var nx00 := lerpf(n000, n100, u.x)
	var nx10 := lerpf(n010, n110, u.x)
	var nx01 := lerpf(n001, n101, u.x)
	var nx11 := lerpf(n011, n111, u.x)
	return lerpf(lerpf(nx00, nx10, u.y), lerpf(nx01, nx11, u.y), u.z)

static func _fbm3(p: Vector3, sd: float, oct: int) -> float:
	var v := 0.0
	var a := 0.5
	for k in oct:
		v += _vnoise3(p, sd) * a
		p *= 2.0
		a *= 0.5
	return v

# Procedural elevation at a local-space unit direction (matches shader's `elev`).
static func elevation(dir: Vector3, p: Dictionary) -> float:
	var detail := _fbm3(dir * p.land_size, p.land_seed, p.land_octaves)
	var cont := _fbm3(dir * p.continent_scale, p.land_seed + 0.5, 4)
	return cont + (detail - 0.5) * (p.continent_mix * 0.4)

# "ocean" | "land" | "ice"
static func classify(dir: Vector3, p: Dictionary) -> String:
	dir = dir.normalized()
	var lat: float = abs(dir.y)
	var cov: float = p.ice_north if dir.y >= 0.0 else p.ice_south
	if lat > 1.0 - cov:
		return "ice"
	if elevation(dir, p) > p.land_cutoff:
		return "land"
	return "ocean"

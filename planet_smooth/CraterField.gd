extends RefCounted
class_name CraterField

# Persistent crater "scar map" for a planet. Stamps craters into an equirectangular R8 image
# that the EarthSphere shader samples — so craters are PERMANENT and UNLIMITED (one texture
# lookup regardless of count). Matches the shader's UV: u=atan2(x,z)/2pi+0.5, v=acos(y)/pi.

var w: int
var h: int
var img: Image
var tex: ImageTexture

func _init(width: int = 1024, height: int = 512) -> void:
	w = width
	h = height
	img = Image.create(w, h, false, Image.FORMAT_R8)
	img.fill(Color(0, 0, 0))
	tex = ImageTexture.create_from_image(img)

# Wipe all craters — a fresh, pristine planet (called when a new epoch arrives).
func clear() -> void:
	img.fill(Color(0, 0, 0))
	tex.update(img)

# local_dir: unit direction in planet local space. ang_radius: crater size in radians.
func stamp(local_dir: Vector3, ang_radius: float, intensity: float = 1.0, wobble_seed: float = 0.0) -> void:
	var n := local_dir.normalized()
	var vc := acos(clampf(n.y, -1.0, 1.0)) / PI
	var vr := ang_radius / PI + 1.0 / float(h)
	var y0 := int(floor((vc - vr) * h))
	var y1 := int(ceil((vc + vr) * h))
	for y in range(y0, y1 + 1):
		if y < 0 or y >= h:
			continue
		var vv := (float(y) + 0.5) / float(h)
		var sy := cos(vv * PI)
		var rlat := sqrt(maxf(0.0, 1.0 - sy * sy))
		# half-width in U (longitude columns widen toward the poles)
		var uhw := 0.55
		if rlat > 0.001:
			uhw = clampf(ang_radius / (TAU * rlat) * 1.4 + 2.0 / float(w), 0.0, 0.55)
		var xc := int((atan2(n.x, n.z) / TAU + 0.5) * w)
		var xspan := int(ceil(uhw * w))
		for dx in range(-xspan, xspan + 1):
			var x := wrapi(xc + dx, 0, w)
			var uu := (float(x) + 0.5) / float(w)
			var phi := (uu - 0.5) * TAU
			var dir := Vector3(rlat * sin(phi), sy, rlat * cos(phi))
			var ang := acos(clampf(dir.dot(n), -1.0, 1.0))
			# gently irregular rim (subtle, so craters read as round, not wavy)
			var wob := sin(phi * 5.0 + wobble_seed) * 0.018 + sin(phi * 11.0 + wobble_seed * 2.3) * 0.010
			var edge := ang_radius * (1.0 + wob)
			if ang > edge:
				continue
			var t := ang / maxf(edge, 1e-5)            # 0 center .. 1 rim
			var add := (1.0 - smoothstep(0.30, 1.0, t)) * intensity   # soft bowl falloff
			var cur := img.get_pixel(x, y).r
			img.set_pixel(x, y, Color(minf(1.0, cur + add), 0, 0))
	tex.update(img)

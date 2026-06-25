class_name BeltBaker
extends RefCounted

# Generates the static asteroid-belt cloud as an RGBA image.
# Stored with direct alpha values (no scaling trick) so BLEND_MODE_MIX works
# transparently over the 3D scene.  Peak alpha 0.15 gives a clearly visible
# cloud while remaining subtle on the dark space background.

const SIGMA     := 70.0
const PEAK_BASE := 0.15
const X_LO_FRAC := -0.14
const X_HI_FRAC :=  1.14


static func bake(vp_size: Vector2,
		sigma: float = SIGMA,
		peak:  float = PEAK_BASE,
		belt_col: Color = Color(0.94, 0.91, 0.86)) -> Image:
	var w    := int(vp_size.x)
	var h    := int(vp_size.y)
	var img  := Image.create(w, h, false, Image.FORMAT_RGBA8)

	var y_max: int = min(int(sigma * 3.0), h - 1)

	var x_lo     := vp_size.x * X_LO_FRAC
	var arc_span := vp_size.x * (X_HI_FRAC - X_LO_FRAC)

	var gauss_lut := PackedFloat32Array()
	gauss_lut.resize(y_max + 1)
	var fade_lut := PackedFloat32Array()
	fade_lut.resize(y_max + 1)

	var lut_i: int = 0
	while lut_i <= y_max:
		var g: float     = peak * exp(-float(lut_i * lut_i) / (2.0 * sigma * sigma))
		var tight: float = lerp(0.75, 0.93, float(lut_i) / float(y_max))
		var fade: float  = lerp(0.07, 0.28, tight)
		gauss_lut[lut_i] = g
		fade_lut[lut_i]  = fade
		lut_i += 1

	var thresh: float = peak * 0.03

	var px: int = 0
	while px < w:
		var fx := float(px)
		var ay := _arc_y(fx, vp_size)
		var t  : float = clamp((fx - x_lo) / arc_span, 0.0, 1.0)

		var dy: int = -y_max
		while dy <= y_max:
			var py: int = int(ay) + dy
			if py >= 0 and py < h:
				var dady: int = abs(dy)
				var g    := gauss_lut[dady]
				if g >= thresh:
					var fade := fade_lut[dady]
					var ea: float = clamp(
						smoothstep(0.0, fade, t) * smoothstep(1.0, 1.0 - fade, t),
						0.0, 1.0)
					var alpha := g * ea
					img.set_pixel(px, py, Color(belt_col.r, belt_col.g, belt_col.b, alpha))
			dy += 1
		px += 1

	return img


static func _arc_y(x: float, vp: Vector2) -> float:
	var norm := (x - vp.x * 0.5) / (vp.x * 0.5)
	return vp.y * 0.85 - norm * norm * 20.0

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4  ring_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
uniform float alpha      : hint_range(0.0, 1.0) = 1.0;
uniform float pixel_size : hint_range(0.01, 1.0) = 0.12;
uniform vec3  ring_center;                        // planet-local impact point
uniform float inner_r    : hint_range(0.0, 20.0) = 0.4;
uniform float outer_r    : hint_range(0.0, 20.0) = 0.6;

varying vec3 v_local;

void vertex() {
	// VERTEX is in planet-local space (ring mesh sits at origin, child of planet)
	v_local = VERTEX;
}

float px_hash(vec3 id) {
	return fract(sin(dot(id, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	// Pixel-snap the radial distance so inner/outer edges step on pixel boundaries,
	// never diagonally through a pixel cell.
	float dist    = length(v_local - ring_center);
	float snapped = floor(dist / pixel_size + 0.5) * pixel_size;
	if (snapped < inner_r || snapped > outer_r) discard;

	// Pixelated dissolve: each pixel cell has a fixed random threshold.
	// As alpha drops the ring dissolves cell-by-cell rather than fading smoothly.
	vec3  px_id = floor(v_local / pixel_size + 0.5);
	float rnd   = px_hash(px_id);
	if (rnd > alpha) discard;

	// Colour variation uses a different hash so dissolve order and shade are uncorrelated.
	float col_rnd = px_hash(px_id + vec3(47.3, 19.7, 83.1));
	vec3 col;
	if      (col_rnd < 0.50) col = ring_color.rgb;
	else if (col_rnd < 0.80) col = ring_color.rgb * 0.70;
	else                      col = ring_color.rgb * 0.45;

	ALBEDO = col;
	ALPHA  = ring_color.a;
}

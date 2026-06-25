shader_type spatial;
render_mode unshaded, cull_disabled;

// No transparency — solid sphere with near-black background + star dots.
// Planet occludes it naturally via depth buffer.

varying vec3 v_world_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = normalize(v_world_pos);

	vec3 cell_a = floor(d * 600.0 + 0.5);
	float h_a   = hash(cell_a);
	float star_a = step(0.997, h_a) * mix(0.60, 1.0, hash(cell_a * 3.1));

	vec3 cell_b = floor(d * 1100.0 + 0.5);
	float h_b   = hash(cell_b);
	float star_b = step(0.998, h_b) * mix(0.30, 0.65, hash(cell_b * 2.7));

	float brightness = max(star_a, star_b);

	float warmth   = hash(cell_a + vec3(0.3, 0.7, 0.1));
	vec3 star_col  = mix(vec3(0.78, 0.88, 1.00), vec3(1.00, 0.95, 0.85), warmth) * brightness;

	// Background matches Environment BG_COLOR so seam is invisible
	ALBEDO = vec3(0.02, 0.02, 0.05) + star_col;
}

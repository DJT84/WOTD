shader_type spatial;
render_mode unshaded;

// Pixel size in world units — match the planet's apparent pixel density
uniform float pixel_size : hint_range(0.01, 0.5) = 0.06;

// Rock colour palette
uniform vec4 color_rock_base  = vec4(0.32, 0.26, 0.20, 1.0);
uniform vec4 color_rock_dark  = vec4(0.18, 0.14, 0.10, 1.0);
uniform vec4 color_rock_light = vec4(0.48, 0.40, 0.30, 1.0);

uniform vec3 sun_dir = vec3(0.55, 0.70, 0.45);

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float px_hash(vec3 id) {
	return fract(sin(dot(id, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	// Snap world position to pixel grid
	vec3 px_id = floor(v_world_pos / pixel_size + 0.5);
	float rnd  = px_hash(px_id);

	// Rock colour variation
	vec3 col;
	if      (rnd < 0.55) col = color_rock_base.rgb;
	else if (rnd < 0.80) col = color_rock_dark.rgb;
	else                 col = color_rock_light.rgb;

	// Hard 2-zone shading using world normal
	float ndotl = dot(v_world_normal, normalize(sun_dir));
	col *= ndotl > 0.0 ? 1.0 : 0.36;

	ALBEDO = clamp(col, 0.0, 1.0);
}

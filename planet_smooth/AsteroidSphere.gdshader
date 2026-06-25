// AsteroidSphere.gdshader — cel-shaded 3D asteroid for Godot 4.x Forward+
// Vertex displacement warps a SphereMesh into an irregular rocky shape.
// Use on a MeshInstance3D with SphereMesh (radius 0.5, 96×48 segments).
// Tumble by rotating the node from script — surface details follow automatically.

shader_type spatial;
render_mode unshaded, cull_back, blend_mix;

// ---- Lighting ----
uniform vec3  sun_dir        = vec3(0.85, 0.25, 0.35);
uniform float light_border_1 = 0.38;
uniform float light_border_2 = 0.58;
uniform bool  shadow_enabled = true;

// ---- Shape displacement ----
uniform float displacement : hint_range(0.0, 0.45) = 0.20;  // 0 = sphere, 0.45 = very lumpy
uniform float shape_scale  : hint_range(0.5, 4.0)  = 2.2;   // low = big blobs, high = many bumps
uniform float shape_seed   = 1.0;

// ---- Surface detail ----
uniform float surface_scale   : hint_range(1.0, 10.0) = 4.5;
uniform float surface_seed    = 3.0;
uniform float band_smoothness : hint_range(0.0, 1.0)  = 0.06;
uniform float edge_softness   : hint_range(0.0, 3.0)  = 0.35;

// ---- Rock colors (4 elevation bands) ----
uniform vec3 rock_color1 : source_color = vec3(0.42, 0.35, 0.26); // lit / high
uniform vec3 rock_color2 : source_color = vec3(0.28, 0.23, 0.17); // mid
uniform vec3 rock_color3 : source_color = vec3(0.16, 0.13, 0.10); // low
uniform vec3 rock_color4 : source_color = vec3(0.08, 0.07, 0.05); // shadow floor

// ---- Craters ----
uniform float crater_scale   : hint_range(1.0, 8.0) = 3.8;
uniform float crater_density : hint_range(0.0, 1.0) = 0.55; // 0 = none, 1 = heavily cratered
uniform float crater_depth   : hint_range(0.0, 1.0) = 0.60; // darkness of crater floors
uniform float crater_seed    = 7.0;

// ---- Metallic sheen (M-type) ----
uniform float metallic       : hint_range(0.0, 1.0) = 0.0;
uniform vec3  specular_color : source_color          = vec3(0.82, 0.80, 0.74);

// ---- Rim glow (dust scatter / silhouette scatter) ----
uniform vec3  rim_color    : source_color        = vec3(0.38, 0.30, 0.22);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.22;
uniform float rim_falloff  : hint_range(1.0, 8.0) = 4.0;

// ---- Outline ----
uniform float outline_strength : hint_range(0.0, 1.0)  = 0.88;
uniform float outline_width    : hint_range(1.0, 10.0) = 5.5;
uniform vec3  outline_color    : source_color           = vec3(0.0, 0.0, 0.0);

// ---- Ghost assembly (0 = pure ghost silhouette, 1 = fully solid) ----
uniform float ghost_fill  : hint_range(0.0, 1.0) = 1.0;
uniform vec3  ghost_color : source_color          = vec3(0.28, 0.40, 0.65);

varying vec3 v_local;
varying vec3 v_world_normal;

// ---------------------------------------------------------------- Noise
float hash3(vec3 p, float sd) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973) + sd * 0.123);
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 x, float sd) {
	vec3 i = floor(x); vec3 f = fract(x);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i + vec3(0,0,0), sd); float n100 = hash3(i + vec3(1,0,0), sd);
	float n010 = hash3(i + vec3(0,1,0), sd); float n110 = hash3(i + vec3(1,1,0), sd);
	float n001 = hash3(i + vec3(0,0,1), sd); float n101 = hash3(i + vec3(1,0,1), sd);
	float n011 = hash3(i + vec3(0,1,1), sd); float n111 = hash3(i + vec3(1,1,1), sd);
	return mix(mix(mix(n000,n100,u.x), mix(n010,n110,u.x), u.y),
	           mix(mix(n001,n101,u.x), mix(n011,n111,u.x), u.y), u.z);
}

float fbm3(vec3 p, float sd, int oct) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < oct; i++) { v += vnoise3(p, sd) * a; p *= 2.0; a *= 0.5; }
	return v;
}

float aastep(float threshold, float val) {
	float aa = fwidth(val) * max(edge_softness, 0.0001);
	float w  = max(aa, band_smoothness * 0.22);
	return smoothstep(threshold - w, threshold + w, val);
}

// ---------------------------------------------------------------- Vertex
void vertex() {
	vec3 n    = normalize(VERTEX);
	float d   = fbm3(n * shape_scale, shape_seed, 4);
	VERTEX    = n * (0.5 + (d - 0.5) * displacement);
	NORMAL    = normalize(VERTEX);
	v_local        = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// ---------------------------------------------------------------- Fragment
void fragment() {
	float ndl  = clamp(dot(v_world_normal, normalize(sun_dir)), 0.0, 1.0);
	float shade = 1.0 - ndl;
	if (!shadow_enabled) shade = 0.0;

	// --- Surface bands ---
	float surf = fbm3(v_local * surface_scale, surface_seed, 5);
	vec3 col   = rock_color4;
	col = mix(col, rock_color3, aastep(0.38, surf));
	col = mix(col, rock_color2, aastep(0.50, surf));
	col = mix(col, rock_color1, aastep(0.62, surf));

	// --- Craters: low-FBM pockets = dark floors, bright transition rim ---
	float threshold = 0.42 - crater_density * 0.18;
	float cN        = fbm3(v_local * crater_scale, crater_seed, 4);
	float cFloor    = 1.0 - aastep(threshold, cN);
	float cRim      = aastep(threshold, cN) - aastep(threshold + 0.06, cN);
	col  = mix(col, col * (1.0 - crater_depth * 0.72), cFloor);
	col += col * cRim * 0.35;

	// --- Lighting bands ---
	col = mix(col, col * 0.52, aastep(light_border_1, shade));
	col = mix(col, col * 0.78, aastep(light_border_2, shade));

	// --- Metallic specular (M-type) ---
	if (metallic > 0.001) {
		vec3  h     = normalize(normalize(sun_dir) + normalize(VIEW));
		float spec  = clamp(dot(v_world_normal, h), 0.0, 1.0);
		float sband = aastep(0.82, pow(spec, 24.0));
		col = mix(col, specular_color, sband * metallic * clamp(ndl * 2.0, 0.0, 1.0));
	}

	// --- Rim dust / scatter ---
	float view_dot = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim      = pow(1.0 - view_dot, rim_falloff);
	col += rim_color * rim * rim_strength * clamp(ndl + 0.20, 0.0, 1.0);

	// --- Ghost: lerp body colors toward ghost tint ---
	col = mix(ghost_color * 0.32, col, ghost_fill);

	// --- Outline / silhouette edge ---
	// In ghost mode the outline becomes a glowing ghost-color rim instead of black
	float outline_t   = pow(1.0 - view_dot, outline_width);
	vec3  eff_outline = mix(ghost_color * 2.2, outline_color, ghost_fill);
	col = mix(col, eff_outline, outline_t * outline_strength);

	ALBEDO = col;

	// --- Alpha: silhouette edge stays visible at all fill levels ---
	float edge_t  = pow(1.0 - view_dot, 2.2);
	float body_a  = mix(0.05, 1.0, ghost_fill);
	float edge_a  = mix(0.88, 1.0, ghost_fill);
	ALPHA = mix(body_a, edge_a, edge_t * (1.0 - ghost_fill * 0.55));
}

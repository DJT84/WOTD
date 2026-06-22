shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Single-channel height map: 0=deep ocean, 0.25=shallow sea, 0.75=land, 1=ice.
// Bilinear filter gives smooth organic coastline curves automatically.
uniform sampler2D terrain_tex : filter_linear_mipmap;
uniform float height_scale : hint_range(0.0, 2.0) = 0.90;

// Blur map: 0=deep ocean, gradient=shallow sea, 1=land.
// thresh_shallow = where deep transitions to shallow, thresh_land = where shallow becomes land.
uniform float thresh_shallow : hint_range(0.0, 1.0) = 0.18;
uniform float thresh_land    : hint_range(0.0, 1.0) = 0.72;
uniform float thresh_high    : hint_range(0.0, 1.0) = 0.90;
uniform float thresh_ice     : hint_range(0.0, 1.0) = 0.97;

// Zone colours — NOT source_color to avoid double gamma-darkening when set via code
uniform vec4 color_deep_ocean  = vec4(0.06, 0.24, 0.58, 1.0);
uniform vec4 color_shallow_sea = vec4(0.18, 0.58, 0.82, 1.0);
uniform vec4 color_land        = vec4(0.42, 0.72, 0.22, 1.0);
uniform vec4 color_highlands   = vec4(0.68, 0.52, 0.28, 1.0);
uniform vec4 color_ice         = vec4(0.88, 0.92, 0.98, 1.0);
uniform float emission_strength : hint_range(0.0, 1.0) = 0.35;

uniform sampler2D clay_normal_tex    : hint_normal;
uniform sampler2D clay_roughness_tex : hint_default_white;
uniform float clay_scale : hint_range(0.05, 5.0) = 0.8;

uniform vec4  crater_a = vec4(0.0); uniform vec4  crater_b = vec4(0.0);
uniform vec4  crater_c = vec4(0.0); uniform vec4  crater_d = vec4(0.0);
uniform float crater_dmg_a = 0.0;  uniform float crater_dmg_b = 0.0;
uniform float crater_dmg_c = 0.0;  uniform float crater_dmg_d = 0.0;

varying vec3 v_local_pos;
varying vec3 v_local_normal;

void vertex() {
	float h = texture(terrain_tex, vec2(UV.x, 1.0 - UV.y)).r;
	// Hard step for displacement — creates a sharp cliff (putty slab edge).
	// Smooth blur values are used only for colour, not for geometry.
	float h_disp = step(thresh_land, h);
	VERTEX        += NORMAL * h_disp * height_scale;
	v_local_pos    = VERTEX;
	v_local_normal = NORMAL;
}

vec4 triplanar(sampler2D tex, vec3 pos, vec3 nor, float scale) {
	vec3 w = abs(nor); w = max(w, vec3(0.0001)); w /= (w.x + w.y + w.z);
	return texture(tex, pos.yz * scale) * w.x
	     + texture(tex, pos.xz * scale) * w.y
	     + texture(tex, pos.xy * scale) * w.z;
}

void apply_crater(vec3 pos, vec4 cdata, float dmg, inout vec3 col) {
	if (dmg <= 0.0 || cdata.w <= 0.0) return;
	float t    = length(pos - cdata.xyz) / cdata.w;
	float bowl = (1.0 - smoothstep(0.0, 0.88, t)) * dmg;
	float rim  = smoothstep(0.86, 0.96, t) * (1.0 - smoothstep(0.96, 1.18, t)) * dmg;
	float halo = smoothstep(1.12, 1.22, t) * (1.0 - smoothstep(1.22, 1.60, t)) * dmg;
	col = mix(col, vec3(0.07, 0.05, 0.035), bowl * 0.78);
	col = mix(col, col * 1.35, rim  * 0.60);
	col = mix(col, col * 0.60, halo * 0.45);
}

void fragment() {
	float h = texture(terrain_tex, vec2(UV.x, 1.0 - UV.y)).r;

	// Threshold the smooth height gradient into hard colour zones.
	// Bilinear filter means the h value transitions smoothly at coastlines,
	// so the threshold boundary traces a smooth organic curve — no staircase.
	vec3 col;
	if      (h < thresh_shallow) col = color_deep_ocean.rgb;
	else if (h < thresh_land)    col = color_shallow_sea.rgb;
	else if (h < thresh_high)    col = color_land.rgb;
	else if (h < thresh_ice)     col = color_highlands.rgb;
	else                         col = color_ice.rgb;

	vec3  nor    = normalize(v_local_normal);
	vec4  clay_n = triplanar(clay_normal_tex,    v_local_pos, nor, clay_scale * 0.09);
	float clay_r = triplanar(clay_roughness_tex, v_local_pos, nor, clay_scale * 0.09).r;

	apply_crater(v_local_pos, crater_a, crater_dmg_a, col);
	apply_crater(v_local_pos, crater_b, crater_dmg_b, col);
	apply_crater(v_local_pos, crater_c, crater_dmg_c, col);
	apply_crater(v_local_pos, crater_d, crater_dmg_d, col);

	ALBEDO           = clamp(col, 0.0, 1.0);
	EMISSION         = col * emission_strength;
	ROUGHNESS        = clamp(0.84 - clay_r * 0.12, 0.65, 0.92);
	METALLIC         = 0.0;
	SPECULAR         = 0.1;
	NORMAL_MAP       = clay_n.rgb;
	NORMAL_MAP_DEPTH = 0.15;
}

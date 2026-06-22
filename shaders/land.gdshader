shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4  land_color   : source_color = vec4(0.54, 0.50, 0.44, 1.0);
uniform vec4  scorch_color : source_color = vec4(0.12, 0.06, 0.02, 1.0);
uniform vec4  sss_color    : source_color = vec4(0.75, 0.85, 0.55, 1.0);
uniform float sss_strength : hint_range(0.0, 0.6)  = 0.18;
uniform float tex_scale    : hint_range(0.5, 12.0) = 5.0;
uniform float normal_depth : hint_range(0.0, 3.0)  = 1.4;

uniform sampler2D normal_tex    : hint_normal,        repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, repeat_enable;
uniform sampler2D color_tex     : source_color,       repeat_enable;

uniform float land_scale     : hint_range(0.5, 5.0)  = 1.1;
uniform float land_threshold : hint_range(0.0, 1.0)  = 0.50;
uniform float land_edge_soft : hint_range(0.01, 0.4) = 0.22;
uniform float displacement   : hint_range(0.0, 1.5)  = 0.50;
uniform float seed_offset    : hint_range(0.0, 99.0) = 0.0;

uniform vec4 impacts[8];

float _hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}
float _noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(_hash(i+vec3(0,0,0)),_hash(i+vec3(1,0,0)),u.x),
		    mix(_hash(i+vec3(0,1,0)),_hash(i+vec3(1,1,0)),u.x),u.y),
		mix(mix(_hash(i+vec3(0,0,1)),_hash(i+vec3(1,0,1)),u.x),
		    mix(_hash(i+vec3(0,1,1)),_hash(i+vec3(1,1,1)),u.x),u.y),u.z);
}
// 3 octaves — large smooth blobs not angular continents
float _fbm(vec3 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 3; i++) { v += _noise(p) * a; p *= 2.0; a *= 0.5; }
	return v;
}

varying float v_mask;
varying vec3  v_sphere;

void vertex() {
	v_sphere = normalize(VERTEX);
	float n  = _fbm(v_sphere * land_scale + vec3(seed_offset * 7.319));
	v_mask   = smoothstep(land_threshold - land_edge_soft,
	                      land_threshold + land_edge_soft, n);
	VERTEX  += NORMAL * displacement * v_mask;
}

void fragment() {
	if (v_mask < 0.04) discard;

	vec2 uv = UV * tex_scale;

	NORMAL_MAP       = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * v_mask;

	float rough = texture(roughness_tex, uv).r;

	vec3  clay     = texture(color_tex, uv).rgb;
	float clay_lum = dot(clay, vec3(0.299, 0.587, 0.114));
	vec3  col      = land_color.rgb * (clay_lum * 0.35 + 0.82);
	col            = clamp(col, 0.0, 1.0);

	// Impact scorch
	float scorch = 0.0;
	for (int i = 0; i < 8; i++) {
		if (impacts[i].w > 0.001) {
			float dist = acos(clamp(dot(v_sphere, impacts[i].xyz), -1.0, 1.0));
			scorch = max(scorch, 1.0 - smoothstep(0.0, impacts[i].w, dist));
		}
	}
	col = mix(col, scorch_color.rgb, scorch * scorch);

	float fresnel = pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 2.5);

	ALBEDO    = col;
	ROUGHNESS = rough;
	METALLIC  = 0.0;
	SPECULAR  = 0.22;
	EMISSION  = sss_color.rgb * fresnel * sss_strength * (1.0 - scorch * 0.8);
}

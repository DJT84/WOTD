shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4  ocean_color  : source_color = vec4(0.06, 0.18, 0.42, 1.0);
uniform vec4  land_color   : source_color = vec4(0.54, 0.50, 0.44, 1.0);
uniform vec4  edge_color   : source_color = vec4(0.18, 0.14, 0.10, 1.0);
uniform vec4  scorch_color : source_color = vec4(0.12, 0.06, 0.02, 1.0);
uniform vec4  sss_color    : source_color = vec4(0.12, 0.40, 0.75, 1.0);
uniform float sss_strength : hint_range(0.0, 1.0)  = 0.30;

uniform float tex_scale        : hint_range(0.5, 12.0) = 4.0;
uniform float land_normal_depth  : hint_range(0.0, 4.0) = 2.5;
uniform float ocean_normal_depth : hint_range(0.0, 4.0) = 0.9;
uniform float ocean_roughness_scale : hint_range(0.0, 1.0) = 0.75;

uniform sampler2D normal_tex    : hint_normal,        repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, repeat_enable;
uniform sampler2D color_tex     : source_color,       repeat_enable;

uniform float land_scale     : hint_range(0.5, 5.0)  = 1.1;
uniform float land_threshold : hint_range(0.0, 1.0)  = 0.50;
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
float _fbm(vec3 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 3; i++) { v += _noise(p) * a; p *= 2.0; a *= 0.5; }
	return v;
}

varying vec3 v_sphere;

void vertex() {
	v_sphere = normalize(VERTEX);
}

void fragment() {
	vec2 uv = UV * tex_scale;

	float n      = _fbm(v_sphere * land_scale + vec3(seed_offset * 7.319));
	bool  is_land = n >= land_threshold;

	// Thin dark edge band just inside the land boundary — fakes clay slab thickness
	float edge_t = smoothstep(land_threshold, land_threshold + 0.06, n);

	vec3  clay     = texture(color_tex, uv).rgb;
	float clay_lum = dot(clay, vec3(0.299, 0.587, 0.114));
	vec3  norm     = texture(normal_tex, uv).rgb;
	float rough    = texture(roughness_tex, uv).r;

	if (is_land) {
		// Clay colour blended with texture for visible surface detail
		vec3 col = mix(land_color.rgb, clay, 0.30);
		col      = clamp(col * (clay_lum * 0.40 + 0.80), 0.0, 1.0);
		// Dark edge band — narrow, only at the land shore
		col = mix(edge_color.rgb, col, edge_t);

		// Impact scorch
		float scorch = 0.0;
		for (int i = 0; i < 8; i++) {
			if (impacts[i].w > 0.001) {
				float dist = acos(clamp(dot(v_sphere, impacts[i].xyz), -1.0, 1.0));
				scorch = max(scorch, 1.0 - smoothstep(0.0, impacts[i].w, dist));
			}
		}
		col = mix(col, scorch_color.rgb, scorch * scorch);

		float land_fresnel = pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 3.0);
		vec4  land_sss     = vec4(0.75, 0.85, 0.55, 1.0);

		ALBEDO           = col;
		NORMAL_MAP       = norm;
		NORMAL_MAP_DEPTH = land_normal_depth;
		ROUGHNESS        = rough;
		METALLIC         = 0.0;
		SPECULAR         = 0.08;
		EMISSION         = land_sss.rgb * land_fresnel * 0.15;
	} else {
		float fresnel = pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 2.0);

		ALBEDO           = ocean_color.rgb;
		NORMAL_MAP       = norm;
		NORMAL_MAP_DEPTH = ocean_normal_depth;
		ROUGHNESS        = rough * ocean_roughness_scale;
		METALLIC         = 0.0;
		SPECULAR         = 0.25;
		EMISSION         = sss_color.rgb * fresnel * sss_strength;
	}
}

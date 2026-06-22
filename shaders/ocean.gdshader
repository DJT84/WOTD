shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4  ocean_color  : source_color = vec4(0.06, 0.18, 0.42, 1.0);
uniform vec4  sss_color    : source_color = vec4(0.15, 0.45, 0.80, 1.0);
uniform float sss_strength : hint_range(0.0, 1.0)  = 0.35;
uniform float tex_scale    : hint_range(0.5, 12.0) = 6.0;
uniform float normal_depth : hint_range(0.0, 3.0)  = 0.8;
uniform float roughness_scale : hint_range(0.0, 1.0) = 0.80;
uniform float warp_amount  : hint_range(0.0, 0.5)  = 0.0;

uniform sampler2D normal_tex    : hint_normal,        repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, repeat_enable;

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

varying vec3 v_sphere;

void vertex() {
	v_sphere = normalize(VERTEX);
	// Low-frequency warp — slightly irregular "hand-rolled" sphere
	float w = _noise(v_sphere * 0.9 + vec3(31.7)) * 2.0 - 1.0;
	VERTEX += NORMAL * w * warp_amount;
}

void fragment() {
	vec2 uv = UV * tex_scale;

	NORMAL_MAP       = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;

	// Scale roughness down — plastic is smoother/shinier than clay
	float rough = texture(roughness_tex, uv).r * roughness_scale;

	float fresnel = pow(1.0 - clamp(dot(VIEW, NORMAL), 0.0, 1.0), 2.0);

	ALBEDO    = ocean_color.rgb;
	ROUGHNESS = rough;
	METALLIC  = 0.0;
	// Clay is matte — low specular, surface detail from normal map only
	SPECULAR  = 0.15;
	EMISSION  = sss_color.rgb * fresnel * sss_strength;
}

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white;

void fragment() {
	ALBEDO    = albedo.rgb * COLOR.rgb * texture(texture_albedo, UV).rgb;
	EMISSION  = COLOR.rgb * albedo.rgb * 0.5;
	ROUGHNESS = 0.85;
	METALLIC  = 0.0;
	SPECULAR  = 0.0;
}

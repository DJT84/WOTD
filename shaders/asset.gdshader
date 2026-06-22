shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4  albedo_color : source_color = vec4(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	ALBEDO    = albedo_color.rgb;
	ROUGHNESS = 0.85;
	METALLIC  = 0.0;
	SPECULAR  = 0.05;
}

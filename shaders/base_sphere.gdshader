shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

uniform vec4 ocean_color : source_color = vec4(0.10, 0.30, 0.50, 1.0);

void fragment() {
	ALBEDO    = ocean_color.rgb;
	ROUGHNESS = 0.9;
	METALLIC  = 0.0;
}

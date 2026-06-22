shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Vertical centre of the sharp band (0 = top, 1 = bottom of screen)
uniform float focus_center     : hint_range(0.0, 1.0) = 0.38;
// Half-height of the fully-sharp zone
uniform float focus_half_width : hint_range(0.0, 0.5) = 0.20;
// Maximum blur radius in UV units
uniform float max_blur         : hint_range(0.0, 0.02) = 0.013;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Distance outside the sharp band drives blur strength
	float dist = max(0.0, abs(uv.y - focus_center) - focus_half_width);
	float t    = dist / max(0.001, 1.0 - focus_half_width);  // 0..1
	float blur = t * t * max_blur;                            // quadratic falloff

	// 9-tap vertical Gaussian
	vec4  col  = vec4(0.0);
	float wsum = 0.0;
	for (int i = -4; i <= 4; i++) {
		float w = exp(-float(i * i) * 0.35);
		col  += texture(screen_texture, uv + vec2(0.0, float(i) * blur)) * w;
		wsum += w;
	}
	COLOR = col / wsum;
}

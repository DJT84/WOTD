shader_type spatial;
// Camera-facing additive halo around the planet. The planet's depth occludes the interior,
// so glow only appears OUTSIDE the silhouette. Forward+ bloom fires when ring_strength > 1.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3  ring_color        : source_color = vec3(0.30, 0.65, 1.0);
uniform float ring_strength     : hint_range(0.0, 8.0)  = 2.5;   // > 1 → HDR → bloom
uniform float ring_falloff      : hint_range(0.3, 10.0) = 3.0;   // higher = tighter / narrower ring
uniform float ring_size         : hint_range(0.5, 3.0)  = 1.0;   // scales quad — also recomputes planet mask
uniform float gradient_strength : hint_range(0.0, 2.0)  = 0.5;   // soft secondary outer halo

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up    = INV_VIEW_MATRIX[1].xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX *
	           vec4(world_pos + cam_right * VERTEX.x + cam_up * VERTEX.y, 1.0);
}

void fragment() {
	// Base quad half-size = 0.85. Planet radius = 0.5 → planet_edge = 0.5/0.85 = 0.588 at ring_size=1.
	// When ring_size scales the quad, UV still spans 0-1 over the larger quad, so we recalibrate:
	float planet_edge = clamp(0.588 / ring_size, 0.10, 0.95);
	float d = length(UV - vec2(0.5)) * 2.0;
	if (d <= planet_edge) discard;
	// t = 0 at the planet silhouette (bright), 1 at the quad edge (dark) — correct fade direction.
	float t = clamp((d - planet_edge) / (1.0 - planet_edge), 0.0, 1.0);
	float sharp = pow(1.0 - t, ring_falloff);
	float soft  = pow(1.0 - t, max(ring_falloff * 0.25, 0.4)) * gradient_strength * 0.4;
	float glow  = (sharp + soft) * ring_strength;
	if (glow < 0.01) discard;
	ALBEDO = ring_color * glow;
	ALPHA  = clamp(glow, 0.0, 1.0);
}

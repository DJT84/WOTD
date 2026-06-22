shader_type spatial;
// Depth test ACTIVE — planet's depth buffer occludes the quad center naturally,
// so the glow only shows where the quad extends past the planet silhouette.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4  atmos_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
// Fraction of quad half-size occupied by the planet: planet_r / (quad_half).
// Quad is 2.5× planet diameter → planet_edge = 1.0 / 1.25 = 0.80.
uniform float planet_edge : hint_range(0.0, 1.0) = 0.80;

void vertex() {
	// Billboard: keep world position but align quad axes to camera right/up.
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up    = INV_VIEW_MATRIX[1].xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX *
	           vec4(world_pos + cam_right * VERTEX.x + cam_up * VERTEX.y, 1.0);
}

void fragment() {
	// d = 0 at quad center, 1 at quad edge.
	float d = length(UV - vec2(0.5)) * 2.0;

	// Discard the interior — depth test handles it anyway, but this also
	// ensures t is remapped so glow = 1.0 right at the planet silhouette.
	if (d <= planet_edge) discard;

	// t = 0 at planet edge, t = 1 at quad edge → glow peaks at silhouette.
	float t    = (d - planet_edge) / (1.0 - planet_edge);
	float glow = pow(1.0 - clamp(t, 0.0, 1.0), 1.5);
	if (glow < 0.02) discard;

	ALBEDO = atmos_color.rgb;
	ALPHA  = glow * atmos_color.a;
}

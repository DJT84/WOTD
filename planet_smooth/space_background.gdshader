shader_type sky;
// Deep space background: three parallax star layers on a deep-navy base.
// Each layer has its own grid spacing and drift speed — closest drifts fastest.
// Stars are true point sources (~1-3 px). Epoch tint is additive and subtle.

uniform vec3  epoch_tint    = vec3(0.0);
uniform float tint_strength : hint_range(0.0, 5.0) = 1.0;

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
vec2 h22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// One star layer: cu×cv equirectangular grid, stars of radius base_r (in cell units).
// drift offsets the UV each frame for parallax.
vec3 star_layer(vec2 uv, vec2 drift, float cu, float cv,
                float density, float base_r, float bright) {
	vec2 u = vec2(fract(uv.x + drift.x), clamp(uv.y + drift.y, 0.001, 0.999));
	vec2 g  = u * vec2(cu, cv);
	vec2 gi = floor(g);
	vec3 col = vec3(0.0);
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 c = gi + vec2(float(dx), float(dy));
			if (c.y < 0.0 || c.y >= cv) continue;
			c.x = mod(c.x + cu, cu);
			if (h21(c) >= density) continue;

			// Sub-cell star position
			vec2 s = (c + h22(c + vec2(47.3, 23.7))) / vec2(cu, cv);
			vec2 d = (u - s) * vec2(cu, cv);
			if (d.x >  cu * 0.5) d.x -= cu;
			if (d.x < -cu * 0.5) d.x += cu;
			float dist = length(d);

			// Size class (80% tiny, 16% small, 4% bright anchor)
			float sz = h21(c + vec2(7.3, 1.9));
			float r   = (sz < 0.80) ? base_r : (sz < 0.96) ? base_r * 2.0 : base_r * 3.2;
			float brt = (sz < 0.80) ? 0.75   : (sz < 0.96) ? 0.95          : 1.40;

			float a = 1.0 - smoothstep(0.0, r, dist);
			if (a < 0.005) continue;

			// Colour: cool-white (74%), warm-cream (13%), pale-blue (13%)
			float hc = h21(c + vec2(13.1, 5.9));
			vec3 sc = (hc < 0.74) ? vec3(0.90, 0.93, 1.00)
			        : (hc < 0.87) ? vec3(1.00, 0.97, 0.89)
			        :               vec3(0.83, 0.89, 1.00);

			col += sc * a * brt * bright;
		}
	}
	return col;
}

void sky() {
	vec3 col = vec3(0.005, 0.008, 0.016);   // #050810 — deep navy, not pure black

	vec3 dn = normalize(EYEDIR);
	vec2 uv = vec2(atan(dn.x, dn.z) / (2.0 * PI) + 0.5,
	               acos(clamp(dn.y, -1.0, 1.0)) / PI);

	float t = TIME;

	// Layer 1 — closest, drifts fastest (one full lap ~3.5 hours)
	col += star_layer(uv, vec2(t * 0.00008, 0.0),
	                  80.0, 40.0, 0.0090, 0.025, 1.00);

	// Layer 2 — mid distance, medium drift (~5.5 hours)
	col += star_layer(uv, vec2(t * 0.00005, t * 0.00002),
	                  130.0, 65.0, 0.0050, 0.022, 0.85);

	// Layer 3 — furthest, slowest drift (~9 hours)
	col += star_layer(uv, vec2(t * 0.00003, 0.0),
	                  170.0, 85.0, 0.0025, 0.019, 0.70);

	col += epoch_tint * tint_strength;

	COLOR = col;
}

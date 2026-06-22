shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled, depth_draw_opaque;

// COLOR.rgb = terrain colour, COLOR.a = 1.0 for sea tiles, 0.0 for land.

uniform vec4  scorch_color  : source_color = vec4(0.10, 0.06, 0.04, 1.0);
uniform float damage_state  : hint_range(0.0, 2.0) = 0.0;
uniform vec3  tile_center   = vec3(0.0);
uniform float crater_radius : hint_range(0.1, 2.0) = 0.68;
uniform float edge_highlight       : hint_range(0.0, 1.0) = 0.0;
uniform vec4  edge_highlight_color : source_color = vec4(1.0, 0.82, 0.1, 1.0);

varying float v_hemisphere;
varying float v_fresnel;
varying vec3  v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
	if (UV.y > 0.5) {
		vec3 sn_world      = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 cam_dir_world = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		v_hemisphere       = dot(sn_world, cam_dir_world);
		v_fresnel          = 0.0;
	} else {
		v_hemisphere = 1.0;
		vec3 world_normal  = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 cam_dir_world = normalize(INV_VIEW_MATRIX[3].xyz - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
		v_fresnel          = pow(1.0 - max(dot(world_normal, cam_dir_world), 0.0), 3.0);
	}
}

// ── Hex-pixelate a distance value into N coarse steps ────────────────────────
// Snapping to ~4-5 visible bands across the crater radius
float hex_step(float d, float cr) {
	float bands  = 4.5;
	float cell   = cr / bands;
	return floor(d / cell) * cell + cell * 0.5;
}

// ── Cheap directional crack pattern using position ────────────────────────────
// Returns 0 = no crack, 1 = crack centre
float crack_pattern(vec3 pos, float scale) {
	vec3 p  = pos * scale;
	// Two intersecting sine-wave families at 60° to mimic hex fracture lines
	float a = abs(sin(p.x * 3.1 + p.y * 1.8));
	float b = abs(sin(p.y * 3.1 - p.z * 1.8));
	float c = abs(sin(p.z * 3.1 + p.x * 1.8));
	float v = min(min(a, b), c);   // near 0 at crack junctions
	return 1.0 - smoothstep(0.0, 0.18, v);
}

void fragment() {
	if (UV.y > 0.5 && v_hemisphere < 0.05) discard;

	float ds  = clamp(damage_state, 0.0, 2.0);
	float sea = COLOR.a;

	if (UV.y > 0.5) {
		// ── Wall ─────────────────────────────────────────────────────────────
		vec3 wall_col = COLOR.rgb * 0.7;
		if (ds > 1.0) {
			wall_col = mix(wall_col, scorch_color.rgb, ds - 1.0);
		}
		ALBEDO    = wall_col;
		EMISSION  = COLOR.rgb * 0.12;
		ROUGHNESS = 0.9;
		METALLIC  = 0.0;
		SPECULAR  = 0.05;
	} else {
		// ── Face ─────────────────────────────────────────────────────────────
		vec3 col = COLOR.rgb * (1.0 - pow(UV.x, 12.0) * 0.15);

		float dist_raw = length(v_local_pos - tile_center);
		float cr       = crater_radius;
		float ds1      = clamp(ds, 0.0, 1.0);

		// Hex-pixelated distance — snaps the crater rings to coarse bands
		float dist = mix(dist_raw, hex_step(dist_raw, cr), ds1);

		// ── Bowl ─────────────────────────────────────────────────────────────
		float bowl_mask = 1.0 - smoothstep(0.0, cr * 0.85, dist);
		float bowl_t    = dist / (cr * 0.85);
		vec3  floor_col = vec3(0.05, 0.04, 0.03);
		vec3  wall_col2 = col * 0.38;
		vec3  bowl_col  = mix(floor_col, wall_col2, pow(bowl_t, 0.6));

		// ── Highlight ring ───────────────────────────────────────────────────
		float highlight = smoothstep(cr * 0.60, cr * 0.80, dist)
		                * (1.0 - smoothstep(cr * 0.80, cr * 0.90, dist));
		vec3  hi_col    = col * 0.75;

		// ── Ejecta rim ───────────────────────────────────────────────────────
		float rim     = smoothstep(cr * 0.85, cr, dist)
		              * (1.0 - smoothstep(cr, cr * 1.10, dist));

		// ── Scorch halo ──────────────────────────────────────────────────────
		float scorch_f = smoothstep(cr * 1.05, cr * 1.15, dist)
		               * (1.0 - smoothstep(cr * 1.15, cr * 1.55, dist));

		// ── Land vs Sea diverge here ─────────────────────────────────────────
		vec3 rim_col;
		vec3 sc_col;
		vec3 crack_emission = vec3(0.0);

		if (sea < 0.5) {
			// ── LAND: hot orange-cracked rim ─────────────────────────────────
			// Rim glows orange-red, brighter at the hex-stepped inner edge
			vec3 lava_rim = mix(vec3(1.0, 0.38, 0.0), vec3(1.0, 0.72, 0.1),
			                    smoothstep(cr * 0.85, cr, dist_raw));
			rim_col = mix(col * 1.2, lava_rim, ds1 * 0.85);

			sc_col  = mix(col, scorch_color.rgb * 0.7, 0.75);

			// Glowing cracks across the scorch zone (damage_state > 1 = Scorched)
			float scorch_zone = bowl_mask + rim + scorch_f;
			float crack       = crack_pattern(v_local_pos, 8.0);
			float crack_glow  = crack * clamp(scorch_zone, 0.0, 1.0)
			                  * clamp(ds - 0.4, 0.0, 1.0);
			// Orange core bleeds through cracks; white-hot at centre
			crack_emission = mix(vec3(1.0, 0.28, 0.0), vec3(1.0, 0.75, 0.2),
			                     bowl_t) * crack_glow * 1.8;
		} else {
			// ── SEA: superheated steam / tsunami rim ─────────────────────────
			// Rim is near-white with cyan tint — vaporised water
			vec3 steam_col = mix(vec3(0.70, 0.92, 1.0), vec3(1.0, 1.0, 1.0),
			                     smoothstep(cr * 0.85, cr, dist_raw) * ds1);
			rim_col = mix(col * 1.15, steam_col, ds1 * 0.90);

			// Scorch zone: deeper blue-black on sea floor of crater
			sc_col = mix(col, vec3(0.04, 0.06, 0.10), 0.80);
		}

		col = mix(col,    bowl_col, bowl_mask * ds1);
		col = mix(col,    hi_col,   highlight * ds1);
		col = mix(col,    rim_col,  rim       * ds1);
		col = mix(col,    sc_col,   scorch_f  * ds1);
		col = clamp(col, 0.0, 1.5);

		if (ds > 1.0) {
			col = mix(col, scorch_color.rgb, (ds - 1.0) * 0.6);
		}
		col = clamp(col, 0.0, 1.0);

		// ── Edge highlight ring ───────────────────────────────────────────────
		float edge_ring = smoothstep(0.55, 1.0, UV.x);
		col = mix(col, edge_highlight_color.rgb, edge_ring * edge_highlight);

		// Sea fresnel shimmer + crack glow emission
		float steam_emission = rim * ds1 * sea * 1.2;
		EMISSION = mix(col * sea * v_fresnel * 0.3,
		               edge_highlight_color.rgb * 0.6,
		               edge_ring * edge_highlight)
		         + crack_emission
		         + vec3(0.85, 0.96, 1.0) * steam_emission;

		float shimmer = sea * v_fresnel * 0.4;
		ALBEDO    = col + vec3(shimmer);
		ROUGHNESS = mix(0.85, 0.05, sea);
		METALLIC  = mix(0.0,  0.0,  sea);
		SPECULAR  = mix(0.05, 0.9,  sea);
	}
}

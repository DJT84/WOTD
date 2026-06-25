// EarthSphere.gdshader — Godot 4.x SPATIAL shader for a real orbitable Earth-like 3D sphere.
// Cel-shaded, high-res, seamless 3D noise. Adds POLAR ICE CAPS + ATMOSPHERE RIM GLOW so one
// shader can represent many climates (greenhouse <-> icehouse) via parameters / epoch presets.
// Put on a MeshInstance3D using a SphereMesh.

shader_type spatial;
render_mode unshaded, cull_back;

// ---- General / lighting ----
uniform vec3  sun_dir = vec3(0.85, 0.25, 0.35);   // direction from planet toward the star
uniform float spin_speed = 0.04;
uniform float axial_tilt : hint_range(-45.0, 45.0) = 23.4; // degrees; positive tilts north toward +X (right)
uniform float edge_softness : hint_range(0.0, 3.0) = 0.75;
uniform float band_smoothness : hint_range(0.0, 1.0) = 0.0; // 0 = crisp vector bands, 1 = smooth gradients
uniform float light_border_1 = 0.4;   // day -> terminator
uniform float light_border_2 = 0.6;   // terminator -> night
uniform float terminator_wave : hint_range(0.0, 0.5) = 0.12; // organic waviness of day/night edge (0 = clean arc)

// Outline (dark silhouette rim) — the "vector sticker" look
uniform float outline_strength : hint_range(0.0, 1.0) = 0.0;
uniform float outline_width : hint_range(1.0, 10.0) = 4.0; // higher = thinner outline
uniform vec3  outline_color : source_color = vec3(0.0, 0.0, 0.0);
uniform bool  shadow_enabled = true;  // false = flat full-lit (no day/night terminator)
uniform bool  clouds_enabled = true;  // false = hide cloud layer

// ---- Water ----
uniform vec3  color1 : source_color = vec3(0.28, 0.52, 0.66);  // lit ocean
uniform vec3  color2 : source_color = vec3(0.14, 0.32, 0.55);  // mid
uniform vec3  color3 : source_color = vec3(0.05, 0.14, 0.32);  // night/shadow
// Sea life: depth zones + animated wave flecks
uniform vec3  ocean_shallow_color : source_color = vec3(0.34, 0.64, 0.68); // continental shelf
uniform float ocean_shallow_amt : hint_range(0.0, 1.0) = 0.55;
uniform float ocean_depth : hint_range(0.0, 1.0) = 0.45;  // how much deep basins darken
uniform float wave_flecks : hint_range(0.0, 1.0) = 0.30;  // sparkle/whitecap highlights
uniform vec3  fleck_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float size = 4.0;
uniform int   octaves = 4;
uniform float seed = 6.0;

// ---- Land ----
uniform float land_cutoff = 0.5;      // higher = less land (more ocean)
uniform float land_step = 0.06;       // spacing between elevation color bands
uniform vec3  landColor1 : source_color = vec3(0.60, 0.62, 0.34);
uniform vec3  landColor2 : source_color = vec3(0.36, 0.52, 0.22);
uniform vec3  landColor3 : source_color = vec3(0.24, 0.40, 0.22);
uniform vec3  landColor4 : source_color = vec3(0.16, 0.24, 0.18);
uniform float land_seed = 8.0;
uniform int   land_octaves = 5;
uniform float land_size = 4.0;
uniform float continent_scale = 1.8;  // low = few big continents (Pangaea), high = many scattered
uniform float continent_mix : hint_range(0.0, 1.0) = 0.5; // how much the coarse continent field dominates
uniform vec3  coast_color : source_color = vec3(0.40, 0.46, 0.22); // coastal vegetation fringe (e.g. Permian)
uniform float coast_strength : hint_range(0.0, 1.0) = 0.0;         // 0 = off
uniform float coast_width = 0.05;

// ---- Real Earth map (for Holocene / Pleistocene: recognizable continents) ----
uniform sampler2D earth_map : source_color, hint_default_white, filter_linear_mipmap;
uniform bool  use_earth_map = false;                       // sample real geography instead of procedural land
uniform float earth_sea_level : hint_range(-0.25, 0.25) = 0.0; // negative = lower sea level -> more exposed land
uniform float earth_coast_lod : hint_range(0.0, 6.0) = 2.5;   // blur the coastline -> rounded, stylized continents
uniform float coast_rough : hint_range(0.0, 0.4) = 0.16;      // procedural roughening so coasts aren't map-precise

// ---- Ice caps (latitude based) ----
uniform float ice_north : hint_range(0.0, 1.0) = 0.18; // north polar cap extent (0=none, 1=to equator)
uniform float ice_south : hint_range(0.0, 1.0) = 0.18; // south polar cap extent (lets caps be asymmetric)
uniform float ice_jitter = 0.22;      // irregularity of the cap edge (higher = more ragged)
uniform float ice_noise_size = 2.6;
uniform float ice_seed = 2.0;
uniform vec3  ice_color : source_color = vec3(0.93, 0.96, 0.99);
uniform vec3  ice_color2 : source_color = vec3(0.74, 0.82, 0.92); // secondary tone (blue/shadowed ice)
uniform float ice_var_size = 5.0;                                  // scale of the ice colour patches

// ---- Clouds ----
uniform float cloud_cover = 0.58;
uniform float cloud_size = 5.5;
uniform float cloud_wispy : hint_range(0.0, 1.0) = 0.0; // 0 = puffy/bunchy, 1 = smooth/wispy/streaky
uniform float cloud_spin_rel = 1.4;
uniform float cloud_heal_time = 12.0;  // seconds for impact-cleared clouds to return
uniform float seedClouds = 5.0;
uniform int   octaves_clouds = 4;
uniform vec3  cloud_color : source_color        = vec3(0.95, 0.96, 0.98);
uniform vec3  cloud_shadow_color : source_color = vec3(0.45, 0.48, 0.62);

// ---- Atmosphere rim ----
uniform vec3  atmosphere_color : source_color = vec3(0.40, 0.62, 1.0);
uniform float atmosphere_strength = 0.5;
uniform float atmosphere_falloff = 3.0;

// ---- Meteor impacts (drawn on the SURFACE, UNDER the clouds) ----
// Driven from GDScript. impact_dir is a local-space unit direction (sticks to the surface as
// the planet spins by node rotation). impact_age in seconds since the strike.
uniform int   impact_count = 0;
uniform vec3  impact_dir[64];
uniform float impact_radius[64];
uniform float impact_age[64];
uniform float impact_water[64];   // 1.0 = ocean strike (foam/tsunami), 0.0 = land strike (crater)

// Permanent baked craters: an equirectangular scar map (R = crater intensity). Unlimited, ~free.
uniform sampler2D scar_map : hint_default_black, filter_linear;
uniform bool  use_scar_map = false;
uniform vec3  scar_floor_color : source_color = vec3(0.10, 0.07, 0.05);

varying vec3 v_local;
varying vec3 v_world_normal;

// ---------------------------------------------------------------- 3D value noise (seamless)
float hash3(vec3 p, float sd) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973) + sd * 0.123);
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 x, float sd) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i + vec3(0,0,0), sd);
	float n100 = hash3(i + vec3(1,0,0), sd);
	float n010 = hash3(i + vec3(0,1,0), sd);
	float n110 = hash3(i + vec3(1,1,0), sd);
	float n001 = hash3(i + vec3(0,0,1), sd);
	float n101 = hash3(i + vec3(1,0,1), sd);
	float n011 = hash3(i + vec3(0,1,1), sd);
	float n111 = hash3(i + vec3(1,1,1), sd);
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

float fbm3(vec3 p, float sd, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += vnoise3(p, sd) * a;
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

vec3 rotateY(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// Tilt around Z so north (+Y) leans toward +X (right) for positive axial_tilt.
// Applied before spin so all surface features, ice caps, and clouds tilt together.
vec3 applyTilt(vec3 p) {
	float a = radians(axial_tilt);
	float c = cos(a); float s = sin(a);
	return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

// Color-band step. band_smoothness widens the transition: 0 = crisp anti-aliased (vector),
// 1 = wide smoothstep (smooth gradient). Drives the smooth<->vector look across every band.
float aastep(float threshold, float val) {
	float aa = fwidth(val) * max(edge_softness, 0.0001);
	float w = max(aa, band_smoothness * 0.22);
	return smoothstep(threshold - w, threshold + w, val);
}

void vertex() {
	v_local = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
}

void fragment() {
	vec3 tilted = applyTilt(v_local);
	vec3 sp = rotateY(tilted, -TIME * spin_speed);
	// A coarse continent field defines the landmass SHAPE (low continent_scale -> a
	// single Pangaea-like supercontinent); fine detail only roughens coasts & drives
	// the internal elevation color bands, so continents stay coherent.
	float detail = fbm3(sp * land_size, land_seed, land_octaves);
	float continent = fbm3(sp * continent_scale, land_seed + 0.5, 4);
	float elev = continent + (detail - 0.5) * (continent_mix * 0.4);

	// Fixed lighting; perturbed so the terminator is organic, not a clean stripe.
	float ndl = clamp(dot(normalize(v_world_normal), normalize(sun_dir)), 0.0, 1.0);
	float shade = 1.0 - ndl;
	shade += (fbm3(sp * size, seed, octaves) - 0.5) * terminator_wave;
	if (!shadow_enabled) shade = 0.0;   // flat, fully-lit surface

	// --- Land (computed first so the sea can read coastline proximity for shelves) ---
	vec3 land = landColor4;
	float landA;
	float land_field;       // >threshold = land
	float land_threshold;
	if (use_earth_map) {
		float u = atan(sp.x, sp.z) / (2.0 * PI) + 0.5;
		float v = acos(clamp(sp.y, -1.0, 1.0)) / PI;
		vec3 emS = textureLod(earth_map, vec2(u, v), earth_coast_lod).rgb;
		land_field = (emS.r + emS.g) * 0.5 - emS.b + (detail - 0.5) * coast_rough;
		land_threshold = earth_sea_level;
		landA = aastep(land_threshold, land_field);
		land = mix(land, landColor3, aastep(0.42, elev));
		land = mix(land, landColor2, aastep(0.52, elev));
		land = mix(land, landColor1, aastep(0.62, elev));
	} else {
		land_field = elev;
		land_threshold = land_cutoff;
		land = mix(land, landColor3, aastep(land_cutoff + land_step,       elev));
		land = mix(land, landColor2, aastep(land_cutoff + land_step * 2.0, elev));
		land = mix(land, landColor1, aastep(land_cutoff + land_step * 3.0, elev));
		float coastBand = aastep(land_cutoff, elev) - aastep(land_cutoff + coast_width, elev);
		land = mix(land, coast_color, coastBand * coast_strength);
		landA = aastep(land_cutoff, elev);
	}
	land = mix(land, land * 0.55, aastep(light_border_1, shade));
	land = mix(land, land * 0.8,  aastep(light_border_2, shade));

	// --- Water (lighting bands + depth zones + animated wave flecks) ---
	vec3 waterCol = color1;
	waterCol = mix(waterCol, color2, aastep(light_border_1, shade));
	waterCol = mix(waterCol, color3, aastep(light_border_2, shade));
	// continental shelf: crisp shallow band hugging the coasts (cel-style, like the land)
	float shore = aastep(land_threshold - 0.05, land_field);
	waterCol = mix(waterCol, ocean_shallow_color, shore * ocean_shallow_amt);
	// deep basins: crisp darker zones away from the coast
	float deepN = fbm3(sp * 2.6, seed + 5.0, 4);
	float deep = (1.0 - aastep(0.46, deepN)) * (1.0 - shore);
	waterCol = mix(waterCol, waterCol * 0.6, deep * ocean_depth);
	// wave flecks: small crisp sparkle highlights, concentrated on the lit side
	float litw = clamp(1.0 - shade * 1.4, 0.0, 1.0);
	float fleckN = fbm3(sp * 42.0 + vec3(TIME * 0.05, 0.0, TIME * 0.03), seed + 9.0, 2);
	float flecks = aastep(0.77, fleckN) * litw;
	waterCol += fleck_color * flecks * wave_flecks;

	vec3 col = mix(waterCol, land, landA);

	// --- Polar ice caps (latitude based; soft feathered snow edge, stays at poles) ---
	float lat = abs(tilted.y);
	float iceN = (fbm3(sp * ice_noise_size, ice_seed, 4) - 0.5) * ice_jitter;
	float cov = (tilted.y >= 0.0) ? ice_north : ice_south;   // asymmetric N/S caps
	float iceEdge = 1.0 - cov;
	float iceA = aastep(iceEdge, lat + iceN);   // crisp, irregular cel edge (not a perfect ring)
	vec3 ice = ice_color;
	float iceVar = fbm3(sp * ice_var_size, ice_seed + 3.0, 4);
	ice = mix(ice, ice_color2, aastep(0.48, iceVar));   // cel patches of blue/shadowed ice
	ice = mix(ice, ice * 0.65, aastep(light_border_1, shade));
	col = mix(col, ice, iceA);

	// --- Permanent baked craters (scar map): unlimited, ~free, stays forever ---
	if (use_scar_map) {
		float su = atan(v_local.x, v_local.z) / (2.0 * PI) + 0.5;
		float sv = acos(clamp(v_local.y, -1.0, 1.0)) / PI;
		float scar = texture(scar_map, vec2(su, sv)).r;
		// Smooth charred bowl tied to the underlying terrain (no flat floor / no bright rim ring).
		float c = smoothstep(0.02, 0.5, scar);
		vec3 charred = mix(col * 0.42, scar_floor_color, 0.35);
		col = mix(col, charred, c);
	}

	// --- Meteor impacts on the surface (BEFORE clouds, so clouds pass over them) ---
	for (int i = 0; i < impact_count; i++) {
		float r = impact_radius[i];
		float age = impact_age[i];
		float life = clamp(1.0 - age / 6.0, 0.0, 1.0);  // fade out over ~6s (transient)
		if (r <= 0.001 || life <= 0.0) {
			continue;  // empty / expired slot
		}
		float d = acos(clamp(dot(v_local, impact_dir[i]), -1.0, 1.0)); // angular distance
		float flash = clamp(1.0 - age / 0.25, 0.0, 1.0);
		if (impact_water[i] > 0.5) {
			// --- OCEAN strike: splash + expanding foam rings (proto-tsunami), no crater ---
			vec3 foam = vec3(0.85, 0.95, 1.0);
			float splash = smoothstep(r, 0.0, d) * clamp(1.0 - age / 0.8, 0.0, 1.0);
			col = mix(col, color1 * 1.4 + vec3(0.05), splash * 0.6);
			float wR1 = age * r * 3.0;
			float w1 = smoothstep(r * 0.16, 0.0, abs(d - wR1)) * clamp(1.0 - age / 1.6, 0.0, 1.0);
			float wR2 = age * r * 1.9;
			float w2 = smoothstep(r * 0.12, 0.0, abs(d - wR2)) * clamp(1.0 - age / 1.9, 0.0, 1.0);
			col += foam * (w1 + w2 * 0.7);
			col = mix(col, foam, smoothstep(r * 1.6, 0.0, d) * flash);
		} else {
			// --- LAND strike: charred crater + molten glow + shockwave ---
			float crater = smoothstep(r, r * 0.65, d);
			col = mix(col, col * 0.32 + vec3(0.05, 0.03, 0.02), crater * life);
			float heat = clamp(1.0 - age / 4.0, 0.0, 1.0);
			vec3 molten = mix(vec3(0.75, 0.12, 0.0), vec3(1.0, 0.78, 0.28), smoothstep(r, 0.0, d));
			col = mix(col, molten, crater * heat);
			col = mix(col, vec3(1.0, 0.97, 0.85), smoothstep(r * 1.7, 0.0, d) * flash);
			float ringR = age * r * 2.6;
			float ring = smoothstep(r * 0.12, 0.0, abs(d - ringR)) * clamp(1.0 - age / 1.2, 0.0, 1.0);
			col += vec3(1.0, 0.85, 0.6) * ring;
		}
	}

	// --- Clouds ---
	if (clouds_enabled) {
		vec3 cp = rotateY(tilted, -TIME * spin_speed * cloud_spin_rel);
		cp.y *= mix(1.0, 2.4, cloud_wispy);   // wispy -> stretch into latitudinal bands
		float c = fbm3(cp * cloud_size * mix(1.0, 1.5, cloud_wispy), seedClouds, octaves_clouds);
		vec3 cloud = cloud_color;
		cloud = mix(cloud, cloud_shadow_color, aastep(light_border_1, shade));
		// puffy = crisp opaque edge; wispy = soft, translucent
		float cw = max(fwidth(c) * max(edge_softness, 0.0001), mix(0.015, 0.20, cloud_wispy));
		float cloudA = smoothstep(cloud_cover - cw, cloud_cover + cw, c) * mix(1.0, 0.7, cloud_wispy);
		// meteors punch holes in the cloud deck (expanding with the shockwave), then heal
		float cloudClear = 0.0;
		for (int i = 0; i < impact_count; i++) {
			float dd = acos(clamp(dot(v_local, impact_dir[i]), -1.0, 1.0));
			float dispR = impact_radius[i] * mix(1.6, 3.4, clamp(impact_age[i] / 1.2, 0.0, 1.0));
			float heal = clamp(1.0 - impact_age[i] / cloud_heal_time, 0.0, 1.0);
			cloudClear = max(cloudClear, smoothstep(dispR, dispR * 0.45, dd) * heal);
		}
		cloudA *= (1.0 - cloudClear);
		col = mix(col, cloud, cloudA);
	}

	// --- Atmosphere rim glow (fresnel, brighter on day side) ---
	float view_dot = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - view_dot, atmosphere_falloff);
	col += atmosphere_color * fres * atmosphere_strength * clamp(ndl + 0.25, 0.0, 1.0);

	// Dark outline at the silhouette (applied last so it reads as a clean rim)
	float rim = pow(1.0 - view_dot, outline_width);
	col = mix(col, outline_color, rim * outline_strength);

	ALBEDO = col;
}

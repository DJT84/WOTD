shader_type spatial;
render_mode unshaded;

uniform sampler2D terrain_tex : filter_nearest;
uniform float pixel_count : hint_range(32.0, 1024.0, 1.0) = 900.0;

uniform float thresh_shallow : hint_range(0.0, 1.0) = 0.20;
uniform float thresh_land    : hint_range(0.0, 1.0) = 0.65;
uniform float thresh_high    : hint_range(0.0, 1.0) = 0.88;

uniform vec4 color_deep_ocean  = vec4(0.06, 0.18, 0.50, 1.0);
uniform vec4 color_shallow_sea = vec4(0.20, 0.52, 0.75, 1.0);
uniform vec4 color_land        = vec4(0.28, 0.60, 0.18, 1.0);
uniform vec4 color_highlands   = vec4(0.52, 0.40, 0.20, 1.0);
uniform vec4 color_midland     = vec4(0.12, 0.36, 0.08, 1.0);  // interior accent scattered in highlands zone
uniform float midland_mix      : hint_range(0.0, 1.0) = 0.0;   // fraction of interior showing midland
uniform vec4 color_ice         = vec4(0.80, 0.88, 0.95, 1.0);

uniform vec3  sun_dir     = vec3(0.55, 0.70, 0.45);
// abs(sin(lat)) threshold above which land is overridden with ice colour.
// Set to 1.01 to disable (no epoch has natural ice above 90°).
uniform float ice_y_abs : hint_range(0.0, 1.01) = 1.01;

uniform sampler2D crater_tex : filter_linear;

varying vec3 v_local_pos;

// Terrain-driven vertex displacement: land tiles pushed outward, ocean recessed.
// Four levels match the four shader zones; amounts are in world units (planet r≈6.5).
void vertex() {
	v_local_pos = VERTEX;
}

float px_hash(vec2 id) {
	return fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
}

// Width of dithered transition band between each pair of adjacent zones.
// Pixels in this band randomly show either zone based on position within it,
// producing a gradual pixelated edge that curves naturally across the grid.
const float DITHER_W = 0.10;

vec3 deep_ocean_col(float rnd, vec2 px_id) {
	float rnd2 = px_hash(px_id * 1.7 + vec2(43.1, 97.6));
	float rnd3 = px_hash(px_id * 0.3 + vec2(211.3, 53.9));
	if      (rnd > 0.99 && rnd2 > 0.4)  return mix(color_shallow_sea.rgb, vec3(1.0), 0.28);
	else if (rnd > 0.97 && rnd3 < 0.6)  return color_deep_ocean.rgb * 1.18;
	else                                 return color_deep_ocean.rgb;
}
vec3 shallow_sea_col(float rnd, vec2 px_id) {
	float rnd2 = px_hash(px_id * 2.3 + vec2(81.7, 137.2));
	if (rnd > 0.995 && rnd2 > 0.35) return mix(color_shallow_sea.rgb, vec3(1.0), 0.42);
	else                             return color_shallow_sea.rgb;
}
vec3 land_col(float rnd) {
	// No random dark pixels on coastal land — they read as noise, not character.
	// Slight brightness boost so the coastal fringe contrasts with the darker interior.
	return color_land.rgb * 1.10;
}
vec3 highlands_col(float rnd, vec2 px_id) {
	// Interior slightly darker than coastal for clear zone layering.
	vec3 base = color_highlands.rgb * 0.92;
	bool is_midland = false;
	if (midland_mix > 0.0) {
		vec2  sc  = px_id / 5.0;
		vec2  ci  = floor(sc);
		vec2  cf  = fract(sc);
		float n00 = px_hash(ci + vec2(0.0, 0.0) + vec2(73.9, 127.3));
		float n10 = px_hash(ci + vec2(1.0, 0.0) + vec2(73.9, 127.3));
		float n01 = px_hash(ci + vec2(0.0, 1.0) + vec2(73.9, 127.3));
		float n11 = px_hash(ci + vec2(1.0, 1.0) + vec2(73.9, 127.3));
		float cn  = mix(mix(n00, n10, cf.x), mix(n01, n11, cf.x), cf.y);
		float t   = (cn - midland_mix) / 0.15;
		if (t < 1.0 && (t <= 0.0 || rnd > t)) { base = color_midland.rgb; is_midland = true; }
	}
	// Subtle dark accent only inside midland patches — never isolated on bright land.
	if (is_midland && rnd > 0.96) return base * 0.80;
	return base;
}

// Flat zone color — no sparkles, no midland variation.
// Used inside craters so the blast doesn't inherit pre-impact surface noise.
vec3 zone_color_flat(float h) {
	if (h < thresh_shallow) return color_deep_ocean.rgb;
	if (h < thresh_land)    return color_shallow_sea.rgb;
	if (h < thresh_high)    return color_land.rgb * 1.10;
	return color_highlands.rgb * 0.92;
}

vec3 zone_color(float h, vec2 px_id) {
	float rnd  = px_hash(px_id);
	float rnd2 = px_hash(px_id + vec2(17.3, 41.7));

	// Dithered transition: deep ocean ↔ shallow sea
	float t_shallow = (h - thresh_shallow) / DITHER_W;
	if (t_shallow < 1.0) {
		if (t_shallow <= 0.0 || rnd2 > t_shallow) return deep_ocean_col(rnd, px_id);
		else                                        return shallow_sea_col(rnd, px_id);
	}
	// Dithered transition: shallow sea ↔ land
	float t_land = (h - thresh_land) / DITHER_W;
	if (t_land < 1.0) {
		if (t_land <= 0.0 || rnd2 > t_land) return shallow_sea_col(rnd, px_id);
		else                                  return land_col(rnd);
	}
	// Dithered transition: land ↔ highlands
	float t_high = (h - thresh_high) / DITHER_W;
	if (t_high < 1.0) {
		if (t_high <= 0.0 || rnd2 > t_high) return land_col(rnd);
		else                                  return highlands_col(rnd, px_id);
	}
	return highlands_col(rnd, px_id);
}


void fragment() {
	vec2 uv_raw  = vec2(UV.x, 1.0 - UV.y);
	vec2 grid    = vec2(pixel_count, pixel_count * 0.5);

	// Screen-space pixel cells — uniform size regardless of sphere position.
	// dFdx/dFdy give the UV change per screen pixel, letting us reconstruct
	// the exact UV at each cell's centre. Everything (terrain, noise, dither)
	// uses that cell-centre UV, so it all rotates with the sphere.
	// Screen-space cells give uniform pixel size. uv_snap finds the UV at each
	// cell centre via screen derivatives — rotates with the sphere. px_id is
	// derived from uv_snap so noise/dither/sparkle all rotate with the surface.
	float cell     = 1080.0 / pixel_count;
	vec2  px_scr   = floor(FRAGCOORD.xy / cell);
	vec2  uv_dx    = dFdx(uv_raw);
	vec2  uv_dy    = dFdy(uv_raw);
	vec2  frag_off = (px_scr + 0.5) * cell - FRAGCOORD.xy;
	vec2  uv_snap  = clamp(uv_raw + uv_dx * frag_off.x + uv_dy * frag_off.y, vec2(0.0), vec2(1.0));
	vec2  px_id    = floor(uv_snap * grid);

	float h = texture(terrain_tex, uv_snap).r;

	// Pixel-snapped sphere position — derived from v_local_pos direction, snapped
	// to the terrain UV grid, then reconstructed. Used for craters, terminator,
	// ice override, and coast shadow. Must be computed before any of those.
	float r         = length(v_local_pos);
	vec3  n_local   = normalize(v_local_pos);
	float c_u       = atan(n_local.x, n_local.z) / (PI * 2.0) + 0.5;
	float c_v       = asin(clamp(n_local.y, -1.0, 1.0)) / PI + 0.5;
	vec2  c_px      = floor(vec2(c_u, c_v) * grid);
	vec2  c_snap    = (c_px + 0.5) / grid;
	float c_lon     = (c_snap.x - 0.5) * PI * 2.0;
	float c_lat     = (c_snap.y - 0.5) * PI;
	vec3  px_sphere = r * vec3(sin(c_lon) * cos(c_lat),
	                           sin(c_lat),
	                           cos(c_lon) * cos(c_lat));

	vec3 col = zone_color(h, px_id);

	// Terminator uses the snapped direction so the shadow edge steps pixel by pixel.
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(normalize(px_sphere), 0.0)).xyz);
	float lit = dot(world_normal, normalize(sun_dir)) > 0.0 ? 1.0 : 0.36;
	col *= lit;


	// Latitude-based ice override: land pixels above the threshold show ice colour.
	// Used for polar caps (Holocene) and massive glaciation (Pleistocene).
	if (h >= thresh_land && abs(normalize(px_sphere).y) > ice_y_abs) {
		col = color_ice.rgb * lit;
	}

	// Crater accumulation texture — painted by CPU at impact time, unlimited craters.
	float crater_mult = texture(crater_tex, uv_snap).r;
	col *= crater_mult;

	// Pixelated planet outline — uses the planet-centre-to-camera direction (a single
	// constant vector, like sun_dir). Because view_dir is constant and world_normal is
	// pixel-snapped, every fragment in the same pixel cell gets the same dot product,
	// so the threshold produces a stepped boundary aligned to the pixel grid.
	vec3  cam_world    = INV_VIEW_MATRIX[3].xyz;
	vec3  centre_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3  view_dir     = normalize(cam_world - centre_world);
	float rim          = dot(world_normal, view_dir);

	// Pixelated silhouette — evaluate rim at the screen pixel cell centre.
	// If the cell centre faces away from camera, discard the whole cell,
	// turning the smooth circular edge into a chunky pixel staircase.
	float cell_sz     = 1080.0 / pixel_count;
	vec2  px_cell     = floor(FRAGCOORD.xy / cell_sz);
	vec2  cell_centre = (px_cell + 0.5) * cell_sz;
	vec2  rim_offset  = cell_centre - FRAGCOORD.xy;
	float rim_centre  = rim + dFdx(rim) * rim_offset.x + dFdy(rim) * rim_offset.y;
	if (rim_centre < 0.0) discard;

	if (rim < 0.04) {
		col = vec3(0.04, 0.04, 0.06);
	}

	ALBEDO = clamp(col, 0.0, 1.0);
}

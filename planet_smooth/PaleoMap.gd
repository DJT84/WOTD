class_name PaleoMap
extends RefCounted

# Procedurally bakes a simplified equirectangular land/sea map for deep-time epochs from
# known paleogeography (supercontinent positions & latitudes), so the EarthSphere shader can
# render roughly-accurate ancient continents WITHOUT any copyrighted map images.
#
# Each blob = [lat_deg, lon_deg, angular_radius_deg, strength]. Longitude is arbitrary (the
# planet's prime meridian is unconstrained); LATITUDE/hemisphere placement is what's accurate.
# Sources: standard reconstructions (Scotese/PALEOMAP-style) for gross continental layout.

const BLOBS := {
	# Cambrian ~500 Ma: Gondwana a huge southern mass; small equatorial cratons (Laurentia,
	# Baltica, Siberia); mostly ocean (high sea level).
	"cambrian": [
		[-50, 0, 55, 1.0], [-66, 40, 38, 1.0], [-34, -36, 44, 0.95], [-20, 62, 28, 0.8],
		[6, 150, 20, 0.75], [-10, 108, 16, 0.7], [16, -128, 18, 0.7]
	],
	# Carboniferous ~320 Ma: Gondwana over the South Pole (Karoo glaciation) + Euramerica on
	# the equator, converging toward Pangaea.
	"carboniferous": [
		[-72, 0, 50, 1.0], [-55, 46, 40, 1.0], [-58, -46, 40, 1.0], [-34, 8, 34, 0.9],
		[8, 150, 38, 1.0], [22, 116, 30, 0.9], [0, 178, 24, 0.8]
	],
	# Permian ~270 Ma: Pangaea — a single C-shaped supercontinent straddling the equator,
	# open to the east (the Tethys Ocean), Panthalassa on the other side.
	"permian": [
		[0, -30, 48, 1.0], [36, -42, 38, 1.0], [-36, -42, 38, 1.0], [62, -22, 26, 0.9],
		[-62, -22, 26, 0.9], [16, -72, 30, 0.85], [-16, -72, 30, 0.85]
	],
	# Jurassic ~170 Ma: Pangaea rifting into Laurasia (north) and Gondwana (south); Tethys
	# between them, central Atlantic just opening.
	"jurassic": [
		[38, -30, 46, 1.0], [46, 26, 38, 1.0], [-42, -26, 46, 1.0], [-48, 34, 36, 1.0],
		[12, -56, 20, 0.7]
	],
	# Cretaceous ~90 Ma: continents dispersing, very high sea level (flooded shelves) -> lower
	# strengths / handled by a higher sea level in JSON.
	"cretaceous": [
		[34, -96, 26, 0.95], [48, 34, 40, 1.0], [-22, -56, 24, 0.9], [8, 18, 30, 0.95],
		[-32, 78, 14, 0.8], [-66, 120, 34, 0.9], [-80, -30, 26, 0.85]
	],
	# Eocene ~50 Ma: near-modern arrangement; India approaching Asia, Australia still far
	# south near Antarctica, Atlantic narrower.
	"eocene": [
		[42, -100, 30, 1.0], [-16, -60, 26, 0.95], [52, 44, 44, 1.0], [6, 18, 30, 0.95],
		[8, 74, 12, 0.8], [-34, 134, 22, 0.9], [-84, 0, 30, 1.0]
	],
}

static func has_epoch(epoch: String) -> bool:
	return BLOBS.has(epoch)

static func _dir(lat: float, lon: float) -> Vector3:
	var cl := cos(lat)
	return Vector3(cl * cos(lon), sin(lat), cl * sin(lon))

static func bake(epoch: String, w: int = 256, h: int = 128) -> ImageTexture:
	if not BLOBS.has(epoch):
		return null
	var blobs: Array = BLOBS[epoch]
	var bdirs: Array[Vector3] = []
	var brad: Array[float] = []
	for b in blobs:
		bdirs.append(_dir(deg_to_rad(b[0]), deg_to_rad(b[1])))
		brad.append(deg_to_rad(b[2]))

	var sd := int(abs(hash(epoch))) % 100000
	# broad coastline warp
	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp.frequency = 1.0
	warp.fractal_octaves = 5
	warp.seed = sd
	# finer detail -> ragged coasts + scattered islands (charm)
	var isl := FastNoiseLite.new()
	isl.noise_type = FastNoiseLite.TYPE_SIMPLEX
	isl.frequency = 2.4
	isl.fractal_octaves = 4
	isl.seed = sd + 17

	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var lat := PI * 0.5 - (float(y) + 0.5) / float(h) * PI
		for x in w:
			var lon := (float(x) + 0.5) / float(w) * TAU - PI
			var d := _dir(lat, lon)
			var base := 0.0
			for i in bdirs.size():
				var ang: float = acos(clamp(d.dot(bdirs[i]), -1.0, 1.0))
				var contrib: float = smoothstep(brad[i], brad[i] * 0.4, ang) * float(blobs[i][3])
				base = max(base, contrib)
			# two noise octaves: broad warp shapes the coast, fine octave adds islands
			var n := warp.get_noise_3dv(d * 3.0) * 0.5 + 0.5
			var n2 := isl.get_noise_3dv(d * 6.0) * 0.5 + 0.5
			var landval: float = clamp(base * 1.18 + (n - 0.5) * 0.66 + (n2 - 0.5) * 0.32 - 0.07, 0.0, 1.0)
			# encode so the shader's landScore = (r+g)/2 - b  ==  2*landval - 1
			img.set_pixel(x, y, Color(landval, landval, 1.0 - landval))

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

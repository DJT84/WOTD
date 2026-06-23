@tool
class_name Planet
extends Node3D

const ROTATION_SPEED: float = TAU / 90.0
const AXIAL_TILT:     float = deg_to_rad(23.5)
const MAX_IMPACTS:    int   = 8

const TERRAIN_CACHE_DIR: String = "user://terrain_cache/"
const CLAY_NORMAL:    String = "res://assets/Clay001_1K-PNG/Clay001_1K-PNG_NormalGL.png"
const CLAY_ROUGHNESS: String = "res://assets/Clay001_1K-PNG/Clay001_1K-PNG_Roughness.png"
const CLAY_COLOR:     String = "res://assets/Clay001_1K-PNG/Clay001_1K-PNG_Color.png"

const SEA_TYPES: Array = ["DEEP_OCEAN", "SHALLOW_SEA", "INLAND_SEA"]

const FEATURES_SEA_COMMON  := ["fish", "crab", "whale", "shark", "octopus", "coral", "jellyfish", "turtle"]
const FEATURES_LAND_COMMON := ["pterodactyl", "mammoth", "fern", "insect", "lizard", "giant_fern"]
const FEATURES_RARE        := ["megalodon", "giant_sloth"]
const FEATURES_SEA_SPECIAL := ["submarine_vents"]
const FEATURES_LAND_SPECIAL := ["volcano"]
const FEATURE_CHANCE       := 0.32
const FEATURE_RARE_CHANCE  := 0.06

const FEATURE_LABEL := {
	"fish":             "FISH",
	"crab":             "CRAB",
	"whale":            "WHALE",
	"shark":            "SHARK",
	"octopus":          "OCTO",
	"coral":            "CORAL",
	"jellyfish":        "JELLY",
	"turtle":           "TURTL",
	"pterodactyl":      "PTER",
	"mammoth":          "MAMM",
	"fern":             "FERN",
	"insect":           "INSCT",
	"lizard":           "LIZRD",
	"giant_fern":       "G.FERN",
	"megalodon":        "★ MEGA",
	"giant_sloth":      "★ SLTH",
	"submarine_vents":  "VENTS",
	"volcano":          "VOLC",
}

const FEATURE_COLOR := {
	"fish":             Color(0.40, 0.72, 1.00),
	"crab":             Color(1.00, 0.45, 0.20),
	"whale":            Color(0.40, 0.65, 1.00),
	"shark":            Color(0.55, 0.75, 0.90),
	"octopus":          Color(0.80, 0.40, 0.90),
	"coral":            Color(1.00, 0.55, 0.35),
	"jellyfish":        Color(0.85, 0.65, 1.00),
	"turtle":           Color(0.40, 0.85, 0.45),
	"pterodactyl":      Color(0.85, 0.78, 0.50),
	"mammoth":          Color(0.80, 0.70, 0.60),
	"fern":             Color(0.40, 0.88, 0.35),
	"insect":           Color(0.70, 0.85, 0.30),
	"lizard":           Color(0.50, 0.80, 0.35),
	"giant_fern":       Color(0.30, 0.95, 0.40),
	"megalodon":        Color(1.00, 0.30, 0.30),
	"giant_sloth":      Color(1.00, 0.30, 0.85),
	"submarine_vents":  Color(1.00, 0.60, 0.20),
	"volcano":          Color(1.00, 0.35, 0.10),
}

signal impact_landed(tile_id: int, intensity: float)

# ── Exports ───────────────────────────────────────────────────────────────────

@export_range(1, 4) var subdivision_depth: int = 3:
	set(v):
		subdivision_depth = v
		if is_inside_tree(): rebuild()

@export_range(0, 7) var current_age: int = 0:
	set(v):
		current_age = v
		_putty_craters.clear()
		if is_inside_tree(): rebuild()

@export var planet_radius: float = 6.5:
	set(v):
		planet_radius = v
		if is_inside_tree(): rebuild()

@export var tile_raise: float = 0.05:
	set(v):
		tile_raise = v
		if is_inside_tree(): rebuild()

@export var land_height: float = 0.12:
	set(v):
		land_height = v
		if is_inside_tree(): rebuild()

# Per-tile terrain type overrides painted in the editor.
# Keys are tile_ids (int), values are terrain type strings e.g. "FOREST_DENSE".
@export var tile_overrides: Dictionary = {}

@export var impact_intensity_min: float = 0.2
@export var impact_intensity_max: float = 0.9
@export var impact_meteor_intensity: float = 3.2

@export var rebuild_planet: bool = false:
	set(v):
		if is_inside_tree():
			rebuild()

@export var use_putty_style: bool = false:
	set(v):
		use_putty_style = v
		if is_inside_tree(): rebuild()

# ── Runtime state ─────────────────────────────────────────────────────────────

var _impacts:       Array          = []
var _tile_nodes:    Array          = []
var _tile_mesh_map: Dictionary     = {}   # tile_id → MeshInstance3D
var _shared_mat:    ShaderMaterial = null
var _mesh_root:     Node3D         = null
var _geo_tiles:     Array          = []   # cached PlanetTile array — used by editor plugin

var _putty_mat:     ShaderMaterial = null
var _putty_mi:      MeshInstance3D = null
var _putty_craters: Array          = []   # [{pos, radius, damage}] — gameplay only
var _atmos_mi:      MeshInstance3D = null
var _terrain_image:  Image = null   # blurred — drives the shader
var _terrain_binary: Image = null   # pre-blur binary — drives is_position_sea
var _crater_image:   Image         = null
var _crater_tex:     ImageTexture  = null
const CRATER_W: int = 512
const CRATER_H: int = 256

const MAX_SHADER_CRATERS := 64
var _shader_crater_normals   := PackedVector3Array()
var _shader_crater_r         := PackedFloat32Array()
var _shader_crater_intensity := PackedFloat32Array()
var _shader_crater_count     := 0

var _hovered_tile_id:    int   = -1
var _selected_tile_id:   int   = -1
var _feature_icons:      Array      = []
var _feature_icon_map:   Dictionary = {}  # tile_id → Label3D

# ── Epoch data ────────────────────────────────────────────────────────────────
#
# palette       — terrain type → Color for this epoch
# land_polygons — list of [lat,lon] polygon arrays defining land areas
# sea_polygons  — list of {type, poly} that override the land classification
#                 (Tethys, Western Interior Seaway, inland seas etc.)
#                 checked BEFORE land polygons so they cut holes in continents
# shallow_sea_depth — how many neighbour-expansion passes = shallow sea ring width
# land_rules    — ordered list of conditions; first match wins, determines tile type
#   conditions: lat_abs_below, lat_abs_above, lat_north_of, lat_south_of,
#               lon_between:[w,e], noise_above, noise_below, coast, default
# life          — life zone percentages and key creatures (used by game logic)

var _age_cfg: Array = [

# ═══════════════════════════════════════════════════════════════════════════════
# 0 — CAMBRIAN  ~541 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Globe dominated by ocean. Gondwana over the south pole. Small cratons scattered
# in the tropics. No life on land. Almost all life in shallow marine shelf seas.
{
	"name": "Cambrian", "ma": 541,
	"noise_seed": 100, "coast_roughness": 5.5, "shallow_sea_depth": 3, "land_expand_deg": 9.0,
	"blur_passes": 2, "thresh_shallow": 0.04,
	"shader_land":      Color("#9A8870"),  # light warm tan — exposed coastal rock
	"shader_highlands": Color("#7A6A55"),  # mid brown — barren interior
	"shader_midland":   Color("#5C4E3C"),  # dark brown — shadow hollows
	"midland_mix":      0.20,
	"ice_y_abs": 1.01,
	"atmosphere_color": Color(0.36, 0.61, 0.71, 0.72),
	"palette": {
		"DEEP_OCEAN":  Color("#2A3B6B"),
		"SHALLOW_SEA": Color("#5B9BB5"),
	},
	"land_polygons": [
		# Gondwana — massive south polar continent. South pole in NW Africa region.
		# Includes proto-Africa, S America, Antarctica, India, Australia all joined.
		[[-75,-10],[-70,30],[-60,60],[-45,70],[-20,65],[0,50],
		 [20,30],[15,-10],[0,-40],[-30,-60],[-55,-50],[-75,-10]],
		# Laurentia — equatorial craton (proto N America), rotated ~45° from modern
		[[30,-130],[45,-110],[40,-80],[25,-60],[5,-70],[-10,-90],[-5,-120],[15,-140],[30,-130]],
		# Baltica — subtropical southern hemisphere (15°S–40°S)
		[[-15,20],[-10,45],[-25,55],[-40,50],[-45,30],[-35,10],[-20,8],[-15,20]],
		# Siberia — isolated northern subtropical plate (10°N–40°N)
		[[10,100],[25,120],[40,135],[45,115],[40,90],[25,80],[10,90],[10,100]],
	],
	"sea_polygons": [],
	"land_rules": [
		{"type": "BARE_ROCK", "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.30, "shallow_sea": 0.60, "inland_sea": 0.10, "land": 0.00},
		"creatures": {
			"shallow_sea": ["Trilobites","Anomalocaris","Opabinia","Hallucigenia","Pikaia","Wiwaxia","Brachiopods","Sponges"],
			"deep_ocean":  ["Early sponges","Jellyfish","Microbial mats"],
			"inland_sea":  ["Trilobites (small)","Early molluscs","Stromatolites"],
			"land":        [],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 1 — CARBONIFEROUS  ~310 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Pangaea assembling. Dense coal forests at the equator. Gondwana glaciation in
# the south. Vast inland seas flood the continental interiors.
{
	"name": "Carboniferous", "ma": 310,
	"noise_seed": 200, "coast_roughness": 4.5, "shallow_sea_depth": 3, "land_expand_deg": 8.0,
	"blur_passes": 2, "thresh_shallow": 0.10,
	"shader_land":      Color("#3E7228"),  # lighter forest green — coastal fringe
	"shader_highlands": Color("#2D5E20"),  # mid coal-forest green — dominant interior
	"shader_midland":   Color("#1A3A12"),  # very dark swamp — deep interior patches
	"midland_mix":      0.20,
	"ice_y_abs": 1.01,
	"atmosphere_color": Color(0.10, 0.42, 0.35, 0.65),
	"palette": {
		"DEEP_OCEAN":   Color("#2A5A6B"),
		"SHALLOW_SEA":  Color("#2A6B5A"),
		"INLAND_SEA":   Color("#2A6B5A"),
		"BARE_ROCK":    Color("#4A3520"),
		"IRON_MUDFLAT": Color("#8B3A2A"),
		"SWAMP":        Color("#1A3A15"),
		"FOREST_DENSE": Color("#2D5E20"),
		"ICE_SHEET":    Color("#D8EEF5"),
	},
	"land_polygons": [
		# Laurussia — N America + Europe merged at equator. Coal swamps at 0°–15°N.
		# Appalachian collision closing the Rheic Ocean on the SE margin.
		[[50,-60],[55,-20],[50,20],[35,35],[20,30],[10,10],
		 [0,-10],[-5,-40],[10,-70],[25,-90],[40,-80],[50,-60]],
		# Gondwana — south polar supercontinent. South pole over Antarctica.
		# Contains Africa, S America, India, Australia, Antarctica all joined.
		[[-80,0],[-75,40],[-60,60],[-40,70],[-20,60],[10,50],
		 [20,20],[10,-20],[-10,-40],[-35,-55],[-60,-40],[-75,-20],[-80,0]],
	],
	"sea_polygons": [
		# Narrow Rheic Ocean remnant between the two supercontinents (~equatorial)
		# Irregular elongated seaway — NE-SW trending, jagged margins
		{"type": "SHALLOW_SEA", "poly": [
			[12,8],[8,-3],[10,-14],[6,-24],[2,-33],[-4,-40],[-9,-38],
			[-12,-28],[-10,-18],[-13,-8],[-7,0],[2,5],[8,6],[12,8]
		]},
	],
	"land_rules": [
		# Gondwana glaciation — southern polar ice cap
		{"type": "ICE_SHEET",    "lat_south_of": -55},
		{"type": "IRON_MUDFLAT", "noise_above": 0.82},
		{"type": "FOREST_DENSE", "coast": true, "lat_abs_below": 48},
		{"type": "SWAMP",        "lat_abs_below": 35},
		{"type": "FOREST_DENSE", "lat_abs_below": 55},
		{"type": "BARE_ROCK",    "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.20, "shallow_sea": 0.35, "inland_sea": 0.15, "land": 0.30},
		"creatures": {
			"land":        ["Meganeura","Arthropleura","Pulmonoscorpius","Hylonomus","Eryops","Amphibians","Giant cockroaches"],
			"shallow_sea": ["Sharks","Crinoids","Brachiopods","Ray-finned fish","Nautiloids"],
			"inland_sea":  ["Sharks","Crinoids","Brachiopods"],
			"deep_ocean":  ["Sharks","Cephalopods","Ray-finned fish"],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 2 — PERMIAN  ~270 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Pangaea — one supercontinent pole to pole, sitting in the eastern hemisphere.
# The western hemisphere is entirely the Panthalassa Ocean.
# The Tethys Sea is a large triangular bay biting in from the east at the equator.
# The most orange/rust globe in the game — almost no green anywhere.
{
	"name": "Permian", "ma": 270,
	"noise_seed": 300, "coast_roughness": 4.0, "shallow_sea_depth": 3, "land_expand_deg": 11.0,
	"blur_passes": 2, "thresh_shallow": 0.40,
	"shader_land":      Color("#B04A35"),  # light rust-red — coastal fringe
	"shader_highlands": Color("#8B3A2A"),  # mid rust — dominant arid interior
	"ice_y_abs": 0.97,   # tiny polar ice remnant (~3% each pole)
	"atmosphere_color": Color(0.92, 0.60, 0.18, 0.55),  # amber-orange haze
	"palette": {
		"DEEP_OCEAN":   Color("#3A6B8A"),
		"SHALLOW_SEA":  Color("#5A8FAA"),
		"INLAND_SEA":   Color("#5A8FAA"),
		"DESERT":       Color("#8B3A2A"),  # for land rules
		"SCRUB":        Color("#c47840"),
		"SAND_DUNE":    Color("#d4a060"),
		"FOREST_LIGHT": Color("#3a4a28"),
		"BARE_ROCK":    Color("#5A2A1A"),
		"ICE_SHEET":    Color("#c8d8e8"),
		"VOLCANIC":     Color("#8a2a10"),
	},
	"land_polygons": [
		# Pangaea — single C-shaped supercontinent, pole to pole.
		# Concavity faces east where the Tethys Sea indents.
		# Panthalassa (proto-Pacific) covers the rest of the globe.
		# More vertices give an organic, irregular coastline after Chaikin smoothing.
		[[-70,-60],[-67,-52],[-62,-44],[-55,-36],[-45,-28],[-34,-20],[-24,-13],[-14,-6],[-4,-1],[0,0],
		 [8,4],[18,9],[28,14],[36,18],[42,22],[50,26],[56,28],[62,30],[68,35],[70,40],[69,47],[66,58],
		 [60,56],[54,54],[50,50],[43,48],[36,47],[28,47],[20,49],[12,50],[4,48],
		 [-4,44],[-12,40],[-20,36],[-30,31],[-40,26],[-50,20],[-58,12],[-64,4],[-68,-4],[-70,-60]],
	],
	"sea_polygons": [
		# Tethys Sea — wedge-shaped embayment, widest at 20°N 90°E, tip at 15°N 20°E
		{"type": "SHALLOW_SEA", "poly": [
			[40,25],[50,50],[40,80],[20,90],[0,80],[5,50],[20,30],[35,25],[40,25]
		]},
	],
	"shader_midland": Color("#5A2010"),  # dark rust-brown — shadow patches
	"midland_mix":    0.20,
	"land_rules": [
		{"type": "ICE_SHEET",    "lat_south_of": -70},
		{"type": "VOLCANIC",     "lat_north_of": 58, "lon_between": [80, 130]},
		{"type": "FOREST_LIGHT", "coast": true, "lat_abs_below": 50},
		{"type": "FOREST_LIGHT", "lat_south_of": -50, "lat_north_of": -65},
		{"type": "BARE_ROCK",    "lat_south_of": -48},
		{"type": "SAND_DUNE",    "lat_abs_below": 20, "noise_above": 0.2},
		{"type": "DESERT",       "lat_abs_below": 45, "noise_above": -0.3},
		{"type": "SCRUB",        "lat_abs_below": 55, "noise_above": -0.4},
		{"type": "BARE_ROCK",    "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.25, "shallow_sea": 0.55, "inland_sea": 0.00, "land": 0.20},
		"creatures": {
			"land":        ["Dimetrodon","Gorgonopsid","Scutosaurus","Moschops","Dicynodon","Edaphosaurus"],
			"shallow_sea": ["Ammonites","Brachiopods","Sharks","Crinoids","Nautiloids","Rugose corals"],
			"deep_ocean":  ["Sharks","Large cephalopods","Ray-finned fish"],
			"inland_sea":  [],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 3 — JURASSIC  ~150 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Pangaea split into Laurasia (north) and Gondwana (south). No ice anywhere on
# Earth. Even the poles have temperate conifer forest. Tethys Ocean wide and warm.
{
	"name": "Jurassic", "ma": 150,
	"noise_seed": 400, "coast_roughness": 4.0, "shallow_sea_depth": 3, "land_expand_deg": 8.0,
	"blur_passes": 2, "thresh_shallow": 0.08,
	"shader_land":      Color("#52A03A"),  # bright jungle green — coastal fringe
	"shader_highlands": Color("#3A7828"),  # mid green — dominant interior
	"ice_y_abs": 1.01,
	"atmosphere_color": Color(0.18, 0.55, 0.72, 0.65),  # steel blue — slate ocean + dark jungle
	"palette": {
		"DEEP_OCEAN":   Color("#1E5A7A"),
		"SHALLOW_SEA":  Color("#4A9EBF"),
		"INLAND_SEA":   Color("#4A9EBF"),
		"FOREST_DENSE": Color("#1E5C15"),  # for land rules
		"FOREST_LIGHT": Color("#3A8C2A"),
		"SWAMP":        Color("#0e2016"),
		"BARE_ROCK":    Color("#6A5A3A"),
		"DESERT":       Color("#9a8850"),
	},
	"land_polygons": [
		# North America — narrow proto-Atlantic opening on east; Gulf of Mexico open
		[[70,-160],[75,-100],[65,-70],[50,-55],[30,-60],
		 [10,-75],[5,-85],[15,-110],[35,-120],[55,-140],[70,-160]],
		# Europe + Asia (Laurasia) — still connected, Tethys to south
		[[70,-10],[75,30],[70,80],[65,120],[55,140],[40,130],
		 [25,110],[15,90],[20,60],[35,45],[50,30],[60,10],[65,-5],[70,-10]],
		# Africa — Tethys on north coast, S Atlantic rift just opening on west
		[[-40,20],[-30,40],[-10,50],[10,45],[30,40],[35,20],
		 [20,10],[5,-5],[-10,-15],[-25,-10],[-40,20]],
		# South America — S Atlantic barely open (~200 km), close to Africa
		[[-60,-70],[-50,-65],[-30,-50],[-10,-40],[5,-45],
		 [10,-60],[0,-75],[-20,-80],[-45,-75],[-60,-70]],
		# India — still attached to Gondwana near Madagascar/Antarctica
		[[-40,55],[-30,70],[-15,75],[-5,70],[-5,55],[-20,48],[-35,50],[-40,55]],
		# Antarctica + Australia (joined Gondwana remnant)
		[[-60,60],[-55,100],[-60,130],[-70,150],[-80,120],[-85,60],[-80,30],[-70,40],[-60,60]],
		# Madagascar
		[[-12,44],[-5,50],[-20,52],[-25,48],[-12,44]],
	],
	"sea_polygons": [
		# Sundance Sea — floods western interior of North America
		{"type": "INLAND_SEA", "poly": [
			[72,-100],[55,-95],[40,-100],[32,-108],[40,-115],[55,-112],[72,-110]
		]},
		# Tethys Ocean — wide between Africa and Laurasia
		{"type": "INLAND_SEA", "poly": [
			[35,20],[20,10],[15,90],[35,45],[35,20]
		]},
	],
	"shader_midland": Color("#265A18"),  # dark canopy — deep interior patches
	"midland_mix":    0.22,
	"land_rules": [
		# Tiny bare rock clusters at immediate coastline only
		{"type": "BARE_ROCK",    "coast": true, "noise_above": 0.55},
		{"type": "SWAMP",        "coast": true, "lat_abs_below": 45},
		{"type": "FOREST_DENSE", "lat_abs_below": 65},
		{"type": "FOREST_LIGHT", "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.20, "shallow_sea": 0.35, "inland_sea": 0.15, "land": 0.30},
		"creatures": {
			"land":        ["Brachiosaurus","Stegosaurus","Allosaurus","Diplodocus","Archaeopteryx","Pterosaurs","Compsognathus"],
			"shallow_sea": ["Ichthyosaurs","Plesiosaurs","Ammonites","Belemnites","Sharks","Marine crocodilians"],
			"inland_sea":  ["Ichthyosaurs","Ammonites","Belemnites"],
			"deep_ocean":  ["Ichthyosaurs","Large fish","Ammonites"],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 4 — CRETACEOUS  ~90 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Most flooded epoch. Sea levels 200m above modern. Western Interior Seaway splits
# North America in two. Europe barely exists — a chain of tropical islands. No ice.
{
	"name": "Cretaceous", "ma": 90,
	"noise_seed": 500, "coast_roughness": 3.5, "shallow_sea_depth": 3, "land_expand_deg": 7.0,
	"blur_passes": 2, "thresh_shallow": 0.10,
	"shader_land":      Color("#5A9038"),  # bright warm green — coastal fringe
	"shader_highlands": Color("#427028"),  # mid green — dominant interior
	"shader_midland":   Color("#2E5018"),  # dark canopy — interior patches
	"midland_mix":      0.22,
	"ice_y_abs": 1.01,
	"atmosphere_color": Color(0.15, 0.72, 0.80, 0.60),  # warm teal — greenhouse hothouse
	"palette": {
		"DEEP_OCEAN":   Color("#3A7AAA"),
		"SHALLOW_SEA":  Color("#5A9EBF"),
		"INLAND_SEA":   Color("#5A9EBF"),
		"FOREST_DENSE": Color("#4A7A30"),  # for land rules
		"FOREST_LIGHT": Color("#5a9830"),
		"FERN_LAND":    Color("#5a8840"),
		"SCRUB":        Color("#88b858"),
		"VOLCANIC":     Color("#8a2a10"),
		"DESERT":       Color("#C8A85A"),
		"BARE_ROCK":    Color("#5A4A2A"),
	},
	"land_polygons": [
		# North America west block (Western Interior Seaway splits continent)
		[[70,-165],[75,-120],[65,-90],[50,-75],[35,-80],
		 [25,-90],[20,-105],[30,-125],[50,-140],[70,-165]],
		# North America east block
		[[70,-80],[65,-60],[50,-55],[35,-65],[25,-75],
		 [30,-85],[45,-85],[65,-85],[70,-80]],
		# Europe — low-lying, extensively flooded; only high ground visible
		[[55,-5],[60,15],[55,25],[45,30],[35,20],[40,5],[50,-5],[55,-5]],
		# Asia — main landmass, broad and intact
		[[70,30],[75,80],[70,130],[55,140],[35,130],
		 [20,110],[20,75],[35,55],[50,45],[65,40],[70,30]],
		# Africa
		[[-40,15],[-30,40],[-10,50],[10,48],[30,38],
		 [35,15],[20,5],[0,-10],[-20,-12],[-35,10],[-40,15]],
		# South America — S Atlantic ~1500 km wide, fully established
		[[-60,-70],[-50,-65],[-30,-48],[-10,-38],[5,-48],
		 [10,-62],[0,-78],[-20,-82],[-45,-75],[-60,-70]],
		# India — mid-Indian Ocean ~5°S, racing north at 15 cm/yr
		[[-15,68],[-5,78],[5,78],[10,72],[8,62],[-5,60],[-15,65],[-15,68]],
		# Arabia
		[[10,40],[20,55],[25,57],[30,48],[25,38],[15,36],[10,40]],
		# Australia + Antarctica (still joined)
		[[-55,80],[-50,110],[-55,140],[-65,155],[-80,130],[-85,80],[-80,50],[-65,55],[-55,80]],
		# Greenland
		[[76,-65],[84,-40],[76,-18],[60,-42],[76,-65]],
		# Madagascar
		[[-12,44],[-12,51],[-26,48],[-24,43],[-12,44]],
	],
	"sea_polygons": [
		# Western Interior Seaway — N-S corridor bisecting North America
		{"type": "INLAND_SEA", "poly": [
			[70,-90],[65,-92],[55,-90],[45,-88],[35,-82],
			[30,-87],[35,-94],[45,-98],[60,-100],[70,-96],[70,-90]
		]},
		# Turgai Strait — shallow seaway separating W and E Asia
		{"type": "INLAND_SEA", "poly": [
			[65,40],[70,30],[65,55],[55,52],[50,45],[65,40]
		]},
	],
	"land_rules": [
		{"type": "VOLCANIC",     "lat_between": [-20, 12], "lon_between": [65, 90]},
		# Jungle patches in mid-continent interior (scattered, not just coast)
		{"type": "FOREST_DENSE", "coast": false, "lat_abs_below": 42, "noise_above": 0.55},
		{"type": "DESERT",       "lat_abs_below": 18, "noise_above": 0.20},
		{"type": "FOREST_DENSE", "coast": true, "lat_abs_below": 30},
		{"type": "FOREST_DENSE", "lat_abs_below": 35, "noise_above": 0.30},
		{"type": "FOREST_LIGHT", "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.18, "shallow_sea": 0.32, "inland_sea": 0.20, "land": 0.30},
		"creatures": {
			"land":        ["T. rex","Triceratops","Velociraptor","Ankylosaurus","Spinosaurus","Pteranodon","Pachycephalosaurus"],
			"shallow_sea": ["Mosasaurs","Plesiosaurs","Xiphactinus","Ammonites","Cretoxyrhina","Archelon","Hesperornis"],
			"inland_sea":  ["Mosasaurs","Ammonites","Sea turtles"],
			"deep_ocean":  ["Mosasaurs","Large fish","Ammonites"],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 5 — EOCENE  ~45 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Near-modern layout. South America still an island. Antarctica still has forest.
# The warmest epoch since the Cretaceous — tropical forest extends to high latitudes.
# First grasslands appear but are small and patchy.
{
	"name": "Eocene", "ma": 45,
	"noise_seed": 600, "coast_roughness": 3.0, "shallow_sea_depth": 2, "land_expand_deg": 7.5,
	"blur_passes": 2, "thresh_shallow": 0.12,
	"shader_land":      Color("#6AAA42"),  # bright warm green — coastal fringe
	"shader_highlands": Color("#4A8030"),  # mid green — dominant interior
	"ice_y_abs": 1.01,
	"atmosphere_color": Color(0.18, 0.65, 0.96, 0.65),
	"palette": {
		"DEEP_OCEAN":   Color("#1E6B8A"),
		"SHALLOW_SEA":  Color("#4A9EBF"),
		"INLAND_SEA":   Color("#5BB4CF"),
		"FOREST_DENSE": Color("#306020"),
		"FOREST_LIGHT": Color("#4A8030"),
		"WETLAND":      Color("#4a8040"),
		"GRASSLAND":    Color("#6AAA42"),
	},
	"shader_midland":   Color("#306020"),  # dark canopy — interior patches
	"midland_mix":      0.22,
	"land_polygons": [
		# North America — no Panama yet, Caribbean seaway open
		[[72,-160],[78,-100],[68,-65],[50,-55],[30,-80],
		 [15,-90],[20,-110],[35,-120],[55,-140],[72,-160]],
		# Greenland — separated from Europe (Norwegian Sea open)
		[[84,-60],[80,-20],[72,-22],[68,-30],[65,-45],[68,-60],[76,-70],[84,-60]],
		# Europe — smaller than modern, North Sea flooding
		[[60,-10],[65,15],[60,30],[50,35],[38,28],[36,10],[45,-5],[55,-10],[60,-10]],
		# Asia — India just crashing in, narrow suture forming Himalayas
		[[70,30],[75,90],[68,140],[50,140],[25,120],
		 [15,100],[20,70],[35,55],[50,45],[65,38],[70,30]],
		# India — just docking with Asia; Himalayas initiating at ~28°N suture
		[[8,68],[12,78],[22,88],[28,82],[30,72],[24,62],[12,62],[8,68]],
		# Africa — Tethys closing to north, becoming Mediterranean
		[[-40,18],[-28,42],[-10,52],[12,50],[32,38],
		 [38,20],[25,8],[5,-8],[-18,-14],[-36,12],[-40,18]],
		# South America — no Panama; Central American seaway open at ~8°N
		[[-58,-68],[-50,-65],[-30,-48],[-10,-36],[5,-48],
		 [10,-62],[0,-78],[-20,-82],[-42,-73],[-58,-68]],
		# Australia — separated from Antarctica ~35 Ma, heading north; now ~50°S–25°S
		[[-38,114],[-32,127],[-28,142],[-38,152],[-48,148],[-52,130],[-48,114],[-38,114]],
		# Antarctica — separated, Drake Passage opening
		[[-68,-80],[-65,-30],[-68,20],[-72,60],[-78,100],[-80,150],[-80,-150],[-78,-110],[-68,-80]],
	],
	"sea_polygons": [
		# Remnant Neo-Tethys — narrow closing seaway north of India
		{"type": "INLAND_SEA", "poly": [[28,60],[30,80],[28,95],[22,92],[24,70],[28,60]]},
	],
	"land_rules": [
		# Layering coast → interior: sand (shader_land) → light forest → dense canopy (midland_mix)
		{"type": "FOREST_LIGHT", "coast": true, "lat_abs_below": 55},
		{"type": "FOREST_DENSE", "lat_abs_below": 48},
		{"type": "FOREST_LIGHT", "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.22, "shallow_sea": 0.38, "inland_sea": 0.10, "land": 0.30},
		"creatures": {
			"land":        ["Gastornis","Pakicetus/Ambulocetus","Eohippus","Andrewsarchus","Uintatherium","Early bats"],
			"shallow_sea": ["Basilosaurus","Modern sharks","Sea turtles","Early sirenians","Fish"],
			"inland_sea":  ["Nummulites","Early dugongs","Crocodilians"],
			"deep_ocean":  ["Early whales","Sharks","Large fish"],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 6 — PLEISTOCENE  ~1 Ma
# ═══════════════════════════════════════════════════════════════════════════════
# Modern positions. Ice-age sea levels ~120m lower expose Beringia and Sundaland.
# Massive ice sheets over N. America, Scandinavia, Greenland, Antarctica.
# The mammoth steppe stretches from Europe to Alaska.
{
	"name": "Pleistocene", "ma": 1,
	"noise_seed": 700, "coast_roughness": 2.5, "shallow_sea_depth": 2, "land_expand_deg": 7.0,
	"blur_passes": 2, "thresh_shallow": 0.45,
	"shader_land":      Color("#C8E4F0"),  # pale ice fringe
	"shader_highlands": Color("#EAF5FB"),  # bright glacial ice
	"shader_midland":   Color("#B8D9EC"),  # blue-shadow ice
	"shader_tundra":    Color("#7A5C38"),  # brown tundra belt
	"midland_mix":      0.22,
	"ice_y_abs":    0.42,
	"tundra_y_abs": 0.24,   # equatorial belt 0°–14° — narrow ring
	"atmosphere_color": Color(0.78, 0.91, 0.96, 0.50),
	"palette": {
		"DEEP_OCEAN":  Color("#3A6B8A"),
		"SHALLOW_SEA": Color("#6A9DB5"),
		"ICE_SHEET":   Color("#DFF0F7"),
		"DEEP_ICE":    Color("#B8D9EC"),
		"TUNDRA":      Color("#6B5A45"),
	},
	"land_polygons": [
		# Mirror of Holocene layout — same continents but ice dominates the visual
		[[72,-62],[55,-55],[45,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-105],[32,-117],[48,-124],[60,-140],[70,-142],[72,-62]],
		[[76,-65],[84,-35],[76,-18],[62,-42],[76,-65]],
		[[8,-77],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[8,-77]],
		[[35,-8],[58,5],[70,28],[65,90],[58,148],[42,138],[22,80],[22,55],[35,32],[35,-8]],
		[[35,-5],[22,-17],[12,-18],[-5,-8],[-35,18],[-35,28],[-10,42],[12,50],[30,45],[35,-5]],
		[[12,42],[30,38],[38,48],[30,60],[22,60],[12,52],[12,42]],
		[[22,100],[42,138],[22,122],[5,102],[22,100]],
		[[-5,98],[18,98],[22,122],[8,120],[-5,108],[-8,100],[-5,98]],
		[[22,68],[8,78],[8,92],[22,92],[35,72],[22,68]],
		[[-12,128],[-15,155],[-38,150],[-38,128],[-28,114],[-12,128]],
		# Antarctica land polygon — ice_y_abs already handles visual appearance
		[[-62,-80],[-60,22],[-62,102],[-62,162],[-80,162],[-85,50],[-85,-60],[-62,-80]],
	],
	"sea_polygons": [],
	"land_rules": [
		# Tundra only at equatorial land — everything else is overridden by ice_y_abs
		{"type": "DEEP_ICE",  "lat_abs_above": 60},
		{"type": "ICE_SHEET", "lat_abs_above": 30},
		{"type": "TUNDRA",    "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.25, "shallow_sea": 0.30, "inland_sea": 0.00, "land": 0.45},
		"creatures": {
			"land":        ["Woolly mammoth","Woolly rhinoceros","Cave lion","Smilodon","Megatherium","Megaloceros","Cave bear","Early humans"],
			"shallow_sea": ["Whales","Dolphins","Great white shark","Large fish"],
			"deep_ocean":  ["Whales","Sperm whale","Modern sharks"],
			"inland_sea":  [],
		},
	},
},

# ═══════════════════════════════════════════════════════════════════════════════
# 7 — HOLOCENE  ~10,000 years ago
# ═══════════════════════════════════════════════════════════════════════════════
# The modern world. Ice sheets retreated to Greenland and Antarctica.
# Sea levels 120m higher than Pleistocene — land bridges submerged.
{
	"name": "Holocene", "ma": 0,
	"noise_seed": 800, "coast_roughness": 2.0, "shallow_sea_depth": 2, "land_expand_deg": 6.5,
	"blur_passes": 2, "thresh_shallow": 0.18,
	"shader_land":      Color("#5AA035"),  # bright green — coastal fringe
	"shader_highlands": Color("#3A7825"),  # mid temperate green — dominant
	"shader_midland":   Color("#265518"),  # dark canopy — interior patches
	"midland_mix":      0.22,
	"ice_y_abs": 0.75,   # ~49° from equator — larger solid caps
	"atmosphere_color": Color(0.15, 0.55, 1.00, 0.72),  # vivid Earth blue
	"palette": {
		"DEEP_OCEAN":   Color("#1E5A8A"),
		"SHALLOW_SEA":  Color("#4A8FBF"),
		"INLAND_SEA":   Color("#5898e0"),
		"FOREST_DENSE": Color("#3A7A2A"),  # for land rules
		"FOREST_LIGHT": Color("#3a7828"),
		"GRASSLAND":    Color("#90b840"),
		"DESERT":       Color("#C8A85A"),
		"TUNDRA":       Color("#7a8858"),
		"ICE_SHEET":    Color("#FFFFFF"),  # polar cap ice — used by lat override
		"WETLAND":      Color("#3a6838"),
		"SCRUB":        Color("#90a848"),
		"URBAN":        Color("#8A8A8A"),  # tiny urban accent
	},
	"land_polygons": [
		# North America
		[[72,-62],[55,-55],[45,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-105],[32,-117],[48,-124],[60,-140],[70,-142],[72,-62]],
		# Greenland
		[[76,-65],[84,-35],[76,-18],[62,-42],[76,-65]],
		# South America
		[[8,-77],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[8,-77]],
		# Eurasia — single unified polygon: W Europe → N Russia → Far East → SE Asia → India → Arabia → back
		[[36,-9],[44,-8],[48,-5],[51,2],[58,5],[71,28],
		 [72,55],[73,100],[68,175],
		 [55,162],[48,142],[42,135],
		 [32,122],[22,120],[18,110],[10,105],[5,103],
		 [8,78],[22,68],
		 [22,59],[12,44],[22,38],[30,34],
		 [36,36],[42,28],[41,22],
		 [36,-9]],
		# Africa — standalone clean polygon
		[[37,-5],[37,10],[30,32],[12,50],
		 [-35,30],[-35,18],[-18,12],[-5,10],
		 [5,-5],[14,-18],[37,-5]],
		# British Isles
		[[50,-5],[58,-3],[58,0],[51,2],[50,-5]],
		# Scandinavia
		[[58,5],[71,28],[70,18],[58,5]],
		# Australia
		[[-15,128],[-15,155],[-38,150],[-38,128],[-28,114],[-15,128]],
		# New Zealand
		[[-35,172],[-35,178],[-46,168],[-46,162],[-35,172]],
		# Antarctica — extended northward so the ice cap reads from equatorial views
		[[-48,-80],[-46,0],[-48,80],[-50,160],[-65,160],[-80,100],[-85,0],[-80,-80],[-48,-80]],
		# Arctic land mass (Franz Josef, Svalbard, Arctic islands) — anchors the north cap
		[[76,-80],[83,0],[76,80],[76,-80]],
		# Japan
		[[30,130],[42,142],[45,142],[42,130],[30,130]],
		# Iceland
		[[63,-24],[66,-14],[65,-18],[63,-24]],
	],
	"sea_polygons": [
		# Mediterranean + Black Sea cut-out so they read as sea
		{"type": "INLAND_SEA", "poly": [
			[30,5],[38,5],[42,30],[42,42],[36,36],[30,34],[28,12],[30,5]
		]},
	],
	"land_rules": [
		# Greenland + Arctic ice
		{"type": "ICE_SHEET",    "lat_north_of": 64, "lon_between": [-58, -18]},
		# Tundra fringe at high latitudes
		{"type": "TUNDRA",       "lat_north_of": 62},
		# Antarctic tundra fringe
		{"type": "TUNDRA",       "lat_south_of": -55},
		# Tropical/equatorial forests — Amazon, Congo, SE Asia
		{"type": "FOREST_DENSE", "lat_abs_below": 12},
		# Desert bands — Sahara, Arabia, Australia interior, Atacama
		{"type": "DESERT",       "lat_between": [18, 35],  "noise_above": -0.1},
		{"type": "DESERT",       "lat_between": [-35, -18], "noise_above": 0.25},
		# Temperate forest — dominant cover of northern mid-latitudes
		{"type": "FOREST_LIGHT", "lat_abs_below": 62},
		# Grassland savanna
		{"type": "GRASSLAND",    "lat_abs_below": 20, "noise_above": 0.35},
		{"type": "GRASSLAND",    "default": true},
	],
	"life": {
		"zones": {"deep_ocean": 0.20, "shallow_sea": 0.30, "inland_sea": 0.00, "land": 0.50},
		"creatures": {
			"land":        ["Lion","Elephant","Tiger","Whale (beached)","Bison","Bears","Wolves","Humans"],
			"shallow_sea": ["Blue whale","Humpback","Great white shark","Dolphins","Coral reef fish","Sea turtles"],
			"deep_ocean":  ["Sperm whale","Giant squid","Anglerfish","Modern sharks"],
			"inland_sea":  [],
		},
	},
},

] # end _age_cfg


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.is_editor_hint():
		_setup_editor_lighting()
	else:
		rotation.z = -AXIAL_TILT
	rebuild()


func _prebake_all_epochs() -> void:
	_ensure_cache_dir()
	for age in _age_cfg.size():
		var key         := "age%d_s%d" % [age, subdivision_depth]
		var tex_path    := TERRAIN_CACHE_DIR + "terrain_" + key + ".png"
		var binary_path := TERRAIN_CACHE_DIR + "binary_"  + key + ".png"
		var tile_path   := TERRAIN_CACHE_DIR + "tiles_"   + key + ".json"
		var needs_tex   := not (FileAccess.file_exists(tex_path) and FileAccess.file_exists(binary_path))
		var needs_tiles := not FileAccess.file_exists(tile_path)
		if not needs_tex and not needs_tiles:
			continue

		print("Baking epoch %d cache..." % age)
		var c: Dictionary = _age_cfg[age]

		if needs_tex:
			var saved_age := current_age
			current_age = age
			_bake_layer_texture(c)   # saves tex + binary PNGs internally
			current_age = saved_age

		if needs_tiles:
			var geo := GeodesicSphere.new()
			geo.generate(subdivision_depth)

			var noise := FastNoiseLite.new()
			noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.fractal_type    = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = 2
			noise.frequency       = 0.55
			noise.seed            = c.noise_seed

			var tile_map: Dictionary = {}
			for tile in geo.tiles:
				tile_map[tile.tile_id] = tile

			var land_set: Dictionary = {}
			var expand_deg: float = c.get("land_expand_deg", 0.0)
			var inflated_land: Array = []
			for poly in c.land_polygons:
				inflated_land.append(_inflate_polygon(poly, expand_deg) if expand_deg > 0.0 else poly)

			for tile in geo.tiles:
				var ll: Vector2      = _tile_lat_lon(tile.center_position)
				var n_val: float     = noise.get_noise_3dv(tile.center_position)
				var coast_lat: float = ll.x + n_val * c.coast_roughness
				var coast_lon: float = ll.y + n_val * c.coast_roughness * 1.5
				var sea_override := ""
				for sp in c.sea_polygons:
					if _point_in_polygon(coast_lat, coast_lon, sp.poly):
						sea_override = sp.type; break
				if sea_override != "":
					tile.terrain_type = sea_override
					tile.is_land      = false
				else:
					var on_land := false
					for poly in inflated_land:
						if _point_in_polygon(coast_lat, coast_lon, poly):
							on_land = true; break
					tile.is_land      = on_land
					tile.terrain_type = "LAND_PENDING" if on_land else "DEEP_OCEAN"
					if on_land:
						land_set[tile.tile_id] = true

			var depth: int = c.get("shallow_sea_depth", 2)
			for _i in range(depth):
				var upgrades: Array = []
				for tile in geo.tiles:
					if tile.terrain_type != "DEEP_OCEAN":
						continue
					for nbr_id in tile.neighbours:
						if (tile_map[nbr_id] as PlanetTile).terrain_type != "DEEP_OCEAN":
							upgrades.append(tile.tile_id); break
				for tid in upgrades:
					tile_map[tid].terrain_type = "SHALLOW_SEA"

			for tile in geo.tiles:
				if tile.terrain_type != "LAND_PENDING":
					continue
				var is_coastal := false
				for nbr_id in tile.neighbours:
					if not land_set.has(nbr_id):
						is_coastal = true; break
				var ll: Vector2  = _tile_lat_lon(tile.center_position)
				var n_val: float = noise.get_noise_3dv(tile.center_position)
				tile.terrain_type = _apply_land_rules(ll.x, ll.y, c.land_rules, n_val, is_coastal)

			var types_out: Array = []
			for t in geo.tiles:
				types_out.append((t as PlanetTile).terrain_type)
			var fw := FileAccess.open(tile_path, FileAccess.WRITE)
			fw.store_string(JSON.stringify(types_out))
			fw.close()

	print("Epoch cache ready.")


func _setup_editor_lighting() -> void:
	var env_node := WorldEnvironment.new()
	var env      := Environment.new()
	env.background_mode        = Environment.BG_COLOR
	env.background_color       = Color(0.15, 0.15, 0.20)
	env.ambient_light_source   = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color    = Color(0.85, 0.85, 0.90)
	env.ambient_light_energy   = 1.2
	env_node.environment       = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	sun.light_energy     = 1.0
	sun.light_color      = Color(1.0, 0.97, 0.92)
	add_child(sun)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	rotate_object_local(Vector3.UP, ROTATION_SPEED * delta)
	# Atmosphere billboard stays at planet world position but never inherits planet rotation.
	if _atmos_mi:
		_atmos_mi.global_position = global_position


# ── Public API ────────────────────────────────────────────────────────────────

func rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh_root:
		_mesh_root.free()
		_mesh_root = null
	_tile_nodes.clear()
	_shared_mat = null
	var _tr := Time.get_ticks_msec()
	_build_planet()
	print("_build_planet: %d ms total" % (Time.get_ticks_msec() - _tr))
	_tr = Time.get_ticks_msec()
	_assign_features()
	print("_assign_features: %d ms" % (Time.get_ticks_msec() - _tr))
	_tr = Time.get_ticks_msec()
	_build_feature_icons()
	print("_build_feature_icons: %d ms" % (Time.get_ticks_msec() - _tr))
	_tint_assets()


func set_tile_override(tile_id: int, terrain_type: String) -> void:
	tile_overrides[tile_id] = terrain_type
	notify_property_list_changed()
	rebuild()


func clear_tile_override(tile_id: int) -> void:
	tile_overrides.erase(tile_id)
	notify_property_list_changed()
	rebuild()


func _apply_overrides_dict(dict: Dictionary) -> void:
	tile_overrides = dict.duplicate()
	notify_property_list_changed()
	rebuild()


func add_impact(world_direction: Vector3, angular_radius: float) -> void:
	_impacts.append({"dir": world_direction.normalized(), "radius": angular_radius})
	if _impacts.size() > MAX_IMPACTS:
		_impacts.pop_front()


func set_age(age: int) -> void:
	current_age = clampi(age, 0, _age_cfg.size() - 1)


func get_epoch_data() -> Dictionary:
	return _age_cfg[current_age]


# ── Feature assignment ─────────────────────────────────────────────────────────

func _assign_features() -> void:
	for t in _geo_tiles:
		var tile := t as PlanetTile
		if randf() > FEATURE_CHANCE:
			continue
		var roll := randf()
		if roll < FEATURE_RARE_CHANCE:
			tile.feature = FEATURES_RARE[randi() % FEATURES_RARE.size()]
		elif roll < FEATURE_RARE_CHANCE + 0.12:
			if tile.is_land:
				tile.feature = FEATURES_LAND_SPECIAL[randi() % FEATURES_LAND_SPECIAL.size()]
			else:
				tile.feature = FEATURES_SEA_SPECIAL[randi() % FEATURES_SEA_SPECIAL.size()]
		else:
			if tile.is_land:
				tile.feature = FEATURES_LAND_COMMON[randi() % FEATURES_LAND_COMMON.size()]
			else:
				tile.feature = FEATURES_SEA_COMMON[randi() % FEATURES_SEA_COMMON.size()]


func _build_feature_icons() -> void:
	for n in _feature_icons:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_feature_icons.clear()
	_feature_icon_map.clear()

	for t in _geo_tiles:
		var tile := t as PlanetTile
		if tile.feature == "":
			continue

		var label       := Label3D.new()
		label.text       = FEATURE_LABEL.get(tile.feature, tile.feature.left(5).to_upper())
		label.font_size  = 52
		label.pixel_size = 0.007
		label.billboard  = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		label.modulate   = FEATURE_COLOR.get(tile.feature, Color.WHITE)
		label.outline_size     = 10
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		label.visible    = false  # only shown on hover

		# Orient flat against the tile surface
		var sn:      Vector3 = tile.center_position.normalized()
		var ref:     Vector3 = Vector3.UP if abs(sn.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
		var up_tang: Vector3 = (ref - sn * sn.dot(ref)).normalized()
		var rt_tang: Vector3 = sn.cross(up_tang).normalized()
		var raise:   float   = tile_raise + (land_height if tile.is_land else 0.0)
		label.transform = Transform3D(Basis(rt_tang, up_tang, sn),
			tile.center_position * (planet_radius + raise + 0.04))

		_mesh_root.add_child(label)
		_feature_icons.append(label)
		_feature_icon_map[tile.tile_id] = label


# ── Hover / Select ─────────────────────────────────────────────────────────────

func _get_or_create_tile_mat(tile_id: int) -> ShaderMaterial:
	if not _tile_mesh_map.has(tile_id):
		return null
	var mi := _tile_mesh_map[tile_id] as MeshInstance3D
	if mi.material_override == null or mi.material_override == _shared_mat:
		mi.material_override = _shared_mat.duplicate() as ShaderMaterial
	return mi.material_override as ShaderMaterial

func set_tile_hover(tile_id: int) -> void:
	if _hovered_tile_id == tile_id:
		return
	# Hide the old tile's icon
	if _hovered_tile_id != -1 and _feature_icon_map.has(_hovered_tile_id):
		(_feature_icon_map[_hovered_tile_id] as Label3D).visible = false
	_hovered_tile_id = tile_id
	if use_putty_style:
		if tile_id != -1 and _feature_icon_map.has(tile_id):
			(_feature_icon_map[tile_id] as Label3D).visible = true
		return
	_refresh_highlights()
	# Show the new tile's icon
	if tile_id != -1 and _feature_icon_map.has(tile_id):
		(_feature_icon_map[tile_id] as Label3D).visible = true


func set_tile_selected(tile_id: int) -> void:
	_selected_tile_id = -1 if tile_id == _selected_tile_id else tile_id
	if use_putty_style:
		return
	_refresh_highlights()


func _refresh_highlights() -> void:
	# Clear every tile's highlight in one pass — bulletproof against leftover state
	for id in _tile_mesh_map:
		var mi := _tile_mesh_map[id] as MeshInstance3D
		if mi.material_override != null and mi.material_override != _shared_mat:
			(mi.material_override as ShaderMaterial).set_shader_parameter("edge_highlight", 0.0)

	# Selected — gold ring
	if _selected_tile_id != -1:
		var mat := _get_or_create_tile_mat(_selected_tile_id)
		if mat:
			mat.set_shader_parameter("edge_highlight_color", Color(1.0, 0.82, 0.1, 1.0))
			mat.set_shader_parameter("edge_highlight", 1.0)

	# Hover — blue-white ring (only if different tile from selected)
	if _hovered_tile_id != -1 and _hovered_tile_id != _selected_tile_id:
		var mat := _get_or_create_tile_mat(_hovered_tile_id)
		if mat:
			mat.set_shader_parameter("edge_highlight_color", Color(0.75, 0.88, 1.0, 1.0))
			mat.set_shader_parameter("edge_highlight", 0.5)

func get_selected_tile() -> PlanetTile:
	if _selected_tile_id == -1:
		return null
	for t in _geo_tiles:
		if (t as PlanetTile).tile_id == _selected_tile_id:
			return t as PlanetTile
	return null

func get_tile_at_screen_pos(screen_pos: Vector2, cam: Camera3D) -> PlanetTile:
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir:    Vector3 = cam.project_ray_normal(screen_pos)
	# Ray-sphere intersection
	var oc:    Vector3 = origin - global_position
	var b:     float   = oc.dot(dir)
	var r:     float   = planet_radius + tile_raise
	var disc:  float   = b * b - (oc.dot(oc) - r * r)
	if disc < 0.0:
		return null
	var hit_t: float  = -b - sqrt(disc)
	if hit_t < 0.0:
		return null
	var hit_world: Vector3 = origin + dir * hit_t
	var hit_local: Vector3 = global_transform.affine_inverse() * hit_world
	var hit_norm:  Vector3 = hit_local.normalized()
	var best_dot:  float   = -1.0
	var best_tile: PlanetTile = null
	for t in _geo_tiles:
		var pt := t as PlanetTile
		var d: float = pt.center_position.normalized().dot(hit_norm)
		if d > best_dot:
			best_dot = d
			best_tile = pt
	return best_tile


# ── Impact ─────────────────────────────────────────────────────────────────────

func trigger_impact(tile_id: int, intensity: float = 1.0) -> void:
	var tile: PlanetTile = null
	for t in _geo_tiles:
		if (t as PlanetTile).tile_id == tile_id:
			tile = t
			break
	if tile == null:
		return
	var palette: Dictionary = _age_cfg[current_age].get("palette", {})
	var tile_col: Color     = palette.get(tile.terrain_type, Color(0.5, 0.5, 0.5))
	var effect := preload("res://scripts/ImpactEffect.gd").new()
	add_child(effect)
	effect.setup(self, tile, intensity, tile_col)


func trigger_impact_with_rock(tile_id: int, intensity: float,
		rock: Node3D, done_cb: Callable) -> void:
	var tile: PlanetTile = null
	for t in _geo_tiles:
		if (t as PlanetTile).tile_id == tile_id:
			tile = t
			break
	if tile == null:
		return
	var palette: Dictionary = _age_cfg[current_age].get("palette", {})
	var tile_col: Color     = palette.get(tile.terrain_type, Color(0.5, 0.5, 0.5))
	var effect := preload("res://scripts/ImpactEffect.gd").new()
	add_child(effect)
	effect.setup_with_rock(self, tile, intensity, tile_col, rock, done_cb)


func apply_impact(tile_id: int, impact_pos: Vector3 = Vector3.ZERO, intensity: float = 1.0, irregular_core: bool = false) -> void:
	# If no explicit impact pos supplied, default to the target tile's centre
	if impact_pos == Vector3.ZERO:
		for t in _geo_tiles:
			var pt := t as PlanetTile
			if pt.tile_id == tile_id:
				var raise: float = tile_raise + (land_height if pt.is_land else 0.0)
				impact_pos = pt.center_position * (planet_radius + raise)
				break

	# Crater world-space radius scales with asteroid size
	var crater_r: float = 0.40 + intensity * 0.25

	if use_putty_style:
		var crater_pos := impact_pos.normalized() * planet_radius
		_putty_craters.append({"pos": crater_pos, "radius": crater_r, "damage": clamp(intensity, 0.3, 1.0)})
		_paint_crater(impact_pos.normalized(), intensity, irregular_core)
		impact_landed.emit(tile_id, intensity)
		return

	# Apply crater shader to every tile close enough to the impact point
	for t in _geo_tiles:
		var pt    := t as PlanetTile
		var raise:  float   = tile_raise + (land_height if pt.is_land else 0.0)
		var t_pos:  Vector3 = pt.center_position * (planet_radius + raise)
		var dist:   float   = impact_pos.distance_to(t_pos)
		if dist > crater_r + 0.6:
			continue
		if not _tile_mesh_map.has(pt.tile_id):
			continue
		var dmg: float = clamp(1.0 - (dist / (crater_r + 0.6)), 0.15, 1.0)
		var mi  := _tile_mesh_map[pt.tile_id] as MeshInstance3D
		var mat := _shared_mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("damage_state",   dmg)
		mat.set_shader_parameter("tile_center",    impact_pos)
		mat.set_shader_parameter("crater_radius",  crater_r)
		mi.material_override = mat

	impact_landed.emit(tile_id, intensity)


# ── Classification ─────────────────────────────────────────────────────────────

# Chaikin corner-cutting: 2 iterations turns a 10-pt sharp polygon into a
# 40-pt smooth curve, rounding every corner organically.
func _chaikin(poly: Array, iterations: int) -> Array:
	var result: Array = poly.duplicate()
	for _iter in range(iterations):
		var next: Array = []
		var n: int = result.size()
		for i in range(n):
			var a = result[i]
			var b = result[(i + 1) % n]
			next.append([a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25])
			next.append([a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75])
		result = next
	return result


func _inflate_polygon(polygon: Array, deg: float) -> Array:
	# Compute planar centroid
	var clat: float = 0.0
	var clon_sin: float = 0.0
	var clon_cos: float = 0.0
	for pt in polygon:
		clat     += pt[0]
		clon_sin += sin(deg_to_rad(pt[1]))
		clon_cos += cos(deg_to_rad(pt[1]))
	clat /= polygon.size()
	var clon: float = rad_to_deg(atan2(clon_sin, clon_cos))

	var result: Array = []
	for pt in polygon:
		var dlat: float = pt[0] - clat
		var dlon: float = fposmod(pt[1] - clon + 180.0, 360.0) - 180.0
		var dist: float = sqrt(dlat * dlat + dlon * dlon)
		if dist < 0.001:
			result.append(pt)
			continue
		var scale: float = (dist + deg) / dist
		result.append([clat + dlat * scale, clon + dlon * scale])
	return result


func _point_in_polygon(lat: float, lon: float, polygon: Array) -> bool:
	var sin_sum := 0.0
	var cos_sum := 0.0
	for pt in polygon:
		var r: float = deg_to_rad(pt[1])
		sin_sum += sin(r)
		cos_sum += cos(r)
	var centre_lon: float = rad_to_deg(atan2(sin_sum, cos_sum))

	var test_lon: float = fposmod(lon - centre_lon + 180.0, 360.0) - 180.0
	var inside := false
	var n: int = polygon.size()
	var j: int = n - 1
	for i in range(n):
		var yi: float = polygon[i][0]
		var xi: float = fposmod(polygon[i][1] - centre_lon + 180.0, 360.0) - 180.0
		var yj: float = polygon[j][0]
		var xj: float = fposmod(polygon[j][1] - centre_lon + 180.0, 360.0) - 180.0
		if ((yi > lat) != (yj > lat)) and \
				(test_lon < (xj - xi) * (lat - yi) / (yj - yi) + xi):
			inside = not inside
		j = i
	return inside


func _tile_lat_lon(tile_pos: Vector3) -> Vector2:
	var lat := rad_to_deg(asin(clamp(tile_pos.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(tile_pos.x, tile_pos.z))
	return Vector2(lat, lon)


func _apply_land_rules(
		lat: float, lon: float,
		rules: Array,
		noise_val: float,
		is_coastal: bool) -> String:

	var abs_lat: float = abs(lat)
	for rule in rules:
		if rule.has("default") and rule.default:
			return rule.type

		var ok := true
		if rule.has("lat_abs_below")  and abs_lat  >= rule.lat_abs_below:  ok = false
		if rule.has("lat_abs_above")  and abs_lat  <= rule.lat_abs_above:  ok = false
		if rule.has("lat_north_of")   and lat      <= rule.lat_north_of:   ok = false
		if rule.has("lat_south_of")   and lat      >= rule.lat_south_of:   ok = false
		if rule.has("lat_between"):
			var lb: Array = rule.lat_between
			if lat < lb[0] or lat > lb[1]:
				ok = false
		if rule.has("lon_between"):
			var lb: Array = rule.lon_between
			var norm_lon: float = fposmod(lon - lb[0] + 180.0, 360.0) - 180.0
			var span: float     = fposmod(lb[1] - lb[0] + 180.0, 360.0) - 180.0
			if norm_lon < 0.0 or norm_lon > span:
				ok = false
		if rule.has("noise_above") and noise_val <= rule.noise_above: ok = false
		if rule.has("noise_below") and noise_val >= rule.noise_below: ok = false
		if rule.has("coast") and rule.coast and not is_coastal:       ok = false

		if ok:
			return rule.type

	return "BARE_ROCK"


# ── Build ─────────────────────────────────────────────────────────────────────

func _tint_assets() -> void:
	var palette: Dictionary = _age_cfg[current_age].get("palette", {})

	for child in get_children():
		if child == _mesh_root:
			continue
		if not child is Node3D:
			continue

		# Find which tile this asset sits on
		var tile: PlanetTile = null
		if child.has_meta("planet_tile_id"):
			var tid: int = child.get_meta("planet_tile_id")
			for t in _geo_tiles:
				if (t as PlanetTile).tile_id == tid:
					tile = t
					break
		else:
			# No meta — find nearest tile by position
			var dir: Vector3 = (child as Node3D).position.normalized()
			var best_dot: float = -1.0
			for t in _geo_tiles:
				var d: float = (t as PlanetTile).center_position.dot(dir)
				if d > best_dot:
					best_dot = d
					tile = t

		if tile == null:
			continue

		var asset_shader := load("res://shaders/asset.gdshader") as Shader
		for mi in _get_mesh_instances(child):
			var surf_mat = (mi as MeshInstance3D).mesh.surface_get_material(0) if (mi as MeshInstance3D).mesh else null
			var is_synty: bool = surf_mat is StandardMaterial3D and (surf_mat as StandardMaterial3D).vertex_color_use_as_albedo
			if is_synty:
				var mat := ShaderMaterial.new()
				mat.shader = asset_shader
				mat.set_shader_parameter("albedo_color", Color(0.62, 0.58, 0.52))
				(mi as MeshInstance3D).material_override = mat
			else:
				# Keep original material but boost emission to lift dark shadows
				var orig: Material = surf_mat
				if orig is StandardMaterial3D:
					var copy := (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
					copy.emission_enabled = true
					copy.emission = copy.albedo_color
					copy.emission_energy_multiplier = 0.3
					(mi as MeshInstance3D).material_override = copy
				else:
					(mi as MeshInstance3D).material_override = null


func _get_mesh_instances(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_get_mesh_instances(child))
	return result


func _cache_key() -> String:
	return "age%d_s%d" % [current_age, subdivision_depth]

func _ensure_cache_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TERRAIN_CACHE_DIR))

func _build_planet() -> void:
	_mesh_root      = Node3D.new()
	_mesh_root.name = "_MeshRoot"
	add_child(_mesh_root)

	var _t0 := Time.get_ticks_msec()
	var geo := GeodesicSphere.new()
	geo.generate(subdivision_depth)
	_geo_tiles = geo.tiles
	print("GeodesicSphere.generate: %d ms" % (Time.get_ticks_msec() - _t0))

	_shared_mat        = ShaderMaterial.new()
	_shared_mat.shader = load("res://shaders/tile.gdshader") as Shader

	var c: Dictionary = _age_cfg[current_age]

	var noise := FastNoiseLite.new()
	noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type    = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.frequency       = 0.55
	noise.seed            = c.noise_seed

	var tile_map: Dictionary = {}
	for tile in geo.tiles:
		tile_map[tile.tile_id] = tile

	# ── Passes 1-3: tile terrain classification (cached to disk) ──────────
	var tile_cache_path: String = TERRAIN_CACHE_DIR + "tiles_" + _cache_key() + ".json"
	var _t1 := Time.get_ticks_msec()
	var land_set: Dictionary = {}
	var loaded_from_cache := false

	if FileAccess.file_exists(tile_cache_path):
		var f := FileAccess.open(tile_cache_path, FileAccess.READ)
		var types: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if types is Array and (types as Array).size() == geo.tiles.size():
			for i in geo.tiles.size():
				var tile := geo.tiles[i] as PlanetTile
				tile.terrain_type = (types as Array)[i]
				tile.is_land      = tile.terrain_type not in SEA_TYPES
				if tile.is_land:
					land_set[tile.tile_id] = true
			loaded_from_cache = true

	if not loaded_from_cache:
		# ── Pass 1: binary land / sea using polygons ─────────────────────────
		var expand_deg: float = c.get("land_expand_deg", 0.0)
		var inflated_land: Array = []
		for poly in c.land_polygons:
			inflated_land.append(_inflate_polygon(poly, expand_deg) if expand_deg > 0.0 else poly)

		for tile in geo.tiles:
			var ll: Vector2 = _tile_lat_lon(tile.center_position)
			var lat: float  = ll.x
			var lon: float  = ll.y
			var n_val: float = noise.get_noise_3dv(tile.center_position)
			var coast_lat: float = lat + n_val * c.coast_roughness
			var coast_lon: float = lon + n_val * c.coast_roughness * 1.5

			# Sea override polygons take priority (Tethys, seaways, etc.)
			var sea_override: String = ""
			for sp in c.sea_polygons:
				if _point_in_polygon(coast_lat, coast_lon, sp.poly):
					sea_override = sp.type
					break

			if sea_override != "":
				tile.terrain_type = sea_override
				tile.is_land      = false
			else:
				var on_land := false
				for poly in inflated_land:
					if _point_in_polygon(coast_lat, coast_lon, poly):
						on_land = true
						break
				tile.is_land      = on_land
				tile.terrain_type = "LAND_PENDING" if on_land else "DEEP_OCEAN"
				if on_land:
					land_set[tile.tile_id] = true

		# ── Pass 2: shallow sea expansion ─────────────────────────────────────
		var depth: int = c.get("shallow_sea_depth", 2)
		for _i in range(depth):
			var upgrades: Array = []
			for tile in geo.tiles:
				if tile.terrain_type != "DEEP_OCEAN":
					continue
				for nbr_id in tile.neighbours:
					var nbr: PlanetTile = tile_map[nbr_id]
					if nbr.terrain_type != "DEEP_OCEAN":
						upgrades.append(tile.tile_id)
						break
			for tid in upgrades:
				tile_map[tid].terrain_type = "SHALLOW_SEA"

		# ── Pass 3: classify land tile types ──────────────────────────────────
		for tile in geo.tiles:
			if tile.terrain_type != "LAND_PENDING":
				continue
			var is_coastal := false
			for nbr_id in tile.neighbours:
				if not land_set.has(nbr_id):
					is_coastal = true
					break

			var ll: Vector2  = _tile_lat_lon(tile.center_position)
			var n_val: float = noise.get_noise_3dv(tile.center_position)
			tile.terrain_type = _apply_land_rules(
				ll.x, ll.y, c.land_rules, n_val, is_coastal)

		# Cache tile terrain types to disk so next load skips polygon tests.
		_ensure_cache_dir()
		var types_out: Array = []
		for t in geo.tiles:
			types_out.append((t as PlanetTile).terrain_type)
		var fw := FileAccess.open(tile_cache_path, FileAccess.WRITE)
		fw.store_string(JSON.stringify(types_out))
		fw.close()

	print("Tile classification (%s): %d ms" % ["cached" if loaded_from_cache else "computed", Time.get_ticks_msec() - _t1])

	# ── Apply manual tile overrides on top ────────────────────────────────
	for tile_id in tile_overrides:
		if tile_map.has(tile_id):
			var ov = tile_overrides[tile_id]
			if ov is String:
				tile_map[tile_id].terrain_type = ov
				tile_map[tile_id].is_land = ov not in SEA_TYPES
			# legacy bool override — silently ignore (user clears via editor)

	# ── Re-sync is_land from final terrain_type ───────────────────────────
	for tile in geo.tiles:
		tile.is_land = tile.terrain_type not in SEA_TYPES

	# ── Build meshes ──────────────────────────────────────────────────────
	var palette: Dictionary = c.palette
	if use_putty_style:
		if Engine.is_editor_hint():
			return   # skip heavy build in editor — enable putty at runtime only
		_build_putty_meshes(geo, palette)
		return

	_tile_mesh_map.clear()
	for tile in geo.tiles:
		var mi := MeshInstance3D.new()
		mi.mesh              = _build_tile_mesh(tile, palette)
		mi.material_override = _shared_mat
		mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_root.add_child(mi)
		_tile_nodes.append(mi)
		_tile_mesh_map[(tile as PlanetTile).tile_id] = mi

	var wall_mesh: ArrayMesh = _build_wall_mesh(geo.tiles, tile_map, palette)
	if wall_mesh.get_surface_count() > 0:
		var wall_mi := MeshInstance3D.new()
		wall_mi.mesh              = wall_mesh
		wall_mi.material_override = _shared_mat
		wall_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_root.add_child(wall_mi)


func _palette_pick(palette: Dictionary, keys: Array, fallback: Color) -> Color:
	for k in keys:
		if palette.has(k):
			return palette[k]
	return fallback


func _build_atmosphere(c: Dictionary) -> void:
	if _atmos_mi:
		_atmos_mi.queue_free()
		_atmos_mi = null

	var atmos_col: Color = c.get("atmosphere_color", Color(0.25, 0.65, 1.0, 0.7))

	var quad := QuadMesh.new()
	# Quad is 3.2× the planet diameter so the halo extends ~60% beyond the planet edge.
	var sz: float = planet_radius * 3.2
	quad.size = Vector2(sz, sz)

	_atmos_mi = MeshInstance3D.new()
	_atmos_mi.mesh        = quad
	_atmos_mi.top_level   = true   # world-space positioning; ignores planet rotation
	_atmos_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/atmosphere.gdshader") as Shader
	mat.set_shader_parameter("atmos_color", atmos_col)
	# planet fills quad half-size ratio: planet_r / (quad_sz/2)
	mat.set_shader_parameter("planet_edge", 1.0 / 1.6)
	_atmos_mi.set_surface_override_material(0, mat)

	add_child(_atmos_mi)
	_atmos_mi.global_position = global_position


func _build_putty_meshes(_geo: GeodesicSphere, palette: Dictionary) -> void:
	_putty_mat = null
	_putty_mi  = null

	var c: Dictionary = _age_cfg[current_age]

	# Bake a small single-channel height texture — fast polygon tests at low res.
	# The GPU bilinear filter turns low-res zone transitions into smooth organic curves.
	var _t2 := Time.get_ticks_msec()
	var terrain_tex: ImageTexture = _bake_layer_texture(c)
	print("_bake_layer_texture: %d ms" % (Time.get_ticks_msec() - _t2))

	# Godot generates the sphere mesh instantly — no custom icosphere needed.
	var sphere := SphereMesh.new()
	sphere.radius          = planet_radius
	sphere.height          = planet_radius * 2.0
	sphere.radial_segments = 128
	sphere.rings           = 64

	_putty_mat        = ShaderMaterial.new()
	_putty_mat.shader = load("res://shaders/pixel.gdshader") as Shader
	_putty_mat.set_shader_parameter("terrain_tex",       terrain_tex)
	_putty_mat.set_shader_parameter("color_deep_ocean",  palette.get("DEEP_OCEAN",  Color(0.05, 0.18, 0.42)))
	_putty_mat.set_shader_parameter("color_shallow_sea", palette.get("SHALLOW_SEA", Color(0.14, 0.42, 0.68)))
	_putty_mat.set_shader_parameter("thresh_shallow", c.get("thresh_shallow", 0.20))
	_putty_mat.set_shader_parameter("color_midland",  c.get("shader_midland",  c.get("shader_highlands", Color(0.12, 0.36, 0.08))))
	_putty_mat.set_shader_parameter("midland_mix",    c.get("midland_mix", 0.0))
	# Coastal fringe (h 0.65-0.88) and interior dominant (h > 0.88).
	# Epochs set shader_land/shader_highlands directly for precise palette control.
	_putty_mat.set_shader_parameter("color_land", c.get("shader_land",
		_palette_pick(palette,
			["WETLAND","SWAMP","FERN_LAND","FOREST_LIGHT","ICE_SHEET","TUNDRA","GRASSLAND","COASTAL_ROCK","BARE_ROCK"],
			Color(0.40, 0.58, 0.20))))
	_putty_mat.set_shader_parameter("color_highlands", c.get("shader_highlands",
		_palette_pick(palette,
			["DEEP_ICE","ICE_SHEET","FOREST_DENSE","DESERT","SAND_DUNE","SCRUB","BARE_ROCK"],
			Color(0.52, 0.44, 0.28))))
	_putty_mat.set_shader_parameter("color_ice",       palette.get("ICE_SHEET", Color(0.90, 0.95, 1.00)))
	_putty_mat.set_shader_parameter("ice_y_abs",       c.get("ice_y_abs", 1.01))
	_putty_mat.set_shader_parameter("color_tundra",    c.get("shader_tundra", Color(0.54, 0.42, 0.28)))
	_putty_mat.set_shader_parameter("tundra_y_abs",    c.get("tundra_y_abs", 0.0))
	if FileAccess.file_exists(CLAY_NORMAL):
		_putty_mat.set_shader_parameter("clay_normal_tex",    load(CLAY_NORMAL))
	if FileAccess.file_exists(CLAY_ROUGHNESS):
		_putty_mat.set_shader_parameter("clay_roughness_tex", load(CLAY_ROUGHNESS))
	_init_crater_texture()

	_putty_mi                   = MeshInstance3D.new()
	_putty_mi.mesh              = sphere
	_putty_mi.material_override = _putty_mat
	_putty_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_root.add_child(_putty_mi)

	_build_atmosphere(c)

	_sync_tile_land_flags()


# Bakes a 256x128 single-channel (R8) height texture.
# R = 0.0 (deep ocean) → blurred gradient → 1.0 (land interior).
# Shader dithering at zone boundaries creates gradual pixelated edges.
func _bake_layer_texture(c: Dictionary) -> ImageTexture:
	const W: int = 256
	const H: int = 128

	# Check cache — skips 32,768 point-in-polygon tests on subsequent loads.
	var key         := _cache_key()
	var tex_path    := TERRAIN_CACHE_DIR + "terrain_" + key + ".png"
	var binary_path := TERRAIN_CACHE_DIR + "binary_"  + key + ".png"
	if FileAccess.file_exists(tex_path) and FileAccess.file_exists(binary_path):
		var cached_img    := Image.load_from_file(tex_path)
		var cached_binary := Image.load_from_file(binary_path)
		if cached_img and cached_binary:
			_terrain_image  = cached_img
			_terrain_binary = cached_binary
			return ImageTexture.create_from_image(cached_img)

	var data := PackedByteArray(); data.resize(W * H)

	var expand_deg: float = c.get("land_expand_deg", 0.0)
	var inflated_land: Array = []
	for poly in c.land_polygons:
		var base: Array = _inflate_polygon(poly, expand_deg) if expand_deg > 0.0 else poly
		inflated_land.append(_chaikin(base, 3))

	# Binary pass: land = 255, ocean = 0. No shallow-sea neighbour checks needed —
	# the box blur below spreads the boundary into a smooth gradient that the shader
	# thresholds into deep / shallow / land zones automatically.
	for y in range(H):
		for x in range(W):
			var u: float      = (float(x) + 0.5) / float(W)
			var v: float      = (float(y) + 0.5) / float(H)
			var lon_r: float  = (u - 0.5) * TAU
			var sin_lat: float = sin((v - 0.5) * PI)
			var cos_lat: float = sqrt(maxf(0.0, 1.0 - sin_lat * sin_lat))
			var pos3d: Vector3 = Vector3(sin(lon_r) * cos_lat, sin_lat, cos(lon_r) * cos_lat)
			var ll: Vector2    = _tile_lat_lon(pos3d)

			var is_sea_ov := false
			for sp in c.sea_polygons:
				if _point_in_polygon(ll.x, ll.y, sp.poly):
					is_sea_ov = true; break

			var is_land := false
			if not is_sea_ov:
				for poly in inflated_land:
					if _point_in_polygon(ll.x, ll.y, poly):
						is_land = true; break

			data[y * W + x] = 255 if is_land else 0

	# Snapshot the binary classification before blurring — used for land/sea
	# queries so they match the hard land polygon boundary, not the blurred edge.
	_terrain_binary = Image.create_from_data(W, H, false, Image.FORMAT_R8, data.duplicate())

	# Box blur — number of passes controls shallow-sea ring width.
	# More passes = wider gradient = wider shallow strip visible in shader.
	for _b in range(c.get("blur_passes", 1)):
		var blurred := data.duplicate()
		for y in range(H):
			for x in range(W):
				var sum := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						sum += data[clampi(y + dy, 0, H - 1) * W + ((x + dx + W) % W)]
				blurred[y * W + x] = sum / 9
		data = blurred

	var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, data)
	_terrain_image = img

	# Save to cache so future loads skip the polygon tests.
	_ensure_cache_dir()
	img.save_png(tex_path)
	_terrain_binary.save_png(binary_path)

	return ImageTexture.create_from_image(img)


func _init_crater_texture() -> void:
	_crater_image = Image.create(CRATER_W, CRATER_H, false, Image.FORMAT_R8)
	_crater_image.fill(Color(1.0, 1.0, 1.0))
	_crater_tex = ImageTexture.create_from_image(_crater_image)
	_shader_crater_normals.resize(MAX_SHADER_CRATERS)
	_shader_crater_r.resize(MAX_SHADER_CRATERS)
	_shader_crater_intensity.resize(MAX_SHADER_CRATERS)
	for i in range(MAX_SHADER_CRATERS):
		_shader_crater_normals[i]   = Vector3.ZERO
		_shader_crater_r[i]         = 0.0
		_shader_crater_intensity[i] = 0.0
	_shader_crater_count = 0
	if _putty_mat:
		_putty_mat.set_shader_parameter("crater_tex", _crater_tex)
		_putty_mat.set_shader_parameter("crater_count", 0)
		_putty_mat.set_shader_parameter("crater_normals", _shader_crater_normals)
		_putty_mat.set_shader_parameter("crater_r", _shader_crater_r)
		_putty_mat.set_shader_parameter("crater_intensity", _shader_crater_intensity)


func _crater_pos_to_uv(n: Vector3) -> Vector2:
	var lon := atan2(-n.x, -n.z)  # negate both to flip 180° — sphere mesh seam offset
	var lat := asin(clamp(n.y, -1.0, 1.0))
	return Vector2(lon / (PI * 2.0) + 0.5, lat / PI + 0.5)


func _crater_uv_to_normal(u: float, v: float) -> Vector3:
	var lon := (u - 0.5) * PI * 2.0
	var lat := (v - 0.5) * PI
	return Vector3(-sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat))


func _paint_crater(n_impact: Vector3, intensity: float, irregular_core: bool = false) -> void:
	if _crater_image == null or _crater_tex == null:
		push_error("_paint_crater: crater image/tex is null")
		return

	var crater_r  := 0.40 + intensity * 0.25
	var angular_r := asin(clamp(crater_r / planet_radius, 0.0, 1.0))
	var uv_margin := angular_r / PI
	var impact_uv := _crater_pos_to_uv(n_impact)

	# Per-crater seed from impact position — same formula as shader, varies shape uniquely.
	var seed  := fmod(absf(n_impact.x * 127.3 + n_impact.y * 311.7 + n_impact.z * 74.1),  1.0)
	var seed2 := fmod(absf(n_impact.x * 269.5 + n_impact.y * 183.3 + n_impact.z * 421.7), 1.0)
	var seed3 := fmod(absf(n_impact.x * 419.2 + n_impact.y * 371.9 + n_impact.z * 154.3), 1.0)

	# Paint, wrapping at the longitude seam if needed.
	for pass_n in range(2):
		var u_offset := 0.0 if pass_n == 0 else (1.0 if impact_uv.x < 0.5 else -1.0)
		if pass_n == 1 and abs(impact_uv.x - 0.5) < 0.5 - uv_margin * 2.0:
			break
		var x_min: int = max(0, int((impact_uv.x + u_offset - uv_margin * 2.0) * CRATER_W))
		var x_max: int = min(CRATER_W - 1, int((impact_uv.x + u_offset + uv_margin * 2.0) * CRATER_W))
		var y_min: int = max(0, int((impact_uv.y - uv_margin * 2.0) * CRATER_H))
		var y_max: int = min(CRATER_H - 1, int((impact_uv.y + uv_margin * 2.0) * CRATER_H))
		for py in range(y_min, y_max + 1):
			for px in range(x_min, x_max + 1):
				var u    := (float(px) + 0.5) / CRATER_W
				var v    := (float(py) + 0.5) / CRATER_H
				var n_px := _crater_uv_to_normal(u, v)
				var cos_d: float = clamp(n_impact.dot(n_px), -1.0, 1.0)
				var angular_d := acos(cos_d)
				# Build local frame for angle — same as shader
				var tang_v := n_px - n_impact * cos_d
				var bx_l   := (Vector3.UP if abs(n_impact.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
				bx_l = n_impact.cross(bx_l).normalized()
				var bz_l   := bx_l.cross(n_impact).normalized()
				var ang    := atan2(tang_v.dot(bz_l), tang_v.dot(bx_l))
				var wobbled_r := angular_r * (1.0 + sin(ang * 11.0 + seed  * TAU)  * 0.025
											+ sin(ang * 17.0 + seed2 * 9.42) * 0.018
											+ sin(ang * 23.0 + seed3 * 4.15) * 0.012)
				if angular_d >= wobbled_r:
					continue
				var t := angular_d / wobbled_r

				var fade_m  := smoothstep(0.80, 1.0, t)

				var existing := _crater_image.get_pixel(px, py).r
				var c: float = existing * lerpf(0.14, 1.0, pow(t, 0.6))
				c = lerp(c, existing, fade_m)
				_crater_image.set_pixel(px, py, Color(c, c, c))

	_crater_tex = ImageTexture.create_from_image(_crater_image)

	# Register crater in shader array — shader renders floor, walls, rim, ejecta.
	var idx := _shader_crater_count % MAX_SHADER_CRATERS
	_shader_crater_normals[idx]   = n_impact
	_shader_crater_r[idx]         = angular_r
	_shader_crater_intensity[idx] = clamp(intensity, 0.0, 1.0)
	_shader_crater_count += 1

	var mat := _putty_mi.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("crater_tex", _crater_tex)
		mat.set_shader_parameter("crater_count", min(_shader_crater_count, MAX_SHADER_CRATERS))
		mat.set_shader_parameter("crater_normals", _shader_crater_normals)
		mat.set_shader_parameter("crater_r", _shader_crater_r)
		mat.set_shader_parameter("crater_intensity", _shader_crater_intensity)
	else:
		push_error("_paint_crater: no material on _putty_mi")


# Sync tile.is_land with the baked terrain texture so both systems agree.
func _sync_tile_land_flags() -> void:
	for tile in _geo_tiles:
		var t := tile as PlanetTile
		t.is_land = not is_position_sea(t.center_position)


# Returns true if the position is over sea, using the pre-blur binary map.
# The binary is exact: land=1.0, sea=0.0 — no blurred transition zone to misclassify.
func is_position_sea(dir: Vector3) -> bool:
	var img := _terrain_binary if _terrain_binary != null else _terrain_image
	if img == null:
		return false
	var n := dir.normalized()
	var u := atan2(-n.x, -n.z) / TAU + 0.5  # matches sphere mesh UV convention
	var v := asin(clamp(n.y, -1.0, 1.0)) / PI + 0.5
	var px := clampi(int(u * img.get_width()),  0, img.get_width()  - 1)
	var py := clampi(int(v * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(px, py).r < 0.5


func _bake_terrain_texture_UNUSED(
		vis: GeodesicSphere,
		col_r: PackedFloat32Array,
		col_g: PackedFloat32Array,
		col_b: PackedFloat32Array,
		palette: Dictionary,
		c: Dictionary,
		inflated_land: Array,
		noise: FastNoiseLite) -> ImageTexture:

	const W: int = 1024
	const H: int = 512
	var data := PackedByteArray()
	data.resize(W * H * 3)

	var ocean: Color = palette.get("DEEP_OCEAN", Color(0.05, 0.15, 0.35))
	var or_b: int = int(ocean.r * 255); var og_b: int = int(ocean.g * 255); var ob_b: int = int(ocean.b * 255)
	for i in range(W * H):
		var ofs: int = i * 3
		data[ofs] = or_b; data[ofs + 1] = og_b; data[ofs + 2] = ob_b

	# ── Phase 1: triangle rasterisation ──────────────────────────────────────
	var eu := PackedFloat32Array(); eu.resize(vis.vertices.size())
	var ev := PackedFloat32Array(); ev.resize(vis.vertices.size())
	for i in range(vis.vertices.size()):
		var sn: Vector3 = vis.vertices[i]
		eu[i] = atan2(sn.x, sn.z) / TAU + 0.5
		ev[i] = asin(clampf(sn.y, -1.0, 1.0)) / PI + 0.5

	for tri in vis.triangles:
		var a: int = tri[0]; var b: int = tri[1]; var ci: int = tri[2]
		var u0: float = eu[a];  var v0: float = ev[a]
		var u1: float = eu[b];  var v1: float = ev[b]
		var u2: float = eu[ci]; var v2: float = ev[ci]
		if maxf(u0, maxf(u1, u2)) - minf(u0, minf(u1, u2)) > 0.5:
			continue
		var rb: int = int(clampf((col_r[a] + col_r[b] + col_r[ci]) / 3.0, 0.0, 1.0) * 255)
		var gb: int = int(clampf((col_g[a] + col_g[b] + col_g[ci]) / 3.0, 0.0, 1.0) * 255)
		var bb: int = int(clampf((col_b[a] + col_b[b] + col_b[ci]) / 3.0, 0.0, 1.0) * 255)
		var px0: int = int(u0 * W); var py0: int = int(v0 * H)
		var px1: int = int(u1 * W); var py1: int = int(v1 * H)
		var px2: int = int(u2 * W); var py2: int = int(v2 * H)
		var bx0: int = maxi(0,     mini(px0, mini(px1, px2)))
		var bx1: int = mini(W - 1, maxi(px0, maxi(px1, px2)))
		var by0: int = maxi(0,     mini(py0, mini(py1, py2)))
		var by1: int = mini(H - 1, maxi(py0, maxi(py1, py2)))
		var dx01: int = px1 - px0; var dy01: int = py1 - py0
		var dx02: int = px2 - px0; var dy02: int = py2 - py0
		var denom: int = dx01 * dy02 - dx02 * dy01
		if denom == 0: continue
		for py in range(by0, by1 + 1):
			for px in range(bx0, bx1 + 1):
				var dx: int = px - px0; var dy: int = py - py0
				var s_n: int = dx * dy02 - dx02 * dy
				var t_n: int = dx01 * dy - dx * dy01
				if denom > 0:
					if s_n < 0 or t_n < 0 or s_n + t_n > denom: continue
				else:
					if s_n > 0 or t_n > 0 or s_n + t_n < denom: continue
				var ofs: int = (py * W + px) * 3
				data[ofs] = rb; data[ofs + 1] = gb; data[ofs + 2] = bb

	# ── Phase 2: polygon-accurate coast refinement ────────────────────────────
	# Find pixels sitting on a terrain boundary (adjacent pixels differ in colour).
	# Expand that set outward by EXPAND_R pixels using fast 1D scanning.
	# Re-classify every pixel in the expanded zone with the exact polygon tests —
	# same logic as the game tile pass — giving sub-pixel-accurate coastlines.
	const EXPAND_R: int = 8

	var zone := PackedByteArray(); zone.resize(W * H); zone.fill(0)
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var ofs: int = (y * W + x) * 3
			var cr: int = data[ofs]; var cg: int = data[ofs + 1]; var cb: int = data[ofs + 2]
			if data[(y * W + x - 1) * 3] != cr or data[(y * W + x + 1) * 3] != cr or \
			   data[((y - 1) * W + x) * 3] != cr or data[((y + 1) * W + x) * 3] != cr or \
			   data[(y * W + x - 1) * 3 + 1] != cg or data[(y * W + x + 1) * 3 + 1] != cg or \
			   data[((y - 1) * W + x) * 3 + 1] != cg or data[((y + 1) * W + x) * 3 + 1] != cg:
				zone[y * W + x] = 1

	# Two-pass separable dilation: O(W×H) regardless of EXPAND_R
	var zh := PackedByteArray(); zh.resize(W * H); zh.fill(0)
	for y in range(H):
		var cd: int = 0
		for x in range(W):
			if zone[y * W + x]: cd = EXPAND_R + 1
			if cd > 0: zh[y * W + x] = 1; cd -= 1
		cd = 0
		for x in range(W - 1, -1, -1):
			if zone[y * W + x]: cd = EXPAND_R + 1
			if cd > 0: zh[y * W + x] = 1; cd -= 1
	var zone2 := PackedByteArray(); zone2.resize(W * H); zone2.fill(0)
	for x in range(W):
		var cd: int = 0
		for y in range(H):
			if zh[y * W + x]: cd = EXPAND_R + 1
			if cd > 0: zone2[y * W + x] = 1; cd -= 1
		cd = 0
		for y in range(H - 1, -1, -1):
			if zh[y * W + x]: cd = EXPAND_R + 1
			if cd > 0: zone2[y * W + x] = 1; cd -= 1

	# Chaikin-smooth the polygons for the refinement phase only (few thousand pixels,
	# so the extra vertex cost is fast). This rounds sharp polygon corners into
	# smooth organic curves — the main fix for rectangular continent outlines.
	var ref_land: Array = []
	for poly in inflated_land:
		ref_land.append(_chaikin(poly, 2))
	var ref_sea: Array = []
	for sp in c.sea_polygons:
		ref_sea.append({"type": sp.type, "poly": _chaikin(sp.poly, 2)})

	var shallow_deg: float = c.get("shallow_sea_depth", 2) * 2.25

	for y in range(H):
		for x in range(W):
			if not zone2[y * W + x]: continue

			# Pixel centre → unit sphere position using the inverse of the UV formula
			var u: float  = (float(x) + 0.5) / float(W)
			var vc: float = (float(y) + 0.5) / float(H)
			var lon_r: float  = (u - 0.5) * TAU
			var sin_lat: float = sin((vc - 0.5) * PI)
			var cos_lat: float = sqrt(maxf(0.0, 1.0 - sin_lat * sin_lat))
			var pos3d: Vector3 = Vector3(sin(lon_r) * cos_lat, sin_lat, cos(lon_r) * cos_lat)

			# Same jittered lat/lon used in the vis-sphere classification
			var ll: Vector2   = _tile_lat_lon(pos3d)
			var nv: float     = noise.get_noise_3dv(pos3d)
			var clat: float   = ll.x + nv * c.coast_roughness
			var clon: float   = ll.y + nv * c.coast_roughness * 1.5

			var terrain: String = "DEEP_OCEAN"
			for sp in ref_sea:
				if _point_in_polygon(clat, clon, sp.poly):
					terrain = sp.type; break

			if terrain == "DEEP_OCEAN":
				var on_land: bool = false
				for poly in ref_land:
					if _point_in_polygon(clat, clon, poly):
						on_land = true; break
				if on_land:
					# Coastal if any 4-neighbour pixel in data (already refined or rasterised)
					# tests as ocean under the polygon check — fast 2px probe in each direction
					var is_coastal: bool = false
					for probe in [Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -3), Vector2i(0, 3)]:
						var nx: int = clampi(x + probe.x, 0, W - 1)
						var ny: int = clampi(y + probe.y, 0, H - 1)
						var pu: float  = (float(nx) + 0.5) / float(W)
						var pvc: float = (float(ny) + 0.5) / float(H)
						var plon: float   = (pu - 0.5) * TAU
						var psin: float   = sin((pvc - 0.5) * PI)
						var pcos: float   = sqrt(maxf(0.0, 1.0 - psin * psin))
						var ppos: Vector3 = Vector3(sin(plon) * pcos, psin, cos(plon) * pcos)
						var pll: Vector2  = _tile_lat_lon(ppos)
						var pnv: float    = noise.get_noise_3dv(ppos)
						var pclat: float  = pll.x + pnv * c.coast_roughness
						var pclon: float  = pll.y + pnv * c.coast_roughness * 1.5
						var probe_land: bool = false
						for poly in ref_land:
							if _point_in_polygon(pclat, pclon, poly):
								probe_land = true; break
						if not probe_land: is_coastal = true; break
					terrain = _apply_land_rules(clat, clon, c.land_rules, nv, is_coastal)
				else:
					# Shallow sea: probe 4 cardinal points at shallow_deg offset
					for dlat in [-shallow_deg, shallow_deg]:
						for poly in ref_land:
							if _point_in_polygon(clat + dlat, clon, poly):
								terrain = "SHALLOW_SEA"; break
						if terrain == "SHALLOW_SEA": break
					if terrain == "DEEP_OCEAN":
						for dlon in [-shallow_deg, shallow_deg]:
							for poly in ref_land:
								if _point_in_polygon(clat, clon + dlon, poly):
									terrain = "SHALLOW_SEA"; break
							if terrain == "SHALLOW_SEA": break

			var col: Color = palette.get(terrain, Color(0.5, 0.5, 0.5))
			var ofs: int = (y * W + x) * 3
			data[ofs] = int(col.r * 255); data[ofs + 1] = int(col.g * 255); data[ofs + 2] = int(col.b * 255)

	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGB8, data)
	return ImageTexture.create_from_image(img)


func _build_tile_mesh(tile: PlanetTile, palette: Dictionary) -> ArrayMesh:
	var verts:   PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs:     PackedVector2Array = PackedVector2Array()
	var colors:  PackedColorArray   = PackedColorArray()
	var indices: PackedInt32Array   = PackedInt32Array()

	var sn:    Vector3 = tile.center_position
	var raise: float   = tile_raise + (land_height if tile.is_land else 0.0)
	var col:   Color   = palette.get(tile.terrain_type, Color.WHITE)
	col.a = 1.0 if not tile.is_land else 0.0

	verts.append(sn * (planet_radius + raise))
	normals.append(sn)
	uvs.append(Vector2(0.0, 0.0))
	colors.append(col)

	for p in tile.polygon:
		verts.append(p * (planet_radius + raise))
		normals.append(sn)
		uvs.append(Vector2(1.0, 0.0))
		colors.append(col)

	var poly_size: int = tile.polygon.size()
	for i in range(poly_size):
		indices.append(0)
		indices.append(i + 1)
		indices.append((i + 1) % poly_size + 1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR]  = colors
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_wall_mesh(tiles: Array, tile_map: Dictionary, palette: Dictionary) -> ArrayMesh:
	var verts:   PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs:     PackedVector2Array = PackedVector2Array()
	var colors:  PackedColorArray   = PackedColorArray()
	var indices: PackedInt32Array   = PackedInt32Array()

	var top_r: float = planet_radius + tile_raise + land_height * 0.98
	var bot_r: float = planet_radius + tile_raise

	for tile in tiles:
		if not tile.is_land:
			continue
		var sn:       Vector3 = tile.center_position
		var land_col: Color   = palette.get(tile.terrain_type, Color.WHITE)

		for nbr_id in tile.neighbours:
			var nbr: PlanetTile = tile_map[nbr_id]
			if nbr.is_land:
				continue

			var shared: Array = []
			for va in tile.polygon:
				for vb in nbr.polygon:
					if va.is_equal_approx(vb):
						shared.append(va)
						break
				if shared.size() == 2:
					break

			if shared.size() != 2:
				continue

			var p0: Vector3 = shared[0]
			var p1: Vector3 = shared[1]
			if p0.cross(p1).dot(sn) > 0.0:
				var tmp: Vector3 = p0
				p0 = p1
				p1 = tmp

			var bi: int = verts.size()
			verts.append(p0 * top_r);  normals.append(sn);  uvs.append(Vector2(0.5, 1.0));  colors.append(land_col)
			verts.append(p1 * top_r);  normals.append(sn);  uvs.append(Vector2(0.5, 1.0));  colors.append(land_col)
			verts.append(p0 * bot_r);  normals.append(sn);  uvs.append(Vector2(0.5, 1.0));  colors.append(land_col)
			verts.append(p1 * bot_r);  normals.append(sn);  uvs.append(Vector2(0.5, 1.0));  colors.append(land_col)

			indices.append(bi + 0);  indices.append(bi + 2);  indices.append(bi + 1)
			indices.append(bi + 1);  indices.append(bi + 2);  indices.append(bi + 3)

	if verts.size() == 0:
		return ArrayMesh.new()

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR]  = colors
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

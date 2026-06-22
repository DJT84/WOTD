@tool
class_name Planet
extends Node3D

const ROTATION_SPEED: float = TAU / 90.0
const AXIAL_TILT:     float = deg_to_rad(23.5)
const MAX_IMPACTS:    int   = 8

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

# ── Runtime state ─────────────────────────────────────────────────────────────

var _impacts:       Array          = []
var _tile_nodes:    Array          = []
var _tile_mesh_map: Dictionary     = {}   # tile_id → MeshInstance3D
var _shared_mat:    ShaderMaterial = null
var _mesh_root:     Node3D         = null
var _geo_tiles:     Array          = []   # cached PlanetTile array — used by editor plugin

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
	"noise_seed": 100, "coast_roughness": 5.0, "shallow_sea_depth": 3, "land_expand_deg": 5.0,
	"palette": {
		"DEEP_OCEAN":   Color("#2a6a82"),
		"SHALLOW_SEA":  Color("#5abcd4"),
		"INLAND_SEA":   Color("#7ad4e8"),
		"BARE_ROCK":    Color("#c9b97a"),
		"COASTAL_ROCK": Color("#a89460"),
		"SCRUB":        Color("#9a9860"),
	},
	"land_polygons": [
		# Gondwana — large southern supercontinent
		[[-8,-18],[-8,40],[-15,85],[-25,130],[-45,155],[-70,150],[-80,60],[-80,-20],[-65,-55],[-40,-45],[-8,-18]],
		# Laurentia (proto-North America)
		[[-5,-115],[5,-65],[20,-55],[30,-75],[25,-105],[5,-120],[-5,-115]],
		# Baltica
		[[-38,18],[-25,55],[-12,52],[-18,18],[-38,18]],
		# Siberia
		[[-22,105],[-10,155],[5,155],[8,108],[-8,100],[-22,105]],
		# Avalonia
		[[-22,-50],[-12,-40],[-10,-52],[-22,-50]],
	],
	"sea_polygons": [],
	"land_rules": [
		{"type": "COASTAL_ROCK", "coast": true},
		{"type": "BARE_ROCK",    "default": true},
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
	"noise_seed": 200, "coast_roughness": 4.5, "shallow_sea_depth": 3, "land_expand_deg": 4.0,
	"palette": {
		"DEEP_OCEAN":    Color("#1E3A48"),
		"SHALLOW_SEA":   Color("#2A5A6B"),
		"INLAND_SEA":    Color("#2A5A6B"),
		"SWAMP":         Color("#1A3A15"),
		"FOREST_DENSE":  Color("#2D5E20"),
		"FERN_LAND":     Color("#2A6B5A"),
		"BARE_ROCK":     Color("#4A3520"),
		"COASTAL_ROCK":  Color("#4A3520"),
		"IRON_MUDFLAT":  Color("#8B3A2A"),
		"ICE_SHEET":     Color("#c8dce8"),
	},
	"land_polygons": [
		# Euramerica / western Laurasia
		[[-8,-108],[8,-62],[22,-48],[35,8],[30,45],[15,52],[5,30],[-5,2],[-10,-38],[-10,-78],[-8,-108]],
		# Siberia + Kazakhstania
		[[8,72],[25,128],[48,142],[55,78],[35,62],[8,72]],
		# Cathaysia
		[[0,105],[15,130],[25,130],[20,108],[5,105],[0,105]],
		# Gondwana
		[[-5,-18],[-5,88],[-18,135],[-42,158],[-70,148],[-80,58],[-80,-22],[-65,-55],[-40,-45],[-5,-18]],
	],
	"sea_polygons": [
		# Inland sea flooding central Laurussia (where central Europe sits)
		{"type": "INLAND_SEA", "poly": [[10,-15],[25,-5],[30,20],[28,40],[20,42],[12,38],[5,18],[0,5],[10,-15]]},
	],
	"land_rules": [
		{"type": "ICE_SHEET",    "lat_south_of": -65},
		# Southern Gondwana — cold, dark mud and swamp fringe, no desert
		{"type": "BARE_ROCK",    "lat_south_of": -45},
		{"type": "FERN_LAND",    "lat_south_of": -30},
		# Iron mudflat — scattered rust-red accent across all latitudes (~10% of tiles)
		{"type": "IRON_MUDFLAT", "noise_above": 0.75},
		# Coastal zones
		{"type": "BARE_ROCK",    "coast": true, "lat_south_of": -20},
		{"type": "SWAMP",        "coast": true, "lat_abs_below": 45},
		{"type": "BARE_ROCK",    "coast": true},
		# Interior land by latitude
		{"type": "FOREST_DENSE", "lat_abs_below": 32},
		{"type": "FERN_LAND",    "lat_abs_below": 55},
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
	"noise_seed": 300, "coast_roughness": 4.0, "shallow_sea_depth": 3, "land_expand_deg": 7.0,
	"palette": {
		"DEEP_OCEAN":  Color("#1a5070"),
		"SHALLOW_SEA": Color("#2a7090"),
		"INLAND_SEA":  Color("#3a8898"),
		"DESERT":      Color("#b05c30"),
		"BARE_ROCK":   Color("#8a3a18"),
		"SCRUB":       Color("#c47840"),
		"SAND_DUNE":   Color("#d4a060"),
		"FOREST_LIGHT":Color("#3a4a28"),
		"ICE_SHEET":   Color("#c8d8e8"),
		"VOLCANIC":    Color("#8a2a10"),
	},
	"land_polygons": [
		# Laurasia (northern half of Pangaea)
		[[75,-40],[80,0],[75,30],[68,60],[62,80],[55,85],[48,82],[40,78],
		 [30,70],[22,62],[18,52],[12,42],[7,30],[3,22],[0,18],
		 [0,10],[5,-20],[20,-28],[35,-32],[50,-38],[65,-35],[75,-40]],
		# Gondwana (southern half of Pangaea) — shares the Tethys-tip shoreline
		[[0,18],[-2,22],[-5,30],[-5,50],[-2,72],[2,95],[5,118],
		 [-10,128],[-25,132],[-42,128],[-58,118],[-68,98],[-75,62],
		 [-80,18],[-80,-20],[-72,-40],[-58,-55],[-42,-52],[-28,-42],
		 [-12,-32],[2,-24],[0,10],[0,18]],
	],
	"sea_polygons": [
		# Tethys Sea — triangular bay opening eastward from the equator
		{"type": "SHALLOW_SEA", "poly": [
			[0,18],[5,25],[12,40],[22,55],[28,70],[20,100],[10,118],
			[5,118],[2,95],[-2,72],[-5,50],[-5,30],[-2,22],[0,18]
		]},
	],
	"land_rules": [
		{"type": "ICE_SHEET",    "lat_south_of": -70},
		# Siberian Traps — volcanic region in NW Pangaea
		{"type": "VOLCANIC",     "lat_north_of": 58, "lon_between": [80, 130]},
		# Coastal forests at the Tethys coast and wetter margins
		{"type": "FOREST_LIGHT", "coast": true, "lat_abs_below": 50},
		{"type": "FOREST_LIGHT", "lat_south_of": -50, "lat_north_of": -65},
		# Vast desert interior — the largest in Earth's history
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
	"noise_seed": 400, "coast_roughness": 4.0, "shallow_sea_depth": 3, "land_expand_deg": 4.0,
	"palette": {
		"DEEP_OCEAN":   Color("#2a5878"),
		"SHALLOW_SEA":  Color("#4a8a9a"),
		"INLAND_SEA":   Color("#6aaaba"),
		"FOREST_DENSE": Color("#2a5228"),
		"FERN_LAND":    Color("#5a9a45"),
		"FOREST_LIGHT": Color("#3a6b35"),
		"SWAMP":        Color("#1e4030"),
		"DESERT":       Color("#9a8850"),
	},
	"land_polygons": [
		# Laurasia — North America
		[[72,-62],[58,-64],[40,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-112],[32,-118],[48,-125],[60,-140],[70,-142],[72,-62]],
		# Laurasia — Europe + Asia (connected)
		[[32,-8],[58,8],[70,32],[68,110],[58,148],[38,135],
		 [22,80],[22,55],[35,32],[32,-8]],
		# South America
		[[-5,-80],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[-5,-80]],
		# Africa
		[[-5,-15],[15,-17],[22,32],[10,46],[-5,42],[-35,28],[-38,18],[-12,12],[-5,-15]],
		# India (isolated, heading north)
		[[-15,65],[-5,75],[-15,90],[-35,80],[-35,70],[-15,65]],
		# Antarctica + Australia (still joined)
		[[-55,22],[-48,100],[-28,128],[-42,168],[-60,158],[-75,108],[-80,48],[-80,-28],[-55,22]],
		# Madagascar
		[[-20,43],[-12,50],[-25,50],[-25,44],[-20,43]],
	],
	"sea_polygons": [
		# Sundance Sea — floods western interior of North America N-S
		{"type": "INLAND_SEA", "poly": [
			[72,-100],[55,-95],[40,-100],[32,-108],[40,-115],[55,-112],[72,-110]
		]},
		# European archipelago — much of NW Europe is underwater
		{"type": "INLAND_SEA", "poly": [
			[42,-2],[55,2],[58,22],[52,25],[45,18],[38,5],[42,-2]
		]},
	],
	"land_rules": [
		{"type": "SWAMP",        "coast": true, "lat_abs_below": 45},
		{"type": "DESERT",       "lat_abs_below": 22, "noise_above": 0.35},
		{"type": "FERN_LAND",    "lat_abs_below": 18},
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
	"noise_seed": 500, "coast_roughness": 3.5, "shallow_sea_depth": 3, "land_expand_deg": 2.0,
	"palette": {
		"DEEP_OCEAN":   Color("#3a6888"),
		"SHALLOW_SEA":  Color("#5a88a8"),
		"INLAND_SEA":   Color("#7aaac8"),
		"FOREST_DENSE": Color("#4a7a38"),
		"FOREST_LIGHT": Color("#6aa840"),
		"FERN_LAND":    Color("#5a8850"),
		"SCRUB":        Color("#88b858"),
		"VOLCANIC":     Color("#8a2a10"),
		"DESERT":       Color("#b89860"),
	},
	"land_polygons": [
		# North America (seaway will cut it — defined via sea_polygon below)
		[[72,-130],[58,-64],[40,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-112],[35,-120],[48,-125],[60,-140],[72,-130]],
		# Europe (smaller — high seas)
		[[35,-8],[55,5],[62,18],[58,28],[48,22],[38,8],[35,-8]],
		# Asia
		[[25,60],[55,62],[78,102],[65,152],[40,135],[25,100],[25,60]],
		# Africa
		[[-5,-15],[15,-17],[22,35],[10,50],[-5,42],[-35,28],[-38,18],[-12,12],[-5,-15]],
		# South America
		[[-5,-80],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[-5,-80]],
		# India (mid-drift ~10°S)
		[[-5,65],[8,77],[-5,90],[-18,85],[-18,68],[-5,65]],
		# Arabia
		[[12,42],[30,38],[30,60],[22,60],[12,50],[12,42]],
		# SE Asia
		[[-5,100],[20,100],[22,122],[5,120],[-5,100]],
		# Australia
		[[-15,125],[-15,155],[-38,150],[-40,130],[-28,115],[-15,125]],
		# Antarctica (still has forest, near south pole)
		[[-62,-78],[-58,22],[-62,102],[-62,162],[-80,162],[-85,50],[-85,-60],[-62,-78]],
		# Greenland
		[[76,-65],[84,-40],[76,-18],[60,-42],[76,-65]],
		# Madagascar
		[[-12,44],[-12,51],[-26,48],[-24,43],[-12,44]],
	],
	"sea_polygons": [
		# Western Interior Seaway — splits North America N to S
		{"type": "INLAND_SEA", "poly": [
			[72,-88],[60,-86],[48,-92],[35,-94],[25,-92],
			[25,-98],[35,-100],[48,-100],[60,-96],[72,-96]
		]},
		# European seaway — floods much of central Europe
		{"type": "INLAND_SEA", "poly": [
			[38,0],[52,2],[58,20],[52,22],[44,18],[36,5],[38,0]
		]},
	],
	"land_rules": [
		# Deccan Traps — India tile is volcanic in this epoch
		{"type": "VOLCANIC",     "lat_between": [-20, 12], "lon_between": [65, 90]},
		{"type": "DESERT",       "lat_abs_below": 22, "noise_above": 0.30},
		{"type": "FERN_LAND",    "coast": true, "lat_abs_below": 25},
		{"type": "SCRUB",        "lat_abs_below": 35, "noise_above": 0.15},
		{"type": "FOREST_DENSE", "lat_abs_below": 55},
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
	"noise_seed": 600, "coast_roughness": 3.0, "shallow_sea_depth": 2, "land_expand_deg": 3.5,
	"palette": {
		"DEEP_OCEAN":   Color("#1E6B8A"),
		"SHALLOW_SEA":  Color("#4A9EBF"),
		"INLAND_SEA":   Color("#5BB4CF"),
		"FOREST_DENSE": Color("#1E5C15"),
		"FOREST_LIGHT": Color("#3A8C2A"),
		"WETLAND":      Color("#6B9E4A"),
		"GRASSLAND":    Color("#C8A85A"),
		"SCRUB":        Color("#C8A85A"),
		"DESERT":       Color("#C8A85A"),
		"SWAMP":        Color("#1E5C15"),
	},
	"land_polygons": [
		# North America
		[[72,-62],[55,-55],[45,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-105],[32,-117],[48,-124],[60,-140],[70,-142],[72,-62]],
		# Greenland
		[[76,-65],[84,-35],[76,-18],[62,-42],[76,-65]],
		# South America (isolated island — no Panama yet)
		[[8,-77],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[8,-77]],
		# Europe
		[[35,-8],[58,5],[70,28],[62,30],[55,22],[48,2],[36,-8],[35,-8]],
		# Africa + Arabia (still somewhat joined)
		[[35,-5],[22,-17],[12,-18],[-5,-8],[-35,18],[-35,28],
		 [-10,42],[12,50],[30,45],[38,45],[30,30],[35,-5]],
		# India (just colliding with Asia — narrow sea still visible)
		[[22,68],[8,78],[8,92],[22,92],[35,72],[22,68]],
		# Central + West Asia
		[[25,55],[62,55],[75,92],[55,60],[25,55]],
		# East Asia
		[[22,100],[42,138],[22,122],[5,102],[22,100]],
		# SE Asia + Indonesia
		[[-5,98],[18,98],[22,122],[8,120],[2,108],[-8,118],[-8,100],[-5,98]],
		# Australia (separated from Antarctica, moving north)
		[[-15,128],[-15,155],[-38,150],[-38,128],[-28,114],[-15,128]],
		# Antarctica with S America bridge + forest (no ice)
		[[-58,-68],[-62,-40],[-62,22],[-62,102],[-62,162],[-78,162],[-85,50],[-85,-60],[-62,-68]],
	],
	"sea_polygons": [
		# Tethys remnant — shallow sea across Turkey, Iran, Central Asia
		{"type": "INLAND_SEA", "poly": [
			[12,35],[28,40],[38,52],[32,68],[22,58],[12,45],[12,35]
		]},
	],
	"land_rules": [
		{"type": "WETLAND",      "coast": true, "lat_abs_below": 30},
		{"type": "GRASSLAND",    "lat_abs_below": 25, "noise_above": 0.35},
		{"type": "FOREST_DENSE", "lat_abs_below": 50},
		{"type": "WETLAND",      "lat_abs_below": 60, "noise_above": 0.25},
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
	"noise_seed": 700, "coast_roughness": 2.5, "shallow_sea_depth": 2, "land_expand_deg": 3.0,
	"palette": {
		"DEEP_OCEAN":  Color("#3A6B8A"),
		"SHALLOW_SEA": Color("#8FC4D8"),
		"ICE_SHEET":   Color("#DFF0F7"),
		"DEEP_ICE":    Color("#B8D9EC"),
		"TUNDRA":      Color("#4A5C35"),
	},
	"land_polygons": [
		# North America (larger — lower sea levels)
		[[72,-62],[55,-55],[45,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-105],[32,-117],[48,-124],[60,-140],[70,-142],[72,-62]],
		# Beringia — land bridge, Alaska to Siberia
		[[55,-168],[68,-162],[68,-178],[55,-178],[55,-168]],
		# Greenland
		[[76,-65],[84,-35],[76,-18],[62,-42],[76,-65]],
		# South America
		[[8,-77],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[8,-77]],
		# Europe
		[[35,-8],[58,5],[70,28],[62,30],[55,22],[48,2],[36,-8],[35,-8]],
		# Africa
		[[35,-5],[22,-17],[12,-18],[-5,-8],[-35,18],[-35,28],
		 [-10,42],[12,50],[22,38],[32,30],[35,-5]],
		# Middle East + Arabia
		[[12,42],[30,38],[38,48],[30,60],[22,60],[12,52],[12,42]],
		# Central + West Asia
		[[25,58],[62,58],[75,92],[55,62],[25,58]],
		# East Asia
		[[22,100],[42,138],[22,122],[5,102],[22,100]],
		# Sundaland — SE Asia joined up (lower sea level)
		[[-5,98],[18,98],[22,122],[8,120],[-5,108],[-8,100],[-5,98]],
		# India
		[[22,68],[8,78],[8,92],[22,92],[35,72],[22,68]],
		# Australia (larger shelves exposed)
		[[-12,128],[-15,155],[-38,150],[-38,128],[-28,114],[-12,128]],
		# New Zealand
		[[-35,172],[-35,178],[-46,168],[-46,162],[-35,172]],
		# Antarctica
		[[-62,-80],[-60,22],[-62,102],[-62,162],[-80,162],[-85,50],[-85,-60],[-62,-80]],
	],
	"sea_polygons": [],
	"land_rules": [
		# Deep ice — the ancient core of the Antarctic sheet
		{"type": "DEEP_ICE",  "lat_south_of": -75},
		# Antarctic perimeter ice
		{"type": "ICE_SHEET", "lat_south_of": -58},
		# Laurentide ice sheet — N America
		{"type": "ICE_SHEET", "lat_north_of": 48, "lon_between": [-140, -55]},
		# Scandinavian ice sheet
		{"type": "ICE_SHEET", "lat_north_of": 55, "lon_between": [-10, 35]},
		# Greenland ice cap
		{"type": "DEEP_ICE",  "lat_north_of": 70, "lon_between": [-58, -18]},
		{"type": "ICE_SHEET", "lat_north_of": 62, "lon_between": [-58, -18]},
		# Tundra refugia — narrow band just below ice sheets
		{"type": "TUNDRA",    "lat_north_of": 40, "noise_above": -0.3},
		{"type": "TUNDRA",    "lat_south_of": -52, "noise_above": -0.3},
		# Everything else defaults to ice — this is the ice age
		{"type": "ICE_SHEET", "default": true},
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
	"noise_seed": 800, "coast_roughness": 2.0, "shallow_sea_depth": 2, "land_expand_deg": 2.5,
	"palette": {
		"DEEP_OCEAN":   Color("#2858a0"),
		"SHALLOW_SEA":  Color("#4878c0"),
		"INLAND_SEA":   Color("#6898d0"),
		"FOREST_DENSE": Color("#2a6a5a"),
		"FOREST_LIGHT": Color("#4a8a3a"),
		"GRASSLAND":    Color("#c8d870"),
		"DESERT":       Color("#d4c090"),
		"TUNDRA":       Color("#8a9878"),
		"ICE_SHEET":    Color("#e0eef8"),
		"WETLAND":      Color("#3a7050"),
		"SCRUB":        Color("#a8b858"),
	},
	"land_polygons": [
		# North America
		[[72,-62],[55,-55],[45,-52],[25,-80],[8,-77],[9,-75],
		 [15,-90],[22,-105],[32,-117],[48,-124],[60,-140],[70,-142],[72,-62]],
		# Greenland
		[[76,-65],[84,-35],[76,-18],[62,-42],[76,-65]],
		# South America
		[[8,-77],[8,-62],[5,-52],[-25,-42],[-55,-65],[-55,-75],[-25,-80],[8,-77]],
		# Europe
		[[35,-8],[58,5],[70,28],[62,30],[55,22],[48,2],[36,-8],[35,-8]],
		# Africa + Arabia
		[[35,-5],[22,-17],[12,-18],[-5,-8],[-35,18],[-35,28],
		 [-10,42],[12,50],[30,45],[38,45],[30,30],[35,-5]],
		# Central + West Asia
		[[25,55],[62,55],[75,92],[55,60],[25,55]],
		# East Asia + China
		[[22,100],[42,138],[22,122],[5,102],[22,100]],
		# SE Asia + Indonesia
		[[-5,98],[18,98],[22,122],[8,120],[2,108],[-8,118],[-8,100],[-5,98]],
		# India
		[[22,68],[8,78],[8,92],[22,92],[35,72],[22,68]],
		# Australia
		[[-15,128],[-15,155],[-38,150],[-38,128],[-28,114],[-15,128]],
		# New Zealand
		[[-35,172],[-35,178],[-46,168],[-46,162],[-35,172]],
		# Antarctica
		[[-62,-80],[-60,22],[-62,102],[-62,162],[-80,162],[-85,50],[-85,-60],[-62,-80]],
		# Japan
		[[30,130],[42,142],[45,142],[42,130],[30,130]],
	],
	"sea_polygons": [
		# Mediterranean / inland seas
		{"type": "INLAND_SEA", "poly": [
			[30,5],[38,5],[42,30],[38,38],[30,36],[28,12],[30,5]
		]},
	],
	"land_rules": [
		# Ice sheets — Greenland and Antarctica only
		{"type": "ICE_SHEET",    "lat_north_of": 64, "lon_between": [-58, -18]},
		{"type": "ICE_SHEET",    "lat_south_of": -70},
		# Tundra fringe below ice
		{"type": "TUNDRA",       "lat_north_of": 62},
		{"type": "TUNDRA",       "lat_south_of": -58},
		# Tropical forests — Amazon, Congo, SE Asia
		{"type": "FOREST_DENSE", "lat_abs_below": 10},
		# Deserts — Sahara, Arabia, Australia, central Asia
		{"type": "DESERT",       "lat_between": [15, 35],  "noise_above": -0.1},
		{"type": "DESERT",       "lat_between": [-35, -15], "noise_above": 0.2},
		# Savannas and grasslands
		{"type": "GRASSLAND",    "lat_abs_below": 42, "noise_above": 0.05},
		# Temperate forest — Europe, eastern N America, East Asia
		{"type": "FOREST_LIGHT", "lat_abs_below": 60},
		# Scrub — Mediterranean, California, South Africa
		{"type": "SCRUB",        "lat_abs_below": 45, "noise_above": 0.30},
		{"type": "TUNDRA",       "lat_north_of": 55},
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


# ── Public API ────────────────────────────────────────────────────────────────

func rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh_root:
		_mesh_root.free()
		_mesh_root = null
	_tile_nodes.clear()
	_shared_mat = null
	_build_planet()
	_assign_features()
	_build_feature_icons()
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
	_refresh_highlights()
	# Show the new tile's icon
	if tile_id != -1 and _feature_icon_map.has(tile_id):
		(_feature_icon_map[tile_id] as Label3D).visible = true


func set_tile_selected(tile_id: int) -> void:
	_selected_tile_id = -1 if tile_id == _selected_tile_id else tile_id
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


func apply_impact(tile_id: int, impact_pos: Vector3 = Vector3.ZERO, intensity: float = 1.0) -> void:
	# If no explicit impact pos supplied, default to the target tile's centre
	if impact_pos == Vector3.ZERO:
		for t in _geo_tiles:
			var pt := t as PlanetTile
			if pt.tile_id == tile_id:
				var raise: float = tile_raise + (land_height if pt.is_land else 0.0)
				impact_pos = pt.center_position * (planet_radius + raise)
				break

	# Crater world-space radius scales with asteroid size
	var crater_r: float = 0.45 + intensity * 0.35

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


func _build_planet() -> void:
	_mesh_root      = Node3D.new()
	_mesh_root.name = "_MeshRoot"
	add_child(_mesh_root)

	var geo := GeodesicSphere.new()
	geo.generate(subdivision_depth)
	_geo_tiles = geo.tiles

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

	# ── Pass 1: binary land / sea using polygons ───────────────────────────
	# Pre-inflate land polygons once — cheaper than inflating per tile.
	var expand_deg: float = c.get("land_expand_deg", 0.0)
	var inflated_land: Array = []
	for poly in c.land_polygons:
		inflated_land.append(_inflate_polygon(poly, expand_deg) if expand_deg > 0.0 else poly)

	var land_set: Dictionary = {}

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

# Epoch Design Specification
## Asteroid Impact Globe Game — Visual & Life Zone Reference for Claude Code

---

## HOW TO READ THIS DOCUMENT

Each epoch section contains:
- **Globe shape** — continent/ocean layout, what the hex sphere should look like overall
- **Tile type distribution** — approximate % breakdown of tile types to place on the sphere
- **Tile colour palette** — exact hex codes for each tile type
- **Land cover geography** — where on the globe each land tile type appears (equator, poles, coasts, interior)
- **Sea geography** — where deep ocean vs shallow sea vs inland sea tiles appear
- **Life zone breakdown** — what % of life exists in each zone
- **Key animals per zone** — the specific creatures to highlight in each zone

Tile type names used throughout: `DEEP_OCEAN`, `SHALLOW_SEA`, `INLAND_SEA`, `BARE_ROCK`, `COASTAL_ROCK`, `DESERT`, `SCRUB`, `FERN_LAND`, `FOREST_LIGHT`, `FOREST_DENSE`, `SWAMP`, `GRASSLAND`, `TUNDRA`, `ICE_SHEET`, `VOLCANIC`

---

## EPOCH 1: CAMBRIAN
**~541 million years ago**

### Globe shape
The globe is dominated by ocean. Gondwana — a large supercontinent — sits over the south pole and stretches toward the equator. Several smaller cratons (Laurentia, Baltica, Siberia) are scattered across the tropics as island-like landmasses surrounded by warm shallow seas. There is no recognisable continent shape from the modern world. The northern hemisphere is almost entirely open ocean (the Iapetus Ocean). Roughly 80% of the globe surface is water when viewed from any angle.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 65% | Dominates northern hemisphere and deep southern ocean |
| SHALLOW_SEA | 18% | Thick fringe around all landmasses; wide shelves on Laurentia |
| INLAND_SEA | 4% | Small epicontinental seas on low-lying parts of Gondwana |
| BARE_ROCK | 10% | The majority of all land above water |
| COASTAL_ROCK | 2% | Narrow strip at shorelines, slightly darker than interior |
| SCRUB | 1% | Thin microbial crust at some coastal edges only |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#2a6a82` | Dark teal-blue — deep, warm Cambrian ocean |
| SHALLOW_SEA | `#5abcd4` | Bright turquoise — clear, warm, carbonate-rich shelf seas |
| INLAND_SEA | `#7ad4e8` | Lighter turquoise — very shallow epicontinental water |
| BARE_ROCK | `#c9b97a` | Sandy ochre — bare desert rock, no soil |
| COASTAL_ROCK | `#a89460` | Darker tan — rock at the shoreline |
| SCRUB | `#9a9860` | Dull olive — thin microbial mat, barely visible |

### Land cover geography
- All land is essentially desert rock — render it as uniform BARE_ROCK with COASTAL_ROCK only at the immediate shoreline edge tiles
- No interior variation needed — this is the simplest land palette in the game
- No green tiles anywhere on land
- Gondwana's southern portion (over the pole) can have slightly darker rock to suggest cooler conditions

### Sea geography
- Shallow sea tiles form a wide band (3–5 tiles deep) around every landmass
- The Laurentian craton (proto-North America, sitting near the equator) should have the widest shallow shelf — almost as much shallow sea as land
- Deep ocean fills everything else
- Inland sea tiles optional — only place on the lowest parts of Gondwana near the equator

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 30% |
| Shallow sea | 60% |
| Inland sea | 10% |
| Land | 0% |

The land is completely lifeless. Almost all life is marine. The shallow seas are the richest zone by far — this is where the Cambrian Explosion happens.

### Key animals by zone

**Shallow sea (60% of life) — the main event**
- Trilobites — dominant arthropods, various sizes, armoured, crawling the seafloor and swimming
- Anomalocaris — large predator, up to 1m, shrimp-like with circular mouth, the apex predator
- Opabinia — five-eyed, trunk-nosed, soft-bodied swimmer
- Hallucigenia — spiny worm walking on stilts, bizarre appearance
- Pikaia — small eel-like creature, earliest vertebrate ancestor
- Wiwaxia — armoured slug-like creature with spines
- Brachiopods — shell creatures covering the seafloor
- Sponges — colonial filter feeders forming reef-like structures

**Deep ocean (30% of life)**
- Early sponges
- Simple jellyfish and medusozoans
- Microbial mat communities on the seafloor

**Inland sea (10% of life)**
- Trilobites (smaller species)
- Early molluscs
- Stromatolite mats

---

## EPOCH 2: CARBONIFEROUS
**~310 million years ago**

### Globe shape
Two major landmasses exist. Laurussia (Europe + North America fused together) sits in the northern tropics. Gondwana (South America + Africa + Antarctica + Australia + India) spans the southern hemisphere down to the south pole. A narrow equatorial seaway (Tethys) separates them. The supercontinent Pangaea is in the process of forming — the two landmasses are colliding but not yet fully joined. High sea levels mean shallow seas penetrate deeply into the continental interiors. The globe has more land than the Cambrian but it is heavily forested at the equator.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 52% | Panthalassa ocean dominates western hemisphere |
| SHALLOW_SEA | 16% | Wide shelves, especially around Laurussia |
| INLAND_SEA | 10% | Significant — flooding low parts of both continents |
| FOREST_DENSE | 8% | The coal forests — equatorial belt only |
| SWAMP | 4% | At the edge of coal forests, coastal lowlands |
| FERN_LAND | 3% | Higher elevation, drier areas within forested zone |
| BARE_ROCK / DESERT | 5% | Interior of Gondwana, higher latitudes |
| ICE_SHEET | 2% | South pole — Gondwana glaciation in late Carboniferous |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#2a6878` | Warm teal-blue — greenhouse world ocean |
| SHALLOW_SEA | `#3a8898` | Medium teal — warm shallow seas |
| INLAND_SEA | `#4aa8b8` | Lighter teal — flooded continental interior |
| FOREST_DENSE | `#1a3d28` | Very dark green — dense coal forest canopy |
| SWAMP | `#243d20` | Dark murky green-brown — waterlogged forest floor |
| FERN_LAND | `#3d7a50` | Mid green — open fern and horsetail areas |
| BARE_ROCK | `#8a7850` | Warm brown — arid Gondwana interior |
| DESERT | `#a08840` | Dry ochre — drier higher-latitude land |
| ICE_SHEET | `#c8dce8` | Cold pale blue-white — south polar glaciation |

### Land cover geography
- FOREST_DENSE and SWAMP tiles are confined strictly to the equatorial band — approximately 30 degrees north and south of the equator on Laurussia's landmass
- The equatorial coal forests are continuous and dense — no gaps or patchy tiles in this band
- Moving away from the equator, transition to FERN_LAND then BARE_ROCK
- Gondwana's interior (which is large and extends to the south pole) is BARE_ROCK and DESERT — it is dry and cool
- South polar tip of Gondwana gets ICE_SHEET tiles
- Highlands and mountain zones (where the Appalachians are forming) get FERN_LAND or BARE_ROCK

### Sea geography
- Inland sea tiles penetrate deep into Laurussia from the east — picture a large shallow sea sitting where central Europe is today
- Wide shallow shelves on both continents' eastern and western coasts
- The Tethys Sea (narrow equatorial ocean between the two landmasses) is SHALLOW_SEA tiles — warm and clear
- Deep ocean fills the vast Panthalassa (western hemisphere)

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 20% |
| Shallow sea | 35% |
| Inland sea | 15% |
| Land | 30% |

Land life is now a major category for the first time. The coal forests are extraordinarily productive.

### Key animals by zone

**Land (30% of life) — the new frontier**
- Meganeura — giant dragonfly, 70cm wingspan, apex aerial predator
- Arthropleura — giant millipede up to 2.6m long, forest floor
- Pulmonoscorpius — large land scorpion
- Hylonomus — first true reptile, small lizard-like
- Eryops — large amphibian, semi-aquatic
- Amphibians of many types dominating swamp edges
- Giant cockroaches and early beetles in the forest

**Shallow sea / Inland sea (50% combined)**
- Sharks — many species, highly diverse in this period (the Golden Age of Sharks)
- Crinoids — sea lilies carpeting the seafloor in vast numbers
- Brachiopods and bryozoans
- Early ray-finned fish
- Nautiloids

**Deep ocean (20%)**
- Sharks (open water species)
- Cephalopods
- Early ray-finned fish

---

## EPOCH 3: PERMIAN
**~270 million years ago**

### Globe shape
This is the most distinctive globe shape in the game. ALL land is fused into a single supercontinent: Pangaea. It stretches from the north pole to the south pole as one unbroken landmass, sitting roughly in the eastern hemisphere. The western hemisphere is almost entirely the Panthalassa ocean. The Tethys Sea cuts into Pangaea from the east as a large tropical gulf. The globe has a striking asymmetry — one half land, one half ocean. No other epoch looks like this.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 70% | Panthalassa — vast, featureless deep ocean |
| SHALLOW_SEA | 10% | Coastal fringe only; Tethys Sea |
| INLAND_SEA | 2% | Almost none — Pangaea is high and dry |
| DESERT | 28% of land | Massive interior desert — the largest in Earth's history |
| BARE_ROCK | 20% of land | Rock badlands and arid uplands |
| FOREST_LIGHT | 18% of land | Conifer and seed fern forest at wetter margins |
| SCRUB | 12% of land | Arid scrub at transition zones |
| ICE_SHEET | 10% of land | South polar region, early Permian |
| VOLCANIC | 2% of land | Siberian Traps region in the north — end-Permian event |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#1a5070` | Deep warm blue — vast Panthalassa |
| SHALLOW_SEA | `#2a7090` | Warm mid-blue — Tethys and coastal shelves |
| DESERT | `#b05c30` | Burnt orange — the iconic Permian desert interior |
| BARE_ROCK | `#8a3a18` | Deep rust — rocky badlands |
| SCRUB_ARID | `#c47840` | Warm amber — dry transitional scrub |
| SAND_DUNE | `#d4a060` | Pale gold — sandy desert regions |
| FOREST_LIGHT | `#3a4a28` | Dark olive-green — conifer and seed fern forest |
| ICE_SHEET | `#c8d8e8` | Pale blue-white — south polar glaciation |
| VOLCANIC | `#8a2a10` | Dark red-brown — Siberian Traps volcanic field |

### Land cover geography
- The interior of Pangaea is dominated by DESERT and BARE_ROCK — it is the most arid continental interior in Earth's history because it is so far from any ocean
- Desert tiles should be most intense (darkest, most saturated orange) in the central and northern interior
- FOREST_LIGHT tiles appear only at the coasts and margins of Pangaea — particularly along the Tethys coast (eastern margin) and in the far north and south where moisture reaches
- ICE_SHEET tiles on the southern tip (south pole end of Pangaea) — more prominent in early Permian, retreating by mid-Permian
- VOLCANIC tiles cluster in the far north (Siberian Traps) — these become more prominent at the end of the Permian epoch as the extinction approaches
- There is almost no green in this globe — it should look strikingly orange and rust compared to every other epoch

### Sea geography
- The Tethys Sea is the most important sea feature — it is a large gulf biting into the eastern side of Pangaea from the equator, place 4–6 tiles wide and reaching deep into the continent
- Coastal shallow sea tiles form only a narrow fringe around Pangaea (1–3 tiles)
- Almost no inland sea tiles — Pangaea sits high with very little flooding
- The western hemisphere is pure DEEP_OCEAN with no land interruption

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 25% |
| Shallow sea / Tethys | 55% |
| Land | 20% |

Note: By the END of the Permian (the Great Dying extinction event), life collapses to near zero in all zones. If showing the epoch at its close, consider a near-empty globe. At 270 Ma (mid-Permian) life is still relatively rich.

### Key animals by zone

**Land (20% of life)**
- Dimetrodon — large sail-backed predator, the most recognisable Permian animal (NOT a dinosaur — a synapsid)
- Edaphosaurus — sail-backed herbivore
- Gorgonopsid — sabre-toothed mammal-relative, top predator
- Scutosaurus — large armoured pareiasaur herbivore
- Moschops — barrel-bodied large herbivore
- Dicynodon — tusked, beak-faced mammal relative, very abundant

**Shallow sea / Tethys (55% of life)**
- Ammonites — coiled shell cephalopods, many species
- Brachiopods — still abundant on the seafloor
- Sharks
- Crinoids
- Nautiloids
- Rugose corals (single horn-shaped corals)

**Deep ocean (25%)**
- Sharks
- Large cephalopods
- Ray-finned fish

---

## EPOCH 4: JURASSIC
**~150 million years ago**

### Globe shape
Pangaea has broken into two main pieces: Laurasia in the north (North America + Europe + Asia) and Gondwana in the south (South America + Africa + Antarctica + Australia + India). A wide seaway called the Tethys Ocean separates them in the tropics. The North Atlantic is just beginning to open as a narrow sea. Sea levels are high, flooding much of the low-lying areas within both landmasses. The globe begins to look loosely recognisable — North America and Europe are connected but flooded. Africa and South America are still joined or very close. Antarctica is not polar — it sits further north and has forests.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 50% | Multiple ocean basins opening up |
| SHALLOW_SEA | 20% | High sea levels create wide shelves |
| INLAND_SEA | 14% | Sundance Sea (N. America), European archipelago seas |
| FOREST_DENSE | 18% of land | Primary land cover across most latitudes |
| FERN_LAND | 12% of land | Lowland fern and cycad areas |
| FOREST_LIGHT | 8% of land | Drier or higher elevation forest |
| SWAMP | 5% of land | Coastal and low-lying areas |
| DESERT | 7% of land | Some arid interior zones remain |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#2a5878` | Rich blue — warm greenhouse ocean |
| SHALLOW_SEA | `#4a8a9a` | Blue-green — warm shallow Jurassic seas |
| INLAND_SEA | `#6aaaba` | Lighter blue-green — flooded continental interior |
| FOREST_DENSE | `#2a5228` | Deep green — conifer and cycad canopy |
| FERN_LAND | `#5a9a45` | Bright mid-green — fern and horsetail lowlands |
| FOREST_LIGHT | `#3a6b35` | Rich mid-green — open woodland |
| SWAMP | `#1e4030` | Very dark green — coastal swamp and delta |
| DESERT | `#9a8850` | Warm khaki — arid interior zones |

### Land cover geography
- Forest covers almost all land at ALL latitudes — even the poles have temperate conifer forest (no ice anywhere on Earth in the Jurassic)
- FOREST_DENSE is the dominant tile across most of both landmasses
- FERN_LAND tiles appear in coastal lowlands and river plains
- SWAMP tiles at coastal edges and deltas — especially where inland seas meet the land
- DESERT only in the driest continental interiors — much less than the Permian
- No BARE_ROCK tiles needed on most land — the Jurassic world is green almost everywhere
- The European region is largely a shallow tropical archipelago — mostly SHALLOW_SEA and INLAND_SEA tiles with small island land tiles

### Sea geography
- The Sundance Sea covers what is now the western interior of North America — a large INLAND_SEA tile region running roughly north-south through the middle of the continent
- Europe is mostly underwater — only highland areas are land tiles; most of what is now France/Germany/UK is SHALLOW_SEA or INLAND_SEA
- The Tethys Ocean (now a wide warm seaway between Laurasia and Gondwana) is the dominant equatorial sea feature — make it wide and prominent
- Africa and South America just beginning to separate — a narrow SHALLOW_SEA strip between them

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 20% |
| Shallow sea | 35% |
| Inland sea | 15% |
| Land | 30% |

### Key animals by zone

**Land (30% of life) — the age of dinosaurs begins**
- Brachiosaurus — enormous long-necked sauropod, up to 26m, the visual icon of this epoch
- Stegosaurus — plated herbivore with spiked tail
- Allosaurus — large predatory theropod, the top land predator
- Diplodocus — extremely long-necked sauropod, up to 33m
- Archaeopteryx — first bird, feathered, small
- Pterosaurs — flying reptiles of various sizes soaring above the forests
- Compsognathus — small, fast, chicken-sized predatory dinosaur
- Mammal ancestors — small, shrew-like, nocturnal, largely hiding

**Shallow sea / Inland sea (50% combined)**
- Ichthyosaurs — dolphin-shaped marine reptiles, fast swimmers
- Plesiosaurs — long-necked marine reptiles
- Ammonites — diverse and extremely abundant, key zone indicator
- Belemnites — squid-like cephalopods
- Sharks
- Large marine crocodilians

**Deep ocean (20%)**
- Ichthyosaurs (open water)
- Large fish
- Ammonites and belemnites

---

## EPOCH 5: CRETACEOUS
**~90 million years ago**

### Globe shape
This is the most dramatically flooded globe in the game. Sea levels are at their all-time Phanerozoic high — roughly 200m above modern levels. The continents are more recognisable than in the Jurassic but are heavily flooded. North America is split in two by the Western Interior Seaway running from the Arctic to the Gulf of Mexico. Europe barely exists above water — it is a chain of tropical islands. South America and Africa have separated and the South Atlantic is now a real ocean but still relatively narrow. India is an island moving north toward Asia. Antarctica is near the south pole but still forested — no ice. The globe has the highest proportion of shallow inland sea tiles of any epoch.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 46% | Atlantic opening, Pacific dominant |
| SHALLOW_SEA | 20% | Widest shelves of any epoch |
| INLAND_SEA | 18% | Western Interior Seaway; European seaways; African seaways |
| FOREST_DENSE | 12% of land | Mixed conifer and angiosperm forest |
| FOREST_LIGHT | 8% of land | More open forest with flowering plants |
| FERN_LAND | 5% of land | Fern and cycad areas, increasingly patchy |
| SCRUB | 5% of land | Transitional flowering shrubland |
| VOLCANIC | 3% of land | Deccan Traps (India) — intensifying toward epoch end |
| DESERT | 2% of land | Small arid zones only |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#3a6888` | Warm deep blue — greenhouse ocean |
| SHALLOW_SEA | `#5a88a8` | Mid blue — warm chalk seas |
| INLAND_SEA | `#7aaac8` | Light blue — flooded continental interiors |
| FOREST_DENSE | `#4a7a38` | Olive green — mixed conifer and angiosperm |
| FOREST_LIGHT | `#6aa840` | Brighter green — angiosperms spreading, more open |
| FERN_LAND | `#5a8850` | Mid green — fern and cycad patches |
| SCRUB | `#88b858` | Lime green — flowering shrubs and low angiosperm plants |
| VOLCANIC | `#8a2a10` | Dark red — Deccan Traps volcanic region (India tile) |
| DESERT | `#b89860` | Warm tan — small arid zones |

### Land cover geography
- IMPORTANT: No grassland or meadow tiles — grass barely exists yet and certainly not as open plains
- Flowering plants (angiosperms) are spreading but mostly within forest — show this as a shift from the darker FOREST_DENSE to more varied FOREST_LIGHT and SCRUB tiles, not as open fields
- The brighter greens (FOREST_LIGHT, SCRUB) represent angiosperm-dominated patches vs the darker FOREST_DENSE for older conifer-dominated areas
- North America west of the Western Interior Seaway is lush and forested (where the dinosaurs are)
- Asia (connected to Europe) has more varied forest and some drier areas
- The India tile should have VOLCANIC coloring to represent the Deccan Traps activity
- Antarctica still has FOREST_LIGHT tiles — no ice

### Sea geography
- The Western Interior Seaway is the most important feature — it splits North America completely in two with INLAND_SEA tiles running north-south. Make it prominent, 4–8 tiles wide
- Europe is a scattered archipelago — mostly SHALLOW_SEA and INLAND_SEA tiles with only the highest areas as small land tile islands
- The Tethys Sea is still present between Laurasia and Africa — wide band of SHALLOW_SEA
- South Atlantic is a real but relatively narrow ocean — DEEP_OCEAN but narrower than today
- Chalk deposits across Europe form very pale shallow seafloor (this is where the name "Cretaceous" comes from — creta = chalk)

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 18% |
| Shallow sea | 32% |
| Inland sea | 20% |
| Land | 30% |

### Key animals by zone

**Land (30% of life) — the most iconic epoch**
- T. rex — apex predator of western North America (west of the seaway), the game's most recognisable creature
- Triceratops — three-horned herbivore, frilled, large
- Velociraptor — small feathered pack hunter (actual size: turkey, not Jurassic Park scale)
- Ankylosaurus — armoured, club-tailed herbivore
- Spinosaurus — enormous semi-aquatic predator (Africa)
- Pachycephalosaurus — dome-headed dinosaur
- Pteranodon — large pterosaur with wingspan up to 7m, soaring over the seaway
- Early flowering plants and the first bees/pollinators

**Shallow sea / Inland sea (52% combined)**
- Mosasaurs — enormous marine lizards up to 17m, the apex sea predator
- Plesiosaurs and Elasmosaurus (extremely long-necked)
- Xiphactinus — large aggressive predatory fish
- Ammonites — peak diversity in this period
- Sharks including Cretoxyrhina (large)
- Sea turtles including Archelon (giant, up to 4m)
- Hesperornis — flightless diving bird swimming in the inland seaway

**Deep ocean (18%)**
- Mosasaurs (open water)
- Large fish
- Ammonites

---

## EPOCH 6: EOCENE
**~45 million years ago**

### Globe shape
The continents are now broadly recognisable as the modern world, though with some key differences. South America is still an island — not yet connected to North America (no Panama). India is colliding with Asia, beginning to push up the Himalayas but not yet tall. Antarctica is still connected to South America via a land bridge and still has forests — no ice sheet yet. Australia has separated from Antarctica and is drifting north. The North Atlantic is fully open. The globe looks like a slightly unfamiliar version of the modern map — close but not quite right. Sea levels are higher than modern but not dramatically so.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 60% | Modern ocean basins mostly formed |
| SHALLOW_SEA | 16% | Less than Cretaceous — sea levels falling |
| INLAND_SEA | 8% | Tethys Sea remnant (proto-Mediterranean); some flooding |
| FOREST_DENSE | 20% of land | Tropical and subtropical jungle — very extensive |
| FOREST_LIGHT | 18% of land | Warm temperate forest at mid-latitudes |
| GRASSLAND | 8% of land | Early patchy grassland — new biome just appearing |
| SCRUB | 10% of land | Open woodland and savanna-edge |
| DESERT | 10% of land | Some arid zones but smaller than modern |
| SWAMP | 4% of land | Coastal tropical wetland |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#2a6888` | Warm blue — still a warm-ocean world |
| SHALLOW_SEA | `#4a88a8` | Mid blue — warm shallow shelves |
| INLAND_SEA | `#6aa8c8` | Light blue — Tethys remnant and coastal flooding |
| FOREST_DENSE | `#5a8a5a` | Muted deep green — tropical jungle |
| FOREST_LIGHT | `#4a7848` | Mid green — warm temperate forest |
| GRASSLAND | `#c8b478` | Pale straw — early, sparse grassland |
| SCRUB | `#8a7840` | Khaki gold — open woodland and savanna edge |
| DESERT | `#b89a60` | Warm tan — arid zones |
| SWAMP | `#3a6038` | Dark green — tropical coastal wetland |

### Land cover geography
- Tropical forest (FOREST_DENSE) extends much further from the equator than today — up to 45–50 degrees latitude in places. This is a very warm world (the PETM heat event peaks early in the Eocene — global average temperature ~14°C warmer than today)
- Even Antarctica has FOREST_LIGHT tiles — broad-leaved temperate forest across the continent
- Early GRASSLAND tiles appear but are small and patchy — place them sparingly at mid-latitudes and in drier continental interiors. This is the first epoch where grassland tiles exist but they are not dominant anywhere
- SCRUB tiles transition between forest and grassland — use them broadly at mid-latitudes
- The Tethys Sea remnant sits where the Mediterranean will be — shallow and shrinking

### Sea geography
- Globe broadly resembles the modern layout but with the following key differences:
  - No opening between South America and Antarctica — land bridge still exists
  - India is just hitting Asia — narrow sea still exists where the Himalayas will be
  - Tethys Sea remnant visible as INLAND_SEA tiles across the Middle East and into central Asia — shrinking but present
  - Higher sea level than modern means some extra coastal flooding — add 1–2 extra shallow sea tile rows around all coasts compared to modern

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 22% |
| Shallow sea | 38% |
| Inland sea | 10% |
| Land | 30% |

### Key animals by zone

**Land (30% of life) — mammals take over**
- Gastornis — enormous flightless predatory bird, 2m tall, the top predator in some regions
- Pakicetus / Ambulocetus — early walking whale, still land-capable, found near coasts
- Eohippus (Hyracotherium) — first horse, size of a small dog, forest browser
- Andrewsarchus — enormous wolf-like hoofed predator, possibly the largest land carnivore mammal ever
- Uintatherium — large rhino-like herbivore with horns and tusks
- Embolotherium — brontothere, early giant mammal
- Early bats — first flying mammals
- Giant ground birds at southern landmasses

**Shallow sea (38% of life)**
- Basilosaurus — enormous serpentine early whale, fully aquatic, up to 18m
- Modern-type sharks diversifying
- Large sea turtles
- Early sirenians (sea cows)
- Abundant fish diversity

**Deep ocean (22%)**
- Early cetaceans (whales)
- Sharks
- Large fish

**Inland sea / Tethys (10%)**
- Nummulites — giant disc-shaped foraminifera carpeting the seafloor in billions (the limestone of the Egyptian pyramids is made of them)
- Early dugongs
- Crocodilians in shallower areas

---

## EPOCH 7: PLEISTOCENE
**~1 million years ago**

### Globe shape
The globe looks almost exactly like the modern world — but colder and icier. The continents are in their current positions. However, sea levels are approximately 120m lower than today because so much water is locked in glaciers — this exposes significant land bridges and continental shelves. Beringia (connecting Alaska to Siberia) is dry land. The North Sea and English Channel are dry — Britain is connected to mainland Europe. The Indonesian archipelago is mostly connected into one large landmass (Sundaland). Ice sheets cover all of Canada, Greenland, most of Scandinavia, and much of northern Russia. Antarctica is under a massive ice sheet (bigger than today). The globe is visually dominated by white at the poles.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 64% | Sea levels low — oceans slightly smaller than modern |
| SHALLOW_SEA | 10% | Less than modern — shelves are dry land |
| INLAND_SEA | 1% | Almost none |
| ICE_SHEET | 18% of land | Canada, Scandinavia, N. Russia, Greenland, Antarctica |
| TUNDRA | 15% of land | Band below ice sheets — cold steppe grassland |
| FOREST_DENSE | 12% of land | Tropical forest compressed at equator |
| FOREST_LIGHT | 10% of land | Temperate forest south of tundra belt |
| GRASSLAND | 20% of land | Vast cold steppes — the mammoth steppe |
| DESERT | 10% of land | Cold deserts and warmer zone dry areas |
| SCRUB | 5% of land | Transitional zones |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#3a5068` | Dark cold blue — chilly glacial ocean |
| SHALLOW_SEA | `#5a7088` | Steel blue — cold shallow seas |
| ICE_SHEET | `#d8e8f0` | Pale blue-white — massive glaciers |
| TUNDRA | `#8a9a80` | Grey-green — cold permafrost steppe |
| FOREST_DENSE | `#4a7a3a` | Mid-dark green — compressed tropical forest |
| FOREST_LIGHT | `#6a8a58` | Muted olive-green — cold temperate forest |
| GRASSLAND | `#a0a868` | Grey-green straw — the mammoth steppe |
| COLD_STEPPE | `#8a9868` | Cooler grey-green — high latitude grassland |
| DESERT | `#c0a870` | Pale warm tan — cold desert and dry zones |

### Land cover geography
- ICE_SHEET dominates the entire northern half of North America (south to approximately modern Kansas), all of Scandinavia and northern Britain, most of northern Russia and Siberia, and all of Greenland
- Antarctica is entirely ICE_SHEET
- Below the ice, a broad band of TUNDRA and GRASSLAND (the mammoth steppe) — this stretches continuously from Western Europe all the way across Asia to the Bering land bridge and into Alaska
- The mammoth steppe is the largest single biome on Earth in this epoch — it should be visually prominent
- Tropical FOREST_DENSE survives at the equator but is compressed — smaller extent than modern day
- The exposed Beringia land bridge (Alaska-Siberia) should be TUNDRA tiles
- Sundaland (SE Asia joined up) is FOREST_DENSE — a large lush landmass connecting what are now islands

### Sea geography
- The North Sea tile should be dry land (TUNDRA or GRASSLAND) — Britain connects to Europe
- Bering Strait is dry — Beringia is a wide land bridge of TUNDRA tiles
- The Persian Gulf is largely dry land
- Indonesia/SE Asia is a large connected landmass — Sundaland
- Otherwise modern ocean configuration but with slightly reduced size due to lower sea levels — add 1–2 fewer shallow sea tile rows around coasts compared to modern

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 25% |
| Shallow sea | 30% |
| Land (temperate/tundra) | 30% |
| Land (tropical) | 15% |

### Key animals by zone

**Land — tundra/steppe (30% of life) — the most recognisable mega-fauna**
- Woolly mammoth — the icon of this epoch, large, hairy, tusked, living on the steppe in herds
- Woolly rhinoceros — hairy rhino, stocky, two horns
- Cave lion — largest lion ever, living in packs across the steppe
- Smilodon (sabre-toothed cat) — in the Americas
- Megatherium — giant ground sloth, size of an elephant (South America)
- Megaloceros — giant deer with enormous antlers spanning 3.7m
- Cave bear — enormous bear, major competitor with early humans
- Hyenas and giant wolves across Europe and Asia

**Land — tropical (15% of life)**
- Early elephants and hippos (Africa)
- Early humans — Homo erectus through to early Homo sapiens appearing toward end of epoch
- Giant tortoises on many island landmasses

**Shallow sea (30% of life)**
- Modern whale and dolphin species
- Modern sharks including great white
- Large fish diversity similar to today

**Deep ocean (25%)**
- Modern cetaceans
- Modern shark species

---

## EPOCH 8: HOLOCENE
**~10,000 years ago to present**

### Globe shape
Exactly the modern world — use this as the player's reference frame. Ice sheets have retreated to Greenland and Antarctica only. Sea levels have risen 120m from the Pleistocene low to modern levels, flooding the land bridges and coastal shelves. Britain is an island again. Beringia is underwater. Sundaland has broken into the Indonesian archipelago. All continents in their modern positions.

### Tile type distribution
| Tile type | % of globe | Notes |
|-----------|-----------|-------|
| DEEP_OCEAN | 63% | Modern ocean distribution |
| SHALLOW_SEA | 16% | Modern continental shelves |
| INLAND_SEA | 3% | Mediterranean, Persian Gulf, Hudson Bay, etc. |
| FOREST_DENSE | 12% of land | Amazon, Congo, SE Asia tropical forest |
| FOREST_LIGHT | 10% of land | Temperate broadleaf and boreal forest |
| GRASSLAND | 18% of land | African savanna, North American prairie, Central Asian steppe |
| DESERT | 22% of land | Sahara, Arabia, Australian outback, central Asia |
| TUNDRA | 8% of land | Arctic fringe — Alaska, N. Canada, Siberia |
| ICE_SHEET | 12% of land | Greenland + Antarctica only |
| WETLAND | 3% of land | Major river deltas and flood plains |
| SCRUB | 5% of land | Mediterranean, California, S. Africa fynbos |

### Tile colour palette
| Tile type | Hex | Description |
|-----------|-----|-------------|
| DEEP_OCEAN | `#2858a0` | Vivid blue — the modern Earth seen from space |
| SHALLOW_SEA | `#4878c0` | Medium blue — modern coastal seas |
| INLAND_SEA | `#6898d0` | Lighter blue — marginal seas |
| FOREST_DENSE | `#2a6a5a` | Dark teal-green — tropical rainforest |
| FOREST_LIGHT | `#4a8a3a` | Mid green — temperate forest |
| GRASSLAND | `#c8d870` | Yellow-green — savanna and prairie |
| DESERT | `#d4c090` | Warm sand — arid zones |
| TUNDRA | `#8a9878` | Grey-green — arctic tundra |
| ICE_SHEET | `#e0eef8` | White-blue — Greenland and Antarctica |
| WETLAND | `#3a7050` | Dark green — wetland and delta |
| SCRUB | `#a8b858` | Olive-green — mediterranean scrub |

### Land cover geography
- This is the reference epoch — follow modern Earth geography exactly
- DESERT dominates North Africa (Sahara), Arabian Peninsula, central Australia, Atacama (S. America coast), Gobi (central Asia)
- FOREST_DENSE concentrated in Amazon basin, Congo basin, and SE Asian archipelago
- GRASSLAND covers African savanna, North American Great Plains, Argentine Pampas, central Asian steppe
- FOREST_LIGHT across Europe, eastern North America, eastern Asia (China/Japan/Korea)
- ICE_SHEET on Greenland and Antarctica only
- TUNDRA fringe along the Arctic coast of North America, Europe, and Asia

### Life zone breakdown
| Zone | % of all life |
|------|--------------|
| Deep ocean | 20% |
| Shallow sea | 30% |
| Land (temperate/grassland) | 25% |
| Land (tropical) | 25% |

### Key animals by zone

**Land — tropical (25%)**
- African elephant, gorilla, chimpanzee
- Tigers, jaguars, leopards
- Hippos, crocodiles, giant anacondas
- Colourful birds — toucans, parrots, birds of paradise

**Land — temperate/grassland (25%)**
- Lion, cheetah, wildebeest, zebra (savanna)
- Bison (North American prairie)
- Bears, wolves, deer (temperate forest)
- Humans — Homo sapiens — the dominant species and the creature the player is presumably trying to make extinct

**Shallow sea (30%)**
- Whales — blue whale, humpback, sperm whale
- Dolphins and porpoises
- Great white shark, hammerhead
- Coral reef ecosystems — the most biodiverse marine habitat
- Sea turtles, manta rays

**Deep ocean (20%)**
- Sperm whales and giant squid
- Deep sea fish — anglerfish, viperfish
- Modern shark species

---

## IMPLEMENTATION NOTES FOR CLAUDE CODE

### Tile placement rules
1. Always check latitude when placing land tiles — many biomes are strictly latitude-limited (e.g. coal forests only near equator in Carboniferous)
2. Shallow sea tiles should always appear between land and deep ocean — never have land tiles directly adjacent to deep ocean tiles (there is always a shelf)
3. Inland sea tiles sit on what would otherwise be land — they are low-lying flooded continental areas, not part of the ocean proper
4. VOLCANIC tiles should be rare (1–3 tiles maximum) and placed at known geological hotspots for each epoch
5. Transition tiles: where two biomes meet, use the intermediate tile type for 1–2 tiles (e.g. FOREST_DENSE → FOREST_LIGHT → GRASSLAND, never FOREST_DENSE directly next to GRASSLAND)

### Life zone display
- Each tile type belongs to exactly one life zone: DEEP_OCEAN tiles → deep ocean zone; SHALLOW_SEA + INLAND_SEA → shallow/inland sea zone; all land tiles → land zone
- When displaying life for an epoch, weight creature appearance frequency by the life zone percentages given above
- Featured creatures should appear on tiles matching their zone — do not show land creatures on sea tiles or vice versa

### Colour temperature across epochs
- Carboniferous → Permian → Jurassic → Cretaceous: ocean progressively shifts from warm teal toward warmer blue as the world remains a greenhouse
- Eocene → Pleistocene: ocean shifts from warm blue to cold slate blue as the world cools
- Holocene: vivid modern blue — the most saturated ocean colour in the game
- The Permian land tiles should be the most visually striking contrast — the only epoch with almost no green on land at all

### Globe distinctiveness checklist
Each epoch should be immediately visually distinct. Key identifiers:
- Cambrian: mostly ocean, bare tan rock, bright turquoise shallow sea
- Carboniferous: thick dark green equatorial band, significant tundra/ice at south pole
- Permian: one continent (asymmetric globe), orange-rust desert, deep blue ocean
- Jurassic: lush green everywhere including poles, lots of inland sea, no ice
- Cretaceous: most flooded — lots of inland sea tiles, North America split in two
- Eocene: near-modern layout but greener at high latitudes, no Antarctic ice
- Pleistocene: white polar caps dominant, grey-green steppe belt, compressed tropical forest
- Holocene: vivid modern Earth — the most colourful and varied palette

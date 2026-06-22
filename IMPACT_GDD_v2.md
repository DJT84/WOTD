# IMPACT — Game Design Document v2

*A short incremental game about the end of everything. You wipe out life on Earth, age by age. Entropy climbs. The scale grows monstrous. And there is always a bigger rock.*

Solo dev. Godot 4. Steam.

---

## What kind of game this is

This is an incremental game. Not idle — you play it actively — but the numbers keep climbing on their own underneath.

The heart of it is a number that grows.

- You destroy life. Every bit of destruction raises Entropy and drops Dust.
- Entropy is your score. It only ever goes up. You never spend it.
- Dust is your currency. You spend it on upgrades.
- Upgrades make you destroy faster and bigger.
- So both numbers climb faster and faster.
- They keep climbing even when you are not playing.

That growing number is the game. Everything else feeds it.

---

## Tone

Fun first. Impacts feel satisfying — big screen shake, chunky sound, rewarding visual feedback. Extinctions land with a good thud of completion. The animals are a little charming. The tone is cosmic absurdity more than cosmic solemnity.

The ending is where the restraint lives. The game can be loud and fun right up until the final cutscene. Then the music stops. No celebration. Just the rock.

---

## The escalation

Six ages of Earth's history. Each age is a big jump in scale. Early on you wipe out a few thousand tiny ocean creatures. By the end you are ending billions. The numbers get huge. Reaching a new age should feel like a step up into something vast.

---

## Where Entropy and Dust come from

Two sources simultaneously.

**Bombardment (automatic).** Small asteroids fall on their own continuously. They chip at life, raising Entropy and trickling Dust with no player input. This keeps growth happening even when the player stops. Upgrades make bombardment faster, heavier, and wider.

**Aimed strikes (active).** The player drags large asteroids onto life clusters. Worth far more per hit than bombardment. This is where the player pushes growth hard.

The bombardment is always weaker per hit than aimed shots. A player can idle slowly or play actively and grow fast.

---

## The aimed strike

1. An asteroid sits ready in a slot at the bottom of the screen.
2. Player drags it onto a life cluster and releases.
3. It always hits. Impact animation plays. Player gains Entropy and Dust. Chain Reactions may trigger.
4. That slot goes on cooldown. A visible timer fills. When full, slot is ready again.

Player starts with 3 slots, each on independent cooldown. Cooldown is tuned so good targets appear faster than slots recharge — the player can never hit everything and must always choose. That choice is the game.

---

## Upgrades

The engine of the game. Spend Dust to grow faster. Faster growth means more Dust, which buys the next upgrade.

The store is always one tap away. Opening it **pauses the game world**. Closing resumes it. There is no between-levels screen — the game never stops.

### Four upgrade groups

**Bombardment** (automatic income)
- Faster — more rocks fall per second
- Heavier — more damage and Entropy per rock
- Wider — larger blast radius per rock

**Asteroids** (aimed shots)
- Bigger rock — more power and wider blast. Tiers named after real impacts in ascending size: Chelyabinsk → Barringer → Tunguska → Chicxulub → Vredefort
- More slots — more shots ready simultaneously (starts at 3)
- Shorter cooldown — slots recharge faster

**Chain Reactions** (bonus destruction)
- Higher trigger chance on hit
- Stronger triggered events
- Higher chance one event chains into another

**Environmental Impact** (suppress regrowth)
- Higher trigger chance
- Stronger suppression
- Longer suppression duration

Plus global multipliers: all-Dust multiplier, larger extinction bonus.

New upgrades unlock as new ages are reached. Ages and upgrades are **data-driven** — defined in resource files, not hardcoded — so tuning requires no code changes.

*v2 scope: asteroid types (comet, metal, ice). Not in v1.*

---

## The ages

Each age has its own colour palette, life cluster appearance, species set, and number scale. The numbers jump significantly each transition.

| # | Age | Life |
|---|-----|------|
| 1 | Cambrian | Strange ocean creatures |
| 2 | Carboniferous | Giant insects, swamp life |
| 3 | Jurassic | Early dinosaurs |
| 4 | Cretaceous | T-Rex and late dinosaurs |
| 5 | Pleistocene | Mammoths, ice age megafauna |
| 6 | Holocene | Modern world — hardest age |

Each extinction the player causes clears the stage for what comes next. The chain of life and extinction runs through all six ages.

---

## The planet — technical specification

### Architecture: 3D Geodesic Sphere in Godot 4

The planet is a **3D geodesic sphere** built from a subdivided icosphere. This is the core visual object of the game and must be implemented correctly before anything else.

**Do not use a cylinder. Do not fake the sphere in 2D. The full circle of the planet must be visible from all angles.**

#### Geodesic sphere generation

Use the **Goldberg polyhedron / subdivided icosphere** approach:

1. Start with a regular icosahedron (20 triangular faces, 12 vertices)
2. Subdivide each triangular face N times (N=4 or N=5 gives a good tile count)
3. Project all vertices onto the unit sphere (normalise each vertex position)
4. Dual the mesh: convert triangular faces to their dual polygons — this produces hexagonal tiles with exactly 12 pentagonal tiles at the original icosahedron vertices
5. Each resulting polygon is one surface tile

This gives approximately:
- N=3: ~80 tiles
- N=4: ~162 tiles  
- N=5: ~252 tiles

**Recommended: N=4 (162 tiles).** Enough tiles for interesting play, not so many the planet looks noisy.

#### Pentagon handling

There will be exactly 12 pentagonal tiles. These cannot be avoided mathematically. Since tiles are generated procedurally from actual vertex positions, pentagons are built correctly as 5-sided polygons — no scaling hack needed. Flag them as `is_pentagon: true` and either assign them landmark status or leave them as low-priority background tiles with no life spawned.

#### Tile data structure

Each tile needs:
```
tile_id: int
center_position: Vector3        # on unit sphere surface
normal: Vector3                 # outward from sphere centre (same as normalised position)
neighbours: Array[int]          # adjacent tile IDs
is_pentagon: bool
terrain_type: String            # "ocean", "land", "any" — matches species tile_preference
landmark_type: String           # "" = none, "mountain", "volcano", "vent", "ice", etc.
is_volcano: bool                # flagged separately for chain reaction targeting
damage_state: int               # 0=healthy, 1=damaged, 2=scorched
life_count: float               # current life population (0.0 if landmark tile)
life_suppressed: bool           # environmental impact active
suppression_timer: float        # remaining suppression duration
```

#### Tile mesh and assets

Tile meshes are **generated procedurally in GDScript** using the dual mesh vertex positions. Each tile is an `ArrayMesh` built from its actual polygon vertices, placed at `center_position` and oriented so its local Y-axis matches `normal`. This guarantees gapless coverage of the sphere with no asset dependency.

Apply per-age colour and damage state via ShaderMaterial uniforms. The shader handles:
- Base colour (age palette, swapped via uniform)
- Edge darkening (face normal calculation gives tile definition without needing border geometry)
- Damage state interpolation (lerp between three colour/emission values via a single float uniform)
- Life density overlay (secondary colour driven by `life_count`)

No external mesh asset is needed for tiles. Do not use the Kenney Hexagon Kit for tile geometry.

The planet rotates continuously on its Y-axis. Rotation speed: approximately 1 full rotation per 90 seconds (tunable). It never stops.

#### Landmarks

Landmarks are 3D meshes placed on top of tile surfaces — same placement pattern as everything else (position at tile center, orient along normal, child of the planet node so they rotate with it). Scale is deliberately exaggerated: mountains and volcanoes should read clearly from the camera distance and feel charming, not realistic.

Each tile has an optional `landmark_type` field. Landmark tiles have `life_count = 0` — they are terrain, not habitat.

**Landmark types by age:**

| Age | Landmarks |
|-----|-----------|
| Cambrian | Hydrothermal vents, sea rock spires |
| Carboniferous | Giant fern clusters, swamp dead trees |
| Jurassic | Volcanoes, dense jungle canopy clumps |
| Cretaceous | Volcanoes, large rock formations |
| Pleistocene | Ice sheet slabs, glaciers |
| Holocene | City clusters (visible as geometry, not just colour) |

Volcanoes are flagged separately (`is_volcano: bool` on tile data) so that Volcano chain reaction events always fire visually from a real volcano tile. When a Volcano chain reaction triggers, the nearest visible volcano tile erupts — particle burst fires from that world position.

**Assets:** Use **Kenney Nature Kit** or **Kenney Isometric** packs for landmark meshes (mountains, trees, rocks). These are standard shapes that work placed on a sphere surface. Import as GLB, apply ShaderMaterial for age palette consistency.

Landmark density: approximately 15–20% of tiles. The planet needs readable negative space between landmarks and life clusters.

#### Camera

Fixed camera positioned outside the sphere, looking at its centre. Slightly elevated (about 20° above equator). The player never moves the camera. The planet rotates; the camera stays still.

This means the player can only see roughly half the planet at any time. Tiles rotate into and out of view. This is intentional — it creates the "wait or hit now?" tension.

#### Tile visibility

A tile is **visible** if its normal vector has a positive dot product with the camera direction vector. Invisible tiles (on the back of the planet) exist in the simulation but are not interactive and not rendered in full detail.

---

## Life on the planet

Life appears as clusters of coloured squares sitting on tile surfaces. These are 2D billboarded sprites on the 3D surface, or small instanced 3D meshes — whichever is cheaper to render at quantity.

- Each tile has a `life_count` float (0.0 to 1.0, scaled to actual population by age multiplier)
- Visual density of the cluster reflects `life_count`
- Colour and appearance change per age

### Damage states

The tile surface has three visual states driven by `damage_state`:

| State | Appearance |
|-------|-----------|
| 0 — Healthy | Age palette colour (green for Cambrian, etc.) |
| 1 — Damaged | Brown, scorched edges |
| 2 — Scorched | Black with orange cracks |

Implement as a ShaderMaterial with a uniform for damage state. Interpolate between states visually.

### Regrowth

If a tile is not suppressed and not actively being hit, `life_count` slowly increases over time toward 1.0. Rate is tunable per age. This creates the background tug-of-war — the player must stay ahead of regrowth.

Regrowth is visible: the player can watch life returning to a tile.

### Hover inspection

When the player hovers over a life cluster:
- A UI panel appears (CanvasLayer, not world space)
- Shows: animal 2D picture, species name, current population count, Entropy and Dust value if hit now
- Panel disappears when cursor moves away

The 2D animal pictures are the only non-geometric art assets in the game. They are not rendered on the planet surface — only in this panel.

---

## Aimed strike — implementation

### Asteroid slots

- Rendered as a UI bar at the bottom of the screen (CanvasLayer)
- Each slot shows: asteroid mesh preview, cooldown timer as a filling arc or bar
- Slot states: READY, DRAGGING, COOLDOWN

### Drag and drop

1. Player clicks/presses on a READY slot
2. Asteroid follows cursor/finger in world space (raycasted onto a sphere slightly outside the planet)
3. On release: check if release point is over a visible life tile
4. If yes: trigger impact at that tile
5. If no (released in empty space): return asteroid to slot, no cooldown penalty

### Impact resolution

On impact:
1. Calculate Entropy gain: `base_entropy * life_count * age_multiplier * asteroid_size_multiplier`
2. Calculate Dust gain: `base_dust * life_count * age_multiplier * asteroid_size_multiplier`
3. Reduce `life_count` on hit tile and neighbouring tiles (blast radius depends on asteroid tier)
4. Update `damage_state` on affected tiles
5. Play impact animation and screen shake
6. Roll for Chain Reaction
7. Roll for Environmental Impact
8. Check extinction conditions
9. Start slot cooldown

---

## Visual effects — implementation

All effects use **GPUParticles2D** projected onto the planet surface, or **GPUParticles3D** in world space. Use screen shake for all impact events via a reusable Tween function called by every event type.

### Screen shake

Single reusable function. Called by every impact, chain reaction, and environmental event. Intensity scales with event size.

```gdscript
func shake(intensity: float, duration: float):
    var tween = create_tween()
    tween.tween_method(apply_camera_offset, Vector3.ZERO, 
        Vector3(randf_range(-1,1), randf_range(-1,1), 0) * intensity, 
        duration * 0.5).set_trans(Tween.TRANS_SINE)
    tween.tween_method(apply_camera_offset, 
        Vector3(randf_range(-1,1), randf_range(-1,1), 0) * intensity,
        Vector3.ZERO, duration * 0.5).set_trans(Tween.TRANS_SINE)
```

### Impact (player asteroid hit)

- Large burst of particles from impact point, outward
- Colour: orange-white core, grey debris
- Screen shake: heavy
- Duration: ~0.8 seconds

### Volcano (chain reaction)

- Particle burst upward from tile, gravity pulls back
- Colour: orange-red, dark smoke
- Spreads damage to tiles in a radius around trigger point
- Screen shake: medium

### Tsunami (chain reaction)

- Directional sweep of blue-teal particles moving laterally across a band of tiles
- Affects a line of tiles in the sweep direction
- Screen shake: medium

### Earthquake (chain reaction)

- Screen shake: heavy, longer duration
- Crack/ripple effect running along a line of tiles
- Tiles in line shift slightly then return
- Implement as AnimatedSprite3D or shader distortion on affected tiles

### Dust cloud / Impact winter (environmental impact)

- Slow-spreading grey particle bloom from trigger point
- Persists visually for duration of suppression
- Fades out as suppression_timer expires
- Low particle count, lingers — different feel from the fast violent events

**Key principle: all four event types are variations of two particle patterns (burst and sweep) with different colours, directions, and speeds. Build one, reskin the others.**

---

## Chain Reactions

On any impact, roll against `chain_reaction_chance` (starts at 5%, upgradeable):

1. If triggered, randomly select event type: Volcano, Tsunami, or Earthquake
2. Each type has a defined area of effect shape (radius, line, sweep)
3. Apply damage to life in that area
4. Roll again against `chain_chain_chance` — if triggered, fire a second event
5. Maximum chain depth: 3 (to prevent runaway recursion)

---

## Environmental Impact

On any impact, roll against `env_impact_chance` (starts at 5%, upgradeable):

1. If triggered, randomly select: Dust Cloud or Impact Winter
2. Set `life_suppressed = true` and `suppression_timer = base_duration * suppression_strength` on affected tiles
3. While suppressed, regrowth rate = 0
4. Timer counts down each frame; when expired, suppression clears

---

## Extinctions

Each age defines a set of target species. Each species has a total population across all tiles. When a species' total population reaches 0, it is extinct.

On extinction:
- A large free asteroid spawns immediately (bypasses slots, no cooldown)
- Size of reward scales with species significance (defined per species in age data)
- A 2D stamp of the animal flashes on screen for 2 seconds then fades (satisfying thud, not a trophy)
- Species is removed from the active list
- When all species in an age are extinct, transition to next age

---

## Age transitions

When all species in an age are extinct:

1. Planet colour palette lerps to next age palette over 2 seconds
2. Old life clusters fade out
3. New life clusters spawn on tiles using new age settings
4. Number multipliers jump up significantly
5. New upgrades unlock in the store
6. A brief title card shows the new age name

The transition should feel like a step up into something larger.

---

## Heat Death — prestige system

After completing all six ages and watching the ending, the player is offered:

*"The universe has reached maximum entropy. Begin again?"*

On confirm:
- All Dust and upgrades reset
- Ages reset to Cambrian
- Permanent starting bonuses for the next run are **automatically calculated** from total Entropy accumulated in the completed run — no secondary currency, no spending step

### Prestige bonus formula

All bonuses scale continuously with final Entropy using a logarithmic curve, so early runs produce meaningful bonuses but diminishing returns prevent trivialisation. The formula for each bonus:

```
prestige_power = clamp(log10(final_entropy / ENTROPY_THRESHOLD), 0.0, 1.0)
```

Where `ENTROPY_THRESHOLD` is the minimum Entropy expected from a completed run (tuned in data). `prestige_power` runs from 0.0 (bare minimum completion) to 1.0 (maximum efficient run).

Each bonus interpolates between its base value and its cap:

| Bonus | Base (prestige_power = 0) | Cap (prestige_power = 1) |
|-------|--------------------------|--------------------------|
| Bombardment strength multiplier | 1.0× | 2.0× |
| Slot cooldown reduction | 0% | 30% |
| Chain reaction base chance | 5% | 10% |
| Global Dust multiplier | 1.0× | 1.5× |

These bonuses apply from the first second of the new run. They are not displayed as a currency — the player just starts noticeably faster.

### Tuning principle

Run 2 should feel noticeably faster in the early ages but the late ages should still require work. Prestige bonuses accelerate; they do not trivialise. The ending must still be earned.

The ending cutscene plays in full on every prestige. No skipping.

---

## The ending (cutscene)

Triggers after final Holocene species is extinct.

1. Planet rotation slows to a stop
2. All particle effects fade
3. Camera pulls back slowly — planet shrinks in frame
4. Strange new life appears on planet surface in wrong colours: purple, amber, blue-green
5. Camera continues pulling back, through asteroid belt geometry (simple instanced rocks)
6. One rock. Twice the size of anything the player threw. Motionless in frame.
7. Hold on it for 3 seconds.
8. No words. Title card: IMPACT fades in. Credits roll.

Implement as a scripted AnimationPlayer sequence taking control from the game loop. Separate scene if cleaner.

---

## Data-driven architecture

**Critical requirement.** Ages and upgrades must be defined in Resource files (.tres or .json), not hardcoded. This allows tuning without code changes.

### Age resource (per age)

```
age_name: String
palette_primary: Color
palette_secondary: Color
palette_scorched: Color
life_scale_multiplier: float        # population numbers this age
entropy_multiplier: float           # Entropy gained per hit this age
dust_multiplier: float              # Dust gained per hit this age
species: Array[SpeciesResource]
bombardment_rate_modifier: float
```

### Species resource (per species)

```
species_name: String
animal_texture: Texture2D           # the 2D picture
extinction_reward_size: int         # 1=small, 2=medium, 3=large free asteroid
starting_population: float          # 0.0-1.0 tile density
tile_preference: String             # "ocean", "land", "any"
```

### Upgrade resource (per upgrade)

```
upgrade_id: String
display_name: String
description: String
group: String                       # "bombardment", "asteroid", "chain", "env"
cost_base: float
cost_scaling: float                 # multiplier per level
max_level: int
effect_per_level: float
unlocks_at_age: int                 # 0 = available from start
```

---

## Save and load

Save to user:// using Godot's FileAccess. Save on every upgrade purchase, age transition, and extinction. Auto-save every 60 seconds.

Save data includes:
- Current Entropy (never resets even on prestige within a run)
- Current Dust
- All upgrade levels
- Current age
- All species population states
- All tile damage states
- Echo count and Echo upgrade levels (persists through prestige)
- Total runs completed

---

## UI layout

All UI on a CanvasLayer above the 3D scene.

- **Top bar**: Entropy (left), Dust (right) — large, always visible
- **Asteroid slots**: Bottom centre — slot previews with cooldown arcs
- **Store button**: Bottom right corner — always visible, one tap
- **Hover panel**: Appears near cursor on cluster hover, disappears on move
- **Extinction stamp**: Centre screen, fades in/out over 2 seconds
- **Age title card**: Centre screen on transition, fades after 3 seconds

Store opens as a separate CanvasLayer. Opening it calls `get_tree().paused = true`. Closing resumes. Store UI scrolls vertically through four upgrade groups.

---

## Art and assets

Everything geometric and abstract except animal pictures.

- Planet tiles: Kenney Hexagon Kit meshes, colour via ShaderMaterial
- Life clusters: instanced simple meshes or billboarded sprites
- Asteroids: simple low-poly rock meshes (can be Kenney or procedural)
- Animal pictures: one flat 2D illustration per major species — the only hand-drawn art
- Reuse each animal picture in: hover panel, extinction stamp, menus, marketing

---

## Build order

- **Weeks 1–2**: Core feel. Rotating geodesic sphere. Tiles with damage states. Bombardment raising Entropy and Dust automatically. One draggable asteroid. One life cluster that dies with a satisfying animation and screen shake. If this isn't fun, fix it before moving on.
- **Week 3**: All slots and cooldowns. Full upgrade store. Save and load.
- **Week 4**: All six ages with data resources. Age transitions. Extinctions and stamps.
- **Week 5**: Chain reactions. Environmental impact. Heat Death prestige.
- **Week 6**: The ending cutscene. Sound. Polish.
- **Weeks 7+**: Steam page. Balancing. Launch.

---

## The one rule

If an idea isn't Entropy climbing, or doesn't make it climb better, leave it out of v1.

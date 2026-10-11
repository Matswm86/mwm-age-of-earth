# Age of Earth: visual design spec

Owner: graphic-designer. Version 1, 2026-10-11. The builder reads this before touching any colour, light, material, model or UI node. Every token carries its rule and its reason. Binding inputs: owner verdict 2026-10-11 ("graphics too weak... models from Sketchfab across the whole game... shades, lighting, objects, everything higher quality") and the owner rule of the same day: **photorealistic, as high-end as possible; no low-poly, stylized, cartoon, toy, Roblox or Minecraft look**. Studio rule: new 3D games are modern realistic high-end. This overrides the "stylized, never photoreal" line in the studio template section 10.

Look target render: `docs/mockups/look_target.jpg` (Blender, `tools/art/look_target.py`). Terrain: `assets/terrain/rift_lake/` (`tools/terrain/cop_to_game.py`). Models: `assets/models/<kind>/` (`tools/assets/process_assets.py`, `tools/assets/retarget_char.py`). Sources and licences: `CREDITS.md`.

## 1. Visual theme

**A real late-afternoon hour on the West Turkana shore, seen from a low helicopter: sun-cured grass and dark lava cobbles on a grey-brown gravel plain, acacias and doum palms along dry stream beds, the green "Jade Sea" of Lake Turkana, long warm shadows.** Nothing is painted or exaggerated; the game reads through light, silhouette and placement, not through saturated colour.

References (what to take, nothing else):
- **Real photos of the West Turkana shore near Lomekwi and Nariokotome** (Turkana Basin Institute and field-season photos): the colour of the ground (grey-brown, not orange), dark basalt cobble pavement, sparse yellow tussocks, Acacia tortilis umbrella crowns, doum palm (Hyphaene) stands along laggas, the jade-green lake with a pale silt band at the shore. This is the colour authority; when a screen and a photo disagree, the photo wins.
- **Age of Empires IV / Company of Heroes 3 at default zoom**: how a realistic RTS stays readable. Take: units lifted by a team-coloured ground disc and rim light, ground detail kept low-contrast so units pop, foliage that never hides units (canopy fade). Do not take their UI or any art.
- **Microsoft Flight Simulator 2024 low-altitude passes over East Africa**: the haze, the low-sun warmth, and how real terrain texture looks from 50-150 m.

## 2. Palette (sRGB hex = Godot `Color(r, g, b)`)

### 2.1 World (lighting and materials must land on these on screen; checked from the look target)
| Token | Hex | Godot | Use | Why |
|---|---|---|---|---|
| ground_straw | #B49A6A | Color(0.706, 0.604, 0.416) | dry grass plain, the 60 % | Turkana dry season |
| ground_gravel | #8C7B60 | Color(0.549, 0.482, 0.376) | gravel pavement between tussocks | real colour, not orange |
| red_earth | #8A5236 | Color(0.541, 0.322, 0.212) | patches, trampled camp floors | laterite soil, used sparingly |
| basalt | #3A3633 | Color(0.227, 0.212, 0.200) | boulders, cobbles, ridges | Nachukui lavas |
| shore_sand | #A89878 | Color(0.659, 0.596, 0.471) | beach ridges | grey volcanic sand |
| wet_mud | #4E4234 | Color(0.306, 0.259, 0.204) | 0-2.5 m from the waterline | wet band |
| acacia_leaf | #6B7344 | Color(0.420, 0.451, 0.267) | acacia, shrubs | dusty olive, never lawn green |
| doum_green | #7E8A4E | Color(0.494, 0.541, 0.306) | doum palm fronds | |
| jade_deep | #2F6E62 | Color(0.184, 0.431, 0.384) | lake beyond 4 m depth | the "Jade Sea" (algae colour) |
| jade_shallow | #5E8C6E | Color(0.369, 0.549, 0.431) | 1-4 m depth | |
| silt_shallow | #7D7A5A | Color(0.490, 0.478, 0.353) | 0-1 m depth | silty edge |
| foam | #D9D4C4 | Color(0.851, 0.831, 0.769) | broken waterline foam | never pure white |
| haze | #C8B89A | Color(0.784, 0.722, 0.604) | depth fog colour | warm dust haze |
| sun | #FFDDB4 | Color(1.000, 0.867, 0.706) | DirectionalLight3D colour | ~4300 K late afternoon |

### 2.2 Teams and markers (the 10 % accent: the brightest, most saturated things on screen are always player-relevant)
| Token | Hex | Godot | Use | Contrast (my calc, WCAG luminance) |
|---|---|---|---|---|
| team_ochre (player) | #C4421E | Color(0.769, 0.259, 0.118) | body paint + ground disc | paint vs skin #4A3428: 2.3:1, so it also needs the disc |
| team_kaolin (rival 1) | #E6E0D2 | Color(0.902, 0.878, 0.824) | white clay paint + disc | vs skin 8.8:1 |
| team_yellow (rival 2, 1v2 only) | #E0B040 | Color(0.878, 0.690, 0.251) | yellow ochre paint + disc | vs skin 5.8:1; vs ground 1.0:1, so its disc gets the dark outline |
| select | #9BE07A | Color(0.608, 0.878, 0.478) | selection ring, move marker (GDD 12: green) | vs ground 1.7:1 alone; with 2 px #1E1C1A outline the outline is 6.3:1 |
| attack | #D2452D | Color(0.824, 0.271, 0.176) | attack marker, under-attack pulse | |
| outline | #1E1C1A | Color(0.118, 0.110, 0.102) | 2 px outline on rings/discs | 6.3:1 on ground_straw |

Split on screen: ~60 % ground (straw, gravel), ~30 % basalt, foliage and water, ~10 % team paint, rings, fire, UI.
No purple anywhere in UI chrome. Team colours never use purple or blue (blue is the water, purple is banned in UI).

### 2.3 HUD (light by default, readable first)
| Token | Hex | Godot | Use | Contrast (my calc) |
|---|---|---|---|---|
| panel | #F2ECE0 | Color(0.949, 0.925, 0.878) | HUD panels at 92 % opacity | |
| panel_alt | #E3D6BC | Color(0.890, 0.839, 0.737) | selected tab, card | |
| text | #2A2620 | Color(0.165, 0.149, 0.125) | body text, numbers | 12.8:1 on panel, 10.5:1 on panel_alt |
| text_dim | #5A5246 | Color(0.353, 0.322, 0.275) | captions | 6.5:1 on panel |
| primary | #2F6E62 | Color(0.184, 0.431, 0.384) | main action buttons (white label) | white on it 5.95:1 |
| danger | #8E2A14 | Color(0.557, 0.165, 0.078) | destructive / under attack (white label) | white on it 8.4:1 |

## 3. Typography
**Inter** (SIL Open Font License 1.1, https://github.com/rsms/inter): one family, tabular figures on for resource counters. Sizes at 1920 x 1080 landscape: resource numbers 40 px SemiBold, body and tooltips 36 px, button labels 36 px SemiBold, age title card 96 px Light (white with a 30 % black drop shadow over the 3D view). Never below 32 px on the phone.

## 4. Components
- Buttons: min 130 x 130 px (48 dp), 24 px gaps, corner radius 18 px, pressed = panel_alt + 2 px inset. Command card buttons show a photographic icon (rendered from the game's own models, section 9) on panel.
- Resource bar: top-left, panel 92 %, icons 56 px (food = fig cluster, wood = branch, stone = cobble, ochre = red lump), all rendered from the real models.
- Selection ring: flat ring decal 0.62 m radius for hominins, 1.0 m animals, building footprint + 0.5 m for buildings; 6 cm line, select colour with 2 px outline; scale 0 -> 1 in 120 ms (GDD 12).
- Team disc: always under every hominin, 0.55 m radius soft disc in team colour at 35 % alpha, multiplied onto the ground; doubles as the contact shadow.
- Health bar: only when damaged or selected, 48 x 6 px above the unit, team colour fill on outline.

## 5. Layout (landscape)
Safe-area margins 48 px. Resource bar top-left; minimap bottom-left 300 x 300 px; command card bottom-right (thumb zone); selection portrait strip bottom-centre. Nothing permanent in the middle 60 % of the screen.

## 6. Depth and motion
UI tweens 0.15-0.25 s ease-out. Camera: eased only; age-up pull-up 1.5 s (GDD 12). Screen shake: none, except 4 px for 0.2 s when the Home Tree takes a hit. Particles only at focal points (section 7.8).

## 7. Game art

### 7.1 Lighting recipe, Godot 4.6 Mobile renderer
Mobile supports: LightmapGI, ReflectionProbe, depth/height fog, glow, tonemapping, adjustments, MSAA, decals. Mobile does **not** support SSAO, SSIL, SSR, SDFGI, VoxelGI, volumetric fog, TAA, subsurface scattering (Godot docs "Renderers" comparison table, read 2026-10-11). Everything below stays inside that list.
- **Sky:** `WorldEnvironment` with `PanoramaSkyMaterial` = Poly Haven `qwantani_late_afternoon` (CC0), 2K LDR/HDR, rotated so its sun sits at the sun azimuth (the look-target script solves the rotation). Background energy 1.0; the sky is mostly off-screen at RTS pitch, it matters for ambient and water reflection.
- **Ambient:** source Sky, energy 0.6, sky contribution 1.0. Reflected light source Sky.
- **Sun:** one `DirectionalLight3D`, elevation **20 degrees**, azimuth **258 degrees** (WSW, shadows fall ENE toward the lake), colour `sun` #FFDDB4, energy 1.6 (tune so ground_straw lands at #B49A6A on screen), angular size 1.2 degrees (soft edge). Fixed: no day/night in v1 (GDD 10).
- **Shadows:** PSSM 2 splits, max distance 120 m (the RTS view never shows more), blend splits on, `directional_shadow/size` 4096 on High, 2048 on Low; soft shadow filter quality Low. Grass, cobbles and ground cover cast **no** shadow; units, animals, trees, buildings do. Trees cast with a lower LOD (Godot import: Generate LODs on; shadow LOD bias 2).
- **Baked light:** `LightmapGI` over terrain, rocks, trees and buildings (static), so every static object has sky occlusion and contact darkening without SSAO. Bake once per map; buildings placed during play get an ambient-occlusion decal (soft dark footprint) instead.
- **Contact shadows for units:** the team disc (section 4) is the contact shadow; it is what stops units floating, since SSAO is not available.
- **Fog / haze:** depth fog on, colour `haze`, density 0.0025, sky affect 0.3, begins ~60 m; height fog off. At default zoom it only warms the top third of the screen; at max zoom-out it separates the far shore.
- **Tonemap:** AgX (Godot 4.4+; Wayfarer ships it on Mobile), exposure 1.0, white 6.0. Adjustments: contrast 1.05, saturation 0.95. Colour-grade LUT allowed after lighting is right (studio `fit_lut.py`, untested on Android).
- **Glow:** on, intensity 0.4, bloom 0.0, HDR threshold 1.2: only fire, water glints and the selection ring glow.
- **AA:** MSAA 4x on High, 2x on Medium, off on Low (foliage uses alpha-to-coverage when MSAA is on).

### 7.2 Terrain material
Height and masks from `assets/terrain/rift_lake/` (see `meta.json`): 1025 x 1025, 0.5 m per sample over 512 m.
- Seven PBR layers, Poly Haven 2K CC0 sets (albedo + normal GL + ARM), weights from `splat_a.png` (R dry grass, G red soil, B volcanic rock, A shore sand) and `splat_b.png` (R wet mud, G cobble bed, B cracked mud). Look-target tiling: withered_grass 3 m, red_mud_stones 2.5 m, dark_rock 3.5 m, coast_sand_01 3 m, brown_mud_02 2.5 m, dry_river_pebbles 1.8 m, mud_cracked_dry_riverbed_002 3 m; each layer rotated by 0.6 rad x layer index to break alignment.
- **Height blend:** weight = (splat x (0.35 + height)^4)^2, normalised. Gives crisp pebble-into-sand edges instead of smeared blends.
- **Tints** (multiply on albedo, the colours above depend on them): grass 0.78/0.70/0.56, red 0.80/0.70/0.62, rock 0.85/0.82/0.80, sand 0.92/0.88/0.82, mud 0.80/0.78/0.74, pebbles 0.95/0.92/0.88, cracked 1.0/0.95/0.90.
- **Macro variation:** one noise at ~25 m wavelength, albedo x 0.82-1.12, kills tiling at RTS height.
- **Camp floors:** every home building paints a trampled disc (radius 8-16 m, noisy edge) toward red_earth with the grass removed; write it into a runtime "trample" mask texture, not new geometry.
- **Phone cost:** never sample 7 layers per pixel. Pack the 7 albedo/normal/ARM sets into three `Texture2DArray`s (2048, ETC2/ASTC, mipmaps) and per pixel pick the **top 2 layers** from the splats (sort in the vertex shader, or bake a `layer_id` RG8 index map offline next to the splat). Cost: 2 layers x 3 arrays = 6 reads + splat + macro noise. Beyond 60 m from the camera use only the top layer.

### 7.3 Rocks, cobbles, ground cover
- Boulders and cobbles: Poly Haven Namaqualand granite scans tinted to basalt (albedo x 0.42/0.38/0.35, saturation 0.5). They read as the dark lava pavement of the Turkana shore.
- Cobble pavement: `rocks/cobbles` + `rocks/stones` instanced (MultiMesh) ~1 per 1.2 m2 on dry plain, none within 3 m of water, half-sunk (-2 cm), no shadow, visibility range 70 m.
- Grass: `plants/grass_tuft` assembled as 3 tussock variants of ~18 tufts each (0.25 m radius), 0.4-1.2 m tall, colour multiply 1.55/1.22/0.70 at saturation 0.3 (sun-cured straw). Density from `veg.png` B, none within 15 m of a home building. No shadow. Visibility range 60 m with a 10 m fade (dithered). The tussock sway is a vertex shader (2 cm at the tips, 0.3 Hz).
- Shore sedge: green-tinted tufts in a 1-6 m band from the waterline (`veg.png` A).

### 7.4 Water: Lake Turkana
- One plane at `water_level` (meta.json). Albedo from depth (`water.png`): silt_shallow at 0 -> jade_shallow at 0.18 -> jade_deep from 0.55. Roughness 0.035. Two scrolling normal maps (4 m and 11 m, opposite directions, 0.03 and 0.015 m/s), strength 0.18.
- Shore foam: from `shore.png` (distance to waterline, 255 = 40 m): foam where distance < 0.9 m, broken by a 0.6 m noise threshold, animated by a slow sin(time + distance) push; colour `foam`, roughness 0.7.
- Fresnel reflection of the sky only (no SSR on Mobile). One ReflectionProbe over the camp shore is optional; skip it first.
- No transparency (opaque water is cheaper and the jade colour is opaque in reality).

### 7.5 Vegetation
| Plant | Model | Size | Where | LOD |
|---|---|---|---|---|
| Acacia tortilis | `trees/acacia_tortilis` (8.1k tris) | 6-9 m tall, 11-14 m crown | dry channels (`veg.png` R), 7 m apart | LOD1 2.5k at 60 m; impostor (8 views) at 110 m |
| Fig (Home Tree) | `trees/home_fig` (60k / 15k) | 17 m | one per home | LOD1 at 45 m; never impostor (focal object) |
| Doum palm | `trees/doum_palm` (24k / 6k) | 8-12 m | shore band 15-60 m from water, channel mouths | impostor at 90 m |
| Shrubs | `plants/shrub_searsia` (20k / 5k), `plants/shrub_leafy` | 1-3 m | everywhere 2.2 m apart, denser in channels | LOD1 at 40 m |
| Grass tussock | section 7.3 | | | |
| Reeds / sedge | section 7.3 | | | |
All leaf materials: alpha scissor 0.5 (never alpha blend), back-lit translucency faked by a 0.25 wrap term in the shader (no SSS on Mobile). **Canopy fade:** any tree whose crown covers a selected or friendly unit on screen dithers to 25 % over 0.3 s; RTS readability beats realism here.

### 7.6 Hominins
- Bodies: `hominins/australopith` (Age 1, 6k tris, 1.3 m) and `hominins/erectus` (Age 2, 9k tris, 1.65 m); both carry 13 clips retargeted from Quaternius UAL (idle, walk, run, gather, pickup, attack, swing, throw, hit, death, crouch, torch, sit). Age 3 (Homo sapiens) body is still missing (section 11).
- RTS zoom: units are ~35-45 px tall at the default camera (look target); keep the default camera at pitch 50 degrees, 43 m from the focus point, 35 mm-equivalent (vertical FOV ~37 degrees). GDD 10 says "63 m across" and "40-60 px": with 1.3 m bodies those two cannot both hold; I chose the 40 px side (~45 m across).
- Team colour = **body paint**: a chest/shoulder band (70-79 % of body height) and a hip band (47-53 %), rough edges (noise), mixed at 35-85 %. Mask it by rest-pose height baked into vertex colour R (`restz`), so the shader does `mix(albedo, team, mask * noise)`. Plus the team disc (section 4). Never tint the whole body or add clothes in Ages 1-2.
- LOD: LOD1 at 1.5k tris (decimate the same rig) beyond 45 m. For 200 units, bake the clips into a vertex animation texture (VAT, 15 fps) and draw one MultiMesh per age per team, clip and phase in INSTANCE_CUSTOM: this is the spike's existing approach with real bodies instead of mannequins.

### 7.7 Buildings (GDD 3.1, 5.2): built from real props, never boxes
| Building | Build it from | Footprint |
|---|---|---|
| Home Tree (Age 1) | `trees/home_fig` + trampled red-earth floor 16 m + 3-4 `props/branch_heap` sleeping nests in the crown fork | 12 m |
| Home Hearth (Age 2) | same tree + `props/hearth_stones` + fire FX (7.8) + ash decal | 12 m |
| Nest Grove / Windbreak | 3 acacias with branch nests in the crowns; Age 2: `props/branch_heap` + `props/dry_branches` arcs on the ground | 8 m |
| Cache | `props/branch_heap` + resource pile per type: tubers (`props/tuber`), cobbles, wood (`props/dry_branches`), ochre (stones tinted #8A3A22) | 4 m |
| Display Ground | cleared trampled oval, broken branches strewn, a ring of 6 boulders | 10 m |
| Throwing Ground | 3 cobble banks (`rocks/cobbles` heaped), a dead-branch target post | 8 m |
| Knapping Floor | 3 m disc of cobbles + flakes (`rocks/stones` small), `props/lithic_core`, 2 hammerstones, Age 2: `props/hand_axe` | 6 m |
| Lookout Tree / Watch Fire | tall acacia + branch platform at 5 m / fire on a boulder rise | 6 m |
| Thorn Fence | 4 m segments of `props/dead_branch` + `props/dry_branches`, 1.1 m high | 4 m |
| Hearth Camp | `props/hearth_stones`, fire, 2 windbreaks | 10 m |
| Ochre Cache | cache + red ochre lumps | 4 m |
| Story Circle | ring of 8 boulders, ochre handprints decal on the largest | 10 m |
| Fish Weir | arc of basalt boulders in the 0-1 m shallows | 6 m |
Construction state = the same props, alpha-dithered in by build %, plus dust (7.8).

### 7.8 Wildlife and FX
- Animals: `animals/gazelle` (8.7k, animated) herds of 8; `animals/hyena` (static 9k) and `animals/hyena_animated` (41k, animated; decimate before use); `animals/leopard` (big cat, 4.9k, run clip); `animals/crocodile` (9k) half-sunk at the waterline; `animals/buffalo` (16k, 134 clips) as the Age 2 large game. Same team-disc rule in neutral grey (#6E675C, 30 %).
- Dust: GPUParticles3D, 16-24 soft billboards per burst, colour ground_gravel at 40 %, 1.2 s life, on building placed, finished, unit death fall.
- Fire (Age 2+): 2 flipbook billboards (flame + smoke) + one OmniLight3D range 8 m, energy 1.5, colour #FFA25A, flicker 0.15 amplitude at 7 Hz; max 4 shadowless fire lights in view.
- Selection: ring decal (section 4). Move marker: ring that shrinks 1.0 -> 0.3 over 300 ms, select colour. Attack marker: same, attack colour.

### 7.9 Texture and budget rules (phone)
LODs: Godot generates mesh LODs on import (keep Generate LODs on); the LOD1 counts in 7.5 are what the import dock should show. Textures 2048 max, ETC2/ASTC with mipmaps (Wayfarer lesson: uncompressed model textures cost 1.4 GB of VRAM). Phone budget at default zoom, owner's SM-S931B (spike: 98 fps with 210 mannequin units, GPU 5.9 ms): about 10 ms GPU of headroom for art at 60 fps (my calc). Spend it in this order: terrain shader (target 2.5 ms), units with real bodies (2 ms), trees + LOD + shadows (2 ms), ground cover (1.5 ms), water + FX (1 ms). Draw calls under 150 (MultiMesh for every repeated thing). Visible triangles: up to ~1.2M is fine on that phone; keep the Low preset under 400k.

## 8. Do and don't
- Do: compare every capture with a real West Turkana photo before calling it done; colour comes from the photo.
- Do: keep units the brightest-contrast things on screen (paint, disc, rim from the low sun).
- Do: use only scanned or PBR assets with real albedo + normal + roughness maps.
- Don't: low-poly, flat-shaded, toy, cartoon or stylized assets, even CC0 ones; vertex-colour noise terrain; primitive mannequins.
- Don't: lawn-green grass, orange ground, saturated sky blue water. The lake is jade, the ground grey-brown and straw.
- Don't: alpha-blended foliage, transparent water, SSAO or SSR (not on Mobile), more than one shadow-casting light.
- Don't: hide units under canopies (canopy fade, 7.5).

## 9. Store assets
- Icon: the Home Tree fig at golden hour, crown silhouetted against the jade lake, rendered from the real models in Blender (512 x 512, alpha), no text.
- Feature graphic (1024 x 500): wide low-angle render of the camp at sunset with the band walking home, from the look-target scene; no "Best/#1/Free".
- Screenshots (real game only, from game-qa's capture bot): (1) the camp at default zoom with Foragers working, (2) a fight at the carcass with hyenas, (3) the Age 2 Home Hearth at dusk-lit fire.

## 10. Visual tier
**Premium realistic 3D** (owner rule 2026-10-11: photorealistic, as high-end as possible). Everything in the template's premium 3D rules still applies (hero scene first, phone budget, four questions), except "stylized, never photoreal", which is reversed for this game.

### Four questions, answered for the features in this spec
| Feature | Noticed at RTS distance? | Phone GPU cost | Cheaper trick? | Fits spec? |
|---|---|---|---|---|
| 7-layer height-blended terrain | Yes: it is 60 % of every frame | ~2.5 ms with top-2 layers + arrays | Bake far albedo; already top-2 | Yes |
| 3D grass tussocks | Yes, they make the plain read as grassland instead of bare sand (look-target test renders with and without them) | ~1.5 ms, no shadows, 60 m range | Grass in the terrain texture alone was tried and read as bare sand | Yes |
| Real hominin bodies + VAT | Yes, the owner's main complaint | ~2 ms for 200 units at 1.5-6k tris | Impostor sprites lose the walk; VAT keeps it | Yes |
| Water normals + foam | Yes, at the shore | <0.5 ms (one plane) | It is the cheap trick (no SSR) | Yes |
| Real-time sun shadows | Yes: low sun, long shadows are the mood | ~1.5 ms, 2 splits, 120 m | Lightmap for statics; real-time only for movers + trees | Yes |
| Canopy fade | Yes, units under trees | ~0 (dither) | | Yes |
| Volumetric haze | Would be, but | not on Mobile | depth fog | depth fog only |

## 11. Known gaps (2026-10-11)
1. **No CC BY / CC0 rigged early-hominin model exists on Sketchfab** (searched: australopithecus, hominin, homo erectus, caveman, primitive man, ape man, chimpanzee, ...). Fallback used: a realistic chimp-like biped (Age 1) and a CC3 Neanderthal (Age 2), both re-rigged with Quaternius CC0 clips. Neither is a true australopith; a paid scan or a custom sculpt is the real fix.
2. **No Age 3 Homo sapiens rigged body** yet: the only CC BY realistic candidate (Maring tribal man, khawaimedia) has no rig and wears cloth. Fallback: the erectus rig with a sapiens head; or a CC BY Renderpeople/Mixamo-rigged scan (Wayfarer uses "Nathan Animated 003" by Renderpeople, CC BY) dressed in a hide wrap.
3. Doum palm is a Mexican fan palm stand-in (single trunk; real doum palms fork). No CC BY doum palm or Ficus sycomorus found; the Home Tree is a banyan (Ficus microcarpa) whose aerial roots are not East African.
4. No CC BY realistic lion/lioness, no hippo that passes the photoreal bar, no reed bed model; the leopard texture is 512 px.
5. Rocks are granite scans tinted to basalt; a real vesicular basalt scan set would be better.

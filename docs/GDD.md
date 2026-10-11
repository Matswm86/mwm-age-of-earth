# Age of Earth (working title): game design doc v1

Version 1, 2026-10-11, game-designer. Binding inputs: `docs/BRIEF.md` (owner decisions 2026-10-11), the studio's RTS plan, Wayfarer GDD sections 2.2, 2.3, 4.3b (`docs/GDD.md` in github.com/Matswm86/mwm-wayfarer), the studio's Godot rules.

Numbers live in ONE file: `data/balance.json`. The tables below copy it for reading; if they disagree, the JSON wins. `tools/balance_sim.py` reads the same file.

Tags: **(checked)** = date verified in Wayfarer GDD section 16 sources; **(unverified)** = not checked; **(my calc)** = output of my own sim; **(fun > accuracy)** = a deliberate departure from the science, listed again in 3.3.

---

## 1. Pitch

**One sentence:** a classic gather-build-advance-fight real-time strategy game where your civilisation starts as a band of early hominins at an East African rift lake and wins its future by discovering the stone that cuts, fire and words.

Genre rules come from the classic age-advancing RTS. Names, art, unit lists and sounds of existing games are not used; store text says "inspired by the genre" (BRIEF legal line).

**v1 scope (owner):** 1 civilisation (one human line), Ages 1-3, 1 real-terrain map (rift lake, Copernicus GLO-30), skirmish vs 1 AI at Easy / Normal / Hard. No campaign, no online. Own app, outside MWM Play.

## 2. Core loop

**Gather -> build -> discover -> train -> drive out.**

1. **Gather** food, wood, stone (and ochre from Age 2) with Foragers.
2. **Build** nests, caches and work grounds around the Home Tree.
3. **Discover** the next age at the Home Tree (Stone That Cuts, then Fire, then Words).
4. **Train** a band of fighters that counter what the rival band fields.
5. **Drive out** the rival band: bring down every one of its home buildings.

Match: 15-25 minutes. One match = one session.

## 3. What the genre's words mean for a hominin band (design problem 1)

### 3.1 Mapping table

| Genre role | Age of Earth element | Why it is believable | What it does in play |
|---|---|---|---|
| Town centre | **Home Tree** (Age 1): a huge fig with sleeping nests. Restyles at Age 2 into the **Home Hearth**: the same tree with a fire ring at its foot | Early hominins likely slept in trees; fire is the leading idea for why later Homo slept on the ground (Wayfarer era 2 card, hypothesis, unverified) | Trains Foragers and Torch-bearers, researches age-ups, accepts every resource, garrisons 10 (they climb into the tree), throws stones at attackers |
| 2nd town centre | **Hearth Camp** (Age 2) | A carried ember lets a band set up a second fire | Expansion drop site, +5 pop, garrison 10, fire radius |
| Villagers | **Foragers** | Every band member gathers | Gather, build, repair, garrison, weak fight |
| Houses | **Nest Grove** (Age 1), restyles to **Windbreak** (Age 2) | Night nests, then brush shelters by the fire | +5 pop each, cap 75 |
| Drop sites | **Cache** (any resource), **Ochre Cache** (Age 2, stone + ochre) | A spot where the band piles food and stones (fun > accuracy) | Cuts walk time; the main economy skill |
| Barracks | **Display Ground**: a cleared patch where males display with branches | Chimpanzee-style display and group patrols (unverified as hominin behaviour) | Trains Bruisers, Spear-bearers, Runners |
| Archery range | **Throwing Ground**: a bank of collected throwing stones | Stone throwing by apes (unverified) | Trains Stone Throwers |
| Tech building | **Knapping Floor**: a flake-littered stone working spot | Stone tool sites (Lomekwi, 3.3 Mya, checked) | Stone That Cuts, Digging Sticks, Handaxe, Heat-treated Stone |
| Tower | **Lookout Tree** (Age 1), upgradable to **Watch Fire** (Age 2) | A sentry in a tall tree; a fire on a rise | Vision; throws stones only with throwers inside (Lookout) or by itself (Watch Fire); Watch Fire scares predators |
| Wall | **Thorn Fence** (4 m segments) | Thorn barriers for animals (fun > accuracy, no evidence this early) | Cheap blocking, burns fast to torches (x3 damage) |
| Monastery / support | **Story Circle** (Age 3) | Words, ochre and gifts (Wayfarer era 3) | Trains Envoys, social techs |
| Farms | **Fish Weir** (Age 3), on shallow shore cells | Stone fish traps (fun > accuracy: evidence is much later, unverified) | The only renewable food besides fig regrowth |
| Military | **Bruisers, Stone Throwers, Spear-bearers, Runners, Torch-bearers, Envoys** | Display, throwing, sticks, persistence running (unverified) | Section 5.3 |
| Enemy civ | **The rival band** across the lake: same line, mirrored | Rival groups competing for a lake shore | The AI opponent |
| Neutral threat | **Predators**: big cats, hyena packs, crocodiles | Real rift fauna (Wayfarer era 1 card) | Pick off lone Foragers; fire stops them from Age 2 |

### 3.2 Defeat and fighting tone
Rival hominins knocked to 0 HP **fall and die on the field, with no blood or gore**; the body fades out after a few seconds (owner decision 2026-10-11, classic-battle tone). Predators and prey fall and lie still (hunt and scavenge). Envoys can **persuade** rival units to join you (Age 3). Rating effect is unverified (IARC form decides); target PEGI 7-12, unverified until the IARC form is filled in.

### 3.3 Where I chose fun over accuracy
1. **One band spans 3+ million years.** Each age-up restyles every unit into the next species (Age 1 australopith-like, Age 2 Homo erectus-like, Age 3 Homo sapiens). Reason: the genre's age-up moment needs visible change, and one civilisation is the owner's scope.
2. **Organised fighting between hominin bands.** Group fights between chimpanzee communities exist (unverified wording); armies with roles do not have evidence at 3 Mya. Reason: the genre needs armies.
3. **All three ages on one rift-lake map.** Wayfarer puts era 3 at the southern Cape coast. Early Homo sapiens also lived in East Africa (Omo Kibish, ~230,000 years ago, unverified). Reason: v1 = 1 map.
4. **Caches, thorn fences, fish weirs** are earlier than any evidence.
5. **Age-1 stone throwing as a ranged weapon** is a stretch from ape behaviour.
6. **Forager walk speed 3.2 m/s** (a real walk is ~1.3 m/s, unverified). Reason: genre pace.
7. **Map scale 1:10** (5.1 km of real rift squeezed into 512 m, heights scaled the same so slopes keep their real angles).
8. **The lake stays the same in all ages within a match.** Both players share one terrain and can be in different ages, so the lake cannot shrink when one of them ages up.

## 4. Ages and age-up discoveries (design problem 2)

| Age | Name in game | Band looks like | Title card | Discovery that ends it | Where researched |
|---|---|---|---|---|---|
| 1 | **The Ground** | Australopith-like, small, long arms, part-time tree climbers | "East Africa, more than 3 million years ago" (Lomekwi 3.3 Mya, checked) | Keystone: **The Stone That Cuts** (required), then age-up **Fire Kept** | Knapping Floor, then Home Tree |
| 2 | **The Fire** | Homo erectus-like, tall, long legs, ground sleepers | "About 1 million years ago" (Wonderwerk ~1 Mya, checked, debated) | **First Words** | Home Hearth |
| 3 | **The Word** | Homo sapiens | "About 100,000 years ago" (unverified for East Africa) | (v1 stops here) Age 4 would be **Sewn Clothing and the Dog** | Home Hearth |

Rules:
- **Stone That Cuts** (Knapping Floor, 100 food 75 stone, 40 s): +25% carcass and game gathering, +10% tuber, +1 melee attack. Required for Fire Kept. Teaches the player that discoveries come from buildings.
- **Fire Kept** (Home Tree, 350 food 100 wood 50 stone, 90 s): needs Stone That Cuts + 2 of {Knapping Floor, Display Ground, Throwing Ground}. On finish: Home Tree -> Home Hearth (HP 1800 -> 2400, fire radius 20 m), Nests -> Windbreaks, units restyle, Age 2 content unlocks.
- **First Words** (Home Hearth, 450 food 100 wood 100 ochre, 100 s): needs 2 of {Hearth Camp, Watch Fire, Ochre Cache}. On finish: units restyle to Homo sapiens, Age 3 content unlocks, a 3 s "first word" audio sting.
- The Home Tree cannot train while researching an age-up (genre rule; makes the timing a choice).
- Age-up is visible to the opponent: a pillar of smoke (Fire) or a drum-like call (Words) at the rival's home (genre rule, gives information).

## 5. Elements

### 5.1 Resources (design problem 3)

| Resource | Sources | Gather rate /s | From | Used for |
|---|---|---|---|---|
| **Food** | Fig trees (regrow), tuber patches, carcasses (predator kills, spawn every 150 s, decay 0.25/s, hyenas steal), antelope herds (Age 2), Fish Weirs (Age 3) | fig 0.40, tuber 0.33, carcass 0.50, game 0.45, weir 0.30 | Age 1 | Foragers, every unit, age-ups |
| **Wood** | Woodland (dead branches, fun > accuracy: unlimited per tree cluster) | 0.38 | Age 1 | Buildings, spears, torches |
| **Stone** | Cobble beds in dry stream beds | 0.30 | Age 1 | Throwers' ammunition cost, Knapping techs, home buildings |
| **Ochre** | Red ochre outcrop on the far side of the home ridge | 0.28 | Age 2 | Age 3 up, Envoys, Age 3 upgrades. (Pigment use ~300,000 years ago in Kenya, unverified) |

Carry 10 per trip (+4 with Carry Slings). Drop time 1 s. Effective rate = carry / (carry/rate + 2 x walk distance / 3.2 + 1).

**Per-player resource kit** (placed identically at both starts; terrain is real, resource placement is designed):

| Kit item | Amount | Walk to drop (m), no cache / cache | Worker slots |
|---|---|---|---|
| 6 fig trees around the Home Tree | 600, regrow 0.05/s per tree | 12 / 12 | 6 |
| 2 tuber patches | 500 | 45 / 10 | 6 |
| 2 starting carcasses | 300 | 60 / 14 | 4 |
| Antelope herd (8 x 80, Age 2) | 640 | 70 / 14 | 6 |
| Far fig grove (shared, mid-map) | 800 | 110 / 14 | 8 |
| 2nd herd (Age 2) | 640 | 120 / 16 | 6 |
| Woodland | 6000 | 30 / 8 | open |
| Stone bed | 1800 | 55 / 8 | open |
| Ochre outcrop | 900 | 90 / 10 | open |

Food runs short around minute 20-24 (my calc, sim trace) unless the player builds Fish Weirs or takes the far grove and second herd. That pushes the late game toward the middle of the map, as the genre does.

### 5.2 Buildings

| Building | Age | Cost | Build s | HP | Effect |
|---|---|---|---|---|---|
| Home Tree / Home Hearth | 1 / 2 | 275 W 100 S (only if rebuilt) | 120 | 1800 / 2400 | Pop +5, all drops, garrison 10, throws 3 dmg every 2 s (1 shot + 0.5 per garrisoned unit), range 16 m, vision 32 m; Hearth: fire radius 20 m |
| Nest Grove / Windbreak | 1 / 2 | 30 W | 20 | 250 / 300 | Pop +5 |
| Cache | 1 | 60 W | 25 | 400 | Drop for all |
| Display Ground | 1 | 150 W | 40 | 900 | Melee units |
| Throwing Ground | 1 | 150 W 25 S | 40 | 900 | Ranged units |
| Knapping Floor | 1 | 100 W 50 S | 40 | 800 | Tool techs |
| Lookout Tree | 1 | 40 W 60 S | 45 | 500 | Vision 30 m, garrison 3, each garrisoned unit adds a 4 dmg throw, range 18 m |
| Thorn Fence | 1 | 5 W / 4 m | 6 | 250 | Blocks; torches deal x3 |
| Hearth Camp | 2 | 275 W 100 S | 120 | 1600 | 2nd home: drops, pop +5, garrison 10, fire radius 16 m |
| Watch Fire | 2 | 75 W 75 S (new or upgrade a Lookout) | 45 | 700 | Vision 34 m, fire radius 25 m, 1 throw + 1 per garrisoned unit, range 20 m |
| Ochre Cache | 2 | 60 W | 25 | 400 | Drop for stone and ochre |
| Story Circle | 3 | 175 W 100 S | 60 | 1000 | Envoys, social techs |
| Fish Weir | 3 | 60 W, rebuild 40 W | 20 | 150 | 300 food then rebuild, 1 Forager |

Builders: 1 Forager builds at the listed time; each extra builder cuts time (time / n, max 4).

### 5.3 Units

| Unit | Age | Class | Cost | Train s | HP | Attack | Every s | Range m | Armour melee/ranged | Speed m/s | Trained at |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Forager | 1 | worker | 50 F | 20 | 30 | 2 | 2.0 | melee | 0/0 | 3.2 | Home Tree |
| Bruiser | 1 | heavy | 60 F 20 W | 24 | 70 | 6 | 2.0 | melee | 1/0 | 3.0 | Display Ground |
| Stone Thrower | 1 | ranged | 35 F 35 S | 26 | 30 | 4 | 2.0 | 16 | 0/0 | 3.0 | Throwing Ground |
| Spear-bearer | 2 | spear | 35 F 25 W | 22 | 45 | 5 | 2.0 | melee (long) | 0/0 | 3.2 | Display Ground |
| Runner | 2 | fast | 80 F 20 S | 28 | 55 | 5 | 1.8 | melee | 0/1 | 5.2 | Display Ground |
| Torch-bearer | 2 | torch | 40 F 60 W | 30 | 40 | 2 (18 vs buildings every 3 s + burn 2/s for 10 s) | 2.0 | melee | 0/0 | 3.0 | Home Hearth |
| Envoy | 3 | support | 80 F 60 O | 40 | 30 | none; heals 1.5 HP/s within 8 m; Persuade (8 s channel, 20 m, recharge 45 s) | | | 0/0 | 2.8 | Story Circle |

Damage = max(1, attack x counter multiplier - armour). Pop 1 each. Pop cap 75 per player.

**Persuade:** works on rival hominin units except Envoys and Foragers inside a fire radius; the target joins your band at full HP. A Runner or any attack on the Envoy breaks the channel.

### 5.4 Counters (design problem 4)

Multipliers (attacker row -> target column; blank = 1.0):

| Attacker \ target | worker | heavy | ranged | spear | fast | torch | support | predator | building |
|---|---|---|---|---|---|---|---|---|---|
| heavy (Bruiser) | | | | **1.5** | | **1.5** | | | **1.5** |
| ranged (Thrower) | | **2.0** | | **1.75** | 0.6 | | | | |
| spear | | | | | **2.5** | | | **2.0** | |
| fast (Runner) | **1.5** | 0.7 | **2.0** | | | **2.0** | **2.0** | | |
| torch | | | | | | | | **1.5** | (own building attack) |

The loop: **Throwers beat Bruisers and Spears; Runners beat Throwers, Torches, Envoys and Foragers; Spears beat Runners and predators; Bruisers beat Spears and buildings.** Torches are siege; Envoys are support. Every pair checked in the sim (section 7.2).

### 5.5 Predators (neutral)
| Predator | Count per map | HP | Attack | Behaviour |
|---|---|---|---|---|
| Big cat | 2 | 90 | 9 / 1.5 s, speed 6.0 | Stalks a unit more than 12 m from any other unit; leaves after one kill; avoids fire radii |
| Hyena pack | 2 packs x 3 | 45 each | 5 / 1.2 s | Steals carcasses; attacks groups of 2 or fewer; avoids fire radii |
| Crocodile | 3 | 150 | 14 / 2.5 s, speed 1.5 | Shore cells only; ambushes units gathering or walking at the water edge |

Age 1 = predators are a real cost (lost Foragers). Age 2 = fire radii make the base safe; torches repel 12 m. This makes **Fire Kept feel like safety**, matching Wayfarer era 2's arc.

## 6. Tech tree, Ages 1-3

| Age | Building | Tech | Cost | Time s | Effect |
|---|---|---|---|---|---|
| 1 | Knapping Floor | **The Stone That Cuts** (keystone) | 100 F 75 S | 40 | Carcass/game gather x1.25, tuber x1.1, +1 melee attack; required for Age 2 |
| 1 | Knapping Floor | Digging Sticks | 50 F 50 W | 25 | Tuber gather x1.25 |
| 1 | Home Tree | **Fire Kept** (age-up) | 350 F 100 W 50 S | 90 | Age 2 |
| 2 | Home Hearth | Carry Slings | 125 F 75 W | 30 | Carry +4 |
| 2 | Home Hearth | Cooking | 150 F 100 W | 45 | Tuber x1.2, game and carcass x1.15 |
| 2 | Knapping Floor | Handaxe | 100 F 100 S | 40 | Wood x1.2, game x1.1, +1 melee attack |
| 2 | Display Ground | Heavy Clubs | 150 F 100 W | 40 | Bruiser +2 attack, +15 HP (becomes Club-bearer) |
| 2 | Throwing Ground | Shaped Stones | 120 F 80 S | 40 | Thrower +1 attack, +2 m range |
| 2 | Home Hearth | **First Words** (age-up) | 450 F 100 W 100 O | 100 | Age 3 |
| 3 | Display Ground | Practiced Fighters | 250 F 100 O | 55 | Bruiser +2 attack, +1/+1 armour (becomes Band Fighter) |
| 3 | Throwing Ground | Throwing Spears | 250 F 150 W | 55 | Thrower +3 attack, +3 m range, +10 HP; becomes Spear Caster, cost changes to 35 F 40 W |
| 3 | Display Ground | Hafted Points | 200 F 100 S | 50 | Spear-bearer +2 attack, +10 HP |
| 3 | Display Ground | Long Runners | 200 F 50 O | 50 | Runner +10 HP, +0.4 speed |
| 3 | Home Hearth | Fire Carriers | 150 F 150 W | 45 | Torch building attack +9 |
| 3 | Knapping Floor | Heat-treated Stone | 150 F 150 W | 45 | Stone gather x1.25, +1 ranged attack |
| 3 | Story Circle | Shared Names | 200 F 100 O | 50 | Forager +15 HP, Forager train time x0.85 |
| 3 | Story Circle | Gift Beads | 150 F 150 O | 50 | Persuade 25% faster, +4 m range |

## 7. Progression, pacing and the balance sim

### 7.1 Match timeline (Normal reference player; times = my calc from the sim)

| Minute | New element | What the player learns | Risk |
|---|---|---|---|
| 0:00 | Home Tree, 6 Foragers, 250 F 250 W 150 S | Select, send to figs/wood, queue Foragers | None |
| ~0:30 | Nest Grove | Pop cap | Pop-blocked if forgotten |
| ~1:50 | Cache at the woodline | Drop sites cut walking | Slow economy |
| ~2:20 | Knapping Floor -> Stone That Cuts (done ~3:05) | Discoveries come from buildings | |
| ~3-5 | First predator encounter on a tuber patch or carcass | Group up, keep Foragers near the base | Lose 1-2 Foragers |
| ~4:15 | Display Ground | Army buildings | First rival scout (Hard raids from ~6) |
| ~7:15 | Click Fire Kept (16 Foragers) | Age-up timing | Home Tree stops training 90 s |
| ~8:45 | **Age 2: The Fire**. Herd cache, Ochre Cache, Watch Fire | Fire radius = safety; hunting; ochre | First real attack (Normal ~10:00) |
| 10-14 | Spear, Runner, Torch; Carry Slings | Counters | Losing the first fight sets you back ~2 min |
| ~14:45 | Click First Words | | |
| ~16:25 | **Age 3: The Word**. Story Circle, Envoys, Fish Weirs, line upgrades | Persuasion, renewable food | Map food runs low ~20-24 |
| 16-25 | Decisive pushes; Torches on the rival home | Siege | Match ends |

Breather (the "every 5th level" rule mapped to an RTS): each age-up research window (90-100 s) is the breather; the AI never launches a new wave while it is itself researching an age-up, and Easy/Normal also hold waves for 60 s after the player reaches a new age.

Pacing targets (asserted by the sim):

| Profile | Reach Age 2 (min) | Reach Age 3 (min) | Extra check |
|---|---|---|---|
| Easy | 8.0-11.0 | 17.0-24.0 | |
| Normal | 6.5-9.0 | 13.0-16.5 | |
| Hard | 6.0-9.0 | 13.0-17.0 | Army at 20 min: Easy < Normal < Hard |

Hard is harder through army size, timing and micro, not through a faster age-up (it builds more Foragers first).

### 7.2 Sim output (real run, 2026-10-11)
`python3 tools/balance_sim.py` reads `data/balance.json`, plays one undisturbed side per AI profile at 1 s ticks (build order, gather split, caches, houses, techs, army wallet), then fights equal-cost armies with focus fire and a free-volley closing phase. No opponent pressure, so times are the fastest an undisturbed band manages.

```
ECONOMY PACING (undisturbed band, same income rules for every profile)
profile    cuts  age2 go   age2  age3 go   age3  forag@10  army@15  army@20  army res@20  verdict
easy        3.6      7.5    9.0     20.2   21.8        16        5        8          860  PASS (target age2 (8.0, 11.0), age3 (17.0, 24.0))
normal      3.1      7.3    8.8     14.7   16.4        19        7       21         2560  PASS (target age2 (6.5, 9.0), age3 (13.0, 16.5))
hard        3.0      7.2    8.7     15.0   16.7        20        8       24         2560  PASS (target age2 (6.0, 9.0), age3 (13.0, 17.0))
army at 20 min rises with difficulty (easy < normal < hard): PASS

COUNTER CHECK (equal 600-resource armies, no upgrades, focus fire)
stone_thrower  ( 8) vs bruiser        ( 7) -> winner stone_thrower  survivors 5/8 vs 0/7  PASS
runner         ( 6) vs stone_thrower  ( 8) -> winner runner         survivors 6/6 vs 0/8  PASS
spear_bearer   (10) vs runner         ( 6) -> winner spear_bearer   survivors 9/10 vs 0/6  PASS
bruiser        ( 7) vs spear_bearer   (10) -> winner bruiser        survivors 5/7 vs 0/10  PASS
bruiser        ( 7) vs runner         ( 6) -> winner bruiser        survivors 6/7 vs 0/6  PASS
stone_thrower  ( 8) vs spear_bearer   (10) -> winner stone_thrower  survivors 3/8 vs 0/10  PASS

ALL PASS
```
Columns: `cuts` = Stone That Cuts done; `go` = age-up clicked; `forag@10` = Foragers at minute 10; `army@N` = military units alive; `army res@20` = resources spent on military by minute 20. All minutes, all (my calc).

What the sim does not cover (the builder and QA must test in game): fights while gathering, predator losses, line upgrades, Envoys, kiting, pathing jams, terrain. The counter results are one-sided by design (hard counters, as in the genre); real fights will be closer because armies mix. The sim also shows ochre piling up in Age 3 because it does not buy Age 3 upgrades or Envoys; the real AI spends it on them.

`python3 tools/balance_sim.py --trace normal` prints the minute log and every event; use it after any balance change. Rule for the builder: **change numbers only in `data/balance.json`, then rerun the sim; ALL PASS before a push.**

## 8. Controls: one phone, landscape (design problem 6)

**Landscape departs from the studio's portrait default.** Reasons: an RTS needs a wide view of the base and the army at once, the command card, minimap and control groups need side space that portrait would take from the playfield, and the two-thumb grip (pan with one hand, command with the other) is natural in landscape. Godot: `window/handheld/orientation = landscape`, base 1920x1080, `stretch/aspect = expand`. All other studio rules hold.

Screen layout (1920x1080 base): minimap bottom-left (300x300 px); resource bar top-left; age + pop top-centre; control-group column right edge (4 buttons); command card bottom-right (2 rows x 3, 150x150 px buttons); selection panel bottom-centre; pause top-right. All buttons at least 48 dp (about 130 px at 1080 tall; buttons drawn at 140-150 px).

| Input | Result |
|---|---|
| Tap own unit | Select it (replaces selection) |
| Double-tap own unit | Select all own units of that type on screen |
| One-finger drag on empty ground (moves > 24 px) | Selection box; on release, selects own military inside; if none, own Foragers inside |
| Tap ground, units selected | Move there (green marker) |
| Tap resource, Foragers selected | Gather it |
| Tap rival unit, building or predator, units selected | Attack it |
| Tap own unfinished or damaged building, Foragers selected | Build / repair |
| Tap own building, nothing selected | Select it, command card shows its trains/techs |
| Long-press ground 400 ms, army selected | Attack-move there (fight anything on the way) |
| Two-finger drag | Pan the camera |
| Pinch | Zoom (camera height 18-60 m; tilt 55 deg at far, 48 deg at near) |
| Tap minimap | Jump the camera; with units selected, tap-hold minimap 400 ms = move there |
| Control group button (4, right edge) | Tap = select group; long-press 600 ms = assign current selection (button flashes); double-tap = select and centre camera |
| Idle Forager button (above control groups) | Selects the next idle Forager and centres on it; shows the count |
| Home button (above idle) | Centres on the Home Tree / Hearth and selects it |
| Command card: building icon | Ghost follows the finger; release on a valid spot shows a tick and cross (each 130 px); tap tick to place |
| Command card: Stop, Garrison, Ungarrison, Set gather point | As named; Set gather point then tap the target |
| X on the selection panel | Clear selection |
| Pause (top-right) | Pause the match (single player); menu: resume, speed 1x / 1.5x, surrender, quit (autosaves) |

No edge-panning, no hotkeys, no right-click. Every command also exists as a command card button, so no gesture is the only way.

## 9. AI opponent (design problem 5)

### 9.1 Structure
Three layers, all data-driven from `ai_profiles` in `data/balance.json`:
- **Strategic** (every 5 s): state machine `OPENING -> BOOM -> AGE_UP -> MUSTER -> ATTACK / DEFEND -> REBUILD`.
- **Economy** (every 2 s): keeps Foragers at `forager_target[age]` split by `gather_split[age]`; builds a Cache beside any source with 3+ Foragers that is more than 5 m further than a cache would make it; houses when free pop <= 2; follows the build order (9.2); income share `army_frac[age]` goes to military, the rest saves for the next purchase (surplus beyond the next goal also goes to military).
- **Tactical** (every 0.5 s): target choice, retreat, focus fire (Hard), garrison.

The AI plays under fog of war: it knows only what its units have seen (last-seen memory). **No resource or vision bonus at any difficulty.** Difficulty changes decisions only.

### 9.2 Build order (Normal; the times are when the sim did it, (my calc))
0:00 3 fig, 2 wood, 1 stone, queue Foragers; Nest Grove at free pop 2 -> ~1:50 Cache at woodline -> ~2:20 Knapping Floor -> Stone That Cuts -> ~4:15 Display Ground -> Digging Sticks, Cache at tubers -> ~7:15 Fire Kept at 16 Foragers -> Age 2: Cache at herd, Ochre Cache, Watch Fire, Carry Slings -> ~14:45 First Words at 24+ Foragers -> Age 3: Story Circle, Handaxe, Fish Weirs when the far grove drops under 300, Cooking, Heat-treated Stone.

Gather split by age (share of Foragers): Age 1 food 0.55 / wood 0.35 / stone 0.10; Age 2 food 0.42 / wood 0.30 / stone 0.12 / ochre 0.16; Age 3 food 0.45 / wood 0.30 / stone 0.10 / ochre 0.15.

### 9.3 Difficulty

| Setting | Easy | Normal | Hard |
|---|---|---|---|
| Foragers target by age | 13 / 20 / 24 | 16 / 26 / 32 | 16 / 28 / 34 |
| Builds caches | no | yes | yes |
| Idle share | 12% | 5% | 2% |
| Earliest Fire / Words click | 7.5 / 15 min | asap | asap |
| Army share by age | 10 / 25 / 40% | 12 / 20 / 50% | 12 / 22 / 55% |
| First attack | 13 min | 10 min | 8 min |
| Wave size | 6 | 10 | 12 |
| Counter-picks scouted units | no (fixed mix) | yes | yes |
| Micro (pull hurt units back, focus throwers, kite with throwers) | no | no | yes |
| Raids Foragers with Runners | no | no | yes |
| Reaction to an attack | 25 s | 10 s | 4 s |
| Garrisons Foragers when the home is hit | no | yes | yes |
| Retreats a wave at | never | 35% of wave HP | 45% |
| Max army | 20 | 40 | 45 |

**Counter-pick rule:** next wave composition weight per unit = base mix weight + 2 x (share of scouted rival units this unit counters, from 5.4) - 1 x (share of scouted rival units that counter it). Re-scouts with one Runner (or Forager in Age 1) every 3 minutes.

**Target priority:** Easy -> nearest building on the way to the rival home. Normal -> rival army if seen, else Foragers near caches, else home. Hard -> Foragers and throwers first; Torch-bearers go for the home only after the defending army is under 5 units.

## 10. Map, scale and the unit cap (design problem 7)

- **Map:** "Rift Lake", West Turkana shore, built from Copernicus GLO-30 with the Wayfarer pipeline (`tools/terrain/cop_to_game.py` in mwm-wayfarer, add a `turkana` preset; the crop coordinates near the Lomekwi 3 site are owed by the builder from a verified source). Uniform 1:10 scale: ~5.1 km real -> **512 x 512 m playable**, heights scaled the same. Lake on one side (shallow shelf shaped by distance from shore, as the `sea` option does), woodland and grass mosaic, volcanic ridges.
- **Navigation:** 128 x 128 grid, 4 m cells (the tech spike's flow-field size).
- **Match formats (owner 2026-10-11):** 1 vs 1 computer opponent, and 1 vs 2 computer opponents. In 1 vs 2 the pop cap drops to 55 per player (3 x 55 = 165 hominins + wildlife = ~208 agents, my calc), so the tech spike must also run that case.
- **Starts:** three start sites (two used in 1 vs 1) chosen on the real terrain at the same distance from the lake; resource kits (5.1) placed identically. Because real terrain is not symmetric, QA runs 50 AI-vs-AI Normal matches with sides swapped; each side must win 45-55%. If not, move kits, never the terrain.
- **Fog of war:** unexplored (black), explored (dim, last-seen buildings), visible.
- **Lighting:** fixed late-afternoon light, no day/night in v1 (baked lightmaps, Wayfarer bake tools).
- **Unit cap:** pop cap 75 per player x 2 = 150 hominins + wildlife (2 herds x 8 x 2 sides = 32, predators 11) = **~193 animated agents at most** (my calc). Tech spike target: **200 instanced, animated units on the flow field at 60 fps on the owner's phone (High), 30 fps floor on the 32-bit tablet (Low)**; game speed 1.5x must hold too. If the spike fails, cut pop cap to 60 (= 163 agents) before cutting anything else.
- **Camera:** units 40-60 px tall at default zoom (BRIEF); about 63 m visible across at default height, so the map is ~8 screens wide (my calc).

## 11. Opening and onboarding

### 11.1 Opening (Wayfarer 4.3b, adapted)
First launch only: pale blue dot in black space, one unbroken 60-90 s camera move, no text, no input: star -> planet -> Earth as it was millions of years ago (coastlines unverified) -> the East African rift -> the lake -> the canopy of the player's Home Tree. The camera settles into the RTS angle above the Home Tree while 6 Foragers climb down to the ground. Title card: "East Africa, more than 3 million years ago". Control hands over in the same shot. Skippable after the first viewing (tap -> "Skip" button 130 px, appears after 2 s). Later matches: a 6 s short version (orbit -> base). Main menu has "Watch the opening".

### 11.2 First match (no text walls)
The first match is vs Easy with the AI's first attack held until 14 min. Hints are a pulsing ring + an icon + at most 6 words, each shown once, each dismissed by doing it:
1. Ring on a Forager: "Tap to select".
2. Ring on figs: "Tap figs to gather".
3. Ring on the Home Tree: "More Foragers here".
4. Pop at 4/5: ring on Nest Grove icon: "Build nests for more".
5. At 2:00: ring on Knapping Floor: "Find the stone that cuts".
6. First predator nearby: alarm call + red ring: "Stay together".
7. Fire Kept affordable: Home Tree glows: "Discover fire".
8. First rival unit seen: ring on control group 1: "Hold to save your band".
No hint after Age 2 except a one-time "Ochre: red rock" marker.

## 12. Feel (feedback per action)

| Action | Sound | Visual | Haptic | Duration |
|---|---|---|---|---|
| Select unit | Soft contact call (varies per age: grunt, hum, word) | Ground ring scale 0 -> 1 | 10 ms tick | 120 ms tween |
| Command move / gather | Short acknowledge call | Green marker pulse at target | 10 ms | 300 ms |
| Attack command | Sharper call | Red marker | 20 ms | 300 ms |
| Resource dropped | Thud / rustle per type | +N float text over the cache, rises 40 px | none | 600 ms |
| Building placed | Wood creak | Ghost turns solid, dust puff | 15 ms | 400 ms |
| Building finished | Chorus call | Scaffold drops, 8 leaf/dust particles | 30 ms | 500 ms |
| Unit trained | Call from the building | Unit steps out, icon pops in the queue | none | 250 ms |
| Discovery done (Stone That Cuts) | Stone-strike crack | Flake sparkle at the Knapping Floor, banner 2 s | 40 ms | 2 s |
| Age-up done | Rising swell + age sting | 1.5 s camera pull-up over the home, every unit plays a 0.8 s restyle shimmer, age name card 2 s | 60 ms x2 | 3.5 s total, play continues underneath |
| Predator near Foragers | Alarm call (distinct) | Red edge pulse on the side of the threat, minimap ping | 80 ms | 1 s |
| Under attack (home or Foragers) | Drum-like alarm | Minimap flash; tapping the alert jumps the camera | 80 ms | 1.5 s |
| Unit downed (rival) | Yelp | Falls and lies still, no blood; fades out | none | 1.2 s fall, 3 s rest, 0.6 s fade |
| Persuaded | Gift chime | Ring changes colour, beads glint | 30 ms | 0.8 s |
| Building burning | Crackle loop | Flames grow with damage | none | while burning |
| Victory / defeat | Music sting | Camera rises over the map; stats screen (time, units, age times) | 100 ms | 4 s |

## 13. Session shape

- **First 60 seconds:** opening (first launch), then tapping Foragers onto figs and wood; something gathered within 10 s, first Forager trained within 25 s.
- **Where a player stops:** at the end of a match (15-25 min). Mid-match exits autosave (every 60 s and on app background, since Android kills background apps); "Continue" on the menu.
- **Why they come back:** beat the next difficulty; try another army plan; a per-difficulty record (fastest win, fastest Age 3) on the menu. No ads, no timers, no daily rewards, no energy, no purchases in v1.

## 14. How later ages extend the game (design problem 8)

Order follows Wayfarer 2.2; each age adds one idea, one age-up discovery, and usually one new map.

| Age | Name | Extends the RTS with |
|---|---|---|
| 4 | Painted Caves | Sewn Clothing + the Dog: a cold-map winter pressure, dogs as scouts and herd drivers, reindeer migrations (new map: limestone valley) |
| 5 | After the Ice | The Boat: skin boats, coast and fjord maps, fishing fleets, water transport of units (Naeroyfjord map) |
| 6 | First Fields | Farming + Pottery: fields as true renewable food, storage pots, livestock pens, settled villages |
| 7 | Bronze and Iron | Smelting: metal resource, smithy line upgrades, first armour, trade routes |
| 8 | The Viking Age | Longships and written law: naval combat, raids by sea, an assembly that grants a one-time bonus |
| 9 | The Empty Valley | Market and money: a trade economy and a plague event that empties buildings |
| 10 | The Fjord Village (1800s) | Steam and the outside world: steamers as fast transport, emigration as a pop trade-off |
| 11 | Power and Roads | Electricity: power plants that boost buildings in a radius, roads that speed units |
| 12 | Today | No new war tech: a last scenario mode where the player protects every trace their line left (the ending mirrors the opening: pull back to the pale blue dot) |

Civilisations: later versions can add rival lines (another hominin species in Ages 1-2 is the natural second civ).

## 15. Owner decisions (2026-10-11)

1. **Fighting tone:** units die on the field with no blood or gore; bodies fade out. Envoys still persuade rivals in Age 3.
2. **Age 3 location:** all three ages stay on the rift-lake map in v1; a southern Cape coast map is the first new map after v1.
3. **Match formats:** v1 ships 1 vs 1 and 1 vs 2 computer opponents (pop cap 55 each in 1 vs 2).
4. **AI:** every difficulty stays honest (no extra resources, no map vision). No "Brutal" level.

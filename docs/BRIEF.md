# Age of Earth (working title): owner brief, 2026-10-11

## What the owner asked for
An Android real-time strategy game with the gameplay of the old Age of Empires and Empire Earth (gather resources, build a town, advance through ages, train an army, beat AI opponents), with graphics updated to 2026 high-end standards.

## Owner decisions (2026-10-11)
- **Own app**, outside MWM Play (MWM Play is a kids' app for ages 4-8; battles push the age rating up).
- **Ages start at the very beginning, like Wayfarer**: the first age is early hominins at an East African rift lake (Wayfarer GDD era 1, "From the trees to the ground"), then fire, then onward through Wayfarer's era list (`docs/GDD.md` section 2.2 in github.com/Matswm86/mwm-wayfarer).
- **Opening scene from Wayfarer** (GDD section 4.3b): pale blue dot in black space, one unbroken 60-90 s camera zoom to Earth as it was ~7-10 million years ago, diving onto the East African rift, lake and forest edge, ending on the first band. Skippable after the first viewing. The RTS camera then takes over.
- **Version 1 = small skirmish**: 1 civilisation (one human line), the first 3 ages, 1 real-terrain map, skirmish vs AI at 3 difficulties. No campaign, no online play.
- Sketchfab API key is available for 3D assets (via the Blender MCP `search_assets` / `import_asset`); every asset needs a licence check and a CREDITS.md line.

## Name
"Age of Earth" is a working title. A web search on 2026-10-11 found no game with that exact name, but the name joins "Age of" (Age of Empires, Microsoft) and "Earth" (Empire Earth). A TMview + Play Store check is owed before the name appears anywhere public.

## Legal line
Genre and rules are free to use. Names, art, models, icons, civilisation art, campaign text, music and sounds of Age of Empires / Empire Earth are not. Store text says "inspired by the genre" only.

## Graphics bar
Realistic, no toy look (studio rule for new 3D games); Race Riders phone budgets. Reuse Wayfarer's real-terrain pipeline (DEM -> chunked terrain, impostor forest, wildlife). The top-down RTS camera keeps hominins at 40-60 px tall, which avoids Wayfarer's hardest art problem (faces at talk distance).

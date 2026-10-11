# Terrain source: Copernicus DEM GLO-30, West Turkana shore ("Rift Lake" map)

## File
- `Copernicus_DSM_COG_10_N03_00_E035_00_DEM.tif`: 1x1 degree tile (3-4 N, 35-36 E), West Turkana, Kenya.
  Fetched 2026-10-11 from the public AWS Open Data bucket `copernicus-dem-30m`
  (`https://copernicus-dem-30m.s3.amazonaws.com/<name>/<name>.tif`, listed at https://registry.opendata.aws/copernicus-dem/).
- Game output: `assets/terrain/rift_lake/` written by `tools/terrain/cop_to_game.py turkana`.

## Where the crop is, and the source for it
- Lomekwi 3 (LOM3), the 3.3 Ma stone-tool site: Harmand et al. 2015, "3.3-million-year-old stone tools from Lomekwi 3,
  West Turkana, Kenya", Nature 521: 310-315, doi:10.1038/nature14464. Its Figure 1 places LOM3 just south of the
  04 00' N graticule, west of Lake Turkana, near the Lomekwi drainage. The paper gives no numeric coordinates.
- Numeric point used: 3.87417 N, 35.75083 E (3 52' 27" N, 35 45' 3" E), the Wikipedia "Lomekwi" infobox
  (https://en.wikipedia.org/wiki/Lomekwi, read 2026-10-11, no source cited there). It agrees with Figure 1 (south of 4 N)
  and sits at 491 m on this DEM at the foot of the Nachukui hills. A second coordinate in circulation
  (3.91083 N, 35.85028 E) falls on the lake shore at 365 m in this DEM, so it was rejected.
- LOM3 is ~10-11 km from today's shore. A 5.12 km box (1:10 -> 512 m) cannot hold both, so the map is the shore
  directly east of LOM3: centre 3.880 N, 35.845 E (box ~3.857-3.903 N, 35.822-35.868 E). About 22 % is lake.
  Real land relief in the box is about 48 m (4.8 m in game): the West Turkana shore is a flat gravel plain cut by dry
  channels (laggas) with old beach ridges, which the DEM shows. 
- Lake level taken from the DSM water surface: 362 m. The lake bed is invented (a shelf shaped by distance from shore).

## Licence (verified 2026-10-10 by the Wayfarer team from the official licence text; same licence, same product)
"Licence for the use of the Copernicus WorldDEM-30", COP-DEM-GLO-30-F Global 30m Full, Free & Open,
https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf
Free of charge, worldwide, reproduction, distribution and adaptation allowed, no non-commercial restriction.
Kenya is not an excluded country.

## Required notices (Article 6), in the game credits and the store listing
> produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved

And in the legal notice of anything we distribute:
> The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.

Do not suggest that Copernicus, ESA, the EU or Airbus endorses the game.

# Where every Overhaul asset comes from

This is the provenance list for the Overhaul's own images, sounds, shaders and fonts. Balatro's own files are not listed: they never ship, the launcher patches the player's own copy.

Columns:
- **Source**: `ai` (made with InkJoker, the local image model), `code` (drawn by a script in this repo from shapes or from the game's palette), `hand` (made by hand), `third-party` (someone else's work, see Licence), `vanilla-derived` (a recolour or composite of Balatro's own sprites).
- **Release**: `ship` (in the public release), `exclude` (listed in tools/release/EXCLUDE.txt; the release build shows the replacement named in the Notes).

Every `ai` file is `exclude`. Other streams add their lines here in the same format.

| Path (under assets/) | Source | Release | Notes |
|---|---|---|---|
| resources/textures/{1x,2x}/MPTraps.png | ai + vanilla-derived | exclude | 12 trap cards and the Trap Pack. Traps: InkJoker spectral model from a layout of the trap frame, then tools/art/balatro_finish.py (pixel grid, trap palette, frame). The trap frame (tools/art/frames/trap.png) is the per-pixel mode of Balatro's spectral cards recoloured red; the AI pack cell (12) is kept but no longer shown: every build draws the Trap Pack at runtime from the player's own Spectral Pack, recoloured red with its label cleared (functions/art/release_art.lua), under the TRAP PACK label. Release: functions/art/release_art.lua also recolours the player's own spectral cards into the 12 traps and writes the trap names on the plates. |
| resources/textures/{1x,2x}/MPJokers.png | ai | exclude | MP jokers (Truce to Grudge), InkJoker joker model, card border from tools/art/joker_art.py, snapped to vanilla joker colours by tools/art/balatro_finish.py. Truce, Shortcut, Envy, Leftovers and Grudge were made again from text on 6 Nov (picks in tools/art/balatro_picks.json). Release: the player's own vanilla jokers in a purple duotone with an MP mark, built at runtime. |
| resources/textures/{1x,2x}/MPModeJokers.png | ai | exclude | The 12 mode jokers, same tools. Summit, Slipstream, Pace Car, Underdog and Wingman were made again from text on 6 Nov. Release: same as MPJokers. |
| resources/textures/{1x,2x}/MPDecks.png | ai | exclude | Lilac, Seer, Tangerine, Cobalt and Gemini deck backs. Release: the player's own deck backs, tinted per deck, with an MP mark. |
| resources/textures/{1x,2x}/MPBlindChips.png | ai | exclude | Clash, Hunt, Raid, Royale and Race chips with Balatro's glint (tools/art/mp_art.py). Release: the player's own boss chips tinted to each mode's colour, glint frames included. |
| resources/textures/{1x,2x}/NemesisChip.png | ai | exclude | Nemesis chip. Release: the player's own Crimson Heart chip, tinted. |
| resources/textures/{1x,2x}/TavernBacks.png | ai | exclude | 40 card backs of the Tavern shop. Release: the player's own deck backs at runtime (release_art.lua), the first 15 as they are, the next ones turned a quarter and a half round the colour wheel. |
| resources/textures/{1x,2x}/TavernPacks.png | ai | exclude | Tavern pack and crate art. Release: each Tavern pack shows the vanilla booster it names (tavern_apply.lua and tavern_shop_ui.lua already fall back to it). |
| resources/textures/{1x,2x}/TavernPortraits.png | ai | exclude | 80 profile portraits. Release: the player's own vanilla jokers (no legendaries), one per portrait, built at runtime by release_art.lua. |
| resources/textures/{1x,2x}/RankBadges.png | code | ship | tools/ranked/badges.py, drawn from its own palettes, no vanilla pixels. |
| resources/textures/{1x,2x}/RankFrames.png | code + vanilla-derived | exclude | tools/ranked/art.py, composed from Balatro's own stickers, chips, deck faces and packs, so it holds vanilla pixels. Release: an empty atlas for now (release_art.lua), so ranked frames, sleeves and the TRUE JIMBO pack show nothing until a runtime build from the player's copy exists. |
| resources/textures/{1x,2x}/RankSleeves.png | code + vanilla-derived | exclude | tools/ranked/art.py, composed from Balatro's own stickers, chips, deck faces and packs, so it holds vanilla pixels. Release: an empty atlas for now (release_art.lua), so ranked frames, sleeves and the TRUE JIMBO pack show nothing until a runtime build from the player's copy exists. |
| resources/textures/{1x,2x}/RankPack.png | code + vanilla-derived | exclude | tools/ranked/art.py, composed from Balatro's own stickers, chips, deck faces and packs, so it holds vanilla pixels. Release: an empty atlas for now (release_art.lua), so ranked frames, sleeves and the TRUE JIMBO pack show nothing until a runtime build from the player's copy exists. |
| resources/shaders/jimbo.fs | hand | ship | TRUE JIMBO edition shader. |
| resources/shaders/tshine_*.fs | hand | ship | 13 Tavern shine shaders. |
| resources/sounds/jukebox/* | third-party | exclude | Covers and remixes by other people. Owned by the jukebox stream; players add their own music in the release. |
| smods/assets/** | third-party | ship | Steamodded's own assets, under Steamodded's licence (release stream: LICENSES/). |
| resources/workshop/* | hand | ship | Mod workshop index, not an image. |

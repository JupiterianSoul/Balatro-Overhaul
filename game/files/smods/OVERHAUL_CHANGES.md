# Changes made for Balatro Overhaul

This folder holds Steamodded 26.1002.0 (https://github.com/Steamodded/smods), licensed under the GNU General Public License v3.0 (see LICENSE in this folder).

It was copied unchanged into Balatro Overhaul on 2026-10-23 and then modified for the Overhaul between 2026-10-23 and 2026-11-03. The changes make it run inside the Overhaul's own mod loader (functions in assets/modloader/) and fix crashes found while testing mods: card descriptions with a missing card, texture packs sharing an atlas key, missing shader settings, marquee text, mod versions that do not start with a number, and the load order of the splash screen and conf.lua modules.

The modified files keep their GPL v3.0 licence. Every change is in the Overhaul's git history (`git log -- assets/smods`).

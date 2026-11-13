# Patch set

This folder is the Overhaul's patch set, the same one the launcher applies to your own copy of Balatro.

- `files/`: files that exist only in the Overhaul, in full.
- `patches/`: edits to Balatro's own files. They hold only the Overhaul's lines and point at the original lines, so none of Balatro's code is here.
- `images/`, `lines/`, `manifest.lua`: the rest of the patch format. `tools/release/patcher` reads and applies it.

Balatro belongs to LocalThunk and Playstack and is not included. To play, let the launcher build the Overhaul from your own copy of the game.

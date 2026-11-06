# Balatro Overhaul

Balatro Overhaul is a free fan mod for [Balatro](https://www.playbalatro.com/). It adds online multiplayer (casual and ranked, with friends, parties, replays and spectating), new single player modes, quests, the Town, the Forge for making your own cards, a mod Workshop and a long list of quality of life changes. It plays in English, French and Spanish, with the rest of Balatro's languages for the base game.

It is an unofficial mod. It is not made, endorsed or supported by LocalThunk or Playstack. Balatro, its name, logo, art, music and code belong to them.

## What you need

- **Your own copy of Balatro.** The Overhaul doesn't contain the game. The launcher finds the copy you bought and builds the Overhaul from it, on your machine. Steam is the supported version on PC. The launcher checks the game version and tells you if yours is a different one.
- A 64-bit PC running Windows, macOS or Linux, for the launcher.
- For Android: the PC launcher builds the phone app from your copy (see below).

## Installing

Download the file for your system from the release page. Check it against `SHA256SUMS.txt` if you want to be sure it wasn't changed.

### Windows

1. Unzip `BalatroOverhaulLauncher-<version>-windows-x64.zip` anywhere.
2. Run `Balatro Overhaul Launcher.exe`.
3. The launcher looks for Balatro in your Steam libraries. If it doesn't find it, open the **My game** tab and paste the path to `Balatro.exe`, or drop the file on the window.
4. Press **Install**, then **Play**.

### macOS

1. Unzip `BalatroOverhaulLauncher-<version>-macos.zip` and move `Balatro Overhaul Launcher.app` to Applications.
2. The app isn't signed by Apple. The first time, right click it and choose **Open**, then **Open** again. If macOS still refuses, run `xattr -cr "/Applications/Balatro Overhaul Launcher.app"` in Terminal.
3. Same as Windows from step 3. On a Mac the game file is inside `Balatro.app`; the launcher finds it in Steam's folder.

### Linux

1. Unpack `BalatroOverhaulLauncher-<version>-linux-x86_64.tar.gz` (or use the single `.AppImage` file if there is one, after `chmod +x`).
2. Run `./AppRun` (or the AppImage).
3. Same as Windows from step 3. Native Steam, `~/.steam`, Flatpak and Snap Steam folders are all searched.

### Android

Not in this launcher build yet: the **Android APK** button says so. The APK maker exists and works from the Overhaul's source folder on a PC with Python 3, Java (keytool) and apksigner; it will come into the launcher in a later update.

The phone app is separate from the official Balatro app: different name, own saves, both can be installed.

### iPhone and iPad

Not available. Building an iPhone app needs a Mac to compile it and every player would have to sideload it with their own Apple account and re-sign it every week.

## Updating

When a new version is out, the launcher and the **Update** row on the title screen offer it. It downloads only the Overhaul's new files, applies them to your copy, keeps your saves and restarts into the new version. The changes are in Settings > Account > Changelog, and in `CHANGELOG.md`.

## Your saves

The Overhaul keeps its own saves, separate from your normal Balatro saves. Installing, updating or removing the Overhaul never touches your Balatro saves, and the launcher never changes your Steam files.

To remove the Overhaul, delete the launcher and its folder: `%APPDATA%\BalatroOverhaulLauncher` on Windows, `~/Library/Application Support/BalatroOverhaulLauncher` on macOS, `~/.local/share/BalatroOverhaulLauncher` on Linux.

## What is not included, and why

- **Balatro's files.** They aren't ours to share, so the release has none of them: no code, no art, no music, no sounds, no fonts. Everything of the game comes from your copy. If someone offers you a download with the game inside, it's not this.
- **Music in the Jukebox.** The covers and remixes some of us used while testing belong to the people who made them. The Jukebox plays music you add yourself (Settings > Jukebox).
- **AI-made art.** The release has none: the Overhaul's pictures are hand-made or built from the game's own sprites on your machine.
- **Developer tools.** The Debug menu and test hooks are switched off in the release.

## Playing online

Online play uses the Overhaul's own server, run by the Overhaul's developer, not by LocalThunk or Playstack.

- Your account is your player name and a random key kept on your device. The server keeps your friends, match results, ranked points and replays.
- Chat goes through a word filter. Be decent: no harassment, no hate, no cheating or exploiting bugs on purpose. You can mute or block any player.
- Crash reports are off until you turn them on in Settings > Account. When on, a crash sends the error, the game version, your platform and your mod list. Nothing personal.
- Bot-latro can use an online AI service (Anthropic, OpenAI, OpenRouter) if you give it your own key. It then sends the run's state to that service, under that service's terms. Your key stays on your device; local models (LM Studio, Ollama) send nothing out.
- No ads, no tracking, nothing is sold.
- Online play with chat is meant for players aged 13 and over.
- To have your account and its data deleted, open an issue on the [GitHub page](https://github.com/JupiterianSoul/Balatro-Overhaul-Releases/issues).
- The server is free and comes with no guarantee: it can be down, reset or closed.

## Mods

The Overhaul runs most Steamodded and Lovely mods. The Workshop lists mods from the community's Balatro Mod Index and downloads each one from its author's own page when you ask; the Overhaul doesn't host anyone's mod. Mods are made by other people: install the ones you trust.

## Credits and licences

Made by JupiterianSoul. Settings > Account > About the Overhaul lists every part made by someone else and its licence; the full texts are in the `LICENSES` folder:

- LÖVE 11.5 and its libraries (zlib licence, the others in `license.txt`)
- Steamodded (GNU GPL 3.0), shipped as source with its licence; the Overhaul's changes are listed in `assets/smods/OVERHAUL_CHANGES.md`
- nativefs (MIT), json.lua by rxi (MIT), the Balatro Mod Index (MIT)
- Thanks to Lovely Injector (MIT) for the patch format mods use, and to Balatro Multiplayer (GNU GPL 3.0), the first multiplayer mod for Balatro, which inspired parts of the multiplayer mode.

Buy Balatro to support the people who made it.

## Problems

Open an issue on the [GitHub page](https://github.com/JupiterianSoul/Balatro-Overhaul-Releases/issues) with what happened, your system and the game version (bottom right of the title screen).

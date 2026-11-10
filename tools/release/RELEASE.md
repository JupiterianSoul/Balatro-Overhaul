# Balatro Overhaul

Balatro Overhaul is a free fan mod for [Balatro](https://www.playbalatro.com/). It adds online multiplayer (casual and ranked, with friends, parties, replays and spectating), new single player modes, quests, The Casino, the Forge for making your own cards, a mod Workshop and a long list of quality of life changes. It plays in English, French and Spanish, with the rest of Balatro's languages for the base game.

It is an unofficial mod. It is not made, endorsed or supported by LocalThunk or Playstack. Balatro, its name, logo, art, music and code belong to them.

## What you need

- **Your own copy of Balatro.** The Overhaul doesn't contain the game. The launcher finds the copy you bought and builds the Overhaul from it, on your machine. Steam is the supported version on PC. The launcher checks the game version and tells you if yours is a different one.
- A 64-bit PC running Windows, macOS or Linux, for the launcher.
- For Android: the official Balatro app from Google Play on the same phone, and Android 6 or newer. No PC needed.

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

1. Install Balatro from Google Play and open it once.
2. On the phone, download `BalatroOverhaulLauncher-<version>-android.apk` from the release page and open it. Android asks once to allow installs from your browser or file manager: allow it, then press **Install**.
3. Open the new **Overhaul Launcher** app. On Android 11 and newer it first opens the **All files access** page. Turn it on if you want mods and your own music in the Jukebox, or go back to skip it (it asks again next time).
4. It's the same launcher as on PC, with the Play, Game, Saves, Settings and About tabs. It finds your Balatro on its own: press **Install** (it reads your Balatro and builds the Overhaul from it, which takes a minute), then **Play**. The app opens on the launcher every time, and **Play** starts the game.

If the install is blocked:

- **Samsung:** Settings > Security and privacy > Auto Blocker must be off while you install, you can turn it back on after.
- **Play Protect** may say the app is from an unknown developer. Tap **More details**, then **Install anyway**. The Overhaul isn't on Google Play, so Play Protect has never seen it.

If it says Balatro isn't installed, install it from Google Play, open it once, then press **Scan again** in the launcher's **Game** tab. If it says your version of Balatro isn't supported yet, a newer Overhaul is needed: download the new `.apk` from the release page and install it over the old one, your saves stay.

The Overhaul app is separate from the official Balatro app: different name, own saves, both stay installed. It needs the official app to stay installed only for the first install and for updates that change the game files.

### iPhone and iPad

Not available. Building an iPhone app needs a Mac to compile it and every player would have to sideload it with their own Apple account and re-sign it every week.

## Updating

When a new version is out, the launcher and the **Update** row on the title screen offer it, on PC and on Android. It downloads only the Overhaul's new files, applies them to your copy, keeps your saves and restarts into the new version. The changes are in Settings > Account > Changelog, and in `CHANGELOG.md`.

## Your saves

The Overhaul keeps its own saves, separate from your normal Balatro saves. Installing, updating or removing the Overhaul never touches your Balatro saves, and the launcher never changes your Steam files.

The first time, the launcher finds your Balatro save and asks if you want to load your progress (unlocks, discoveries and stats) into the Overhaul or start fresh. It only reads your Balatro save, and it zips both saves into its `backups` folder first. The **Saves** tab does it again later, imports a save `.zip` or a Balatro save folder, and exports the Overhaul's save. In the game, Settings > Account has **Import a save** and **Export my save** too (also in the profile window); an import makes a backup in the game's `backups` folder and restarts the game. Exports never hold your settings or your online key.

To remove the Overhaul on Android, uninstall the Overhaul app; Balatro and its saves stay. The Overhaul's own saves are deleted with it, so don't uninstall it to update: install the new `.apk` over it instead. On PC, delete the launcher and its folder: `%APPDATA%\BalatroOverhaulLauncher` on Windows, `~/Library/Application Support/BalatroOverhaulLauncher` on macOS, `~/.local/share/BalatroOverhaulLauncher` on Linux.

## What is not included, and why

- **Balatro's files.** They aren't ours to share, so the release has none of them: no code, no art, no music, no sounds, no fonts. Everything of the game comes from your copy. If someone offers you a download with the game inside, it's not this.
- **Music in the Jukebox.** The covers and remixes some of us used while testing belong to the people who made them. The Jukebox plays music you add yourself (Settings > Jukebox).
- **AI-made art.** The release has none: the Overhaul's pictures are hand-made or built from the game's own sprites on your machine.
- **Developer tools.** The Debug menu and test hooks are switched off in the release.

## Playing online

Online play uses the Overhaul's own server, run by the Overhaul's developer, not by LocalThunk or Playstack.

- Your account is your player name and a random key kept on your device. The server keeps your friends, match results, ranked points and replays.
- Chat goes through a word filter. Be decent: no harassment, no hate, no cheating or exploiting bugs on purpose. You can mute or block any player.
- Crash reports are on by default: a crash sends the error, the game version, your platform, what you were doing and your mod list. Nothing personal. Turn them off in Settings > Account.
- No ads, no tracking, nothing is sold.
- Online play with chat is meant for players aged 13 and over.
- To have your account and its data deleted, open an issue on the [GitHub page](https://github.com/JupiterianSoul/Balatro-Overhaul).
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

Open an issue on the [GitHub page](https://github.com/JupiterianSoul/Balatro-Overhaul) with what happened, your system and the game version (bottom right of the title screen).

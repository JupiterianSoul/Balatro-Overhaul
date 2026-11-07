# Balatro Overhaul

A free fan mod for [Balatro](https://www.playbalatro.com/): online multiplayer (casual and ranked, with friends, parties, replays and spectating), new solo modes, quests and progression, achievements, The Casino, the Forge for making your own jokers, a mod Workshop, and a long list of quality of life changes. In English, French and Spanish.

**Current version: 2.0 (pre-release).** It's a pre-release, so expect a few rough edges. Tell me about them (see [Problems](#problems)).

It's unofficial. It isn't made, endorsed or supported by LocalThunk or Playstack. Balatro, its name, logo, art, music and code belong to them.

## You need your own Balatro

The Overhaul doesn't contain the game. The launcher finds the copy you bought, checks it, and builds the Overhaul from it on your computer. Nothing of Balatro is in anything you download here. Steam is the supported version on PC (Xbox / Game Pass copies are found too, but may not be supported yet). On Android you need the official Balatro app from Google Play.

## Download

Grab the file for your system from the [latest release](../../releases/latest):

| System | File |
|---|---|
| Windows | `BalatroOverhaulLauncher-<version>-windows-x64.zip` |
| macOS | `BalatroOverhaulLauncher-<version>-macos.zip` |
| Linux | `BalatroOverhaulLauncher-<version>-linux-x86_64.tar.gz` (or the `.AppImage`) |
| Android | `BalatroOverhaul-<version>-android.apk` |

`SHA256SUMS.txt` has the checksums if you want to check a download.

## Installing on PC

1. Unzip the launcher anywhere and start it (`Balatro Overhaul Launcher.exe`, the `.app`, or `./AppRun` on Linux).
2. It looks for Balatro in your Steam libraries. Not found? Open the **Game** tab and drop `Balatro.exe` (or `Balatro.app`) on the window, or paste its path.
3. The first time, it finds your Balatro save and asks if you want to **load your progress** into the Overhaul or **start fresh**. Both saves are backed up first, and your Balatro save is never changed.
4. Press **Install**, then **Play**.

macOS: the app isn't signed by Apple. The first time, right click it and choose **Open**, then **Open** again. If macOS still refuses, run `xattr -cr "/Applications/Balatro Overhaul Launcher.app"` in Terminal.

## Installing on Android

1. Install Balatro from Google Play and open it once.
2. On the phone, download the `.apk` and open it. Allow installs from your browser or file manager when Android asks, then press **Install**.
3. Open the **Overhaul** app. The first start reads your Balatro and builds the Overhaul (about a minute), then restarts into the game.

Samsung: turn Auto Blocker off while you install (Settings > Security and privacy). Play Protect may warn about an unknown developer: **More details**, then **Install anyway**.

iPhone and iPad aren't supported.

## Updating

The launcher and the **Update** button on the title screen offer new versions. Only the Overhaul's own files are downloaded; your saves stay. If you're on 2.5, 2.6 or 2.7, you'll be offered 2.0 like any other update. Multiplayer needs everyone on the same version: the game tells you when a room runs another one.

## Your saves

The Overhaul keeps its own saves, separate from Balatro's.

- **Bring your Balatro progress:** the launcher offers it on first start. You can do it again any time in the launcher's **Saves** tab, which lists every Balatro save it finds.
- **Move a save between computers:** Settings > Account > **Export my save** (or **Export** in the launcher) writes one `.zip`. On the other computer, use **Import a save** in the game, or **Import** in the launcher, or just drop the `.zip` on the window.
- **Profiles:** Options > **Profile** switches between your three profiles, like in Balatro, and has Import save and Export save too.
- **Backups:** before any import, the current save is zipped into a `backups` folder (the game's and the launcher's). Nothing is ever overwritten without a copy.
- Exports never contain your settings or your online key, so they're safe to share.

## Playing online

Online play goes through the Overhaul's own server, run by me, not by LocalThunk or Playstack.

- Your account is your player name and a random key kept on your device. The server keeps your friends, match results, ranked points and replays.
- Chat goes through a word filter. Be decent. You can mute or block anyone.
- Crash reports are on by default and help me fix things fast: the error, the game version, your platform, what you were doing and your mod list. Nothing personal. Turn them off in Settings > Account.
- No ads, no tracking, nothing is sold. Online play with chat is meant for players aged 13 and over.
- To have your account and its data deleted, open an issue.
- The server is free and comes with no guarantee: it can be down, reset or closed.

## What isn't included

- **Balatro's files.** Everything of the game comes from your own copy.
- **AI-made art.** The release has none. The Overhaul's pictures are hand-made or built from the game's own sprites on your machine, and the release only deals Balatro's own 150 jokers.
- **Music in the Jukebox.** Add your own in Settings > Jukebox.
- **Developer tools.** The Debug menu is switched off.

## Mods

The Overhaul runs most Steamodded and Lovely mods. The Workshop lists mods from the community's Balatro Mod Index and downloads each one from its author's page. Install the ones you trust.

## Problems

Open an issue with what happened, your system and the version (bottom right of the title screen, or Settings > Account > About). A crash report, if it was sent, already has the details.

## Support

The Overhaul is free and always will be. If you want to help pay for the server, there's a [Patreon](https://www.patreon.com/cw/JupiterianSoul). Thanks either way.

## Credits

Made by JupiterianSoul. Special thanks to Samlegeek63 and Monoceros.

Built with LÖVE 11.5 (zlib), Steamodded (GNU GPL 3.0, shipped as source with its licence), nativefs (MIT), json.lua by rxi (MIT) and the Balatro Mod Index (MIT). Thanks to Lovely Injector (MIT) for the patch format mods use, and to Balatro Multiplayer (GNU GPL 3.0), the first multiplayer mod for Balatro. The full licence texts ship in the `LICENSES` folder; Settings > Account > About lists every part made by someone else.

Buy Balatro to support the people who made it.

<div align="center">

<img src="docs/logo.png" width="160" alt="Balatro Overhaul">

# Balatro Overhaul

**A free fan mod for [Balatro](https://www.playbalatro.com/): online multiplayer, new modes, minigames, your own jokers and a lot more.**

[![Latest release](https://img.shields.io/github/v/release/JupiterianSoul/Balatro-Overhaul?include_prereleases&label=version&color=fe5f55)](https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/JupiterianSoul/Balatro-Overhaul/total?color=009dff)](https://github.com/JupiterianSoul/Balatro-Overhaul/releases)
![Windows](https://img.shields.io/badge/Windows-supported-0078d4?logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-supported-555555?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-supported-f0b400?logo=linux&logoColor=black)
![Android](https://img.shields.io/badge/Android-supported-3ddc84?logo=android&logoColor=white)
![Languages](https://img.shields.io/badge/languages-EN%20%7C%20FR%20%7C%20ES-8a63d2)

[**Download**](https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest) &nbsp;·&nbsp; [Install guide](#install) &nbsp;·&nbsp; [What's new](CHANGELOG.md) &nbsp;·&nbsp; [Report a problem](https://github.com/JupiterianSoul/Balatro-Overhaul/issues) &nbsp;·&nbsp; [Support the server](https://www.patreon.com/cw/JupiterianSoul)

</div>

> [!IMPORTANT]
> You need your own copy of Balatro. Nothing you download here contains the game: the Overhaul is built from the copy you bought, on your own device.

<div align="center">
<img src="docs/screenshots/launcher.png" width="49%" alt="The launcher's Play tab">
<img src="docs/screenshots/launcher-android.png" width="49%" alt="The launcher's Android tab">
</div>

## What's in it

**Play together**
- Online matches against friends or strangers: casual, ranked with seasons, and parties for up to eight players (Battle Royale, Teams, Raid and Race).
- PvP Boss Blinds, multiplayer jokers, decks and stakes made for versus play, emotes, chat with a word filter, friends and blocking.
- Replays of every match and live spectating.

**More to play alone**
- New modes and challenges, a daily and weekly run, quests, achievements and a progression track with rewards.
- New Overhaul stakes after Gold: Chaos, Apocalypse, Oblivion and Transcendent.
- The Casino and a set of minigames, including Jimbo Jam, a rhythm game that plays any song you add to your Jukebox.

**Make it yours**
- The Forge: build your own jokers, blinds, decks and more, with your own pixel art, and share them online.
- A Workshop that installs Steamodded and Lovely mods from the community's mod index, on PC and on Android.
- A Jukebox for your own music, card skins, palettes, suit colours and table looks.

**Quality of life**
- Touch, controller and keyboard everywhere, a phone layout that fits in portrait and landscape, and an on-screen keyboard.
- Speed settings, frame rate caps up to 165, sharp scaling on high DPI screens, and the CRT effect like vanilla.
- Saves you can export, import and move between devices, with automatic backups.

## Install

Download the file for your device from the [latest release](https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest).

| Device | File | You need |
|---|---|---|
| Windows | `BalatroOverhaulLauncher-<version>-windows-x64.zip` | Balatro on Steam |
| macOS | `BalatroOverhaulLauncher-<version>-macos.zip` | Balatro on Steam |
| Linux | `BalatroOverhaulLauncher-<version>-linux-x86_64.tar.gz` | Balatro on Steam |
| Android | `BalatroOverhaul-<version>-android.apk` | Balatro from Google Play |

`SHA256SUMS.txt` in each release lets you check your download.

<details open>
<summary><b>Windows</b></summary>

1. Unzip the launcher anywhere and open `Balatro Overhaul Launcher.exe`. If Windows warns about an unknown publisher, click **More info**, then **Run anyway**.
2. The launcher finds Balatro in your Steam libraries. If it doesn't, open the **Game** tab and drop `Balatro.exe` on the window, or paste its path.
3. The first time, it offers to **bring your Balatro progress** or **start fresh**. Both saves are backed up first, and your Balatro save is never changed.
4. Press **Install**, then **Play**. The launcher adds desktop, Start menu and Steam shortcuts.

</details>

<details>
<summary><b>macOS</b></summary>

1. Unzip and drag `Balatro Overhaul Launcher.app` to Applications.
2. The app isn't signed by Apple: right click it, choose **Open**, then **Open** again. If macOS says it is damaged, run `xattr -cr "/Applications/Balatro Overhaul Launcher.app"` in Terminal.
3. Then it works like on Windows: it finds Balatro, you press **Install**, then **Play**.

</details>

<details>
<summary><b>Linux</b></summary>

1. Unpack the archive and run `./balatro-overhaul-launcher` (or double click it).
2. It finds Balatro in your Steam libraries (native Steam and Flatpak), checks it, and builds the Overhaul in `~/.local/share/BalatroOverhaulLauncher`.
3. Press **Install**, then **Play**. The launcher adds Balatro Overhaul and its launcher to your app menu.

</details>

<details>
<summary><b>Android, straight from your phone</b></summary>

1. Install Balatro from Google Play and open it once.
2. Download `BalatroOverhaul-<version>-android.apk` on the phone and open it. Allow installs from your browser or file manager when Android asks.
3. Open the **Overhaul** app. The first start reads your Balatro and builds the Overhaul (about a minute), then restarts into the game.

Samsung: turn Auto Blocker off while you install (Settings > Security and privacy). If Play Protect warns about an unknown developer, tap **More details**, then **Install anyway**.

</details>

<details>
<summary><b>Android, built by the PC launcher</b></summary>

No Balatro on your phone, but you own it on Steam? The PC launcher can build the phone app from your Steam copy.

1. Install the Overhaul on your PC with the launcher (see above).
2. Open the launcher's **Android** tab and press **Make Android APK**. It takes a few seconds and needs nothing else installed.
3. Copy the `.apk` it made to your phone (the tab shows where it is) and open it there.

The app is signed with a key made for you on your PC, so later versions install over it and keep your saves.

</details>

iPhone and iPad aren't supported.

## Updates

New versions show up on the title screen of the game, on every platform, and in the launcher. Only the Overhaul's own files are downloaded and your saves are never touched. Multiplayer needs everyone on the same version, and the game tells you when a room runs another one.

## Your saves

The Overhaul keeps its own saves, separate from Balatro's.

- **Bring your Balatro progress** when the launcher first starts, or later from its **Saves** tab.
- **Move a save** to another device: Settings > Account > **Export my save** writes one `.zip`. Import it in the game or the launcher, or drop it on the window.
- **Backups**: before any import, the current save is zipped into a `backups` folder.
- Exports never contain your settings or your online key, so they're safe to share.

## Playing online

Online play goes through the Overhaul's own server, run by me, not by LocalThunk or Playstack.

- Your account is your player name and a random key kept on your device. The server keeps your friends, match results, ranked points and replays.
- Crash reports are on by default and help me fix things fast: the error, the game version, your platform, what you were doing and your mod list. Nothing personal. Turn them off in Settings > Account.
- No ads, no tracking, nothing is sold. Online play with chat is meant for players aged 13 and over.
- To have your account and its data deleted, [open an issue](https://github.com/JupiterianSoul/Balatro-Overhaul/issues).
- The server is free and comes with no guarantee: it can be down, reset or closed.

## Problems

[Open an issue](https://github.com/JupiterianSoul/Balatro-Overhaul/issues) with what happened, your device and the version (bottom right of the title screen). If a crash report was sent, it already has the details.

## Support

The Overhaul is free and always will be. If you want to help pay for the server, there's a [Patreon](https://www.patreon.com/cw/JupiterianSoul). Thanks either way.

## Licence

The Overhaul's own code, art and text are **all rights reserved**. You may download, install and play it, and share links to this page. You may not copy, modify, redistribute or reuse its code or assets in another project. See [LICENSE](LICENSE) for the full terms, and [LICENSES](LICENSES) for the open source parts it uses, which keep their own licences.

## Credits

Made by JupiterianSoul. Special thanks to Samlegeek63 and Monoceros.

Built with LÖVE 11.5 (zlib), Steamodded (GNU GPL 3.0, shipped as source with its licence), nativefs (MIT), json.lua by rxi (MIT) and the Balatro Mod Index (MIT). Thanks to Lovely Injector (MIT) for the patch format mods use, and to Balatro Multiplayer (GNU GPL 3.0), the first multiplayer mod for Balatro.

The Overhaul is unofficial. It isn't made, endorsed or supported by LocalThunk or Playstack. Balatro, its name, logo, art, music and code belong to them. Buy Balatro to support the people who made it.

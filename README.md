<div align="center">

<img src="docs/overhaul-launcher-icon.png" width="160" alt="Balatro Overhaul">

# Balatro Overhaul

**An overhaul of [Balatro](https://www.playbalatro.com/) with new modes, content and online play.**

[![Latest release](https://img.shields.io/github/v/release/JupiterianSoul/Balatro-Overhaul?include_prereleases&label=version&color=fe5f55)](https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/JupiterianSoul/Balatro-Overhaul/total?color=009dff)](https://github.com/JupiterianSoul/Balatro-Overhaul/releases)
![Windows](https://img.shields.io/badge/Windows-supported-0078d4?logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-supported-555555?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-supported-f0b400?logo=linux&logoColor=black)
![Android](https://img.shields.io/badge/Android-supported-3ddc84?logo=android&logoColor=white)
![Languages](https://img.shields.io/badge/languages-EN%20%7C%20FR%20%7C%20ES-8a63d2)

[**Download**](https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest) &nbsp;·&nbsp; [Install guide](#install) &nbsp;·&nbsp; [Changelog](CHANGELOG.md) &nbsp;·&nbsp; [Report a bug](https://github.com/JupiterianSoul/Balatro-Overhaul/issues) &nbsp;·&nbsp; [Patreon](https://www.patreon.com/cw/JupiterianSoul)

</div>

> [!IMPORTANT]
> You need to own Balatro. The downloads here don't contain the game, the launcher builds the mod from your own copy.

<div align="center">
<img src="docs/screenshots/launcher.png" width="49%" alt="The launcher on PC">
<img src="docs/screenshots/phone-launcher.png" width="49%" alt="The launcher on Android">
</div>

## Features

- Online multiplayer: 1v1 and parties up to 8, casual or ranked, with friends or random players
- 4 new stakes after Gold Stake
- Custom runs where you set the rules, plus daily and weekly runs
- The Forge: make your own jokers, decks, tarots and more, and share them
- The Casino: quests, cosmetics and minigames
- XP, levels, quests and 242 achievements
- Jimbo comments on your runs
- Mods menu and workshop, works on Android too
- Touch, controller and keyboard on PC and phone
- English, French and Spanish

See the [changelog](CHANGELOG.md) for details.

## Install

Get the file for your device from the [latest release](https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest):

| Device | File | You need |
|---|---|---|
| Windows | `BalatroOverhaulLauncher-2.0-windows-x64.zip` | Balatro on Steam |
| macOS | `BalatroOverhaulLauncher-2.0-macos.zip` | Balatro on Steam |
| Linux | `BalatroOverhaulLauncher-2.0-linux-x86_64.tar.gz` | Balatro on Steam |
| Android | `BalatroOverhaulLauncher-2.0-android.apk` | Balatro from Google Play |

It's the same launcher everywhere: it finds your Balatro, you press **Install**, then **Play**.

<details open>
<summary><b>Windows</b></summary>

Unzip it anywhere and open `Balatro Overhaul Launcher.exe`. Windows will probably warn you about an unknown publisher, click **More info** then **Run anyway**.

If Balatro is on Steam the launcher finds it by itself. If not, drag `Balatro.exe` onto the window.

The first time, it asks if you want to keep your Balatro progress or start fresh. Either way both saves get backed up, and your real Balatro save is never touched. Then press **Install** and **Play**. It also adds shortcuts to your desktop, Start menu and Steam.

</details>

<details>
<summary><b>macOS</b></summary>

Unzip and put `Balatro Overhaul Launcher.app` in Applications. The app isn't signed by Apple, so the first time you have to right click it, **Open**, then **Open** again. If macOS says it's damaged, run this in Terminal:

```
xattr -cr "/Applications/Balatro Overhaul Launcher.app"
```

After that it works like on Windows.

</details>

<details>
<summary><b>Linux</b></summary>

Unpack it and run `./balatro-overhaul-launcher`. It finds Balatro in your Steam library (Flatpak Steam too), and adds the game and the launcher to your app menu after the install.

</details>

<details>
<summary><b>Android</b></summary>

You need Balatro from Google Play, opened at least once.

Download the `.apk` on your phone and open it. Android will ask you to allow installs from your browser or file manager. Then open **Overhaul Launcher**, press **Install** (takes about a minute) and **Play**.

It's the same launcher as on PC, so you also get the Saves tab to export or import your saves.

On Samsung, turn off Auto Blocker while you install (Settings > Security and privacy). If Play Protect complains, tap **More details** then **Install anyway**.

<p align="center"><img src="docs/screenshots/phone-launcher-portrait.png" width="30%" alt="The launcher on a phone in portrait"></p>

</details>

<details>
<summary><b>Android, if you only have Balatro on Steam</b></summary>

The PC launcher has an **Android** tab that makes the phone app from your Steam copy. Install the Overhaul on your PC first, then press **Make Android APK**, copy the file to your phone and install it.

<p align="center"><img src="docs/screenshots/launcher-android.png" width="60%" alt="The Android tab of the PC launcher"></p>

</details>

No iPhone, sorry.

## Updates

When there's a new version, the game tells you on the title screen and installs it. The launcher does too. Your saves stay where they are. For multiplayer, everyone needs to be on the same version.

## Saves

The Overhaul has its own saves, separate from Balatro's.

- To move your save to another device, use **Export my save** (in Settings > Account, or the launcher's Saves tab). It makes one `.zip` you can import on the other side.
- Before any import, your current save is backed up.
- Exports don't include your settings or your online key, so you can share them.

## Online

Multiplayer runs on my own server, not LocalThunk's or Playstack's.

Your account is just your name and a random key stored on your device. Crash reports are on by default: they send the error, the version, your platform and your mod list, nothing personal, and you can turn them off in Settings > Account. No ads, no tracking.

If you want your account deleted, open an issue. The server is free, so it can go down from time to time.

## Bugs

Open an [issue](https://github.com/JupiterianSoul/Balatro-Overhaul/issues) and tell me what happened, on which device, and the version (bottom right of the title screen).

## Support

It's free and it'll stay free. If you want to help pay for the server there's a [Patreon](https://www.patreon.com/cw/JupiterianSoul), no pressure.

## License

All rights reserved. You can download it, play it and share the link, but you can't reuse, modify or redistribute the code. Full text in [LICENSE](LICENSE). The open source parts it uses keep their own licenses, see [LICENSES](LICENSES).

## Credits

Made by JupiterianSoul. Thanks to Samlegeek63 and Monoceros.

Uses LÖVE 11.5, Steamodded, nativefs, json.lua and the Balatro Mod Index. Thanks to Lovely Injector, and to Balatro Multiplayer, which did multiplayer first.

This is a fan mod. It's not made or endorsed by LocalThunk or Playstack, and Balatro belongs to them. Go buy it.

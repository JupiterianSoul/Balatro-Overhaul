# Balatro Overhaul on phones

This is how the public release gets onto Android and iPhone without us ever handing out a copy of Balatro. Short version:

- **Android works.** The player builds their own APK from their own copy of the game, the same way Balatro Mobile Maker does. Our maker ships only the open LÖVE 11.5 runtime, the Overhaul's own Java bits and the Overhaul's own files. `tools/release/android/make_apk.py` does it.
- **Android with only a phone works on desktop LÖVE and in every check we can run without a phone.** An Android app can find the official Balatro app and read its APK without root. The installer APK (`BalatroOverhaulLauncher-<version>-android.apk`, its own app called "Overhaul") does that, builds the Overhaul with the same patcher as the PC launcher and runs it. It has not run on a real phone yet (see "Still to check on a phone").
- **iPhone is not something we can build here.** It needs a Mac to compile the LÖVE iOS app once, and every player then has to sideload it with their own Apple ID (7 days per signature with a free account). The App Store copy of Balatro can't be read by another app on a normal iPhone.

## How Balatro Mobile Maker does it

[Balatro Mobile Maker](https://github.com/blake502/balatro-mobile-maker) runs on the player's PC. It finds `Balatro.exe` in the default Steam folder (or a `Balatro.exe` / `Game.love` next to the tool), unpacks the game with 7-Zip, applies a few optional patches (FPS cap, landscape lock, high DPI, CRT shader off), then:

- **Android:** downloads OpenJDK, apktool, uber-apk-signer and `love-11.5-android-embed.apk`, decodes the LÖVE APK with apktool, copies the zipped game to `assets/game.love`, swaps in its own `AndroidManifest.xml`, rebuilds with apktool, signs with uber-apk-signer's debug key and, if the phone is plugged in with USB debugging, installs it with `adb install`. From its source (`View.cs`):
  - `apktool.jar d -s -o balatro-apk love-11.5-android-embed.apk`
  - `fileCopy("balatro.zip", "balatro-apk/assets/game.love")`
  - `fileCopy("Balatro-APK-Patch/AndroidManifest.xml", "balatro-apk/AndroidManifest.xml")`
  - `uber-apk-signer.jar -a balatro.apk`, then `adb install balatro.apk`
- **iOS:** downloads a prebuilt `balatro-base.ipa` (a LÖVE iOS app they compiled on a Mac), drops `game.love` into it and leaves the player to sideload it with AltStore.

The game files never leave the player's machine. That is the part that keeps it a mod and not a copy of the game, and it is the part we copy.

## The Overhaul's Android maker

Two steps, so players never need apktool:

1. **Runtime APK (built by us, shippable).** `make_apk.py runtime` decodes the official `love-11.5-android.apk` (checked by sha256, anything else is refused), and:
   - writes our own manifest: package `com.jupiteriansoul.balatrooverhaul`, label "Balatro Overhaul", no `.love` file handlers, no LÖVE loader activity, a unique androidx-startup authority so it can sit next to plain LÖVE on the same phone;
   - turns on LÖVE's embed mode (`res/values/bools.xml`, `embed = true`), which makes `GameActivity` load `assets/game.love` and never show the LÖVE no-game screen;
   - adds the Overhaul's own Java parts, in smali, from `tools/release/android/smali/` (see the next section);
   - writes `assets/overhaul_runtime.json` (package, version, LÖVE hash) and nothing else in `assets/`.
   
   Output: `dist/release/android/overhaul-runtime.apk`, about 7 MB. It contains no Lua, no game art and no game sound.
2. **Player APK (built on the player's machine).** `make_apk.py build --game <patched folder>` zips the patched game into `game.love`, adds it to a copy of the runtime as a stored entry, makes the app icon from the player's own Joker card (`resources/textures/2x/Jokers.png`, the first card, on Balatro red), aligns every stored entry (4 bytes, 4096 for `.so`), and signs with v1, v2 and v3 using a key it makes for that player. The key stays the same between builds so updates install over the old app and keep saves. Output: `dist/android/BalatroOverhaul-<version>.apk`, which is outside `dist/release/` on purpose since it holds the player's game.

Commands:

```
python3 tools/release/android/make_apk.py runtime
python3 tools/release/android/make_apk.py standin
python3 tools/release/android/make_apk.py build --game .night/mobile/standin
python3 tools/release/android/make_apk.py inspect dist/android/BalatroOverhaul-2.5.apk
python3 tools/release/android/test_android.py
```

`build` takes `--game DIR` (a folder with `main.lua`, the launcher's patched output) or `--game-love FILE`, plus `--runtime`, `--icon PNG`, `--out DIR`, `--keystore FILE` (password in `FILE.pass`) and `--key-dir DIR`. It refuses a keystore with "release" in its name: it only ever signs with the player's own key.

What the player's machine needs for `build`: Python 3, Java (for `keytool` and `apksigner`) and `apksigner` from Android build-tools. apktool is only needed for `runtime`, which we run once. When run from this repo the key lives in `.night/mobile/android-keys/`, outside the repo in the player's data folder (`~/.local/share/balatro-overhaul/android`, `%APPDATA%\balatro-overhaul\android`, `~/Library/Application Support/balatro-overhaul/android`).

Installing: with USB debugging on, `adb install -r dist/android/BalatroOverhaul-<version>.apk`. Without a cable, copy the APK to the phone and open it (Android asks once to allow installs from that file manager).

## What the old phone build had, and what carries over

The dev build (`build.sh`) is the official Playstack APK, decoded and rebuilt with our changes. That can't ship. Here is what it adds and where each piece ends up in the LÖVE runtime:

| Dev build | Runtime APK |
|---|---|
| `TlsTunnel` (127.0.0.1:44380, Java does TLS for multiplayer, the mod workshop and the bot, since LÖVE 11.5 has no HTTPS) started from Playstack's `PlatformActivity` | Same class, started at the end of `GameActivity.onCreate` |
| `HighRefreshRate` (asks for the highest refresh mode, 90 or 120 Hz) in `GameActivity.onCreate` and `SDLSurface.surfaceChanged` | Same class, same two calls |
| Rotate with the phone only when auto-rotate is on (`SDLActivity.bomOrientation`) | Same method and the same two call sites |
| All files access request on Android 11+ for the Downloads scan (mods installer, jukebox imports) | Same request; on Android 6 to 10 it asks for the normal storage permission instead, which the dev build never did |
| Permissions: INTERNET, VIBRATE, BLUETOOTH, storage, all files access | Same, plus READ_MEDIA_AUDIO for music on Android 13+ |
| Landscape, fullscreen, `singleTop`, cleartext allowed (local test server), legacy storage | Same |
| Native libs: liblove, libopenal, libmpg123, libc++_shared for arm64-v8a and armeabi-v7a | LÖVE 11.5's own builds of the same four, same two ABIs |
| "Overhauled by Jupiterian Soul" toast at start | Same toast, same text |
| Ownership check: refuses to start unless the Play Store Balatro is installed (needs QUERY_ALL_PACKAGES) | Not carried over. In the release the game files are the player's own copy, so ownership is already proven, and the check would lock out Steam owners who build from their PC copy |
| `love.platform` (Playstack's native module: Play Games sign-in, achievements, cloud saves, billing, Singular analytics, notch position) | Not there. The game already stubs it when missing (`assets/main.lua`, `engine/save_manager.lua`, `engine/load_manager.lua`), the same way the PC build runs |

What doesn't carry over:

- Google Play Games achievements and cloud saves, Play billing, Playstack's analytics and review prompt. They belong to Playstack's app and Google account setup; the stubs turn them off.
- The notch position from `love.platform.getNotchPosition`. LÖVE's own safe area (`love.window.getSafeArea`) still works.
- Saves don't move over by themselves: the new app has its own package and its own save folder.
- Debug flags: the dev manifest is `debuggable`, the runtime is not.

Not tested on a real phone yet: nothing here has run on a device. Checked so far: the smali assembles, the patched methods are present after a decode round trip, `apksigner verify` passes v1/v2/v3, `zipalign -c -p 4` passes, `aapt` shows the right package, label, activity and permissions.

## Reading the official app on the phone

Yes, an Android app can read another app's installed APK, without root:

- `PackageManager.getApplicationInfo(pkg, 0).sourceDir` is "the full path to the base APK for this application" ([ApplicationInfo](https://developer.android.com/reference/android/content/pm/ApplicationInfo)). That file is readable by other apps, which is how APK extractor apps work, for example [APK Extractor on IzzyOnDroid](https://apt.izzysoft.de/packages/io.github.abdurazaaqmohammed.ApkExtractor/).
- Since Android 11 the other app has to be visible first. Declaring it by name in `<queries>` is enough, no QUERY_ALL_PACKAGES needed ([package visibility](https://developer.android.com/training/package-visibility/declaring)). The runtime declares `com.playstack.balatro.android`, the Google Play package of Balatro ([Play listing id](https://appgoblin.info/apps/com.playstack.balatro.android)).
- The official APK is itself a LÖVE game: the Lua, art and sound sit in its `assets/` as plain files. Play may install it as a base APK plus config splits; the game files are in the base APK.
- Storage Access Framework is not needed for this. SAF only helps if a player wants to pick a `Balatro.exe` or `.love` from their Downloads, which the all files access permission already covers.

What the runtime does: at start, `GameActivity` looks the official app up and puts the path of its base APK in the environment variable `OVERHAUL_OFFICIAL_APK`, so Lua can read it with `os.getenv`. The on-phone installer below uses it.

## On-phone install

1. The player installs `BalatroOverhaulLauncher-<version>-android.apk`: the runtime with its own package (`com.jupiteriansoul.balatrooverhaul.phone`), label ("Overhaul") and icon (`tools/release/android/icon/installer.png`, no Balatro art), plus a `game.love` that holds only the bootstrap (`tools/release/android/bootstrap/`), the launcher's patcher (`tools/release/patcher/apply.lua`, `zipread.lua`, `love_ctx.lua`, copied at build time) and the patch set. No game files, so it can be shared.
2. On first start the bootstrap reads `OVERHAUL_OFFICIAL_APK`, copies the official APK into its own save folder (`official.zip`), mounts it and reads its `assets/` through `love.filesystem`. `apply.lua` checks `version.jkr` and the size and sha256 of every vanilla file the patch set uses, then rebuilds the Overhaul into `overhaul_game.new/`, writes a marker with the patch id, swaps it to `overhaul_game/`, deletes the copy and restarts LÖVE (`love.event.quit("restart")`).
3. Every start after that, `main.lua` sees the marker, mounts `overhaul_game/` in front of everything else, runs the game's own `conf.lua` and `main.lua`, and from there it is the normal game. A new patch (new Overhaul version) has a new id, so it installs again.

Screens: one centred column, gold title, a progress bar, and two error screens (Balatro not installed, Balatro version not supported yet) with "Tap to close". Strings in EN, FR and ES, picked from the phone language (`OVERHAUL_LANG`, set by the runtime from `Locale.getDefault()`).

The patch set is the PC launcher's own format (`tools/release/patcher/make_patch.py`), made against the official APK instead of `Balatro.exe`: `make_patch.py --vanilla` takes an APK and reads the game from its `assets/`. One installer, one patcher, two vanillas. The installer refuses a patch set whose `game_version` has no `[M]` (the Steam build), because the phone only has the mobile files.

Lines one Balatro has and the other doesn't: each patch set is built with the other game as `--other` (the PC set with the official APK, the phone set with the Steam copy), so a line the Overhaul shares with either Balatro ships as a reference or an edit, never as plain text. `pack_overhaul.sh` checks the PC set and the whole release against both the Steam copy and the APK, and `pack.sh` checks `android/` against the APK and then against the Steam copy. Both stop on any vanilla line, file or image.

Why it needs its own patch set: the Overhaul is built on the mobile version of Balatro (`version.jkr` says `1.0.1o-FULL [M]`, `PROD_mobile`), while the PC launcher's vanilla is the Steam build (`1.0.1o-FULL`, `PROD_PC_Console`), which has no `engine/platform.lua` or `engine/load_manager.lua` at all.

Building it (`tools/release/android/pack.sh`, called by `pack_overhaul.sh`):

```
adb shell pm path com.playstack.balatro.android
adb pull <the base.apk path it prints> .night/official-base.apk
bash tools/release/pack_overhaul.sh
```

`pack.sh` takes the official APK from `BALATRO_MOBILE_APK` or `pack_overhaul.sh --mobile-apk FILE` (default `.night/official-base.apk` in the worktree, then in the main checkout) and the signing key from `INSTALLER_KEYSTORE` or `--installer-key FILE` (default a test key it makes in the main checkout's `.night/android-installer/`, so every worktree signs with the same key). It prints the certificate SHA-256 it signed with: a phone only installs a new installer over the old one when that matches, otherwise the old app (and its saves) has to be uninstalled first. Without an official APK it skips the installer; with `--mobile-apk` pointing at a missing file it stops. It writes `dist/release/android/BalatroOverhaulLauncher-<version>-android.apk` and `android-patch-<version>.zip` (with its feed entry in `.zip.json`), then runs the vanilla checks below. By hand:

```
python3 tools/release/patcher/make_patch.py --vanilla .night/official-base.apk --out .night/patch-mobile
python3 tools/release/android/make_apk.py installer --patch .night/patch-mobile --keystore <key.p12>
```

`installer` builds its own runtime with the installer package and label unless `--runtime` is given, and signs with `--keystore` (password in `<key>.p12.pass`; made if missing). The release key is the runner's: the installer is the one APK signed by us, not by the player, and every later installer must use the same key or Android refuses the update.

Tested here with `balatro-v0.7-full.apk` (package `com.playstack.balatro.android`, `1.0.1o-FULL [M]`, no Overhaul code in it) standing in for the official app:

- `tools/release/android/test_bootstrap.sh` with `INSTALLER_APK=<the built APK>` runs the APK's own `game.love` in desktop LÖVE: the install reaches the Overhaul's first-run name prompt and `patcher/roundtrip_check.py` finds all 724 files byte for byte equal to `assets/` minus `EXCLUDE.txt`.
- `tools/release/android/test_android.py` (with `OFFICIAL_APK`): package, label, `<queries>`, permissions, signature, alignment, its own icon, the patcher files equal to `tools/release/patcher/`, no game file outside the patch set, the vanilla check against the official APK and the Steam copy, refusal of a Steam patch set, and the PC path from the Steam copy.
- `tools/release/android/test_update.py` (with `OFFICIAL_APK`): install, damaged and wrong-Balatro updates, the full in-game update, no downgrade, recovery after a kill mid-swap and the PC-built APK.

## Still to check on a phone

None of this has run on a device. On an Android phone with USB debugging on:

```
adb install -r dist/release/android/BalatroOverhaulLauncher-<version>-android.apk
adb shell pm path com.playstack.balatro.android
adb shell monkey -p com.jupiteriansoul.balatrooverhaul.phone -c android.intent.category.LAUNCHER 1
adb logcat -s SDL LOVE GameActivity AndroidRuntime
adb shell run-as com.jupiteriansoul.balatrooverhaul.phone ls files/save/BalatroOverhaul
```

`run-as` only works on a debuggable build; on the release build check from the screen instead. What to look for:

- `sourceDir` is readable and `OVERHAUL_OFFICIAL_APK` is set (the bootstrap gets past "Looking for Balatro...").
- The Play copy's `version.jkr` and vanilla files match the patch set (the stand-in may not be byte for byte the Play copy; if it says "not supported", the patch set has to be made from the phone's own `base.apk`, pulled with the commands above).
- Time and memory of the first install on a phone (the copy is about 65 MB, the build about 720 files).
- The restart into the game (`love.event.quit("restart")` on Android), the toast, the TLS tunnel (multiplayer connects), rotation and high refresh rate.
- An in-game update from the `android_patch` feed, and installing a newer installer APK over the old one (saves kept).
- Uninstalling the official Balatro afterwards: the Overhaul keeps running from `overhaul_game/`, only updates need the official app back.

## The launcher's APK maker

The PC launcher's Android tab builds the same updatable APK as `make_apk.py build --vanilla`, with nothing to install: no Python, no Java, no Android tools. It is plain Lua in `tools/release/android/launcher/` (`make_apk.lua`, `p256.lua`), shipped in `launcher.love` under `android/` with the unsigned runtime (`android/runtime.apk`, made by `make_apk.py runtime` during `pack_overhaul.sh`), the bootstrap and `love_ctx.lua`.

1. It checks the player's Balatro against the launcher's patch set (the same full check as an install).
2. It writes `game.love`: the bootstrap, the patcher, the patch set the launcher has now (bundled or downloaded) and every file of the player's Balatro under `vanilla/`, copied as they are compressed in `Balatro.exe` (no recompression).
3. It copies the runtime's entries, drops any old signature, adds `game.love` stored, and aligns stored entries like zipalign (4 bytes, 4096 for `.so`).
4. It signs with APK Signature Scheme v2, ECDSA P-256 with SHA-256. The key is made once per player from the OS random source and kept in the launcher's save folder (`android/player-key.txt`), so later APKs install over the first one and keep saves. The certificate is self-signed and rebuilt the same from the key every time.

The APK lands in the launcher's save folder as `BalatroOverhaul-<version>.apk` (the Android tab says where). Android 7 and newer install it; v1 (JAR) signing is not written, so Android 5 and 6 can't. Its in-game updates come from the `android_patch_pc` feed, which `publish_feed.ts` fills with the launcher's own patch set.

Test: `run_launcher.sh --cli apk --balatro <Balatro.exe>` (with `LAUNCHER_APK_DIR` for the output), then `apksigner verify -v --min-sdk-version 24`, `zipalign -c -p 4`, and `test_bootstrap.sh` with `INSTALLER_APK=<that APK> NO_OFFICIAL=1`, which installs from the APK's own `vanilla/`. Checked 7 Nov: apksigner verifies v2, aligned, the round trip gives back `assets/` exactly, the game reaches the name prompt, and a Samsung phone (Android 15) accepted the install.

## Updates

Android updates the game files without reinstalling the APK, the same way the main menu Update button works on PC. This works for every APK that runs the bootstrap: the on-phone installer, and APKs built on a PC with `build --vanilla`.

1. In the game, `assets/functions/overhaul_update.lua` sees `OVERHAUL_BOOTSTRAP` (set by the bootstrap before it starts the game) and asks the update feed for `android_patch` (installed from the official app) or `android_patch_pc` (built from a PC copy). It picks the feed from the `[M]` tag in the vanilla `version.jkr` the install was made from.
2. The Update button downloads the patch zip to `update/patch.zip` in the save folder, checks the size and sha256 against the feed, and shows "Restart to update". Restart goes through the modloader (`MODLOADER.restart()`), which stops the game's threads and restarts LÖVE into the bootstrap.
3. The bootstrap mounts the zip, reads its manifest and installs it when it is newer than what is installed and made for the same Balatro (`version.jkr` and the sha256 of every vanilla file it touches). The new install is built in `overhaul_game.new/` and swapped in at the end, then the zip is deleted. Saves are not inside `overhaul_game/`, so they stay.
4. Anything wrong keeps the version the player has: a damaged zip is deleted ("The downloaded update was damaged and has been deleted"), a zip made for another Balatro is deleted with its own message, and both screens end with "Tap to play the version you have". If the phone dies between removing the old install and renaming the new one, the next start finishes the swap. The patch bundled in the APK never downgrades a newer downloaded install, and a bundled patch that fails once is skipped until the APK changes.

The APK itself only needs reinstalling when the LÖVE runtime or the Java parts change. Reinstalling over it with the same key keeps the saves.

Making the update for the feed (`pack.sh` does the first one):

```
python3 tools/release/patcher/make_patch.py --vanilla <official APK or Balatro.exe> --out <set>
python3 tools/release/android/make_apk.py zip --patch <set> --out android-patch.zip
```

`zip` writes the feed entry to `<zip>.json` (Overhaul version, vanilla version, size, sha256). Two zips per release: one made against the official mobile APK (`android_patch`) and one against the Steam copy (`android_patch_pc`). The server's update manifest accepts both next to `android` (`server/src/updates.ts`).

PC-built APK that can update: `make_apk.py build --vanilla <your Balatro.exe, folder or .love> --patch <set>` (a set from `make_patch.py` against that Balatro, like the launcher's `patchset/`) puts the bootstrap, the launcher's patcher, the patch set and the player's own vanilla files (in `vanilla/`) into `game.love`. The phone then installs and updates without the official app. It refuses a Balatro the patch set was not made for. A plain `build --game` APK has no bootstrap, so it never checks for updates (the runtime sets `OVERHAUL_RUNTIME=1` and the check stays off, because the `android` feed is the full dev APK); those players rebuild from the launcher.

Tested here (`tools/release/android/test_update.py`, run inside `unshare -rn` so only loopback exists, with a local HTTP feed and desktop LÖVE in Xvfb): fresh install with an empty feed, a damaged zip, a zip for another Balatro, the full in-game download, check, restart and install of a newer version with a save file kept, no downgrade on the next start, recovery after a kill mid-swap, and the PC-built APK installing from its own `vanilla/`. 26 checks. The update screens were shot with a stub at 1280x720, 1560x720 and 720x1560 in EN, FR and ES.

## iPhone

What it would take, and why we don't ship it:

- **Building:** iOS apps are compiled and signed with Xcode, which only runs on macOS. LÖVE ships no ready iOS app, only the libraries to build one in Xcode (`love-11.5-apple-libraries.zip`). Balatro Mobile Maker gets around it by shipping a base IPA they compiled on a Mac. We have no Mac, so there is no base IPA to put the game in.
- **Installing:** with no App Store release, each player signs the app with their own Apple ID through [AltStore](https://faq.altstore.io/altstore-world/your-altstore) or [Sideloadly](https://sideloadly.io/faq), from Windows or macOS. With a free Apple ID an app expires after 7 days and only 3 sideloaded apps are allowed; a paid developer account ($99 a year) lifts that to a year ([guide](https://www.whistleout.com/CellPhones/Guides/how-to-sideload-apps-on-ios-with-altstore-sideloadly)). In the EU, alternative app marketplaces exist, but they need a paid developer account and Apple's notarization of the app, and shipping someone else's game inside it is exactly what we can't do.
- **Using the App Store copy:** an iPhone app can't read another app's bundle (the sandbox forbids it), and App Store apps are FairPlay encrypted; decrypting them needs a jailbroken device or a Mac and may be illegal depending on the country ([FairPlay notes](https://notes.generalzero.org/Mobile/iOS/IPA.html), [Anvil Secure](https://www.anvilsecure.com/blog/locked-up-but-not-locked-out-ios-app-pentesting-without-jailbreak.html)). So the iPhone game files have to come from the player's PC copy, like Balatro Mobile Maker does.

The honest options for iPhone players: (1) someone with a Mac builds a LÖVE 11.5 iOS app once (no game inside, so it could be shared), the PC launcher puts the patched `game.love` into it and the player sideloads it with AltStore or Sideloadly every 7 days; (2) play on PC or Android. Option 1 needs a Mac session we don't have tonight.

Updates on an iPhone build: the Android bootstrap is plain Lua, so it would run the same way inside such an IPA. The launcher would put the bootstrap, the patch set and the player's PC vanilla files into `game.love` (like `build --vanilla`, since the App Store copy can't be read), and updates would land in the app's own data folder as a patch zip, with no re-signing. Apple's guideline 2.5.2 forbids an App Store app from downloading code that changes it ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#software-requirements)), but a sideloaded app is never reviewed. The 7-day re-sign on a free Apple ID stays, and it is the real limit, not updates.

## What is not possible

- Shipping a ready-made APK or IPA with the game in it. Every APK that holds `game.love` is built on the player's own machine from the player's own copy.
- Getting Play Games achievements or cloud saves in the Overhaul app.
- An iPhone build without a Mac, or an iPhone install that lasts more than 7 days on a free Apple ID.
- Reading the App Store copy of Balatro from another iPhone app.

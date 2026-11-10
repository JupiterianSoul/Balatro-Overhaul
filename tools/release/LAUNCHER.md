# Balatro Overhaul launcher and patch set

The Overhaul is built by editing Balatro's own Lua files, so the normal Overhaul build
(`assets/` zipped into a .love) contains a full copy of the game. We can't hand that to
the public. The public release is a small launcher instead: it holds the Overhaul's own
files plus a patch set, finds the player's own copy of Balatro, checks it, and builds the
Overhaul from it on their machine. Nothing from Balatro is in anything we publish.

## How other Balatro projects do it

**Balatro Mobile Maker** (blake502) turns the player's Steam copy into an Android APK. The
README calls it "a NON-PIRACY avenue for players" and says it works by "converting their
Steam copy of Balatro to a mobile app". It reads `Balatro.exe` (or `Game.love`) from the
default Steam folder, or from its own folder if the player copies it there. It never
ships the game.
<https://github.com/blake502/balatro-mobile-maker>

**balatromobile** (antipatico) is a Python rewrite of the same idea. Its README says you
still need a copy of the game (buy it on Steam).
<https://github.com/antipatico/balatromobile>

**Lovely** (the injector most Balatro mods run on) does not ship modified game files at
all. It "embeds code into a LÖVE 2d game at runtime" through Lua API detouring, using
`pattern`, `regex` and `copy` patches that match lines in the game's source as it loads.
Mods sit in a separate Mods folder and can be removed without reinstalling the game.
MIT licence. <https://github.com/ethangreen-dev/lovely-injector>

**Steamodded** loads mods through Lovely, same model: the player's own game, mods next to
it.

**Balatro Multiplayer** (the BMP mod) installs as a Steamodded mod into the player's own
Balatro, by hand or through r2modman or the BET launcher ("a simple launcher made for
Balatro, like Balatro Mod Manager"). Its install page says to start Balatro through
Steam and log in with the Steam account, so the player always needs their own copy.
<https://balatromp.com/download>

The common rule across all of them: never share a single game file, always start from
the player's own copy.

## What LocalThunk has said about mods

From his Discord, collected on the Balatro Modding Guide
(<https://mrdarrengriffin.github.io/BalatroModdingGuide/does-balatro-allow-mods>):

- "I'm not anti mod, I love that it's fostered a great community" (8 May 2025)
- "the existence of mods doesn't bother me at all" (6 May 2025)
- "I won't be adding any kind of modding interface" and "The closest I might do is some
  kind of folder to drag and drop mods into" (8 May 2025)
- "I try to avoid looking at any Balatro mods so that I can remain as fresh as possible
  as a designer." (5 May 2025)

So mods are tolerated and even welcome, as long as they don't become a way to get the
game without buying it.

## The EULA

I could not read Balatro's EULA text: Steam's EULA page for the app
(<https://store.steampowered.com/eula/2379780_eula_0>) failed to load, and Playstack's
site only refers to "the End User License Agreement and Terms of Service" in its video
policy (<https://www.playbalatro.com/video-policy>). Because of that, the launcher follows
the strictest reading the community already works under:

- no Balatro file, code line or image is in anything we publish (proved by a check
  script, below);
- the player must own the game, and the launcher only reads their copy;
- no DRM is touched (the Steam build has none in the game data; we read the same zip
  that Balatro Mobile Maker reads);
- the Overhaul is presented as a fan mod, not made or endorsed by LocalThunk or
  Playstack, and it tells players to buy Balatro.

If Playstack ever asks, the patch set format makes it easy to show exactly what we ship.

## What we ship

`tools/release/pack_overhaul.sh` builds `dist/release/`:

| File | What it is |
|---|---|
| `patchset/` | The Overhaul's own files and the patches (below) |
| `launcher.love` | The launcher app with the patch set inside |
| `BalatroOverhaulLauncher-<v>-linux-x86_64.tar.gz` | The LÖVE 11.5 AppImage contents unpacked, with our AppRun and launcher.love. If `mksquashfs` is installed the script also writes a single file AppImage |
| `BalatroOverhaulLauncher-<v>-windows-x64.zip` | LÖVE 11.5 for Windows, the launcher fused into `Balatro Overhaul Launcher.exe`, plus the plain `love.exe` that runs the installed Overhaul |
| `BalatroOverhaulLauncher-<v>-macos.zip` | `Balatro Overhaul Launcher.app` (love.app with launcher.love in Resources, unsigned) with a pristine LÖVE runtime nested inside, and a READ ME FIRST note (right click > Open, or `xattr -cr`) |
| `RELEASE.md`, `LAUNCHER.md`, `MOBILE.md` | Docs, when present |
| `SHA256SUMS.txt` | Checksums of everything above |

LÖVE is zlib licensed; its licence file ships with each package.

`tools/release/EXCLUDE.txt` lists what never ships (one path or glob per line, `# reason`
after it; `dir/` drops a folder, `*` stays in one folder, `**` crosses folders). Each
stream adds its own lines under its own heading.

## The patch set

`make_patch.py` reads the vanilla game from the Steam `Balatro.exe` (a fused LÖVE exe, the
game zip appended) and the Overhaul's `assets/`, and writes `manifest.lua` plus files.
Every file of the Overhaul gets one of these kinds:

- `keep`: the vanilla file, unchanged. Only its path and sha256 are listed.
- `own`: a file the Overhaul added, stored as is under `files/`.
- `patch`: a text file the Overhaul changed (or an own file that quotes vanilla lines),
  stored as a `.bop` op list under `patches/`.
- `image`: a vanilla image the Overhaul drew on. Only the changed pixels are stored, as
  `<name>.own.png` plus a `<name>.mask.png` saying which pixels to replace.
- `copy`: an own file that is byte for byte a vanilla file under another name.

A `.bop` file is a header (`BOP 1`, `eol lf|crlf`, `final 0|1`, `base N`) then ops:

```
c N              copy the next N lines of the vanilla file
s N              skip N vanilla lines (removed or replaced by the Overhaul)
l N              N lines the Overhaul wrote follow, as is
r F L LEAD TRAIL one line taken from vanilla file F, line L, with the Overhaul's own
                 indentation (LEAD, TRAIL are %XX encoded whitespace, - for none)
end
```

So a patch holds only positions and the Overhaul's own lines. Removed vanilla lines and
context lines are never written. A line the Overhaul moved or re-indented is a reference,
not a copy. The manifest records the game version (`version.jkr`, today `1.0.1o-FULL`)
and the sha256 and size of every vanilla file the patch set reads.

`check_patch.py` proves it: it loads every vanilla line longer than 20 characters
(stripped) and fails if any of them appears in the patch set, the launcher, or any file
inside the release archives (it opens zips, the fused exe and the tar.gz). It also fails
on any file that is a copy of a vanilla file, and on any PNG whose pixels mostly match a
vanilla image of the same size. Lines of LÖVE's own licence are allowed (vanilla
`engine/string_packer.lua` quotes the same MIT text).

## The launcher

A small LÖVE app (`tools/release/launcher/`) built to look like the game's own Options and
Mod Menu windows: a centred window with a pale rim, gold title, red tabs with the red pointer
over the open one, chunky buttons with drop shadows and an orange QUIT, over the game's swirl
and CRT. It ships no Balatro code or art. Once it has opened the player's copy it borrows, in
memory and only while it runs, the game's font, its background and CRT shaders, the Joker
card, the card back and a few button sounds (`launcher/gfx.lua`). Before that it uses its own
swirl and CRT, LÖVE's built in font and a plain face down card.

- **PLAY**: the Joker card, two status cards (your Balatro, the Overhaul), one big button
  that follows the state (FIND MY GAME, CHOOSE A COPY, INSTALL, UPDATE, PLAY; a progress bar
  while it works), REINSTALL or PLAY next to OPEN FOLDER, and the message under them. Errors
  show in red with the fix under them.
- **GAME**: every copy found, with a STEAM, XBOX or PICKED badge, its path and state, and USE;
  a pager when there are more than fit; SCAN AGAIN and PASTE A PATH. Dropping `Balatro.exe`,
  `Balatro.love`, `Balatro.app` or the game folder on the window also works.
- **SAVES**: every Balatro save the launcher found (Steam on Windows and macOS, the Proton
  `compatdata/2379780` folder of each Steam library on Linux, native `Balatro` and `love/Balatro`
  saves) with its profiles and LOAD, the Overhaul save, IMPORT (a save `.zip` or a Balatro save
  folder, from a pasted path or dropped on the window), EXPORT MY SAVE (a `.zip` in `exports/`)
  and BACKUPS.
- **ANDROID**: what the Android maker does and MAKE ANDROID APK (grey until a build has the
  maker in it).
- **SETTINGS**: language (English, French, Spanish; picked from the system at first start),
  sounds, CRT effect. Saved in `settings.lua`.
- **ABOUT**: versions, what the launcher does and doesn't do, credits, where the Overhaul
  saves, licences.

Everything is sized in game units from the window size (body 15 x 7 units wide screen,
11.6 x 15 portrait, wider on very wide screens), text is centred on its measured ink. Touch
(Android, iOS, or `LAUNCHER_TOUCH=1`) makes rows and buttons taller; portrait puts the tabs on
two rows and stacks the card over the buttons. Input: mouse and touch; arrows move the focus
between buttons, Enter or Space presses, Tab cycles, Q / E or Page Up / Down switch tabs,
Escape quits; on a controller the d-pad moves, A presses, B goes back to PLAY, the shoulder
buttons switch tabs. Juice: buttons lift and lighten on hover, sink on press and bounce on
release, the body slides in on a tab switch, the card sways, tilts towards the cursor and
spins when clicked.

Saves: at the first start, once a Balatro save is found, the launcher zips it into
`backups/` and asks LOAD MY PROGRESS, START FRESH or CHOOSE ANOTHER SAVE (the answer is kept in
`settings.lua`, the SAVES tab changes it later). Loading zips the current Overhaul save into
`backups/` first (the last 20 backups are kept), then writes each profile's `profile.jkr`,
`meta.jkr` and `unlock_notify.jkr` into the Overhaul save; Balatro's `settings.jkr` and a run in
progress (`save.jkr`) are left out, and Balatro's own save is only ever read. The launcher reaches
the Overhaul save by switching its LÖVE identity to `love/Overhaul` (`LOVE/Overhaul` on Windows
and macOS) for the copy and back. Exports and imports use `assets/functions/save_io.lua`, the same
code as the in-game Settings import and export: plain zips, never `settings.jkr` (it holds the
online key), keys, logs, backups or caches. Tests: `OVERHAUL_NO_SAVE_SCAN=1` (the default of
`run_launcher.sh` and every launcher test) turns the save search off, `OVERHAUL_BALATRO_SAVES`
lists folders to use instead, `test/make_fake_saves.py HOME` writes fake ones, and the shots
`play+ask`, `saves+load`, `saves+confirm`, `saves+export` show each step.

Finding the game: the Steam folders of each OS (Linux native, `~/.steam`, Flatpak and Snap
Steam; `Program Files (x86)\Steam` on Windows; `~/Library/Application Support/Steam` on
macOS), every library listed in `libraryfolders.vdf`, then `steamapps/common/Balatro/`
`Balatro.exe` or `Balatro.app/Contents/Resources/Balatro.love`. A path the player picked
is remembered. The game file is only ever opened for reading.

Xbox app, PC Game Pass and Microsoft Store (Windows only, `patcher/find.lua` `F.scan_xbox`):

- Every fixed or removable drive (through `GetLogicalDrives` with LuaJIT's FFI; C to H when
  the FFI is not there). On each drive the `.GamingRoot` file says where the Xbox app keeps its
  games (`XboxGames` when it is missing or unreadable).
- In that folder every subfolder whose name has "balatro" in it (`FindFirstFileA`; without the
  FFI a fixed list of likely names), then its `Content` folder: `Balatro.exe`, `Balatro.love`
  or `Game.love`, or the game's files loose in the folder (`main.lua` plus `version.jkr`). A
  loose copy is read file by file, exactly like the zip.
- `Program Files\WindowsApps` is listed when Windows allows it (it does not for normal
  users). When nothing readable was found, `%LOCALAPPDATA%\Packages` is checked for a Balatro
  package: then the copy is shown as "Protected by Windows" with the fix (reinstall it with
  the Xbox app into an XboxGames folder, or use the Steam copy).
- An Xbox copy goes through the same checks. When its version or its files differ from the
  Steam build the patch set was made from, the message says it is an Xbox / Game Pass build
  the Overhaul does not know yet (instead of the Steam "verify your files" advice). Supporting
  it means building a patch set against that build (`make_patch.py --vanilla` on its
  `Balatro.exe`, or on a zip of its loose files) and shipping that manifest too.

Checking: the launcher reads `version.jkr` and refuses another version with a clear
message ("This is Balatro 1.0.1n. Overhaul 2.5 needs Balatro 1.0.1o."). Then it hashes
every vanilla file the patch set uses; any difference means a modded or damaged copy, and
the message says to verify the game files in Steam. A file that is not a Balatro zip, or a
missing copy, each get their own message.

Installing: the Overhaul is rebuilt into the launcher's own save folder (`Overhaul/` in
`~/.local/share/BalatroOverhaulLauncher`, `%APPDATA%\BalatroOverhaulLauncher` or
`~/Library/Application Support/BalatroOverhaulLauncher`). Every rebuilt file is checked
against the sha256 in the manifest (images against the sha256 of their pixels). The new
build goes into `Overhaul.new/` first and only replaces `Overhaul/` once every file has
passed, so a failed install or update leaves the old one playable. A stamp file is written
last, so a broken install never counts as installed.

Playing: the launcher starts the installed folder with its own LÖVE runtime (AppRun
`--overhaul-run` on Linux, `love.exe` next to the launcher on Windows, the nested
`runtime/love.app` on macOS). The game's save identity comes from the folder name, so its
saves go to `love/Overhaul` (Linux) or `LOVE/Overhaul` (Windows, macOS), away from
Balatro's own saves, which the launcher never opens.

Online play: the server is `wss://`, and each OS reaches it its own way.

- Linux and macOS: the game's WebSocket worker (`assets/multiplayer/android_ws.lua`) talks
  plain TCP to the TLS tunnel on `127.0.0.1:44380` (`linux/tls_tunnel.py`, the same one the
  main app's start script runs). `launcher.love` carries it as `tunnel/tls_tunnel.py`; on Play
  the launcher writes it and `run_overhaul.sh` into its save folder and starts the game
  through that script, which starts the tunnel with python3 (skipping macOS's
  `/usr/bin/python3` stub when the command line tools are not installed, so no install
  dialog pops up), runs the game in the foreground and stops the tunnel when the game ends.
  When a tunnel is already on the port (the main app's), the new one exits at once and the
  game uses the old one. Without python3 the game says "The secure connection helper is
  not running" instead of a raw `tunnel_fail`.
- Windows: the worker uses WinHTTP through LuaJIT's FFI, no tunnel. `assets/https.lua`
  (update checks, Workshop, crash reports) loads Balatro's native `https.dll` when it finds
  one on `package.cpath`, else its own WinHTTP code. On Play the launcher copies `https.dll`
  from the player's Balatro folder into `Overhaul/` and starts `love.exe` with that folder as
  its working directory (`start "" /D`), so `.\https.dll` is found.
- macOS: the same copy for `https.so` when the player's `Balatro.app` has one
  (`Contents/Frameworks` or `Contents/Resources`); otherwise `https.lua` uses the system curl.
- Connecting: the game gives the server 20 seconds to be reached; once WinHTTP or the tunnel
  says the request went out it waits up to `CONNECT_TIMEOUT` (75 s, for a cold server). A
  timeout or a worker error shows a message with the last step or the WinHTTP error name,
  and is written to `mp_connection.log` in the save folder.

Android: the Android APK button calls `android/make_apk.lua` inside launcher.love when the
mobile stream ships one (`tools/release/android/launcher/` is copied in as `android/`).
It gets `{game_path, game_dir, out_dir, lang, progress(i, n)}` and returns the APK path, or
nil and an error. Without it the button explains that this build has no Android maker.

A headless mode is there for tests and scripts:
`love launcher.love --cli check|install|update [--balatro PATH] [--play]`. (Not `--game`:
LÖVE takes that one for itself.)

## Versions

Two values in `assets/globals.lua`:

- `OVERHAUL_VERSION` is the build number, a plain integer that only goes up (30 is the first
  public release). It is what everything compares: the launcher feed, the game's Update button,
  the server's `/version`, the MP room check (exact match) and replays. Every comparison reads
  the digit runs of the two strings in order, so build 30 is newer than every 2.x install
  (`{30}` against `{2, 7}`), and those installs are offered it as an update. A 2.x client
  that tries to join a 2.0 room is refused with "This room runs V 30, you have V 2.7. Update
  to join."; a 2.0 client shows the other side as "build 31" or "V 2.7".
- `OVERHAUL_NAME` is what players see: "2.0 (pre-release)". The corner label, About, the
  update prompt and the launcher show it. `make_patch.py` writes it into the manifest as
  `overhaul_name`, `make_feed.py` into the feed as `latest.name`, `release.ts` into each
  build of `latest.json`, and the server passes it on (40 characters at most). Old launchers
  and games ignore it and show the build number.

`tools/release/test_version.lua` checks both against the real comparison code of the game and
the launcher.

## Updates

Updates work like the main menu Update button of the main app, except that only a new
patch set ever travels, never a game build.

The feed is one small JSON file. Its URL lives in one place, `C.FEED_URL` in
`launcher/core.lua` (`OVERHAUL_FEED` overrides it for tests, `OVERHAUL_NO_UPDATE_CHECK=1`
turns the check off). `pack_overhaul.sh` writes it next to the zip it points at:

```json
{
  "format": 1,
  "latest": {
    "version": "2.6",
    "game_version": "1.0.1o-FULL",
    "url": "patchset-2.6.zip",
    "size": 9478986,
    "sha256": "f38fa853...",
    "patch_format": 2,
    "changelog": {"en": "...", "fr": "...", "es": "..."}
  },
  "page": "https://where.the.launcher.is.downloaded/"
}
```

`url` may be relative to the feed. `changelog` is a string or one string per language
(`--changelog FILE` on the pack script). `patch_format` goes up only when the patch set
format changes in a way old launchers can't read; they then say "Overhaul 2.6 needs a newer
launcher" and show `page`.

### Where the feed lives and how to publish

The game server serves it: `GET /release/feed.json` and `GET /release/patchset-<version>.zip`
(`server/src/updates.ts`, `ReleaseService`). The files sit in the same private R2 bucket as
the `/version` builds, under `release/` (`debug/release/` with `R2_PREFIX=debug/`). The
server reads `release/feed.json` (cached 60 s, the last good copy is kept if R2 fails),
checks it, always rewrites `url` to `patchset-<version>.zip` so the launcher asks the server,
and answers the zip with a 302 to a presigned R2 link that lasts 10 minutes. Nothing
published, or no R2 settings, gives a 404, which the launcher and the game read as "no
update". 30 requests a minute per IP. With `RELEASE_DIR=/some/folder` the server serves
that folder instead of R2 (the tests use it, and it works for self-hosting).

Why R2 behind the server and not GitHub Releases: every launcher already out there asks
the server URL in `C.FEED_URL`, Render already has the read-only R2 key (no new setting),
R2 has no egress fees and stays inside the free tier for a few MB per release, and release
files on the private main repo would need a login (a separate public repo would work, but
it is one more place to keep in sync). Nothing large goes into git.

To publish an update:

1. Bump `OVERHAUL_VERSION` in `assets/globals.lua` (the build number, a plain integer that only
   goes up: 30 is Overhaul 2.0 (pre-release), the next build is 31) and set `OVERHAUL_NAME` to the
   name players see, then commit.
2. `tools/release/pack_overhaul.sh` (optionally `--changelog notes.json` with
   `{"en": ..., "fr": ..., "es": ...}`). It writes `dist/release/patchset-<v>.zip` and
   `dist/release/feed.json`.
3. `set -a; . ~/.config/balatro-overhaul/release.env; set +a` then
   `bun tools/release/publish_feed.ts --dry-run`, read it, then run it again without
   `--dry-run`.

`publish_feed.ts` checks that the zip matches `feed.json` (size, sha256, the version in its
`manifest.lua`), refuses a version that is not newer than the published one (`--force` to
republish), uploads the zip first and `feed.json` last so the feed never points at a
missing file, and keeps the last two patch sets so a download that started just before
still finishes. Launchers see the new version within a minute. Options: `--from DIR`,
`--to DIR` (a folder instead of R2), `--channel debug`, `--page URL`, `--min-launcher N`.
`min_launcher` is the feed format a launcher must read; the server folds it into
`patch_format`, so launchers that only know `patch_format` show "needs a newer launcher"
and `page`. Launchers from 2.7 on read format 2; the 2.6 launchers read format 1, so they
send their players to `page` for the 2.7 launcher instead of updating.

In the launcher: at start it fetches the feed in a thread. If `latest.version` is newer
than its own patch set, the Play tab shows "Version 2.5 installed, 2.6 is out", the
changelog under it, and the button becomes UPDATE. UPDATE downloads the zip into
`updates/`, checks its size and sha256, mounts it, checks that its manifest says the same
version, then installs from it exactly like a normal install (the player's copy is checked
against the new manifest too). Only when that worked does the launcher keep the new set
(`settings.lua` remembers it, the old zip is deleted). Anything wrong (no connection,
damaged download, not a patch set, a Balatro version the new set doesn't know) leaves the
installed Overhaul and the old patch set as they were, with a message saying so. At the
next start the kept zip is hashed again and used only while it is newer than the set built
into the launcher, so a new launcher download always wins over an old update. An older or
equal feed shows nothing; no connection shows nothing.

In the game: the launcher writes `overhaul_launcher_link.lua` next to the installed
`Overhaul/` folder (feed URL and how to start the launcher). `assets/functions/launcher_update.lua`
looks for that file next to the game's own folder; only a launcher install has one, so the
main app and Debug are not affected. When it is there, the main menu check reads the feed
instead of the server's `/version`, the usual UPDATE AVAILABLE button and prompt show up
("The game closes, the launcher installs the update and starts it again."), and UPDATE
starts the launcher with `--update --play` and quits. A launcher window that is still open from before notices the new install within two seconds (it watches `install.lua`), reloads the downloaded patch set from `settings.lua` and stops offering the update. The launcher downloads and installs
the update with its progress bar, starts the new version and closes itself. Saves live in
`love/Overhaul`, outside the game folder, so an update never touches them.

On the phone the bootstrap's own feeds do the same: `publish_feed.ts` puts `android_patch` (the mobile patch set from `pack.sh`) and `android_patch_pc` (the launcher's patch set, for APKs the launcher built) into `latest.json` next to the launcher feed, so the title screen of every public build offers the update.

In a release build (`RELEASE_BUILD`) on PC without that link file, the main menu check is
off, so a release game never fetches a full build from the server.

## Testing

- `python3 tools/release/patcher/make_patch.py --out DIR` then
  `python3 tools/release/patcher/check_patch.py DIR`
- `tools/release/pack_overhaul.sh` (ends with the vanilla check on all of dist/release)
- `tools/release/launcher/test/e2e_linux.sh`: unpacks the Linux package into an empty
  folder, installs from the Steam copy, compares the result with `assets/` minus
  EXCLUDE.txt byte for byte (the two changed atlases pixel for pixel, since the launcher
  re-encodes them), checks the wrong version, modded, not a game and missing messages,
  boots the installed game and plays it with the soak bot. It runs inside a network
  namespace with only loopback, so the test game cannot reach the live server.
- `tools/release/launcher/test/check_packages.py dist/release`: static checks of the
  Windows and macOS packages (fused exe layout, app bundle, Info.plist, exec bits,
  symlinks, checksums).
- `tools/release/launcher/test/update_test.sh` (after `pack_overhaul.sh --launcher-only`):
  builds a newer patch set from a copy of `assets/` with another version number, serves
  feeds on 127.0.0.1 (QA_PORT) inside a loopback-only network namespace, and checks: an
  older feed, no connection, a damaged download (the install stays as it was, no staging
  folder left), a feed that needs a newer launcher, the real update (round trip against
  the newer assets), the next start using the downloaded set, and the link file.
- `tools/release/launcher/test/update_gui.sh`: the same feed with the launcher window
  (`--update --play`: updates, starts the game, closes itself), shots of the Play tab
  while an update is found, downloading and done (desktop, touch and portrait), and the
  installed game's UPDATE AVAILABLE button and prompt through tools/menu_shots, which must
  start the launcher with `--update --play`.
- `tools/release/launcher/test/feed_server_test.sh` (after `pack_overhaul.sh --launcher-only`,
  `RELEASE_DIR_IN` = its `--out`): the same update path against the real game server
  (`RELEASE_DIR` mode) with releases put there by `publish_feed.ts`: nothing published, the
  same version, a refused republish, server down, a damaged zip, a wrong sha256 in the feed,
  a zip missing on the server, `--min-launcher 2`, the real update (round trip, the save in
  `love/Overhaul` untouched), the next start, then (`FEED_STEPS=ingame`) the installed game's
  Update button starting the real launcher, which updates and starts the game again.
- Launcher screenshots: `LAUNCHER_SHOT_DIR=dir LAUNCHER_SHOTS=play,game,android,settings,about`
  (`play+install`, `play+progress` run an install first, `play+focus` shows the keyboard
  focus, `android+apk` runs the Android maker), `LAUNCHER_SIZE=1560x720`, `LAUNCHER_TOUCH=1`,
  `LAUNCHER_LANG=fr`, `LAUNCHER_FAKE_FEED=2.6` (shots only: pretend the feed has that
  version), `LAUNCHER_MUTE=1`. Shots are always muted. Wrap the run with
  `tools/release/launcher/test/run_launcher.sh` and an `XDG_DATA_HOME` under `.night/`; set
  `XVFB_NUM` to a free display number when several runs go at once (`xvfb-run -a` races).
- Error states: `tools/release/launcher/test/make_fakes.py Balatro.exe .night/fake` writes an
  old version, a modded copy and a file that is not a game; point `OVERHAUL_GAME` at one with
  `OVERHAUL_NO_SCAN=1`. `OVERHAUL_NO_SCAN=1` alone gives the "not found" screens.

## Known limits

- Windows and macOS packages were built and checked statically only (no Wine, no Mac).
- macOS: the app is unsigned. Gatekeeper needs right click > Open, or `xattr -cr`.
- Windows: Lua's `io.open` uses the ANSI code page, so a Steam library on a path with
  non ASCII characters may not open. Dropping the file on the window has the same limit.
- No single file AppImage without `mksquashfs` on the build machine; the tar.gz holds the
  same AppDir.
- The Xbox / Game Pass / Microsoft Store scan was written and unit tested
  (`patcher/test_patcher.lua`) without a Windows machine. Not checked for real: the FFI calls
  (`GetLogicalDrives`, `FindFirstFileA`) on Windows, the exact name of Balatro's folder and
  package in the Xbox app, the layout of its `Content` folder (exe, .love or loose files), the
  binary layout of `.GamingRoot` beyond the "RGBX" header and UTF-16 path, and whether the Xbox
  build matches the Steam 1.0.1o files. The loose file path was checked on Linux with the Steam
  copy unpacked into a folder (install and hash check pass).
- The launcher only knows Balatro 1.0.1o. A new Balatro version needs a new patch set
  (run the pack script against the new copy and fix what changed).
- iPhone is the mobile stream's (tools/release/MOBILE.md).
- Downloads go through the game's own `assets/https.lua` (curl on Linux and macOS,
  WinHTTP on Windows). Its curl call gives up after 120 seconds, so a ~9 MB patch set needs
  about 1 Mbit/s or better; slower lines get the "could not download" message.
- The feed is live only once the server with `/release/` is deployed and a release has
  been published with `publish_feed.ts`; until then the launcher simply finds no update.
  Render's free plan sleeps, so the first check after a quiet spell can take about a
  minute; the launcher waits up to 120 seconds and the game retries after 2 minutes.

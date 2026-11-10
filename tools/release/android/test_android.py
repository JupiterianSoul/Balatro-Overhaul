#!/usr/bin/env python3
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NIGHT = REPO / ".night" / "mobile"
STEAM = Path.home() / ".local/share/Steam/steamapps/common/Balatro/Balatro.exe"
MAKER = [sys.executable, str(HERE / "make_apk.py")]
PATCHER_DIR = REPO / "tools" / "release" / "patcher"
MAKE_PATCH = [sys.executable, "-B", str(PATCHER_DIR / "make_patch.py"), "--exclude", str(REPO / "tools" / "release" / "EXCLUDE.txt")]
CHECK_PATCH = [sys.executable, "-B", str(PATCHER_DIR / "check_patch.py")]
OFFICIAL = Path(os.environ.get("OFFICIAL_APK", str(NIGHT / "fake" / "official.apk")))
WANT_PERMS = {"android.permission.INTERNET", "android.permission.VIBRATE", "android.permission.MANAGE_EXTERNAL_STORAGE",
              "android.permission.READ_EXTERNAL_STORAGE", "android.permission.READ_MEDIA_AUDIO"}
NO_PERMS = {"android.permission.RECORD_AUDIO", "android.permission.QUERY_ALL_PACKAGES", "com.android.vending.BILLING",
            "com.google.android.gms.permission.AD_ID", "com.android.vending.CHECK_LICENSE"}

STEAM_ONLY_LINES = 40

failures = []


def check(ok, what):
    print(("ok   " if ok else "FAIL ") + what, flush=True)
    if not ok:
        failures.append(what)


def run(cmd):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if res.returncode != 0:
        print(res.stdout[-3000:])
    return res


def inspect(apk):
    res = run(MAKER + ["inspect", str(apk)])
    text = res.stdout
    return json.loads(text[text.index("{"):])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def vanilla_hashes():
    hashes = {}
    if STEAM.is_file():
        with zipfile.ZipFile(STEAM) as z:
            for n in z.namelist():
                if not n.endswith("/"):
                    data = z.read(n)
                    if len(data) >= 64:
                        hashes[sha(data)] = n
    return hashes


def main():
    NIGHT.mkdir(parents=True, exist_ok=True)
    work = str(NIGHT)
    runtime = REPO / "dist" / "release" / "android" / "overhaul-runtime.apk"
    check(run(MAKER + ["runtime", "--work", work]).returncode == 0, "runtime builds")
    info = inspect(runtime)
    check(info.get("package") == "com.jupiteriansoul.balatrooverhaul", "runtime package name")
    check(info.get("label") == "Balatro Overhaul", "runtime label")
    check(info.get("activity") == "org.love2d.android.GameActivity", "launch activity is LOVE's GameActivity")
    perms = set(info.get("permissions", []))
    check(WANT_PERMS <= perms, "runtime keeps the Overhaul's phone permissions")
    check(not (perms & NO_PERMS), "runtime has no Play, billing, ads or microphone permissions")
    check(info.get("game_love") is None and not info.get("lua_outside_game"), "runtime holds no game and no Lua")
    with zipfile.ZipFile(runtime) as z:
        assets = sorted(n for n in z.namelist() if n.startswith("assets/"))
        smali_ok = True
    check(all(n.startswith("assets/dexopt/") or n == "assets/overhaul_runtime.json" for n in assets),
          "runtime assets are only LOVE's dexopt files and overhaul_runtime.json")

    van = vanilla_hashes()
    check(bool(van), "Steam vanilla found for the leak scan")
    leaks = []
    with zipfile.ZipFile(runtime) as z:
        for n in z.namelist():
            if sha(z.read(n)) in van:
                leaks.append("runtime:" + n)
    for root, _dirs, files in os.walk(HERE):
        if "__pycache__" in root:
            continue
        for fn in files:
            p = Path(root) / fn
            if sha(p.read_bytes()) in van:
                leaks.append(str(p.relative_to(REPO)))
    for p in (REPO / "dist" / "release" / "android").glob("*"):
        if p.is_file() and sha(p.read_bytes()) in van:
            leaks.append(str(p.relative_to(REPO)))
    check(not leaks, "no vanilla file inside the maker or dist/release/android %s" % (leaks[:5] or ""))

    for f in sorted((HERE / "smali" / "org" / "love2d" / "android").glob("*.smali")):
        repo_copy = REPO / "smali" / "org" / "love2d" / "android" / f.name
        if repo_copy.is_file() and repo_copy.read_bytes() != f.read_bytes():
            smali_ok = False
            print("     %s differs from %s" % (f.name, repo_copy.relative_to(REPO)))
    check(smali_ok, "bundled smali matches the dev build's own classes")

    standin = NIGHT / "standin"
    check(run(MAKER + ["standin"]).returncode == 0, "stand-in game folder")
    out_dir = NIGHT / "apk"
    res = run(MAKER + ["build", "--game", str(standin), "--out", str(out_dir), "--work", work])
    check(res.returncode == 0, "APK builds from the stand-in")
    apks = sorted(out_dir.glob("BalatroOverhaul-[0-9]*.apk"))
    if apks:
        info = inspect(apks[-1])
        gl = info.get("game_love") or {}
        check(gl.get("has_main") and gl.get("stored"), "game.love is stored in assets/ with main.lua at its root")
        check(info.get("signature_ok") and any("v2" in s and s.endswith("true") for s in info.get("signature", [])),
              "APK signed with v2")
        check(info.get("aligned") is True, "APK passes zipalign -c -p 4")
        check(info.get("version_name") == info.get("runtime_info", {}).get("version_name"), "version name carried over")
    if OFFICIAL.is_file():
        patch = NIGHT / "patch_mobile"
        check(run(MAKE_PATCH + ["--vanilla", str(OFFICIAL), "--assets", str(standin), "--out", str(patch)]).returncode == 0,
              "patch set builds against the official APK's assets/")
        res = run(MAKER + ["installer", "--patch", str(patch), "--out", str(out_dir), "--work", work,
                           "--keystore", str(NIGHT / "installer-keys" / "installer-test.p12")])
        check(res.returncode == 0, "installer APK builds")
        inst = out_dir / "BalatroOverhaul-installer.apk"
        if inst.is_file():
            info = inspect(inst)
            check(info.get("package") == "com.jupiteriansoul.balatrooverhaul.phone", "installer has its own package name")
            check(info.get("label") == "Overhaul Launcher", "installer has its own label")
            check(info.get("queries") == ["com.playstack.balatro.android", "com.jupiteriansoul.balatrooverhaul"], "installer declares the official app and Balatro Overhaul in <queries>")
            check("android.permission.REQUEST_INSTALL_PACKAGES" in info.get("permissions", []), "installer may hand the app it builds to Android's installer")
            perms = set(info.get("permissions", []))
            check(WANT_PERMS <= perms and not (perms & NO_PERMS), "installer permissions: the Overhaul's own, no QUERY_ALL_PACKAGES")
            check(info.get("signature_ok") and info.get("aligned") is True, "installer is signed (v1, v2, v3) and aligned")
            icon_name = "res/drawable-xxxhdpi/love.png"
            with zipfile.ZipFile(inst) as z:
                icon = z.read(icon_name) if icon_name in z.namelist() else b""
                with zipfile.ZipFile(runtime) as r:
                    base_icon = r.read(icon_name) if icon_name in r.namelist() else b""
                with z.open("assets/game.love") as gl, zipfile.ZipFile(gl) as love:
                    names = set(love.namelist())
                    shared = all(love.read("patcher/" + n) == (PATCHER_DIR / n).read_bytes()
                                 for n in ("apply.lua", "zipread.lua", "love_ctx.lua"))
                    man_in = love.read("patch/manifest.lua") if "patch/manifest.lua" in names else b""
            check(bool(icon) and icon != base_icon, "installer icon is its own, not LOVE's")
            check({"main.lua", "conf.lua", "overhaul_install.lua"} <= names and shared,
                  "installer game.love holds the bootstrap and the launcher's patcher files unchanged")
            check(man_in == (patch / "manifest.lua").read_bytes(), "installer game.love holds the patch set")
            check(not any(n.startswith(("vanilla/", "functions/", "multiplayer/", "engine/")) for n in names),
                  "installer game.love holds no game files outside the patch set")
            res = run(CHECK_PATCH + ["--vanilla", str(OFFICIAL), str(inst)])
            check(res.returncode == 0, "vanilla check of the installer against %s" % OFFICIAL.name)
            if STEAM.is_file():
                res = subprocess.run(CHECK_PATCH + ["--vanilla", str(STEAM), str(inst)], stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True)
                hits = [l for l in res.stdout.splitlines() if l.startswith("VANILLA ")]
                m = re.search(r"^FAIL: (\d+) problems", res.stdout, re.M)
                count = int(m.group(1)) if m else 0
                lines_only = all("!assets/game.love!patch/patches/" in l and ": vanilla line " in l for l in hits)
                print("     %d Steam-only vanilla lines in the mobile patch set's literals" % count)
                check(lines_only and count <= STEAM_ONLY_LINES and (m or res.returncode == 0),
                      "against Balatro.exe: only the known Steam-only lines, inside line patches (%d, at most %d)" % (count, STEAM_ONLY_LINES))
        upd_dir = NIGHT / "apk_upd"
        if STEAM.is_file():
            patch_pc = NIGHT / "patch_pc"
            check(run(MAKE_PATCH + ["--vanilla", str(STEAM), "--assets", str(standin), "--out", str(patch_pc)]).returncode == 0,
                  "patch set builds against the Steam copy")
            res = run(MAKER + ["installer", "--patch", str(patch_pc), "--out", str(out_dir / "bad"), "--work", work])
            check(res.returncode != 0, "installer refuses a patch made against the Steam files")
            res = run(MAKER + ["build", "--vanilla", str(STEAM), "--patch", str(patch_pc), "--out", str(upd_dir), "--work", work])
            check(res.returncode == 0, "updatable APK builds from the player's Steam copy and a patch set")
            apks = sorted(upd_dir.glob("BalatroOverhaul-[0-9]*.apk"))
            if apks:
                info = inspect(apks[-1])
                check(info.get("signature_ok") and info.get("aligned") is True, "updatable APK is signed and aligned")
                with zipfile.ZipFile(apks[-1]) as z, z.open("assets/game.love") as gl, zipfile.ZipFile(gl) as love:
                    names = set(love.namelist())
                    man_in = love.read("patch/manifest.lua") if "patch/manifest.lua" in names else b""
                check({"main.lua", "conf.lua", "overhaul_install.lua", "patcher/apply.lua", "vanilla/version.jkr"} <= names,
                      "updatable game.love holds the bootstrap, the patcher and the player's own vanilla")
                check(man_in == (patch_pc / "manifest.lua").read_bytes(), "updatable game.love holds the patch set")
            res = run(MAKER + ["build", "--vanilla", str(OFFICIAL), "--patch", str(patch_pc), "--out", str(upd_dir / "bad"), "--work", work])
            check(res.returncode != 0 and "made for" in res.stdout, "updatable APK refuses a Balatro the patch set was not made for")
        res = run(MAKER + ["build", "--vanilla", str(OFFICIAL), "--out", str(upd_dir / "bad"), "--work", work])
        check(res.returncode != 0, "--vanilla without --patch is refused")
    print("\n%d failure(s)" % len(failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()

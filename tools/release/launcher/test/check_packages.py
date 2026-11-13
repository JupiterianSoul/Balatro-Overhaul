#!/usr/bin/env python3
import glob
import hashlib
import io
import json
import os
import plistlib
import subprocess
import sys
import tarfile
import zipfile

APP = "Balatro Overhaul Launcher"
NEEDED = ["main.lua", "conf.lua", "core.lua", "ui.lua", "lang.lua", "feed.lua", "net.lua", "https.lua",
          "json.lua", "patcher/apply.lua", "patcher/zipread.lua", "patcher/find.lua", "patchset/manifest.lua"]
problems = []


def bad(msg):
    problems.append(msg)
    print("BAD " + msg)


def check_love(where, data):
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return bad(where + ": no launcher zip inside")
    names = set(z.namelist())
    for n in NEEDED:
        if n not in names:
            bad("%s: %s missing" % (where, n))
    for n in names:
        if n.endswith(".lua"):
            r = subprocess.run(["luajit", "-bl", "-", "/dev/null"], input=z.read(n), capture_output=True)
            if r.returncode != 0:
                bad("%s!%s does not compile: %s" % (where, n, r.stderr.decode()[:200]))
    print("ok %s: launcher.love with %d files" % (where, len(names)))


def check_feed(rel):
    try:
        feed = json.load(open(os.path.join(rel, "feed.json"), encoding="utf-8"))
        latest = feed["latest"]
        data = open(os.path.join(rel, latest["url"]), "rb").read()
    except (OSError, ValueError, KeyError, TypeError) as e:
        return bad("feed.json: %s" % e)
    if feed.get("format") != 1 or latest.get("patch_format") not in (1, 2):
        bad("feed.json: unknown format")
    if len(data) != latest["size"] or hashlib.sha256(data).hexdigest() != latest["sha256"]:
        bad("feed.json: size or sha256 does not match " + latest["url"])
    z = zipfile.ZipFile(io.BytesIO(data))
    names = set(z.namelist())
    manifest = z.read("manifest.lua").decode("utf-8") if "manifest.lua" in names else ""
    if ('overhaul_version = "%s",' % latest["version"]) not in manifest:
        bad("feed.json: %s has no manifest for %s" % (latest["url"], latest["version"]))
    shipped = set()
    for root, _, files in os.walk(os.path.join(rel, "patchset")):
        for f in files:
            shipped.add(os.path.relpath(os.path.join(root, f), os.path.join(rel, "patchset")).replace(os.sep, "/"))
    if names != shipped:
        bad("feed.json: %s does not hold the same files as patchset/" % latest["url"])
    print("ok feed.json: Overhaul %s, %s (%d files, sha256 ok)" % (latest["version"], latest["url"], len(names)))


def main(rel):
    love = open(os.path.join(rel, "launcher.love"), "rb").read()
    check_love("launcher.love", love)

    win = glob.glob(os.path.join(rel, "*-windows-x64.zip"))
    if not win:
        bad("no Windows zip")
    for p in win:
        z = zipfile.ZipFile(p)
        names = set(z.namelist())
        for n in ["love.exe", APP + ".exe", "love.dll", "lua51.dll", "SDL2.dll", "OpenAL32.dll",
                  "mpg123.dll", "msvcp120.dll", "msvcr120.dll", "license.txt", "README.txt"]:
            if APP + "/" + n not in names:
                bad("Windows: %s missing" % n)
        exe = z.read(APP + "/" + APP + ".exe")
        plain = z.read(APP + "/love.exe")
        if exe[:2] != b"MZ" or len(exe) != len(plain) + len(love) or exe[len(plain):] != love:
            bad("Windows: launcher exe is not love.exe + launcher.love")
        elif b"\x89PNG" not in exe[:len(plain)]:
            bad("Windows: launcher exe has LOVE's icon")
        else:
            print("ok Windows: %s = love.exe (%d) + launcher.love (%d)" % (APP + ".exe", len(plain), len(love)))
            check_love("Windows exe", exe)

    mac = glob.glob(os.path.join(rel, "*-macos.zip"))
    if not mac:
        bad("no macOS zip")
    for p in mac:
        z = zipfile.ZipFile(p)
        names = set(z.namelist())
        base = APP + ".app/Contents/"
        for n in ["Info.plist", "MacOS/love", "Resources/launcher.love",
                  "Resources/runtime/love.app/Contents/MacOS/love",
                  "Resources/runtime/love.app/Contents/Info.plist"]:
            if base + n not in names:
                bad("macOS: %s missing" % n)
        if "READ ME FIRST.txt" not in names:
            bad("macOS: READ ME FIRST.txt missing")
        if z.read(base + "Resources/launcher.love") != love:
            bad("macOS: launcher.love differs")
        info = plistlib.loads(z.read(base + "Info.plist"))
        if info.get("CFBundleIdentifier") != "com.balatrooverhaul.launcher" or "UTExportedTypeDeclarations" in info:
            bad("macOS: Info.plist not set up")
        modes = {i.filename: (i.external_attr >> 16) for i in z.infolist()}
        for n in [base + "MacOS/love", base + "Resources/runtime/love.app/Contents/MacOS/love"]:
            if not modes.get(n, 0) & 0o111:
                bad("macOS: %s is not executable in the zip" % n)
        links = sum(1 for m in modes.values() if (m & 0o170000) == 0o120000)
        print("ok macOS: app bundle, nested runtime, Info.plist %s, %d symlinks kept"
              % (info.get("CFBundleIdentifier"), links))
        if links == 0:
            bad("macOS: framework symlinks were lost")

    lin = glob.glob(os.path.join(rel, "*-linux-x86_64.tar.gz"))
    if not lin:
        bad("no Linux tar.gz")
    for p in lin:
        with tarfile.open(p) as t:
            members = {m.name: m for m in t.getmembers()}
            for n in ["AppRun", "bin/love", "launcher.love", "balatro-overhaul-launcher", "README.txt"]:
                m = members.get(APP + "/" + n)
                if not m:
                    bad("Linux: %s missing" % n)
                elif n in ("AppRun", "bin/love", "balatro-overhaul-launcher") and not m.mode & 0o111:
                    bad("Linux: %s not executable" % n)
            if t.extractfile(APP + "/launcher.love").read() != love:
                bad("Linux: launcher.love differs")
        print("ok Linux: AppDir folder with AppRun, bin/love, launcher.love")

    check_feed(rel)

    sums = os.path.join(rel, "SHA256SUMS.txt")
    listed, wrong = [], []
    for line in open(sums, encoding="utf-8").read().splitlines() if os.path.exists(sums) else []:
        digest, name = line.split("  ", 1)
        listed.append(name)
        found = glob.glob(os.path.join(rel, name)) + glob.glob(os.path.join(rel, "*", name))
        if len(found) != 1 or hashlib.sha256(open(found[0], "rb").read()).hexdigest() != digest:
            wrong.append(name)
    public = sorted(os.path.basename(p) for p in glob.glob(os.path.join(rel, "**", "BalatroOverhaulLauncher-*"), recursive=True))
    if not os.path.exists(sums) or wrong or sorted(listed) != public:
        bad("SHA256SUMS.txt does not verify: %s" % (wrong or sorted(set(public) ^ set(listed))))
    else:
        print("ok SHA256SUMS.txt verifies")
    if problems:
        print("FAIL: %d problems" % len(problems))
        sys.exit(1)
    print("OK: packages look right")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "dist", "release"))

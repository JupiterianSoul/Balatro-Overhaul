#!/usr/bin/env python3
import hashlib
import http.server
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import zipfile
from pathlib import Path
os.environ.pop("WAYLAND_DISPLAY", None)
os.environ["SDL_VIDEODRIVER"] = "x11"
os.environ["SDL_AUDIODRIVER"] = "dummy"
os.environ["ALSOFT_DRIVERS"] = "null"

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NIGHT = REPO / ".night" / "mobile"
WORK = NIGHT / "upd"
SHOTS = NIGHT / "shots"
PORT = int(os.environ.get("QA_PORT", "38891"))
OFFICIAL = Path(os.environ.get("OFFICIAL_APK", str(NIGHT / "fake" / "official.apk"))).resolve()
OTHER_VANILLA = WORK / "official_other.apk"
OTHER_ONLY = "resources/sounds/other_balatro_only.ogg"
SAVE_NAME = "BalatroOverhaul"
PC_GAME = os.environ.get("PC_GAME")

DRIVER = r'''
do
	local log_path = os.getenv("UPDATE_TEST_LOG")
	local function log(s)
		local f = log_path and io.open(log_path, "a")
		if f then f:write(s, "\n") f:close() end
	end
	local boot = rawget(_G, "OVERHAUL_BOOTSTRAP")
	log("boot " .. tostring(OVERHAUL_VERSION) .. " feed=" .. tostring(boot and boot.feed))
	local t, started, restarting, checked, last = 0, false, false, false, nil
	local up = love.update
	love.update = function(dt)
		if up then up(dt) end
		t = t + dt
		local U = rawget(_G, "OverhaulUpdate")
		if not U then return end
		if U.state ~= last then
			last = U.state
			log("state " .. tostring(U.state))
		end
		if t > 3 and not U.test_checked then
			U.test_checked = true
			U.check(true)
		end
		if U.test_checked and not checked and not U.checking and U.next_check then
			checked = true
			log("checked")
		end
		if U.state == "available" and not started then
			started = true
			U.start()
		end
		if U.state == "ready" and not restarting then
			restarting = true
			log("restart")
			G.FUNCS.overhaul_update_restart()
		end
	end
end
'''

fails = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what, flush=True)
    if not cond:
        fails.append(what)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def replace_file(path, data):
    path.unlink()
    path.write_bytes(data)


def make_game(dst, version):
    src = NIGHT / "standin"
    if dst.exists():
        shutil.rmtree(dst)
    subprocess.run(["cp", "-al", str(src), str(dst)], check=True)
    main = dst / "main.lua"
    replace_file(main, main.read_bytes() + DRIVER.encode())
    cfg = dst / "multiplayer" / "mp_config.lua"
    text = cfg.read_text(encoding="latin-1")
    text = text.replace('"wss://balatro-overhaul-muliplayer.onrender.com/ws"', '"ws://127.0.0.1:%d/ws"' % PORT)
    replace_file(cfg, text.encode("latin-1"))
    g = dst / "globals.lua"
    text = g.read_text(encoding="latin-1")
    text, n = re.subn(r"^OVERHAUL_VERSION = '[^']*'", "OVERHAUL_VERSION = '%s'" % version, text, count=1, flags=re.M)
    if n != 1:
        sys.exit("no OVERHAUL_VERSION line in %s" % g)
    replace_file(g, text.encode("latin-1"))


def make_patch(vanilla, game, out):
    exclude = WORK / "exclude.txt"
    rules = (REPO / "tools" / "release" / "EXCLUDE.txt").read_text(encoding="utf-8").splitlines()
    exclude.write_text("\n".join(l for l in rules if not l.startswith("assets/dev_build.txt")) + "\n", encoding="utf-8")
    subprocess.run([sys.executable, "-B", str(REPO / "tools" / "release" / "patcher" / "make_patch.py"), "--vanilla", str(vanilla),
                    "--assets", str(game), "--exclude", str(exclude), "--out", str(out)],
                   check=True, stdout=subprocess.DEVNULL)


def make_other_vanilla(src, dst, game):
    moved = None
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        prefix = "assets/" if "assets/version.jkr" in zin.namelist() else ""
        for info in zin.infolist():
            data = zin.read(info)
            rel = info.filename[len(prefix):] if info.filename.startswith(prefix) else None
            if info.filename.endswith("version.jkr"):
                data = data.replace(b"1.0.1o", b"1.0.2a", 1)
            elif not moved and rel and rel.endswith(".ogg") and (game / rel).is_file() and (game / rel).read_bytes() == data:
                moved = rel
                zout.writestr(prefix + OTHER_ONLY, data)
                continue
            zout.writestr(info, data)
    return moved


def make_pc_game(official, love, loose):
    if loose.exists():
        shutil.rmtree(loose)
    with zipfile.ZipFile(official) as zin, zipfile.ZipFile(love, "w", zipfile.ZIP_DEFLATED) as zout:
        prefix = "assets/" if "assets/version.jkr" in zin.namelist() else ""
        for n in zin.namelist():
            rel = n[len(prefix):]
            if n.startswith(prefix) and not n.endswith("/") and not rel.startswith("dexopt/"):
                data = zin.read(n)
                zout.writestr(rel, data)
                (loose / rel).parent.mkdir(parents=True, exist_ok=True)
                (loose / rel).write_bytes(data)


def vanilla_version(apk):
    with zipfile.ZipFile(apk) as z:
        names = set(z.namelist())
        name = "assets/version.jkr" if "assets/version.jkr" in names else "version.jkr"
        return z.read(name).split(b"\n")[0].strip().decode()


def zip_patch(patch, out):
    subprocess.run([sys.executable, "-B", str(HERE / "make_apk.py"), "zip", "--patch", str(patch), "--out", str(out)],
                   check=True, stdout=subprocess.DEVNULL)
    return json.loads(Path(str(out) + ".json").read_text())


def make_app(dst, patch, vanilla_from=None):
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)
    subprocess.run([sys.executable, "-B", str(HERE / "make_apk.py"), "phone-tree", "--out", str(dst)], check=True)
    (dst / "patcher").mkdir()
    for name in ("apply.lua", "zipread.lua", "love_ctx.lua"):
        shutil.copy2(REPO / "tools" / "release" / "patcher" / name, dst / "patcher" / name)
    subprocess.run(["cp", "-al", str(patch), str(dst / "patch")], check=True)
    if vanilla_from:
        with zipfile.ZipFile(vanilla_from) as z:
            for n in z.namelist():
                if n.startswith("assets/") and not n.endswith("/"):
                    p = dst / "vanilla" / n[len("assets/"):]
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_bytes(z.read(n))


def make_launcher(dst, patch):
    make_app(dst, patch)
    maker = dst / "launcher" / "android"
    maker.mkdir()
    for f in sorted((HERE / "launcher").glob("*.lua")):
        shutil.copy2(f, maker / f.name)
    (dst / "android").mkdir()
    with zipfile.ZipFile(dst / "android" / "runtime.apk", "w") as z:
        z.writestr("AndroidManifest.xml", b"stand-in")
        z.writestr("assets/overhaul_runtime.json", b"{}")


MAKER_EDITS = [
    ("globals.lua", "loadstring", "    if love.system.getOS() == 'Android' or love.system.getOS() == 'iOS' then\n        self.F_SAVE_TIMER = 5\n        self.F_DISCORD = true\n        self.F_NO_ACHIEVEMENTS = true\n        self.F_CRASH_REPORTS = false\n        self.F_SOUND_THREAD = true\n        self.F_VIDEO_SETTINGS = false\n        self.F_ENGLISH_ONLY = false\n        self.F_QUIT_BUTTON = false\n    end"),
    ("functions/button_callbacks.lua", "G.CONTROLLER.text_input_hook == e and G.CONTROLLER.HID.controller", "  if G.CONTROLLER.text_input_hook == e and (G.CONTROLLER.HID.controller or G.CONTROLLER.HID.touch) then"),
    ("resources/shaders/flame.fs", "#endif", "#endif\n#ifdef GL_ES\n\tprecision MY_HIGHP_OR_MEDIUMP float;\n#endif"),
    ("main.lua", "G.FPS_CAP = G.FPS_CAP or", "        G.FPS_CAP = G.FPS_CAP or select(3, love.window.getMode())['refreshrate']"),
    ("functions/button_callbacks.lua", "resizable = true,", "    resizable = not (love.system.getOS() == 'Android' or love.system.getOS() == 'iOS'),"),
    ("conf.lua", "t.window.width = 0", "    t.window.width = 0\n    t.window.usedpiscale = false"),
    ("globals.lua", "crt = ", "            crt = 0,"),
    ("game.lua", "G.SHADERS['CRT'])", ""),
]


def make_maker_apk(src, out):
    with zipfile.ZipFile(src) as z:
        files = {n: z.read(n) for n in z.namelist() if not n.endswith("/")}
    for name, needle, line in MAKER_EDITS:
        lines = files[name].decode("utf-8").splitlines()
        hit = next((i for i, l in enumerate(lines) if needle in l), None)
        if hit is None:
            sys.exit("Mobile Maker stand-in: no line with %r in %s" % (needle, name))
        lines[hit] = line
        files[name] = ("\r\n".join(lines) + "\r\n").encode("utf-8")
    inner = WORK / "maker_game.love"
    with zipfile.ZipFile(inner, "w", zipfile.ZIP_DEFLATED) as g:
        for n, d in files.items():
            g.writestr(n, d)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as a:
        a.writestr("AndroidManifest.xml", b"x")
        a.write(inner, "assets/game.love")


def make_pc_launcher(dst, patch):
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)
    rel = REPO / "tools" / "release"
    for f in sorted((rel / "launcher").glob("*.lua")):
        shutil.copy2(f, dst / f.name)
    (dst / "patcher").mkdir()
    for name in ("apply.lua", "zipread.lua", "find.lua"):
        shutil.copy2(rel / "patcher" / name, dst / "patcher" / name)
    shutil.copy2(REPO / "assets" / "https.lua", dst / "https.lua")
    shutil.copy2(REPO / "assets" / "functions" / "save_io.lua", dst / "save_io.lua")
    shutil.copy2(REPO / "assets" / "smods" / "libs" / "json" / "json.lua", dst / "json.lua")
    subprocess.run(["cp", "-al", str(patch), str(dst / "patchset")], check=True)
    shutil.copytree(HERE / "launcher", dst / "android")
    (dst / "android" / "patcher").mkdir()
    shutil.copy2(rel / "patcher" / "love_ctx.lua", dst / "android" / "patcher" / "love_ctx.lua")
    subprocess.run([sys.executable, "-B", str(HERE / "make_apk.py"), "phone-tree", "--out", str(dst / "android" / "bootstrap")], check=True)
    with zipfile.ZipFile(dst / "android" / "runtime.apk", "w") as z:
        z.writestr("AndroidManifest.xml", b"stand-in")
        z.writestr("assets/overhaul_runtime.json", b"{}")


def apk_signatures(apk):
    tool = os.environ.get("APKSIGNER") or shutil.which("apksigner")
    if not tool:
        found = sorted(Path.home().glob("Android/Sdk/build-tools/*/apksigner"))
        tool = str(found[-1]) if found else None
    if not tool:
        return None
    res = subprocess.run([tool, "verify", "--verbose", "--min-sdk-version", "21", str(apk)],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if res.returncode != 0:
        return set()
    return set(re.findall(r"Verified using (v\d) scheme[^\n]*: true", res.stdout))


def check_signed(built, what):
    if built is not None and built["signed"] is None:
        print("     apksigner not found, signatures not checked", flush=True)
        return
    check(built is not None and built["signed"] == {"v1", "v2"}, what)


def unpack_app(tag, apk, dst):
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)
    if not apk or not apk.is_file():
        return None
    with zipfile.ZipFile(apk) as z:
        love = z.read("assets/game.love")
    packed = WORK / (tag + ".love")
    packed.write_bytes(love)
    with zipfile.ZipFile(packed) as z:
        z.extractall(dst)
        return {"size": len(love), "names": set(z.namelist()), "signed": apk_signatures(apk)}


def pc_make_apk(tag, launcher, game, dst):
    out_dir = WORK / (tag + "_out")
    xdg = WORK / (tag + "_xdg")
    for d in (out_dir, xdg):
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)
    env = dict(os.environ, XDG_DATA_HOME=str(xdg), LAUNCHER_APK_DIR=str(out_dir), LAUNCHER_MUTE="1", LAUNCHER_NO_ASK="1", OVERHAUL_NO_SCAN="1")
    env.pop("OVERHAUL_GAME", None)
    t0 = time.time()
    with open(WORK / (tag + ".log"), "wb") as log:
        subprocess.run(["xvfb-run", "-a", "love", str(launcher), "--cli", "apk", "--balatro", str(game)],
                       env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600, check=False)
    print("     %s ran %.0f s" % (tag, time.time() - t0), flush=True)
    apks = sorted(out_dir.glob("BalatroOverhaul-*.apk"))
    return unpack_app(tag, apks[0] if apks else None, dst)


def tree_sums(root):
    return {str(f.relative_to(root)): sha(f.read_bytes()) for f in sorted(root.rglob("*")) if f.is_file()}


def tap_make_app(tag, launcher, xdg, dst, official=True):
    bridge = WORK / (tag + "_bridge")
    if bridge.exists():
        shutil.rmtree(bridge)
    bridge.mkdir()
    (bridge / "can_install").write_text("1\n")
    left = save_dir(xdg) / "BalatroOverhaul.apk"
    if left.exists():
        left.unlink()
    run(tag, launcher, xdg, 300, launcher="play+app", official=official, extra={"OVERHAUL_BRIDGE_FAKE": str(bridge)})
    return unpack_app(tag, bridge / "installed.apk", dst)


class Feed:
    build = None
    blob = b""
    hits = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        Feed.hits.append(self.path)
        if self.path.startswith("/version"):
            platform = self.path.split("platform=")[1].split("&")[0] if "platform=" in self.path else ""
            build = None
            if Feed.build and platform == Feed.build["platform"]:
                build = {k: Feed.build[k] for k in ("version", "size", "sha256", "file")}
                build["protocol"] = 0
                if "link=1" in self.path:
                    build["url"] = "http://127.0.0.1:%d/patch.zip" % PORT
            body = json.dumps({"version": build["version"] if build else "2.5", "platform": platform, "build": build}).encode()
        elif self.path == "/patch.zip":
            body = Feed.blob
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def run(tag, app, xdg, seconds, stop=None, screen="1280x720", lang="en", official=True, shots=(), launcher="play+play", extra=None):
    log = WORK / (tag + ".log")
    drv = WORK / (tag + ".driver")
    for f in (log, drv):
        if f.exists():
            f.unlink()
    env = dict(os.environ, XDG_DATA_HOME=str(xdg), OVERHAUL_LANG=lang, UPDATE_TEST_LOG=str(drv), OVERHAUL_INKJOKER_BIN="/nonexistent/inkjoker")
    env.pop("OVERHAUL_OFFICIAL_APK", None)
    (WORK / "launcher_shots").mkdir(exist_ok=True)
    env.update(LAUNCHER_MUTE="1", LAUNCHER_NO_ASK="1", OVERHAUL_NO_UPDATE_CHECK="1")
    if launcher is not None:
        env.update(LAUNCHER_SHOT_DIR=str(WORK / "launcher_shots"), LAUNCHER_SHOTS=launcher)
    if official:
        env["OVERHAUL_OFFICIAL_APK"] = str(OFFICIAL if official is True else official)
    env.update(extra or {})
    script = r'''
love "$APP" > "$LOG" 2>&1 &
pid=$!
t=0
while kill -0 $pid 2>/dev/null && [ $t -lt $LIMIT ]; do
    sleep 1
    t=$((t+1))
    for s in $SHOTS; do [ "$t" = "$s" ] && import -window root "$SHOTDIR/${TAG}_$t.png"; done
    if [ -n "$STOP" ] && grep -q "$STOP" "$DRV" 2>/dev/null; then
        sleep 3
        import -window root "$SHOTDIR/${TAG}_end.png"
        break
    fi
done
[ $t -ge $LIMIT ] && import -window root "$SHOTDIR/${TAG}_end.png"
kill $pid 2>/dev/null
sleep 1
kill -9 $pid 2>/dev/null
true
'''
    env.update(APP=str(app), LOG=str(log), LIMIT=str(seconds), SHOTS=" ".join(str(s) for s in shots),
               SHOTDIR=str(SHOTS), TAG=tag, STOP=stop or "", DRV=str(drv))
    t0 = time.time()
    subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 %sx24" % screen, "bash", "-c", script], env=env, check=False)
    print("     %s ran %.0f s" % (tag, time.time() - t0), flush=True)
    return drv.read_text() if drv.exists() else ""


def save_dir(xdg):
    return xdg / "love" / SAVE_NAME


def marker(xdg):
    p = save_dir(xdg) / "overhaul_game" / ".overhaul_installed"
    return p.read_text().split("\n") if p.exists() else []


def manifest_id(patch):
    return sha((patch / "manifest.lua").read_bytes())


def main():
    nets = [n for _, n in socket.if_nameindex() if n != "lo"]
    if nets:
        sys.exit("run me inside `unshare -rn` (no network but loopback); found %s" % nets)
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    if not OFFICIAL.is_file():
        sys.exit("missing %s (set OFFICIAL_APK to a stand-in official Balatro APK)" % OFFICIAL)
    if not (NIGHT / "standin" / "main.lua").is_file():
        subprocess.run([sys.executable, str(HERE / "make_apk.py"), "standin"], check=True)
    WORK.mkdir(parents=True, exist_ok=True)
    SHOTS.mkdir(parents=True, exist_ok=True)
    vver = vanilla_version(OFFICIAL)
    feed = "android_patch" if "[M]" in vver else "android_patch_pc"
    print("prepare games and patch sets", flush=True)
    make_game(WORK / "v1", "2.5")
    make_game(WORK / "v2", "9.9")
    moved = make_other_vanilla(OFFICIAL, OTHER_VANILLA, WORK / "v2")
    make_patch(OFFICIAL, WORK / "v1", WORK / "patch1")
    make_patch(OFFICIAL, WORK / "v2", WORK / "patch2")
    make_patch(OTHER_VANILLA, WORK / "v2", WORK / "patch_other")
    entry2 = zip_patch(WORK / "patch2", WORK / "patch2.zip")
    zip_patch(WORK / "patch_other", WORK / "patch_other.zip")
    check(moved is not None and ('"%s"' % OTHER_ONLY) in (WORK / "patch_other" / "manifest.lua").read_text(encoding="utf-8"),
          "the other Balatro's patch set needs a file this Balatro does not have (%s moved)" % moved)
    check(entry2["version"] == "9.9" and entry2["vanilla_version"] == vver, "zip entry has the Overhaul and vanilla versions")
    make_app(WORK / "app", WORK / "patch1")
    make_app(WORK / "app_vanilla", WORK / "patch1", vanilla_from=OFFICIAL)
    id1, id2 = manifest_id(WORK / "patch1"), manifest_id(WORK / "patch2")

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    xdg = WORK / "xdg"
    if xdg.exists():
        shutil.rmtree(xdg)
    save = save_dir(xdg)

    print("1. fresh install from the official app, no update in the feed", flush=True)
    out = run("u1_fresh", WORK / "app", xdg, 90, stop="checked", shots=(4,), launcher="play+install,play+play")
    check("boot 2.5 feed=" + feed in out, "game 2.5 boots under the bootstrap with the %s feed" % feed)
    check(marker(xdg)[:2] == [id1, "2.5"], "marker holds patch 1 and version 2.5")
    check(any(h.startswith("/version?platform=%s&" % feed) or h == "/version?platform=" + feed for h in Feed.hits), "in-game check asks the %s feed" % feed)

    print("2. damaged download in the save folder", flush=True)
    (save / "update").mkdir(parents=True, exist_ok=True)
    shutil.copy2(WORK / "patch2.zip", save / "update" / "patch.zip")
    (save / "update" / "patch.zip.sha256").write_text("0" * 64 + "  patch.zip\n")
    run("u2_damaged", WORK / "app", xdg, 25, screen="1560x720", shots=(6,))
    check(marker(xdg)[:2] == [id1, "2.5"], "damaged update leaves the old install")
    check(not (save / "update" / "patch.zip").exists(), "damaged update is deleted")
    check(not (save / "update" / "skip").exists(), "a damaged download is not skipped for good")
    check(not (save / "overhaul_game.new").exists(), "no half install left")
    out = run("u2_after", WORK / "app", xdg, 60, stop="boot 2.5")
    check("boot 2.5" in out, "next start plays the version the player has")

    print("3. update made for another Balatro", flush=True)
    shutil.copy2(WORK / "patch_other.zip", save / "update" / "patch.zip")
    (save / "update" / "patch.zip.sha256").write_text(sha((WORK / "patch_other.zip").read_bytes()) + "  patch.zip\n")
    run("u3_other", WORK / "app", xdg, 30, screen="720x1560", lang="fr", shots=(12,))
    check(marker(xdg)[:2] == [id1, "2.5"], "wrong-vanilla update leaves the old install")
    check(not (save / "update" / "patch.zip").exists(), "wrong-vanilla update is deleted")

    print("4. in-game update from the feed: download, check, restart, install, start 9.9", flush=True)
    Feed.build = dict(entry2, platform=feed)
    Feed.blob = (WORK / "patch2.zip").read_bytes()
    Feed.hits.clear()
    keep = save / "1" / "keep_me.txt"
    keep.parent.mkdir(parents=True, exist_ok=True)
    keep.write_text("save data")
    out = run("u4_update", WORK / "app", xdg, 150, stop="boot 9.9", lang="es", shots=(8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30))
    check("state downloading" in out and "state ready" in out and "restart" in out, "the game downloads, checks and restarts")
    check("boot 9.9" in out, "the bootstrap installs the update and starts 9.9")
    check(marker(xdg)[:2] == [id2, "9.9"], "marker holds patch 2 and version 9.9")
    check("/patch.zip" in Feed.hits and any("link=1" in h for h in Feed.hits), "the patch set came from the feed link")
    check(not (save / "update" / "patch.zip").exists(), "installed update zip is removed")
    check(not (save / "update" / "patch.zip.part").exists(), "no partial download left")
    check(not (save / "update" / "patch.zip.sha256").exists(), "sha file is removed")
    check(keep.is_file() and keep.read_text() == "save data", "save files are kept through the update")

    print("5. next start: no downgrade to the bundled 2.5", flush=True)
    stamp = (save / "overhaul_game" / "main.lua").stat().st_mtime
    out = run("u5_again", WORK / "app", xdg, 60, stop="boot 9.9")
    check("boot 9.9" in out and "boot 2.5" not in out, "9.9 starts again, bundled 2.5 is not reinstalled")
    check((save / "overhaul_game" / "main.lua").stat().st_mtime == stamp, "no reinstall on a normal start")

    print("6. killed between removing the old install and renaming the new one", flush=True)
    os.rename(save / "overhaul_game", save / "overhaul_game.new")
    out = run("u6_recover", WORK / "app", xdg, 60, stop="boot 9.9")
    check("boot 9.9" in out, "the finished new install is picked up")
    check((save / "overhaul_game").is_dir() and not (save / "overhaul_game.new").exists(), "folders are back in place")

    print("7. APK built on a PC with the player's own vanilla files inside", flush=True)
    Feed.build = None
    xdg2 = WORK / "xdg_vanilla"
    if xdg2.exists():
        shutil.rmtree(xdg2)
    out = run("u7_vanilla", WORK / "app_vanilla", xdg2, 90, stop="boot 2.5", official=False, launcher="play+install,play+play")
    check("boot 2.5" in out, "installs from the bundled vanilla without the official app")
    check(marker(xdg2)[:2] == [id1, "2.5"], "marker after the bundled-vanilla install")
    check(not (save_dir(xdg2) / "official.zip").exists(), "no official copy made")

    print("7b. APK made by the PC launcher (MAKE ANDROID APK): the game is finished while the APK is made", flush=True)
    with zipfile.ZipFile(OFFICIAL) as z:
        official_files = [n for n in z.namelist() if n.startswith("assets/") and not n.endswith("/") and not n.startswith("assets/dexopt/")]
    make_pc_game(OFFICIAL, WORK / "pc_game.love", WORK / "pc_game")
    make_pc_launcher(WORK / "pc_launcher", WORK / "patch1")
    built = pc_make_apk("u7b_make", WORK / "pc_launcher", WORK / "pc_game.love", WORK / "app_pc")
    check(built is not None, "the PC launcher makes an APK from the player's Balatro")
    check_signed(built, "the APK has the old (v1) and the new (v2) signature, so Android 5 and 6 install it too")
    names = built["names"] if built else set()
    kept_vanilla = [n for n in names if n.startswith("vanilla/")]
    print("     game package %.1f MB, %d of %d official files kept twice" % ((built or {"size": 0})["size"] / 1e6, len(kept_vanilla), len(official_files)), flush=True)
    check({"overhaul_built", "game_main.lua", "game_conf.lua", "main.lua", "updating.lua", "overhaul_install.lua", "patcher/apply.lua",
           "patcher/love_ctx.lua", "vanilla_shared.txt", "vanilla/version.jkr", "direct_play"} <= names, "the APK holds the finished game next to the start files")
    check(not any(n.startswith(("patch/", "patch_pc/")) for n in names), "the patch set itself is not in the APK")
    check(0 < len(kept_vanilla) < len(official_files) / 2, "only the official files the Overhaul changes are kept a second time")
    built_marker = (WORK / "app_pc" / "overhaul_built").read_text().split("\n") if built else []
    check(built_marker[:3] == [id1, "2.5", vver], "the marker names patch 1, version 2.5 and the player's Balatro")
    loose = pc_make_apk("u7b_loose", WORK / "pc_launcher", WORK / "pc_game", WORK / "app_pc_loose")
    check(loose is not None and tree_sums(WORK / "app_pc_loose") == tree_sums(WORK / "app_pc"), "a Balatro folder gives the same game as the packed Balatro")
    xdg_pc = WORK / "xdg_pc"
    if xdg_pc.exists():
        shutil.rmtree(xdg_pc)
    save_pc = save_dir(xdg_pc)
    out = run("u7b_first", WORK / "app_pc", xdg_pc, 90, stop="checked", official=False, launcher=None, shots=(3,))
    check("boot 2.5 feed=" + feed in out and out.count("boot") == 1, "first start goes straight into game 2.5")
    check(not (save_pc / "overhaul_game").exists() and not (save_pc / "overhaul_game.new").exists(), "nothing was patched or copied on the first start")
    Feed.build = dict(entry2, platform=feed)
    Feed.blob = (WORK / "patch2.zip").read_bytes()
    out = run("u7b_update", WORK / "app_pc", xdg_pc, 150, stop="boot 9.9", official=False, launcher=None)
    check("state ready" in out and "boot 9.9" in out, "the APK's game downloads an update in game and starts 9.9")
    check(marker(xdg_pc)[:2] == [id2, "9.9"] and marker(xdg_pc)[4:5] == [id1], "the update is installed on top of the built game")
    Feed.build = None

    print("8. Balatro Overhaul made by the phone launcher: straight into the game, saves carried, in-game update", flush=True)
    make_app(WORK / "app_direct", WORK / "patch1", vanilla_from=OFFICIAL)
    (WORK / "app_direct" / "direct_play").write_text("1\n")
    carried = WORK / "app_direct" / "carry" / "1"
    carried.mkdir(parents=True)
    (carried / "carried.txt").write_text("carried profile")
    Feed.build = None
    xdg3 = WORK / "xdg_direct"
    if xdg3.exists():
        shutil.rmtree(xdg3)
    save3 = save_dir(xdg3)
    out = run("u8_direct", WORK / "app_direct", xdg3, 90, stop="boot 2.5", official=False, launcher=None)
    check("boot 2.5" in out, "first start installs from the files inside and starts the game with no tap")
    check(marker(xdg3)[:2] == [id1, "2.5"], "marker after the first start")
    profile = save3 / "1" / "carried.txt"
    check(profile.is_file() and profile.read_text() == "carried profile", "the launcher's save is in the new app")
    check((save3 / "carry_done").is_file(), "the carry is marked done")
    profile.write_text("played in the app")
    out = run("u8_again", WORK / "app_direct", xdg3, 60, stop="boot 2.5", official=False, launcher=None)
    check("boot 2.5" in out and out.count("boot") == 1, "next start goes straight into the game")
    check(profile.read_text() == "played in the app", "the carry never overwrites the app's own saves")
    xdg_old = WORK / "xdg_old"
    if xdg_old.exists():
        shutil.rmtree(xdg_old)
    shutil.copytree(xdg3, xdg_old)
    Feed.build = dict(entry2, platform=feed)
    Feed.blob = (WORK / "patch2.zip").read_bytes()
    out = run("u8_update", WORK / "app_direct", xdg3, 150, stop="boot 9.9", official=False, launcher=None)
    check("state ready" in out and "boot 9.9" in out, "the app downloads the update in game and starts 9.9 by itself")
    check(marker(xdg3)[:2] == [id2, "9.9"], "marker holds patch 2 after the in-game update")
    check(profile.read_text() == "played in the app", "saves kept through the in-game update")

    print("9. the phone launcher finishes the game while it makes the app: no patching on the first start", flush=True)
    Feed.build = None
    with zipfile.ZipFile(OFFICIAL) as z:
        official_files = [n for n in z.namelist() if n.startswith("assets/") and not n.endswith("/") and not n.startswith("assets/dexopt/")]
    make_launcher(WORK / "launcher1", WORK / "patch1")
    xdg_l = WORK / "xdg_launcher"
    if xdg_l.exists():
        shutil.rmtree(xdg_l)
    (save_dir(xdg_l) / "1").mkdir(parents=True)
    (save_dir(xdg_l) / "1" / "carried.txt").write_text("carried profile")
    built = tap_make_app("u9_make", WORK / "launcher1", xdg_l, WORK / "app_built")
    check(built is not None, "Make the app in the launcher gives an app")
    check_signed(built, "the app has the old (v1) and the new (v2) signature, so Android 5 and 6 install it too")
    names = built["names"] if built else set()
    kept_vanilla = [n for n in names if n.startswith("vanilla/")]
    print("     game package %.1f MB, %d of %d official files kept twice" % ((built or {"size": 0})["size"] / 1e6, len(kept_vanilla), len(official_files)), flush=True)
    check({"overhaul_built", "game_main.lua", "game_conf.lua", "main.lua", "updating.lua", "vanilla_shared.txt", "vanilla/version.jkr", "direct_play"} <= names, "the app holds the finished game next to the start files")
    check(not any(n.startswith(("patch/", "patch_pc/")) for n in names), "the patch set itself is not in the app")
    check(0 < len(kept_vanilla) < len(official_files) / 2, "only the official files the Overhaul changes are kept a second time")
    check("carry/1/carried.txt" in names, "the launcher's save is packed for the first start")
    xdg4 = WORK / "xdg_built"
    if xdg4.exists():
        shutil.rmtree(xdg4)
    save4 = save_dir(xdg4)
    out = run("u9_first", WORK / "app_built", xdg4, 90, stop="checked", official=False, launcher=None, shots=(3,))
    check("boot 2.5 feed=" + feed in out and out.count("boot") == 1, "first start goes straight into game 2.5")
    check(not (save4 / "overhaul_game").exists() and not (save4 / "overhaul_game.new").exists(), "nothing was patched or copied on the first start")
    profile4 = save4 / "1" / "carried.txt"
    check(profile4.is_file() and profile4.read_text() == "carried profile", "the launcher's save is in the new app")
    profile4.write_text("played in the app")

    print("   rebuild over an app made the old way, same version number", flush=True)
    old_save = save_dir(xdg_old)
    check(marker(xdg_old)[:2] == [id1, "2.5"] and (old_save / "overhaul_game" / "main.lua").is_file(), "the old app patched itself into its save folder")
    out = run("u9_over_old", WORK / "app_built", xdg_old, 90, stop="boot 2.5", official=False, launcher=None)
    check("boot 2.5" in out and out.count("boot") == 1, "after the rebuild the game starts at once")
    check(not (old_save / "overhaul_game").exists(), "the old patched copy is removed")
    check((old_save / "1" / "carried.txt").read_text() == "played in the app", "saves survive the rebuild")

    print("   rebuild with the same launcher, then quit and reopen", flush=True)
    built = tap_make_app("u9_remake", WORK / "launcher1", xdg_l, WORK / "app_built")
    check(built is not None, "Rebuild the app gives an app again")
    out = run("u9_reopen", WORK / "app_built", xdg4, 60, stop="boot 2.5", official=False, launcher=None)
    check("boot 2.5" in out and out.count("boot") == 1, "the rebuilt app starts at once")
    check(profile4.read_text() == "played in the app" and not (save4 / "overhaul_game").exists(), "saves kept, nothing patched")

    print("   in-game update inside the finished app", flush=True)
    Feed.build = dict(entry2, platform=feed)
    Feed.blob = (WORK / "patch2.zip").read_bytes()
    out = run("u9_update", WORK / "app_built", xdg4, 150, stop="boot 9.9", official=False, launcher=None, shots=(8, 12, 16, 20, 24))
    check("state ready" in out and "boot 9.9" in out, "the app downloads the update in game and starts 9.9")
    check(marker(xdg4)[:2] == [id2, "9.9"] and marker(xdg4)[4:5] == [id1], "the update is installed on top of the built game")
    check(profile4.read_text() == "played in the app", "saves kept through the in-game update")
    Feed.build = None
    stamp = (save4 / "overhaul_game" / "main.lua").stat().st_mtime
    out = run("u9_quit_reopen", WORK / "app_built", xdg4, 60, stop="boot 9.9", official=False, launcher=None)
    check("boot 9.9" in out and "boot 2.5" not in out and out.count("boot") == 1, "quit and reopen: 9.9 starts at once")
    check((save4 / "overhaul_game" / "main.lua").stat().st_mtime == stamp, "no reinstall after quit and reopen")

    print("   rebuild with an older launcher keeps the newer game, a newer launcher takes over", flush=True)
    tap_make_app("u9_remake_old", WORK / "launcher1", xdg_l, WORK / "app_built")
    out = run("u9_keep_new", WORK / "app_built", xdg4, 60, stop="boot 9.9", official=False, launcher=None)
    check("boot 9.9" in out and "boot 2.5" not in out, "a rebuild from the older launcher does not downgrade the game")
    make_launcher(WORK / "launcher2", WORK / "patch2")
    built = tap_make_app("u9_make_new", WORK / "launcher2", xdg_l, WORK / "app_built2")
    check(built is not None, "the newer launcher makes the app")
    out = run("u9_new_build", WORK / "app_built2", xdg4, 60, stop="boot 9.9", official=False, launcher=None)
    check("boot 9.9" in out and out.count("boot") == 1, "the app from the newer launcher starts 9.9 at once")
    check(not (save4 / "overhaul_game").exists(), "the copy from the in-game update is removed after the rebuild")
    check(profile4.read_text() == "played in the app", "saves kept through every rebuild")

    print("10. Balatro Mobile Maker game (a PC Balatro inside an APK): made by the phone launcher, then an in-game update", flush=True)
    if not PC_GAME:
        print("     skipped, set PC_GAME to a PC Balatro (Balatro.exe)", flush=True)
    else:
        Feed.build = None
        pc_vver = vanilla_version(PC_GAME)
        make_maker_apk(PC_GAME, WORK / "maker.apk")
        make_patch(PC_GAME, WORK / "v1", WORK / "patch_pc1")
        make_patch(PC_GAME, WORK / "v2", WORK / "patch_pc2")
        entry_pc2 = zip_patch(WORK / "patch_pc2", WORK / "patch_pc2.zip")
        pc2 = manifest_id(WORK / "patch_pc2")
        make_launcher(WORK / "launcher_mk", WORK / "patch1")
        subprocess.run(["cp", "-al", str(WORK / "patch_pc1"), str(WORK / "launcher_mk" / "patch_pc")], check=True)
        xdg_ml = WORK / "xdg_maker_launcher"
        xdg_m = WORK / "xdg_maker"
        for d in (xdg_ml, xdg_m):
            if d.exists():
                shutil.rmtree(d)
        save_m = save_dir(xdg_m)
        built = tap_make_app("u10_make", WORK / "launcher_mk", xdg_ml, WORK / "app_maker", official=WORK / "maker.apk")
        check(built is not None, "Make the app gives an app from a Mobile Maker game")
        built_marker = (WORK / "app_maker" / "overhaul_built").read_text().split("\n") if built else []
        check(built_marker[:3] == [id1, "2.5", pc_vver], "the marker names the launcher's build, version 2.5 and the PC Balatro inside")
        conf = (WORK / "app_maker" / "game_conf.lua").read_text(encoding="latin-1") if built else ""
        check("usedpiscale = false" in conf, "the option the player picked in Mobile Maker is kept")
        out = run("u10_first", WORK / "app_maker", xdg_m, 90, stop="checked", official=False, launcher=None, shots=(3,))
        check("boot 2.5 feed=android_patch_pc" in out and out.count("boot") == 1, "first start goes straight into game 2.5 with the PC feed")
        check(not (save_m / "overhaul_game").exists() and not (save_m / "overhaul_game.new").exists(), "nothing was patched or copied on the first start")
        Feed.build = dict(entry_pc2, platform="android_patch_pc")
        Feed.blob = (WORK / "patch_pc2.zip").read_bytes()
        out = run("u10_update", WORK / "app_maker", xdg_m, 150, stop="boot 9.9", official=False, launcher=None)
        check("state ready" in out and "boot 9.9" in out, "the game downloads the update in game and starts 9.9")
        check(marker(xdg_m)[:2] == [pc2, "9.9"] and marker(xdg_m)[4:5] == [id1], "the update is installed on top of the built game")
        conf = save_m / "overhaul_game" / "conf.lua"
        check(conf.is_file() and "usedpiscale = false" in conf.read_text(encoding="latin-1"), "the Mobile Maker option survives the update")
        Feed.build = None

    srv.shutdown()
    print("%d failure(s)" % len(fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()

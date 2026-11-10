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

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
NIGHT = REPO / ".night" / "mobile"
WORK = NIGHT / "upd"
SHOTS = NIGHT / "shots"
PORT = int(os.environ.get("QA_PORT", "38891"))
OFFICIAL = Path(os.environ.get("OFFICIAL_APK", str(NIGHT / "fake" / "official.apk"))).resolve()
OTHER_VANILLA = WORK / "official_other.apk"
SAVE_NAME = "BalatroOverhaul"

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


def make_other_vanilla(src, dst):
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in zin.infolist():
            data = zin.read(info)
            if info.filename.endswith("version.jkr"):
                data = data.replace(b"1.0.1o", b"1.0.2a", 1)
            zout.writestr(info, data)


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


def run(tag, app, xdg, seconds, stop=None, screen="1280x720", lang="en", official=True, shots=(), launcher="play+play"):
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
        env["OVERHAUL_OFFICIAL_APK"] = str(OFFICIAL)
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
    make_other_vanilla(OFFICIAL, OTHER_VANILLA)
    vver = vanilla_version(OFFICIAL)
    feed = "android_patch" if "[M]" in vver else "android_patch_pc"
    print("prepare games and patch sets", flush=True)
    make_game(WORK / "v1", "2.5")
    make_game(WORK / "v2", "9.9")
    make_patch(OFFICIAL, WORK / "v1", WORK / "patch1")
    make_patch(OFFICIAL, WORK / "v2", WORK / "patch2")
    make_patch(OTHER_VANILLA, WORK / "v2", WORK / "patch_other")
    entry2 = zip_patch(WORK / "patch2", WORK / "patch2.zip")
    zip_patch(WORK / "patch_other", WORK / "patch_other.zip")
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
    Feed.build = dict(entry2, platform=feed)
    Feed.blob = (WORK / "patch2.zip").read_bytes()
    out = run("u8_update", WORK / "app_direct", xdg3, 150, stop="boot 9.9", official=False, launcher=None)
    check("state ready" in out and "boot 9.9" in out, "the app downloads the update in game and starts 9.9 by itself")
    check(marker(xdg3)[:2] == [id2, "9.9"], "marker holds patch 2 after the in-game update")
    check(profile.read_text() == "played in the app", "saves kept through the in-game update")

    srv.shutdown()
    print("%d failure(s)" % len(fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()

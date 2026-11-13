#!/usr/bin/env python3
import hashlib
import json
import os
import re
import shutil
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
WANT_PERMS = {"android.permission.INTERNET", "android.permission.VIBRATE"}
FILE_PERMS = {"android.permission.MANAGE_EXTERNAL_STORAGE", "android.permission.READ_EXTERNAL_STORAGE",
              "android.permission.WRITE_EXTERNAL_STORAGE", "android.permission.READ_MEDIA_AUDIO",
              "android.permission.READ_MEDIA_IMAGES", "android.permission.READ_MEDIA_VIDEO",
              "android.permission.READ_MEDIA_VISUAL_USER_SELECTED", "android.permission.ACCESS_MEDIA_LOCATION",
              "android.permission.MANAGE_MEDIA", "android.permission.MANAGE_DOCUMENTS"}
NO_PERMS = {"android.permission.RECORD_AUDIO", "android.permission.QUERY_ALL_PACKAGES", "com.android.vending.BILLING",
            "com.google.android.gms.permission.AD_ID", "com.android.vending.CHECK_LICENSE"} | FILE_PERMS
FILE_ACCESS_CODE = ("isExternalStorageManager", "MANAGE_APP_ALL_FILES_ACCESS_PERMISSION", "MANAGE_ALL_FILES_ACCESS_PERMISSION",
                    "requestLegacyExternalStorage", "files_ask", "files_ok")

STEAM_ONLY_LINES = 0

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


DOCS_CLASS = "org.love2d.android.OverhaulDocs"


def providers(apk):
    aapt = shutil.which("aapt") or next(iter(sorted((Path.home() / "Android/Sdk/build-tools").glob("*/aapt"))), None)
    if not aapt:
        return None
    tree = subprocess.run([str(aapt), "dump", "xmltree", str(apk), "AndroidManifest.xml"], stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True).stdout.splitlines()
    out, cur, depth = [], None, 0
    for line in tree:
        ind = len(line) - len(line.lstrip())
        if cur is not None and ind <= depth and line.lstrip().startswith("E: "):
            cur = None
        if line.lstrip().startswith("E: provider"):
            cur, depth = {"lines": []}, ind
            out.append(cur)
        elif cur is not None:
            cur["lines"].append(line.strip())
    res = []
    for p in out:
        attrs = {}
        for l in p["lines"]:
            m = re.match(r'A: android:(\w+)\(0x[0-9a-f]+\)=(?:"([^"]*)"|\(type 0x12\)0x([0-9a-f]+))', l)
            if m and m.group(1) not in attrs:
                attrs[m.group(1)] = m.group(2) if m.group(2) is not None else (m.group(3) != "0")
        attrs["actions"] = [re.search(r'="([^"]+)"', l).group(1) for i, l in enumerate(p["lines"])
                            if i > 0 and p["lines"][i - 1].startswith("E: action") and '="' in l]
        res.append(attrs)
    return res


def docs_provider_ok(provs, pkg):
    hit = [p for p in provs or [] if p.get("name") == DOCS_CLASS]
    if len(hit) != 1:
        return False
    p = hit[0]
    return (p.get("authorities") == pkg + ".files" and p.get("exported") is True and p.get("grantUriPermissions") is True
            and p.get("permission") == "android.permission.MANAGE_DOCUMENTS"
            and "android.content.action.DOCUMENTS_PROVIDER" in p.get("actions", []))


def dex_has(apk, cls):
    needle = ("L" + cls.replace(".", "/") + ";").encode()
    with zipfile.ZipFile(apk) as z:
        return any(needle in z.read(n) for n in z.namelist() if re.match(r"classes\d*\.dex$", n))


def jvm_path_test():
    javac, java = shutil.which("javac"), shutil.which("java")
    jars = sorted((Path.home() / "Android/Sdk/platforms").glob("android-*/android.jar"))
    if not (javac and java and jars):
        return None
    import tempfile
    src = HERE / "java"
    with tempfile.TemporaryDirectory() as out:
        files = [str(f) for f in sorted((src / "stub").rglob("*.java"))] + [str(src / "src/org/love2d/android/OverhaulDocs.java"),
                 str(src / "test/org/love2d/android/DocsPathTest.java")]
        if run([javac, "-nowarn", "--release", "8", "-d", out, "-cp", str(jars[-1])] + files).returncode != 0:
            return False
        res = run([java, "-cp", out + os.pathsep + str(jars[-1]), "org.love2d.android.DocsPathTest"])
        print("     " + res.stdout.strip().splitlines()[-1] if res.stdout.strip() else "")
        return res.returncode == 0


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
    check(not (perms & FILE_PERMS), "runtime declares no file or media permission %s" % (sorted(perms & FILE_PERMS) or ""))
    dev_manifest = (REPO / "AndroidManifest.xml").read_text()
    dev_file_perms = sorted(p for p in FILE_PERMS if '<uses-permission android:name="%s"' % p in dev_manifest)
    check(not dev_file_perms, "dev build manifest declares no file or media permission %s" % (dev_file_perms or ""))
    picker = re.compile(r'<activity [^>]*android:exported="false"[^>]*android:name="org\.love2d\.android\.OverhaulPicker"')
    check(bool(picker.search(dev_manifest)) and bool(picker.search((HERE / "make_apk.py").read_text())),
          "the file picker activity is declared in both manifests and not exported")
    provs = providers(runtime)
    check(provs is not None, "aapt found to read the manifests")
    check(docs_provider_ok(provs, "com.jupiteriansoul.balatrooverhaul"),
          "runtime declares the game folder provider: exported, MANAGE_DOCUMENTS, grantUriPermissions, DOCUMENTS_PROVIDER, authority <package>.files")
    check(dex_has(runtime, DOCS_CLASS), "runtime dex holds OverhaulDocs")
    docs_dev = re.search(r'<provider android:authorities="com\.jupiteriansoul\.balatro\.overhaul\.files" android:exported="true" android:grantUriPermissions="true" android:name="org\.love2d\.android\.OverhaulDocs" android:permission="android\.permission\.MANAGE_DOCUMENTS">\s*<intent-filter>\s*<action android:name="android\.content\.action\.DOCUMENTS_PROVIDER"/>', dev_manifest)
    check(bool(docs_dev), "dev build manifest declares the game folder provider with its own authority")
    smali_docs = [d / "OverhaulDocs.smali" for d in (HERE / "smali" / "org" / "love2d" / "android", REPO / "smali" / "org" / "love2d" / "android")]
    check(all(f.is_file() for f in smali_docs), "OverhaulDocs smali is in the bundled and the dev smali")
    check(jvm_path_test() is not False, "game folder provider path checks (JVM: ../, absolute, symlinks, names)")
    sys.path.insert(0, str(HERE))
    import make_apk as maker_mod
    game_man = maker_mod.manifest_text(maker_mod.DEFAULT_PACKAGE, "Balatro Overhaul")
    inst_man = maker_mod.manifest_text(maker_mod.INSTALLER_PACKAGE, "Overhaul Launcher")
    saves_act = re.search(r'<activity [^>]*android:name="org\.love2d\.android\.OverhaulSaves"[^>]*/>', game_man)
    check(bool(saves_act) and 'android:exported="true"' in saves_act.group(0) and "permission" not in saves_act.group(0),
          "game app declares the OverhaulSaves activity, exported for the launcher, with no intent filter")
    check("OverhaulSaves" not in inst_man, "the launcher itself has no OverhaulSaves activity")
    with zipfile.ZipFile(runtime) as z:
        bin_man = z.read("AndroidManifest.xml")
        dex = b"".join(z.read(n) for n in z.namelist() if re.match(r"classes\d*\.dex$", n))
    check("org.love2d.android.OverhaulSaves".encode("utf-16-le") in bin_man or b"org.love2d.android.OverhaulSaves" in bin_man,
          "runtime manifest has the OverhaulSaves activity")
    check(b"Lorg/love2d/android/OverhaulSaves;" in dex, "runtime dex has the OverhaulSaves class")
    check((HERE / "smali" / "org" / "love2d" / "android" / "OverhaulSaves.smali").is_file()
          and (REPO / "smali" / "org" / "love2d" / "android" / "OverhaulSaves.smali").is_file(), "OverhaulSaves smali is bundled")
    java = (HERE / "java" / "src" / "org" / "love2d" / "android" / "OverhaulSaves.java").read_text()
    def jset(name):
        m = re.search(name + r" = new HashSet<String>\(Arrays\.asList\((.*?)\)\);", java, re.S)
        return set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()
    sio = (REPO / "assets" / "functions" / "save_io.lua").read_text()
    def lset(name, text):
        m = re.search(name + r" = \{(.*?)\n?\}", text, re.S)
        body = m.group(1) if m else ""
        return set(re.findall(r'(?:\["([^"]+)"\]|\b([A-Za-z_][\w.]*)) = true', body)) and {a or b for a, b in re.findall(r'(?:\["([^"]+)"\]|\b([A-Za-z_][\w.]*)) = true', body)}
    launcher_saves = (REPO / "tools" / "release" / "launcher" / "saves.lua").read_text()
    want_dirs = lset("M.SKIP_DIRS", sio) | lset("M.SOURCE_DIRS", sio) | lset("V.PHONE_SKIP", launcher_saves)
    want_files = (lset("M.SKIP_FILES", sio) - {"M.LOCK"}) | {"overhaul_running.lock"} | lset("V.PHONE_FILES", launcher_saves)
    check(want_dirs and want_dirs <= jset("SKIP_DIRS"), "OverhaulSaves skips every folder the Lua export skips %s" % sorted(want_dirs - jset("SKIP_DIRS")))
    check(want_files and want_files <= jset("SKIP_FILES"), "OverhaulSaves skips every file the Lua export skips %s" % sorted(want_files - jset("SKIP_FILES")))
    check(jset("ROOT_LUA") == lset("M.ROOT_LUA", sio), "OverhaulSaves keeps the same root data .lua files as the Lua export")
    check("FLAG_GRANT_WRITE_URI_PERMISSION" not in java and "EXTERNAL_STORAGE" not in java, "OverhaulSaves grants read only and needs no storage permission")
    leftovers = []
    for f in [REPO / "AndroidManifest.xml", HERE / "make_apk.py", HERE / "phone" / "core.lua",
              REPO / "assets" / "functions" / "mods_ui.lua", REPO / "assets" / "functions" / "jukebox.lua",
              REPO / "assets" / "modloader" / "installer.lua"] + sorted((HERE / "java" / "src").rglob("*.java")) \
            + sorted((HERE / "smali").rglob("Overhaul*.smali")) + sorted((REPO / "smali" / "org" / "love2d" / "android").glob("Overhaul*.smali")):
        text = f.read_text(errors="replace")
        leftovers += ["%s: %s" % (f.relative_to(REPO), w) for w in FILE_ACCESS_CODE if w in text]
    check(not leftovers, "no All files access code left in the bridge, the manifests or the game %s" % (leftovers[:5] or ""))
    shared = []
    for f in [HERE / "phone" / "core.lua", REPO / "assets" / "modloader" / "installer.lua", REPO / "assets" / "functions" / "jukebox.lua"]:
        text = f.read_text(errors="replace")
        shared += ["%s: %s" % (f.relative_to(REPO), w) for w in ("/storage/emulated/0/Download", "/sdcard/Download", "EXTERNAL_STORAGE") if w in text]
    check(not shared, "no phone Downloads path left in the game or the launcher %s" % (shared[:5] or ""))
    app_files = set(re.findall(r'"([^"]+)"', re.search(r"M\.APP_FILES = \{([^}]*)\}", (HERE / "launcher" / "make_apk.lua").read_text()).group(1)))
    boot = {f.name for f in (HERE / "bootstrap").glob("*.lua")}
    check(boot <= app_files, "the phone launcher copies every bootstrap file into the game app %s" % (sorted(boot - app_files) or ""))
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
        other = ["--other", str(STEAM)] if STEAM.is_file() else []
        check(run(MAKE_PATCH + ["--vanilla", str(OFFICIAL)] + other + ["--assets", str(standin), "--out", str(patch)]).returncode == 0,
              "patch set builds against the official APK's assets/")
        res = run(MAKER + ["installer", "--patch", str(patch), "--out", str(out_dir), "--work", work,
                           "--keystore", str(NIGHT / "installer-keys" / "installer-test.p12")])
        check(res.returncode == 0, "installer APK builds")
        inst = out_dir / "BalatroOverhaul-installer.apk"
        if inst.is_file():
            info = inspect(inst)
            check(info.get("package") == "com.jupiteriansoul.balatrooverhaul.phone", "installer has its own package name")
            check(info.get("label") == "Overhaul Launcher", "installer has its own label")
            check(info.get("queries") == ["com.playstack.balatro.android", "com.unofficial.balatro", "com.jupiteriansoul.balatrooverhaul"], "installer declares the official app, a Balatro Mobile Maker app and Balatro Overhaul in <queries>")
            check("android.permission.REQUEST_INSTALL_PACKAGES" in info.get("permissions", []), "installer may hand the app it builds to Android's installer")
            perms = set(info.get("permissions", []))
            check(WANT_PERMS <= perms and not (perms & NO_PERMS), "installer permissions: the Overhaul's own, no QUERY_ALL_PACKAGES")
            check(info.get("signature_ok") and info.get("aligned") is True, "installer is signed (v1, v2, v3) and aligned")
            check(providers(inst) is not None and not any(p.get("name") == DOCS_CLASS for p in providers(inst)),
                  "installer does not show its own folder (it holds the player's signing key) in the Files app")
            with zipfile.ZipFile(inst) as z, z.open("assets/game.love") as gl, zipfile.ZipFile(gl) as love:
                inner = love.read("android/runtime.apk") if "android/runtime.apk" in love.namelist() else None
            if inner:
                inner_path = NIGHT / "installer-inner-runtime.apk"
                inner_path.write_bytes(inner)
                check(docs_provider_ok(providers(inner_path), "com.jupiteriansoul.balatrooverhaul") and dex_has(inner_path, DOCS_CLASS),
                      "the runtime the phone launcher builds the game app from has the game folder provider")
                inner_path.unlink()
            else:
                check(False, "installer game.love holds android/runtime.apk")
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
            with zipfile.ZipFile(inst) as z, z.open("assets/game.love") as gl, zipfile.ZipFile(gl) as love:
                needs = set()
                for n in names:
                    if n.startswith("launcher/") and n.endswith(".lua"):
                        for line in love.read(n).decode("utf-8", "replace").splitlines():
                            if "pcall" not in line:
                                needs |= set(re.findall(r'\brequire\s*\(?\s*"([\w.]+)"', line))
            have = {n[len("launcher/"):-4].replace("/", ".") for n in names if n.startswith("launcher/") and n.endswith(".lua")} \
                | {n[:-4].replace("/", ".") for n in names if n.endswith(".lua")}
            missing = sorted(r for r in needs if r not in have and r.split(".")[0] not in ("love", "socket", "ssl", "ffi", "bit", "jit", "utf8"))
            check(not missing, "every module the phone launcher requires is inside the installer's game.love %s" % (missing or ""))
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

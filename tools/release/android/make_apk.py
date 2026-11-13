#!/usr/bin/env python3
import argparse
import hashlib
import io
import json
import os
import re
import secrets
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
IN_REPO = (REPO / ".git").exists() and (REPO / "tools" / "release" / "android").resolve() == HERE

KNOWN_LOVE = {
    "10a804f84da2cbe1b9c65736bcae0572accc1c7ded46b132c2de73d7e35b1f00": "11.5a",
}
DEFAULT_LOVE_APK = Path.home() / ".local/state/balatro-night/downloads/love-11.5-android.apk"
DEFAULT_PACKAGE = "com.jupiteriansoul.balatrooverhaul"
DEFAULT_LABEL = "Balatro Overhaul"
INSTALLER_PACKAGE = "com.jupiteriansoul.balatrooverhaul.phone"
INSTALLER_LABEL = "Overhaul Launcher"
INSTALLER_NAME = "BalatroOverhaul-installer.apk"
INSTALLER_ICON = HERE / "icon" / "installer.png"
PATCHER = REPO / "tools" / "release" / "patcher"
PATCHER_LUA = ("apply.lua", "zipread.lua", "love_ctx.lua")
LAUNCHER = REPO / "tools" / "release" / "launcher"
LAUNCHER_SHARED = ("main.lua", "ui.lua", "gfx.lua", "lang.lua", "net.lua", "app_icon.lua", "saves.lua", "modfiles.lua", "news.lua", "lcode.lua")
NATIVE_FILE = HERE / "NATIVE"
NATIVE_NAME = "native.txt"
OFFICIAL_PACKAGE = "com.playstack.balatro.android"
MAKER_PACKAGE = "com.unofficial.balatro"
RUNTIME_NAME = "overhaul-runtime.apk"
RUNTIME_INFO = "assets/overhaul_runtime.json"
KEY_ALIAS = "overhaul"
MIN_SDK = 21

STANDIN_SKIP_DIRS = {"dexopt"}
STANDIN_SKIP_FILES = {
    "ERROR_LOG.txt", "SESSION_LOG.txt", "DEV_CHANGELOG.txt", "FEATURES.txt", "info.txt", "perf_log.on",
}
STORE_EXT = {".ogg", ".png", ".jpg", ".jpeg", ".mp3", ".ogv", ".zip", ".love", ".apk"}

ICON_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ICON_BG = (0xFE, 0x5F, 0x55)
ICON_BG_EDGE = (0xC9, 0x3F, 0x37)


def say(msg):
    print(msg, flush=True)


def die(msg, code=1):
    print("make_apk: " + msg, file=sys.stderr, flush=True)
    sys.exit(code)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def find_tool(name, env=None):
    if env and os.environ.get(env):
        return os.environ[env]
    return shutil.which(name)


def run(cmd, quiet=True):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if res.returncode != 0:
        tail = "\n".join(res.stdout.strip().splitlines()[-25:])
        die("command failed: %s\n%s" % (" ".join(str(c) for c in cmd), tail))
    if not quiet:
        say(res.stdout.rstrip())
    return res.stdout


def apktool_cmd():
    jar = os.environ.get("APKTOOL_JAR")
    if jar:
        java = find_tool("java", "JAVA") or die("java not found (needed for APKTOOL_JAR)")
        return [java, "-jar", jar]
    tool = find_tool("apktool", "APKTOOL")
    if not tool:
        die("apktool not found: install it or set APKTOOL / APKTOOL_JAR")
    return [tool]


def read_overhaul_version(game_dir):
    g = game_dir / "globals.lua"
    if g.is_file():
        m = re.search(r"OVERHAUL_VERSION\s*=\s*['\"]([0-9][0-9A-Za-z.\-]*)['\"]", g.read_text(errors="replace"))
        if m:
            return m.group(1)
    return "0.0"


def version_code_for(name):
    parts = [int(p) for p in re.findall(r"\d+", name)[:3]]
    while len(parts) < 3:
        parts.append(0)
    return max(1, parts[0] * 10000 + min(parts[1], 99) * 100 + min(parts[2], 99))


def default_key_dir():
    if IN_REPO:
        return REPO / ".night" / "mobile" / "android-keys"
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(Path.home(), ".local", "share")
    if sys.platform == "win32":
        base = os.environ.get("APPDATA", base)
    elif sys.platform == "darwin":
        base = os.path.join(Path.home(), "Library", "Application Support")
    return Path(base) / "balatro-overhaul" / "android"


MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:compileSdkVersion="34" android:compileSdkVersionCodename="14" package="{pkg}" platformBuildVersionCode="34" platformBuildVersionName="14">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
{extra_perms}    <uses-feature android:glEsVersion="0x00020000"/>
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
    <uses-feature android:name="android.hardware.bluetooth" android:required="false"/>
    <uses-feature android:name="android.hardware.gamepad" android:required="false"/>
    <uses-feature android:name="android.hardware.usb.host" android:required="false"/>
    <uses-feature android:name="android.hardware.type.pc" android:required="false"/>
    <uses-feature android:name="android.hardware.audio.low_latency" android:required="false"/>
    <uses-feature android:name="android.hardware.audio.pro" android:required="false"/>
    <queries>
        <package android:name="{official}"/>
{extra_queries}    </queries>
    <permission android:name="{pkg}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" android:protectionLevel="signature"/>
    <uses-permission android:name="{pkg}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/>
    <application android:allowBackup="true" android:appCategory="game" android:appComponentFactory="androidx.core.app.CoreComponentFactory" android:extractNativeLibs="true" android:icon="@drawable/love" android:label="{label}" android:usesCleartextTraffic="true">
        <activity android:configChanges="keyboard|keyboardHidden|navigation|orientation|screenLayout|screenSize|smallestScreenSize" android:exported="true" android:label="{label}" android:launchMode="singleTop" android:name="org.love2d.android.GameActivity" android:resizeableActivity="false" android:screenOrientation="landscape" android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
                <category android:name="tv.ouya.intent.category.GAME"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"/>
            </intent-filter>
        </activity>
        <activity android:configChanges="keyboard|keyboardHidden|navigation|orientation|screenLayout|screenSize|smallestScreenSize|uiMode" android:exported="false" android:name="org.love2d.android.OverhaulPicker" android:theme="@android:style/Theme.Translucent.NoTitleBar"/>
{saves_activity}        <provider android:authorities="{pkg}.overhaul.files" android:exported="false" android:grantUriPermissions="true" android:name="org.love2d.android.OverhaulFiles"/>
        <provider android:authorities="{pkg}.androidx-startup" android:exported="false" android:name="androidx.startup.InitializationProvider">
            <meta-data android:name="androidx.emoji2.text.EmojiCompatInitializer" android:value="androidx.startup"/>
            <meta-data android:name="androidx.lifecycle.ProcessLifecycleInitializer" android:value="androidx.startup"/>
        </provider>
{docs}    </application>
</manifest>
"""

DOCS_PROVIDER = """        <provider android:authorities="{pkg}.files" android:exported="true" android:grantUriPermissions="true" android:name="org.love2d.android.OverhaulDocs" android:permission="android.permission.MANAGE_DOCUMENTS">
            <intent-filter>
                <action android:name="android.content.action.DOCUMENTS_PROVIDER"/>
            </intent-filter>
        </provider>
"""

GAME_ACTIVITY_ONCREATE_TAIL = """    invoke-static {p0}, Lorg/love2d/android/HighRefreshRate;->apply(Landroid/app/Activity;)V

    const-string v1, "T3ZlcmhhdWxlZCBieSBKdXBpdGVyaWFuIFNvdWw="
    const/4 v0, 0x0
    invoke-static {v1, v0}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B
    move-result-object v0
    new-instance v1, Ljava/lang/String;
    invoke-direct {v1, v0}, Ljava/lang/String;-><init>([B)V
    const/4 v0, 0x1
    invoke-static {p0, v1, v0}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;
    move-result-object v0
    invoke-virtual {v0}, Landroid/widget/Toast;->show()V

    invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
    move-result-object v0
    const-string v1, ".phone"
    invoke-virtual {v0, v1}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
    move-result v0
    const v1, 0xad5c
    if-eqz v0, :port_set
    const v1, 0xad5d
    :port_set
    sput v1, Lorg/love2d/android/TlsTunnel;->port:I

    :try_start_port
    invoke-static {v1}, Ljava/lang/String;->valueOf(I)Ljava/lang/String;
    move-result-object v0
    const-string v1, "OVERHAUL_TUNNEL_PORT"
    const/4 v2, 0x1
    invoke-static {v1, v0, v2}, Landroid/system/Os;->setenv(Ljava/lang/String;Ljava/lang/String;Z)V
    :try_end_port
    .catch Ljava/lang/Exception; {:try_start_port .. :try_end_port} :catch_port
    :catch_port

    invoke-static {}, Lorg/love2d/android/TlsTunnel;->startTunnel()V

    :try_start_official
    invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
    move-result-object v0
    const-string v1, "%(official)s"
    const/4 v2, 0x0
    invoke-virtual {v0, v1, v2}, Landroid/content/pm/PackageManager;->getApplicationInfo(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;
    move-result-object v0
    iget-object v0, v0, Landroid/content/pm/ApplicationInfo;->sourceDir:Ljava/lang/String;
    const-string v1, "OVERHAUL_OFFICIAL_APK"
    const/4 v2, 0x1
    invoke-static {v1, v0, v2}, Landroid/system/Os;->setenv(Ljava/lang/String;Ljava/lang/String;Z)V
    :try_end_official
    .catch Ljava/lang/Exception; {:try_start_official .. :try_end_official} :catch_official
    :catch_official

    :try_start_runtime
    const-string v1, "OVERHAUL_RUNTIME"
    const-string v0, "1"
    const/4 v2, 0x1
    invoke-static {v1, v0, v2}, Landroid/system/Os;->setenv(Ljava/lang/String;Ljava/lang/String;Z)V
    :try_end_runtime
    .catch Ljava/lang/Exception; {:try_start_runtime .. :try_end_runtime} :catch_runtime
    :catch_runtime

    :try_start_lang
    invoke-static {}, Ljava/util/Locale;->getDefault()Ljava/util/Locale;
    move-result-object v0
    invoke-virtual {v0}, Ljava/util/Locale;->getLanguage()Ljava/lang/String;
    move-result-object v0
    const-string v1, "OVERHAUL_LANG"
    const/4 v2, 0x1
    invoke-static {v1, v0, v2}, Landroid/system/Os;->setenv(Ljava/lang/String;Ljava/lang/String;Z)V
    :try_end_lang
    .catch Ljava/lang/Exception; {:try_start_lang .. :try_end_lang} :catch_lang
    :catch_lang

    return-void
.end method
"""

BOM_ORIENTATION = """.method public static bomOrientation()I
    .locals 1

    invoke-static {}, Lorg/love2d/android/OverhaulBridge;->orientation()I

    move-result v0

    return v0
.end method

"""


def replace_once(text, old, new, where):
    count = text.count(old)
    if count != 1:
        die("unexpected LOVE runtime layout in %s (anchor found %d times)" % (where, count))
    return text.replace(old, new, 1)


def patch_game_activity(path, official):
    text = path.read_text()
    start = text.find(".method protected onCreate(Landroid/os/Bundle;)V")
    if start < 0:
        die("GameActivity.onCreate not found")
    end = text.find(".end method", start)
    body = text[start:end + len(".end method")]
    body = replace_once(body, "    .locals 3\n", "    .locals 4\n", "GameActivity.onCreate")
    tail_at = body.rfind("    return-void\n.end method")
    if tail_at < 0:
        die("GameActivity.onCreate has no plain return")
    body = body[:tail_at] + (GAME_ACTIVITY_ONCREATE_TAIL % {"official": official}).rstrip("\n")
    path.write_text(text[:start] + body + text[end + len(".end method"):])


SAVES_ACTIVITY = '        <activity android:configChanges="keyboard|keyboardHidden|navigation|orientation|screenLayout|screenSize|smallestScreenSize|uiMode" android:excludeFromRecents="true" android:exported="true" android:name="org.love2d.android.OverhaulSaves" android:noHistory="false" android:taskAffinity="" android:theme="@android:style/Theme.Translucent.NoTitleBar"/>\n'


def manifest_text(pkg, label):
    perms, queries = "", ""
    if pkg == INSTALLER_PACKAGE:
        perms = '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n'
        queries = '        <package android:name="%s"/>\n        <package android:name="%s"/>\n' % (MAKER_PACKAGE, DEFAULT_PACKAGE)
    docs = "" if pkg == INSTALLER_PACKAGE else DOCS_PROVIDER.format(pkg=pkg)
    saves = "" if pkg == INSTALLER_PACKAGE else SAVES_ACTIVITY
    return MANIFEST.format(pkg=pkg, label=label, official=OFFICIAL_PACKAGE, extra_perms=perms, extra_queries=queries, docs=docs, saves_activity=saves)


OPEN_URL_HEAD = """    .locals 2

    invoke-static {p0}, Lorg/love2d/android/OverhaulBridge;->handles(Ljava/lang/String;)Z

    move-result v0

    if-eqz v0, :cond_overhaul_url

    invoke-static {p0}, Lorg/love2d/android/OverhaulBridge;->run(Ljava/lang/String;)Z

    move-result v0

    return v0

    :cond_overhaul_url
"""


def patch_open_url(path):
    text = path.read_text()
    start = text.find(".method public static openURLFromLOVE(Ljava/lang/String;)Z")
    if start < 0:
        die("GameActivity.openURLFromLOVE not found")
    end = text.find(".end method", start)
    body = replace_once(text[start:end], "    .locals 2\n", OPEN_URL_HEAD, "GameActivity.openURLFromLOVE")
    path.write_text(text[:start] + body + text[end:])


def patch_destroy(path):
    text = path.read_text()
    start = text.find(".method protected onDestroy()V")
    if start < 0:
        die("GameActivity.onDestroy not found")
    end = text.find(".end method", start)
    body = replace_once(text[start:end], "    invoke-super {p0}, Lorg/libsdl/app/SDLActivity;->onDestroy()V\n\n    return-void\n",
                        "    invoke-super {p0}, Lorg/libsdl/app/SDLActivity;->onDestroy()V\n\n"
                        "    invoke-virtual {p0}, Landroid/app/Activity;->isFinishing()Z\n\n    move-result v0\n\n"
                        "    if-eqz v0, :cond_overhaul_alive\n\n"
                        "    invoke-static {}, Landroid/os/Process;->myPid()I\n\n    move-result v0\n\n"
                        "    invoke-static {v0}, Landroid/os/Process;->killProcess(I)V\n\n"
                        "    :cond_overhaul_alive\n    return-void\n", "GameActivity.onDestroy")
    path.write_text(text[:start] + body + text[end:])


def patch_sdl_activity(path):
    text = path.read_text()
    text = replace_once(text, ".method public onWindowFocusChanged(Z)V\n",
                        BOM_ORIENTATION + ".method public onWindowFocusChanged(Z)V\n", "SDLActivity")
    text = replace_once(
        text,
        "    if-eqz p1, :cond_1\n\n    sget-object p1, Lorg/libsdl/app/SDLActivity$NativeState;->RESUMED:Lorg/libsdl/app/SDLActivity$NativeState;\n",
        "    if-eqz p1, :cond_1\n\n    invoke-static {}, Lorg/libsdl/app/SDLActivity;->bomOrientation()I\n\n    move-result v0\n\n"
        "    invoke-virtual {p0, v0}, Landroid/app/Activity;->setRequestedOrientation(I)V\n\n"
        "    sget-object p1, Lorg/libsdl/app/SDLActivity$NativeState;->RESUMED:Lorg/libsdl/app/SDLActivity$NativeState;\n",
        "SDLActivity.onWindowFocusChanged")
    text = replace_once(
        text,
        "    sget-object p1, Lorg/libsdl/app/SDLActivity;->mSingleton:Lorg/libsdl/app/SDLActivity;\n\n    invoke-virtual {p1, v3}, Landroid/app/Activity;->setRequestedOrientation(I)V\n",
        "    invoke-static {}, Lorg/libsdl/app/SDLActivity;->bomOrientation()I\n\n    move-result v3\n\n"
        "    sget-object p1, Lorg/libsdl/app/SDLActivity;->mSingleton:Lorg/libsdl/app/SDLActivity;\n\n    invoke-virtual {p1, v3}, Landroid/app/Activity;->setRequestedOrientation(I)V\n",
        "SDLActivity.setOrientationBis")
    path.write_text(text)


def patch_sdl_surface(path):
    text = path.read_text()
    text = replace_once(
        text,
        "    invoke-static {p3, p4, p2, p1, v0}, Lorg/libsdl/app/SDLActivity;->nativeSetScreenResolution(IIIIF)V\n\n    invoke-static {}, Lorg/libsdl/app/SDLActivity;->onNativeResize()V\n",
        "    invoke-static {p3, p4, p2, p1, v0}, Lorg/libsdl/app/SDLActivity;->nativeSetScreenResolution(IIIIF)V\n\n"
        "    invoke-virtual {p0}, Landroid/view/SurfaceView;->getHolder()Landroid/view/SurfaceHolder;\n    move-result-object v0\n"
        "    invoke-interface {v0}, Landroid/view/SurfaceHolder;->getSurface()Landroid/view/Surface;\n    move-result-object v0\n"
        "    invoke-static {v0}, Lorg/love2d/android/HighRefreshRate;->applySurface(Landroid/view/Surface;)V\n\n"
        "    invoke-static {}, Lorg/libsdl/app/SDLActivity;->onNativeResize()V\n",
        "SDLSurface.surfaceChanged")
    text = replace_once(text, ".field public mIsSurfaceReady:Z\n",
                        ".field public mIsSurfaceReady:Z\n\n.field public static overhaulForce:Z\n", "SDLSurface fields")
    text = replace_once(
        text,
        "    invoke-virtual {p1}, Landroid/app/Activity;->getRequestedOrientation()I\n\n    move-result p1\n\n"
        "    const/4 p2, 0x1\n\n    const/4 p3, 0x0\n",
        "    invoke-virtual {p1}, Landroid/app/Activity;->getRequestedOrientation()I\n\n    move-result p1\n\n"
        "    const/4 p2, 0x1\n\n    const/4 p3, 0x0\n\n"
        "    sget-boolean p4, Lorg/libsdl/app/SDLSurface;->overhaulForce:Z\n\n    if-nez p4, :cond_overhaul_force\n",
        "SDLSurface.surfaceChanged skip check")
    text = replace_once(
        text,
        "    const-string p2, \"Skip .. Surface is not ready.\"\n\n"
        "    invoke-static {p1, p2}, Landroid/util/Log;->v(Ljava/lang/String;Ljava/lang/String;)I\n\n"
        "    iput-boolean p3, p0, Lorg/libsdl/app/SDLSurface;->mIsSurfaceReady:Z\n\n    return-void\n\n    :cond_8\n",
        "    const-string p2, \"Skip .. Surface is not ready.\"\n\n"
        "    invoke-static {p1, p2}, Landroid/util/Log;->v(Ljava/lang/String;Ljava/lang/String;)I\n\n"
        "    iput-boolean p3, p0, Lorg/libsdl/app/SDLSurface;->mIsSurfaceReady:Z\n\n"
        "    invoke-static {p0}, Lorg/libsdl/app/OverhaulSurfaceRetry;->later(Lorg/libsdl/app/SDLSurface;)V\n\n"
        "    return-void\n\n    :cond_8\n    :cond_overhaul_force\n",
        "SDLSurface.surfaceChanged skip")
    path.write_text(text)
    (path.parent / "OverhaulSurfaceRetry.smali").write_text(SURFACE_RETRY)


SURFACE_RETRY = """.class public Lorg/libsdl/app/OverhaulSurfaceRetry;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;


.field private final surface:Lorg/libsdl/app/SDLSurface;


.method public constructor <init>(Lorg/libsdl/app/SDLSurface;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lorg/libsdl/app/OverhaulSurfaceRetry;->surface:Lorg/libsdl/app/SDLSurface;

    return-void
.end method

.method public static later(Lorg/libsdl/app/SDLSurface;)V
    .locals 3

    new-instance v0, Lorg/libsdl/app/OverhaulSurfaceRetry;

    invoke-direct {v0, p0}, Lorg/libsdl/app/OverhaulSurfaceRetry;-><init>(Lorg/libsdl/app/SDLSurface;)V

    const-wide/16 v1, 0x5dc

    invoke-virtual {p0, v0, v1, v2}, Landroid/view/View;->postDelayed(Ljava/lang/Runnable;J)Z

    return-void
.end method

.method public run()V
    .locals 7

    iget-object v0, p0, Lorg/libsdl/app/OverhaulSurfaceRetry;->surface:Lorg/libsdl/app/SDLSurface;

    iget-boolean v1, v0, Lorg/libsdl/app/SDLSurface;->mIsSurfaceReady:Z

    if-nez v1, :done

    invoke-virtual {v0}, Landroid/view/SurfaceView;->getHolder()Landroid/view/SurfaceHolder;

    move-result-object v1

    invoke-interface {v1}, Landroid/view/SurfaceHolder;->getSurface()Landroid/view/Surface;

    move-result-object v2

    if-eqz v2, :done

    invoke-virtual {v2}, Landroid/view/Surface;->isValid()Z

    move-result v2

    if-eqz v2, :done

    invoke-interface {v1}, Landroid/view/SurfaceHolder;->getSurfaceFrame()Landroid/graphics/Rect;

    move-result-object v2

    invoke-virtual {v2}, Landroid/graphics/Rect;->width()I

    move-result v3

    invoke-virtual {v2}, Landroid/graphics/Rect;->height()I

    move-result v4

    if-lez v3, :done

    if-lez v4, :done

    const-string v5, "SDL"

    const-string v6, "Overhaul: the surface kept the other orientation, starting with it"

    invoke-static {v5, v6}, Landroid/util/Log;->v(Ljava/lang/String;Ljava/lang/String;)I

    const/4 v5, 0x1

    sput-boolean v5, Lorg/libsdl/app/SDLSurface;->overhaulForce:Z

    :try_start
    invoke-virtual {v0, v1, v5, v3, v4}, Lorg/libsdl/app/SDLSurface;->surfaceChanged(Landroid/view/SurfaceHolder;III)V
    :try_end
    .catchall {:try_start .. :try_end} :catch_all

    const/4 v5, 0x0

    sput-boolean v5, Lorg/libsdl/app/SDLSurface;->overhaulForce:Z

    :done
    return-void

    :catch_all
    move-exception v6

    const/4 v5, 0x0

    sput-boolean v5, Lorg/libsdl/app/SDLSurface;->overhaulForce:Z

    throw v6
.end method
"""


def patch_apktool_yml(path, version_name, version_code):
    text = path.read_text()
    text = re.sub(r"minSdkVersion: *'?\d+'?", "minSdkVersion: %d" % MIN_SDK, text)
    text = re.sub(r"versionCode: *'?\d+'?", "versionCode: %d" % version_code, text)
    text = re.sub(r"versionName: *.*", "versionName: '%s'" % version_name, text)
    if "- love\n" not in text:
        text = text.replace("doNotCompress:\n", "doNotCompress:\n- love\n- ogg\n", 1)
    path.write_text(text)


def patch_bools(path):
    text = path.read_text()
    text = replace_once(text, '<bool name="embed">false</bool>', '<bool name="embed">true</bool>', "bools.xml")
    if '<bool name="selector_active">false</bool>' not in text:
        text = text.replace('<bool name="selector_active">true</bool>', '<bool name="selector_active">false</bool>')
    path.write_text(text)


def build_runtime(args):
    love_apk = Path(args.love_apk or os.environ.get("LOVE_ANDROID_APK") or DEFAULT_LOVE_APK)
    if not love_apk.is_file():
        die("LOVE Android APK not found: %s (pass --love-apk)" % love_apk)
    digest = sha256_file(love_apk)
    if digest not in KNOWN_LOVE and not args.allow_unknown_love:
        die("unknown LOVE Android APK %s (sha256 %s); only LOVE 11.5a is supported" % (love_apk, digest))
    out = Path(args.out).resolve() if args.out else (REPO / "dist" / "release" / "android" / RUNTIME_NAME)
    out.parent.mkdir(parents=True, exist_ok=True)
    version_name = args.version_name or (read_overhaul_version(REPO / "assets") if IN_REPO else "0.0")
    version_code = args.version_code or version_code_for(version_name)
    work = Path(tempfile.mkdtemp(prefix="overhaul-runtime-", dir=args.work or None))
    try:
        dec = work / "dec"
        say("1/4 decode %s" % love_apk.name)
        run(apktool_cmd() + ["d", "-f", "-o", str(dec), str(love_apk)])
        say("2/4 patch manifest, smali and flags")
        (dec / "AndroidManifest.xml").write_text(
            manifest_text(args.package, args.label))
        patch_apktool_yml(dec / "apktool.yml", version_name, version_code)
        patch_bools(dec / "res" / "values" / "bools.xml")
        smali_src = HERE / "smali" / "org" / "love2d" / "android"
        smali_dst = dec / "smali" / "org" / "love2d" / "android"
        for f in sorted(smali_src.glob("*.smali")):
            shutil.copy2(f, smali_dst / f.name)
        patch_game_activity(smali_dst / "GameActivity.smali", OFFICIAL_PACKAGE)
        patch_open_url(smali_dst / "GameActivity.smali")
        patch_destroy(smali_dst / "GameActivity.smali")
        patch_sdl_activity(dec / "smali" / "org" / "libsdl" / "app" / "SDLActivity.smali")
        patch_sdl_surface(dec / "smali" / "org" / "libsdl" / "app" / "SDLSurface.smali")
        info = {
            "package": args.package, "label": args.label, "version_name": version_name,
            "version_code": version_code, "love": KNOWN_LOVE.get(digest, "unknown"), "love_sha256": digest,
            "official_package": OFFICIAL_PACKAGE, "min_sdk": MIN_SDK,
        }
        (dec / "assets").mkdir(exist_ok=True)
        (dec / RUNTIME_INFO).write_text(json.dumps(info, indent=1, sort_keys=True) + "\n")
        say("3/4 rebuild")
        raw = work / "runtime-raw.apk"
        run(apktool_cmd() + ["b", "-o", str(raw), str(dec)])
        say("4/4 write %s" % out)
        tmp = out.with_suffix(".tmp")
        rewrite_apk(raw, tmp, {}, drop_signatures=True)
        os.replace(tmp, out)
    finally:
        if not args.keep_work:
            shutil.rmtree(work, ignore_errors=True)
        else:
            say("work dir kept: %s" % work)
    say("runtime: %s (%s, %s %s, code %d)" % (out, human(out.stat().st_size), args.package, version_name, version_code))
    return out


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%d %s" % (n, unit)) if unit == "B" else ("%.1f %s" % (n, unit))
        n /= 1024.0


def align_extra(offset, name_len, alignment):
    base = offset + 30 + name_len
    pad = (-(base + 6)) % alignment
    return struct.pack("<HHH", 0xD935, 2 + pad, alignment) + b"\0" * pad


def rewrite_apk(src, dst, replace, drop_signatures=False, add=None):
    add = add or []
    with zipfile.ZipFile(src) as zin, open(dst, "wb") as raw:
        with zipfile.ZipFile(raw, "w", allowZip64=False) as zout:
            seen = set()
            names = [i for i in zin.infolist() if not i.is_dir()]
            for info in names:
                name = info.filename
                if drop_signatures and name.startswith("META-INF/") and (
                        name.endswith((".SF", ".RSA", ".DSA", ".EC")) or name == "META-INF/MANIFEST.MF"):
                    continue
                if name in seen:
                    continue
                seen.add(name)
                data = replace[name] if name in replace else zin.read(name)
                write_entry(zout, raw, name, data, info.compress_type, info.date_time)
            for name, source, method in add:
                if name in seen:
                    die("entry already in APK: %s" % name)
                write_entry(zout, raw, name, source, method, (2026, 1, 1, 0, 0, 0))


def write_entry(zout, raw, name, source, method, date_time):
    zi = zipfile.ZipInfo(name, date_time=date_time)
    zi.compress_type = method
    zi.create_system = 0
    zi.external_attr = 0
    if method == zipfile.ZIP_STORED:
        alignment = 4096 if name.endswith(".so") else 4
        zi.extra = align_extra(raw.tell(), len(name.encode("utf-8")), alignment)
    if isinstance(source, (bytes, bytearray)):
        zout.writestr(zi, bytes(source))
        return
    size = os.path.getsize(source)
    zi.file_size = size
    with open(source, "rb") as f, zout.open(zi, "w", force_zip64=False) as w:
        for block in iter(lambda: f.read(1 << 20), b""):
            w.write(block)


def make_game_love(game_dir, dst, skip_standin=False):
    count = 0
    with zipfile.ZipFile(dst, "w", allowZip64=True) as z:
        for root, dirs, files in os.walk(game_dir):
            dirs.sort()
            rel_root = os.path.relpath(root, game_dir)
            if skip_standin:
                dirs[:] = [d for d in dirs if not (rel_root == "." and d in STANDIN_SKIP_DIRS)]
            for fn in sorted(files):
                if skip_standin and rel_root == "." and (fn in STANDIN_SKIP_FILES or fn.endswith(".md")):
                    continue
                full = os.path.join(root, fn)
                arc = fn if rel_root == "." else os.path.join(rel_root, fn).replace(os.sep, "/")
                ext = os.path.splitext(fn)[1].lower()
                method = zipfile.ZIP_STORED if ext in STORE_EXT else zipfile.ZIP_DEFLATED
                z.write(full, arc, compress_type=method)
                count += 1
    return count


def png_chunks(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        yield kind, data[pos + 8:pos + 8 + length]
        pos += 12 + length


def png_size(data):
    for kind, body in png_chunks(data):
        if kind == b"IHDR":
            return struct.unpack(">II", body[:8])
    raise ValueError("PNG without IHDR")


def png_read_region(path, x0, y0, w, h):
    data = Path(path).read_bytes()
    idat = []
    for kind, body in png_chunks(data):
        if kind == b"IHDR":
            width, height, depth, ctype, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
    if depth != 8 or ctype not in (2, 6) or interlace != 0:
        raise ValueError("unsupported PNG format")
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    need_rows = min(height, y0 + h)
    need_bytes = need_rows * (stride + 1)
    raw = zlib.decompressobj().decompress(b"".join(idat), need_bytes)
    if len(raw) < need_bytes:
        raise ValueError("truncated PNG")
    keep = min(stride, (x0 + w) * bpp)
    prev = bytearray(keep)
    rows = []
    for y in range(need_rows):
        off = y * (stride + 1)
        ft = raw[off]
        line = bytearray(raw[off + 1:off + 1 + keep])
        if ft == 1:
            for i in range(bpp, keep):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(keep):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(keep):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(keep):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        elif ft != 0:
            raise ValueError("bad PNG filter")
        if y >= y0:
            px = []
            for x in range(x0, x0 + w):
                i = x * bpp
                px.append((line[i], line[i + 1], line[i + 2], line[i + 3] if bpp == 4 else 255))
            rows.append(px)
        prev = line
    return rows


def png_write(rows):
    h = len(rows)
    w = len(rows[0])
    body = bytearray()
    for row in rows:
        body.append(0)
        for r, g, b, a in row:
            body += bytes((r, g, b, a))

    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(body), 9)) + chunk(b"IEND", b""))


def resample(rows, tw, th):
    sh = len(rows)
    sw = len(rows[0])
    out = []
    for ty in range(th):
        ya, yb = ty * sh / th, (ty + 1) * sh / th
        line = []
        for tx in range(tw):
            xa, xb = tx * sw / tw, (tx + 1) * sw / tw
            if tw >= sw and th >= sh:
                line.append(rows[min(sh - 1, int(ya))][min(sw - 1, int(xa))])
                continue
            acc = [0.0, 0.0, 0.0, 0.0]
            total = 0.0
            for sy in range(int(ya), min(sh, int(yb + 0.9999))):
                wy = min(yb, sy + 1) - max(ya, sy)
                for sx in range(int(xa), min(sw, int(xb + 0.9999))):
                    wx = min(xb, sx + 1) - max(xa, sx)
                    r, g, b, a = rows[sy][sx]
                    wgt = wx * wy
                    acc[0] += r * a * wgt
                    acc[1] += g * a * wgt
                    acc[2] += b * a * wgt
                    acc[3] += a * wgt
                    total += wgt
            if acc[3] <= 0:
                line.append((0, 0, 0, 0))
            else:
                line.append((int(acc[0] / acc[3] + 0.5), int(acc[1] / acc[3] + 0.5),
                             int(acc[2] / acc[3] + 0.5), min(255, int(acc[3] / total + 0.5))))
        out.append(line)
    return out


def blend(dst, src):
    r, g, b, a = src
    if a == 0:
        return dst
    dr, dg, db = dst
    f = a / 255.0
    return (int(r * f + dr * (1 - f) + 0.5), int(g * f + dg * (1 - f) + 0.5), int(b * f + db * (1 - f) + 0.5))


def compose_icon(card, size):
    ch = max(1, int(round(size * 0.78)))
    cw = max(1, int(round(ch * len(card[0]) / len(card))))
    scaled = resample(card, cw, ch)
    ox = (size - cw) // 2
    oy = (size - ch) // 2
    shadow = max(1, size // 32)
    canvas = []
    for y in range(size):
        t = y / max(1, size - 1)
        bg = tuple(int(ICON_BG[i] * (1 - t * 0.35) + ICON_BG_EDGE[i] * t * 0.35 + 0.5) for i in range(3))
        canvas.append([bg] * size)
    for y in range(ch):
        for x in range(cw):
            a = scaled[y][x][3]
            if a:
                sy, sx = oy + y + shadow, ox + x + shadow
                if 0 <= sy < size and 0 <= sx < size:
                    canvas[sy][sx] = blend(canvas[sy][sx], (0, 0, 0, a * 90 // 255))
    for y in range(ch):
        for x in range(cw):
            canvas[oy + y][ox + x] = blend(canvas[oy + y][ox + x], scaled[y][x])
    return [[(r, g, b, 255) for r, g, b in row] for row in canvas]


def icon_source(game_dir, icon_arg):
    if icon_arg:
        data = Path(icon_arg).read_bytes()
        w, h = png_size(data)
        return png_read_region(icon_arg, 0, 0, w, h), "file"
    made = game_dir / "app_icon.png" if game_dir else None
    if made and made.is_file():
        data = made.read_bytes()
        w, h = png_size(data)
        return png_read_region(made, 0, 0, w, h), "file"
    atlas = game_dir / "resources" / "textures" / "2x" / "Jokers.png" if game_dir else None
    if atlas and atlas.is_file():
        return png_read_region(atlas, 0, 0, 142, 190), "card"
    return None, None


def icon_replacements(runtime, game_dir, icon_arg):
    try:
        src, kind = icon_source(game_dir, icon_arg)
    except (ValueError, OSError, struct.error) as e:
        say("icon: kept the runtime icon (%s)" % e)
        return {}
    if not src:
        say("icon: kept the runtime icon (no Jokers.png in the game folder)")
        return {}
    out = {}
    with zipfile.ZipFile(runtime) as z:
        for name in z.namelist():
            m = re.match(r"res/drawable-([a-z]+)dpi[^/]*/love\.png$", name)
            if not m:
                continue
            try:
                w, h = png_size(z.read(name))
            except ValueError:
                w = ICON_SIZES.get(m.group(1) + "dpi", 96)
            exact = Path(icon_arg).with_name("%s_%d.png" % (Path(icon_arg).stem, w)) if icon_arg else None
            if exact and exact.is_file():
                out[name] = exact.read_bytes()
            elif kind == "card":
                out[name] = png_write(compose_icon(src, w))
            else:
                out[name] = png_write(resample(src, w, w))
    say("icon: %d densities from the %s" % (len(out), "game's own Joker card" if kind == "card" else "given PNG"))
    return out


def ensure_keystore(ks, pass_file):
    keytool = find_tool("keytool", "KEYTOOL") or die("keytool not found (comes with Java)")
    ks.parent.mkdir(parents=True, exist_ok=True)
    if ks.exists():
        if not pass_file.exists():
            die("keystore %s has no password file %s" % (ks, pass_file))
        return
    password = secrets.token_urlsafe(18)
    fd = os.open(str(pass_file), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(password + "\n")
    run([keytool, "-genkeypair", "-keystore", str(ks), "-storetype", "PKCS12", "-alias", KEY_ALIAS,
         "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
         "-dname", "CN=Balatro Overhaul player build, O=Balatro Overhaul",
         "-storepass", password, "-keypass", password])
    os.chmod(ks, 0o600)
    say("keystore: created %s" % ks)


def sign_apk(apk, ks, pass_file):
    apksigner = find_tool("apksigner", "APKSIGNER")
    if not apksigner:
        die("apksigner not found (Android build-tools)")
    run([apksigner, "sign", "--ks", str(ks), "--ks-key-alias", KEY_ALIAS,
         "--ks-pass", "file:%s" % pass_file,
         "--min-sdk-version", str(MIN_SDK), "--v1-signing-enabled", "true", "--v2-signing-enabled", "true", str(apk)])


def build_apk(args, icon_game=None):
    game_dir = Path(args.game).resolve() if args.game else None
    game_love = Path(args.game_love).resolve() if args.game_love else None
    if not game_dir and not game_love:
        die("pass --game DIR (patched game folder) or --game-love FILE")
    if game_dir and not (game_dir / "main.lua").is_file():
        die("%s has no main.lua: not a game folder" % game_dir)
    if game_love and not zipfile.is_zipfile(game_love):
        die("%s is not a .love zip" % game_love)
    runtime = Path(args.runtime).resolve() if args.runtime else (REPO / "dist" / "release" / "android" / RUNTIME_NAME)
    if not runtime.is_file():
        if args.runtime:
            die("runtime APK not found: %s" % runtime)
        say("runtime APK missing, building it first")
        rargs = argparse.Namespace(**vars(args))
        rargs.out = str(runtime)
        build_runtime(rargs)
    with zipfile.ZipFile(runtime) as z:
        if RUNTIME_INFO not in z.namelist():
            die("%s is not an Overhaul runtime APK" % runtime)
        info = json.loads(z.read(RUNTIME_INFO))
        if "assets/game.love" in z.namelist():
            die("runtime APK already holds a game")
    out_dir = Path(args.out).resolve() if args.out else (REPO / "dist" / "android")
    out_dir.mkdir(parents=True, exist_ok=True)
    key_dir = Path(args.key_dir).resolve() if args.key_dir else default_key_dir()
    ks = Path(args.keystore).resolve() if args.keystore else key_dir / "overhaul-player.p12"
    pass_file = Path(args.keystore + ".pass") if args.keystore else key_dir / "overhaul-player.p12.pass"
    if ks.name.endswith(".env") or ("release" in ks.name.lower() and not getattr(args, "allow_any_key", False)):
        die("refusing keystore %s: the maker only signs with its own player key" % ks)
    version = info.get("version_name", "0.0")
    if game_dir and (game_dir / "globals.lua").is_file():
        version = read_overhaul_version(game_dir)
    final = out_dir / (getattr(args, "out_name", None) or ("BalatroOverhaul-%s.apk" % version))
    work = Path(tempfile.mkdtemp(prefix="overhaul-apk-", dir=args.work or None))
    try:
        love = game_love
        if game_dir:
            say("1/4 pack game.love from %s" % game_dir)
            love = work / "game.love"
            n = make_game_love(game_dir, love, skip_standin=args.standin_filter)
            say("      %d files, %s" % (n, human(love.stat().st_size)))
        else:
            say("1/4 use %s" % game_love)
        with zipfile.ZipFile(love) as z:
            if "main.lua" not in z.namelist():
                die("game.love has no main.lua at its root")
        say("2/4 add game and icon to the runtime")
        replace = icon_replacements(runtime, icon_game or game_dir, args.icon)
        unsigned = work / "unsigned.apk"
        rewrite_apk(runtime, unsigned, replace, drop_signatures=True,
                    add=[("assets/game.love", str(love), zipfile.ZIP_STORED)])
        zipalign = find_tool("zipalign", "ZIPALIGN")
        if zipalign:
            run([zipalign, "-c", "-p", "4", str(unsigned)])
        say("3/4 sign")
        ensure_keystore(ks, pass_file)
        sign_apk(unsigned, ks, pass_file)
        say("4/4 write %s" % final)
        shutil.move(str(unsigned), str(final))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    say("apk: %s (%s)" % (final, human(final.stat().st_size)))
    return final


def manifest_field(text, name):
    m = re.search(r'^  %s = "(.*)",$' % name, text, re.M)
    return m.group(1) if m else None


def read_patch_set(patch):
    man = patch / "manifest.lua"
    if not man.is_file():
        die("no patch set at %s (make it with tools/release/patcher/make_patch.py)" % patch)
    text = man.read_text(encoding="utf-8")
    if not re.search(r"^  format = [12],$", text, re.M):
        die("%s is not a patch set from tools/release/patcher/make_patch.py" % man)
    return {"game_version": manifest_field(text, "game_version") or "",
            "overhaul_version": manifest_field(text, "overhaul_version") or "0",
            "overhaul_name": manifest_field(text, "overhaul_name")}


def vanilla_refs(patch):
    text = (patch / "manifest.lua").read_text(encoding="utf-8")
    return re.findall(r'\{\n\s+path = "([^"]+)",\n\s+sha256 = "([0-9a-f]{64})",\n\s+size = \d+,\n\s+\}', text)


def phone_tree(dst):
    dst = Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    for f in sorted((HERE / "bootstrap").glob("*.lua")):
        shutil.copy2(f, dst / f.name)
    shutil.copy2(REPO / "assets" / "https.lua", dst / "https.lua")
    shutil.copy2(REPO / "assets" / "smods" / "libs" / "json" / "json.lua", dst / "json.lua")
    ui = dst / "launcher"
    ui.mkdir(exist_ok=True)
    for name in LAUNCHER_SHARED:
        shutil.copy2(LAUNCHER / name, ui / name)
    shutil.copy2(REPO / "assets" / "functions" / "save_io.lua", ui / "save_io.lua")
    for f in sorted((HERE / "phone").glob("*.lua")):
        shutil.copy2(f, ui / f.name)
    return dst


def native_hash():
    h = hashlib.sha256()
    for f in sorted((HERE / "smali").rglob("*.smali")):
        h.update(f.relative_to(HERE).as_posix().encode() + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()


def native_level(bump=False):
    lines = NATIVE_FILE.read_text().split() if NATIVE_FILE.exists() else ["0", ""]
    level, seen = int(lines[0]), lines[1] if len(lines) > 1 else ""
    now = native_hash()
    if bump and now != seen:
        level += 1
        NATIVE_FILE.write_text("%d\n%s\n" % (level, now))
    elif now != seen:
        die("the Java bridge (smali/) changed since %s was written: run make_apk.py native --bump" % NATIVE_FILE.name)
    return level


def phone_code(runtime, dst):
    dst = Path(dst)
    if dst.exists():
        shutil.rmtree(dst)
    phone_tree(dst)
    (dst / "patcher").mkdir()
    for name in PATCHER_LUA:
        shutil.copy2(PATCHER / name, dst / "patcher" / name)
    (dst / "android").mkdir()
    shutil.copy2(runtime, dst / "android" / "runtime.apk")
    maker = dst / "launcher" / "android"
    maker.mkdir(exist_ok=True)
    for f in sorted((HERE / "launcher").glob("*.lua")):
        shutil.copy2(f, maker / f.name)
    return dst


def bootstrap_game(work, patch, patch_pc=None):
    game = work / "game"
    phone_tree(game)
    (game / NATIVE_NAME).write_text("%d\n" % native_level())
    (game / "patcher").mkdir()
    for name in PATCHER_LUA:
        shutil.copy2(PATCHER / name, game / "patcher" / name)
    shutil.copytree(patch, game / "patch")
    if patch_pc:
        shutil.copytree(patch_pc, game / "patch_pc")
    return game


def add_app_maker(args, man, game):
    app_dir = game / "android"
    app_dir.mkdir(exist_ok=True)
    gargs = argparse.Namespace(**vars(args))
    gargs.package, gargs.label = DEFAULT_PACKAGE, DEFAULT_LABEL
    gargs.out = str(app_dir / "runtime.apk")
    gargs.version_name = args.version_name or man.get("overhaul_name") or man["overhaul_version"]
    gargs.version_code = args.version_code or version_code_for(man["overhaul_version"])
    build_runtime(gargs)
    maker = game / "launcher" / "android"
    maker.mkdir(exist_ok=True)
    for f in sorted((HERE / "launcher").glob("*.lua")):
        shutil.copy2(f, maker / f.name)


def build_installer(args):
    patch = Path(args.patch).resolve()
    man = read_patch_set(patch)
    if "[M]" not in man["game_version"] and not args.allow_pc_vanilla:
        die("patch set was made against '%s', not the mobile game; the phone install needs a patch made from the official APK" % man["game_version"])
    if not args.keystore and not IN_REPO:
        die("pass --keystore: the installer is signed with the publisher's key, not a player key")
    work = Path(tempfile.mkdtemp(prefix="overhaul-installer-", dir=args.work or None))
    try:
        game = bootstrap_game(work, patch, getattr(args, "patch_pc", None))
        add_app_maker(args, man, game)
        bargs = argparse.Namespace(**vars(args))
        if not args.runtime:
            rargs = argparse.Namespace(**vars(args))
            rargs.out = str(work / "runtime.apk")
            rargs.version_name = args.version_name or man.get("overhaul_name") or man["overhaul_version"]
            rargs.version_code = args.version_code or version_code_for(man["overhaul_version"])
            build_runtime(rargs)
            bargs.runtime = rargs.out
        bargs.game = str(game)
        bargs.game_love = None
        bargs.icon = args.icon or str(INSTALLER_ICON)
        bargs.standin_filter = False
        bargs.out_name = INSTALLER_NAME
        bargs.version_name = None
        bargs.keystore = args.keystore or str(REPO / ".night" / "android-installer" / "installer-test.p12")
        bargs.allow_any_key = True
        return build_apk(bargs)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def build_updatable(args):
    sys.path.insert(0, str(PATCHER))
    sys.dont_write_bytecode = True
    from make_patch import Vanilla
    patch = Path(args.patch).resolve()
    man = read_patch_set(patch)
    try:
        van = Vanilla(args.vanilla)
    except (OSError, zipfile.BadZipFile):
        die("%s is not a Balatro copy (Balatro.exe, folder or .love)" % args.vanilla)
    if not van.version:
        die("%s has no version.jkr: not a Balatro copy" % args.vanilla)
    if van.version != man["game_version"]:
        die("your Balatro is %s, this patch set is made for %s" % (van.version, man["game_version"]))
    for rel, want in vanilla_refs(patch):
        if rel not in van.files:
            die("your Balatro has no %s" % rel)
        if hashlib.sha256(van.files[rel]).hexdigest() != want:
            die("your Balatro's %s is not the one this patch set needs" % rel)
    work = Path(tempfile.mkdtemp(prefix="overhaul-updatable-", dir=args.work or None))
    try:
        game = bootstrap_game(work, patch)
        n = 0
        for rel in sorted(van.files):
            if rel.split("/")[0] in ("dexopt",):
                continue
            dst = game / "vanilla" / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(van.files[rel])
            n += 1
        say("bootstrap, patch set %s and %d files of your Balatro %s" % (man["overhaul_version"], n, van.version))
        bargs = argparse.Namespace(**vars(args))
        bargs.game = str(game)
        bargs.game_love = None
        bargs.standin_filter = False
        bargs.out_name = "BalatroOverhaul-%s.apk" % man["overhaul_version"]
        return build_apk(bargs, icon_game=game / "vanilla")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def zip_patch_set(args):
    patch = Path(args.patch).resolve()
    man = read_patch_set(patch)
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(patch.rglob("*")):
            if f.is_file():
                info = zipfile.ZipInfo(f.relative_to(patch).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, f.read_bytes())
    os.replace(tmp, out)
    data = out.read_bytes()
    entry = {"file": out.name, "version": man["overhaul_version"], "vanilla_version": man["game_version"],
             "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    Path(str(out) + ".json").write_text(json.dumps(entry, indent=1) + "\n")
    say(json.dumps(entry, indent=1))
    return entry


def build_standin(args):
    src = REPO / "assets"
    dst = Path(args.out).resolve() if args.out else REPO / ".night" / "mobile" / "standin"
    if not (src / "main.lua").is_file():
        die("no assets/main.lua in %s" % REPO)
    if dst.exists():
        shutil.rmtree(dst)
    n = 0
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        if rel == ".":
            dirs[:] = [d for d in dirs if d not in STANDIN_SKIP_DIRS]
        if not args.with_jukebox and rel.replace(os.sep, "/").startswith("resources/sounds/jukebox"):
            dirs[:] = []
            continue
        os.makedirs(dst / rel, exist_ok=True)
        for fn in files:
            if rel == "." and (fn in STANDIN_SKIP_FILES or fn.endswith(".md")):
                continue
            s = os.path.join(root, fn)
            d = dst / rel / fn
            try:
                os.link(s, d)
            except OSError:
                shutil.copy2(s, d)
            n += 1
    say("stand-in: %s (%d files, jukebox songs %s)" % (dst, n, "kept" if args.with_jukebox else "left out"))
    return dst


def inspect_apk(args):
    apk = Path(args.apk).resolve()
    report = {"apk": str(apk), "size": apk.stat().st_size}
    aapt = find_tool("aapt", "AAPT")
    if aapt:
        badging = subprocess.run([aapt, "dump", "badging", str(apk)], stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True).stdout
        m = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", badging)
        if m:
            report.update(package=m.group(1), version_code=int(m.group(2)), version_name=m.group(3))
        m = re.search(r"application-label:'([^']*)'", badging)
        report["label"] = m.group(1) if m else None
        m = re.search(r"sdkVersion:'(\d+)'", badging)
        report["min_sdk"] = int(m.group(1)) if m else None
        report["permissions"] = sorted(set(re.findall(r"uses-permission: name='([^']+)'", badging)))
        m = re.search(r"launchable-activity: name='([^']+)'", badging)
        report["activity"] = m.group(1) if m else None
        tree = subprocess.run([aapt, "dump", "xmltree", str(apk), "AndroidManifest.xml"], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True).stdout
        m = re.search(r"E: queries .*?(?=\n    E: )", tree, re.S)
        report["queries"] = re.findall(r'android:name\(0x[0-9a-f]+\)="([^"]+)"', m.group(0)) if m else []
    with zipfile.ZipFile(apk) as z:
        names = z.namelist()
        report["game_love"] = None
        if "assets/game.love" in names:
            gi = z.getinfo("assets/game.love")
            with z.open(gi) as f:
                inner = zipfile.ZipFile(io.BytesIO(f.read()))
                report["game_love"] = {"size": gi.file_size, "stored": gi.compress_type == zipfile.ZIP_STORED,
                                       "files": len(inner.namelist()), "has_main": "main.lua" in inner.namelist()}
        report["native_libs"] = sorted(n for n in names if n.startswith("lib/"))
        report["runtime_info"] = json.loads(z.read(RUNTIME_INFO)) if RUNTIME_INFO in names else None
        report["lua_outside_game"] = sorted(n for n in names if n.endswith(".lua"))
    apksigner = find_tool("apksigner", "APKSIGNER")
    if apksigner:
        res = subprocess.run([apksigner, "verify", "--verbose", str(apk)], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True)
        report["signature_ok"] = res.returncode == 0
        report["signature"] = [l for l in res.stdout.splitlines() if l.startswith("Verified using")]
    zipalign = find_tool("zipalign", "ZIPALIGN")
    if zipalign:
        res = subprocess.run([zipalign, "-c", "-p", "4", str(apk)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        report["aligned"] = res.returncode == 0
    print(json.dumps(report, indent=1))
    return report


def main(argv=None):
    p = argparse.ArgumentParser(description="Balatro Overhaul Android APK maker (LOVE 11.5 runtime, the player's own game files)")
    sub = p.add_subparsers(dest="cmd", required=True)

    def common_runtime(sp):
        sp.add_argument("--love-apk", help="love-11.5-android.apk (default: LOVE_ANDROID_APK or the night downloads folder)")
        sp.add_argument("--allow-unknown-love", action="store_true")
        sp.add_argument("--package", default=DEFAULT_PACKAGE)
        sp.add_argument("--label", default=DEFAULT_LABEL)
        sp.add_argument("--version-name")
        sp.add_argument("--version-code", type=int)
        sp.add_argument("--work", help="folder for temporary files")
        sp.add_argument("--keep-work", action="store_true")

    r = sub.add_parser("runtime", help="build the game-less runtime APK (LOVE + Overhaul Java parts, no game files)")
    common_runtime(r)
    r.add_argument("--out", help="output APK (default dist/release/android/%s)" % RUNTIME_NAME)

    b = sub.add_parser("build", help="put a patched game into the runtime, align and sign")
    common_runtime(b)
    b.add_argument("--game", help="patched Overhaul game folder (has main.lua)")
    b.add_argument("--game-love", help="a ready game.love instead of a folder")
    b.add_argument("--runtime", help="runtime APK (default dist/release/android/%s, built if missing)" % RUNTIME_NAME)
    b.add_argument("--icon", help="PNG for the app icon (default: made from the game's own Joker card)")
    b.add_argument("--out", help="output folder (default dist/android)")
    b.add_argument("--key-dir", help="folder for the player signing key")
    b.add_argument("--keystore", help="PKCS12 keystore to sign with (password in <keystore>.pass)")
    b.add_argument("--standin-filter", action="store_true", help="leave dev notes out of game.love")
    b.add_argument("--vanilla", help="your own Balatro (Balatro.exe, folder or .love): with --patch, makes an APK that installs and updates the Overhaul on the phone")
    b.add_argument("--patch", help="patch set from tools/release/patcher/make_patch.py, made against that Balatro")

    s = sub.add_parser("standin", help="make a stand-in game folder from assets/ under .night/")
    s.add_argument("--out")
    s.add_argument("--with-jukebox", action="store_true")

    n = sub.add_parser("installer", help="runtime plus the on-phone installer and a mobile patch set (no game files)")
    common_runtime(n)
    n.set_defaults(package=INSTALLER_PACKAGE, label=INSTALLER_LABEL)
    n.add_argument("--patch", required=True, help="patch set from tools/release/patcher/make_patch.py, made against the official APK")
    n.add_argument("--patch-pc", help="the PC patch set, used when the phone's Balatro APK was made from the PC game")
    n.add_argument("--runtime")
    n.add_argument("--icon", help="PNG for the app icon (default tools/release/android/icon/installer.png)")
    n.add_argument("--out", help="output folder (default dist/android)")
    n.add_argument("--key-dir")
    n.add_argument("--keystore")
    n.add_argument("--allow-pc-vanilla", action="store_true", help="tests only: accept a patch made against the Steam files")

    zp = sub.add_parser("zip", help="pack a patch set into one zip for the Android update feed (writes <out>.json with size and sha256)")
    zp.add_argument("--patch", required=True)
    zp.add_argument("--out", required=True)

    pt = sub.add_parser("phone-tree", help="copy the phone app's Lua (dispatch, install engine, launcher UI) into a folder")
    pt.add_argument("--out", required=True)

    pc = sub.add_parser("phone-code", help="the phone launcher's code without patch sets, laid out like its game.love (launcher self-update)")
    pc.add_argument("--runtime", required=True, help="the runtime APK the launcher builds game apps from")
    pc.add_argument("--out", required=True)

    nv = sub.add_parser("native", help="print the native level of the launcher APK (Java bridge); --bump after changing it")
    nv.add_argument("--bump", action="store_true")

    i = sub.add_parser("inspect", help="print package, permissions, game.love and signature of an APK")
    i.add_argument("apk")

    args = p.parse_args(argv)
    if args.cmd == "runtime":
        build_runtime(args)
    elif args.cmd == "build":
        if args.vanilla or args.patch:
            if not (args.vanilla and args.patch) or args.game or args.game_love:
                die("pass --vanilla and --patch together, without --game or --game-love")
            build_updatable(args)
        else:
            build_apk(args)
    elif args.cmd == "installer":
        build_installer(args)
    elif args.cmd == "zip":
        zip_patch_set(args)
    elif args.cmd == "standin":
        build_standin(args)
    elif args.cmd == "inspect":
        inspect_apk(args)
    elif args.cmd == "phone-tree":
        phone_tree(args.out)
    elif args.cmd == "phone-code":
        phone_code(args.runtime, args.out)
    elif args.cmd == "native":
        print(native_level(args.bump))


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: tools/release/pack_overhaul.sh [--launcher-only] [--out DIR] [--vanilla Balatro.exe] [--mobile-apk FILE] [--installer-key FILE] [--changelog FILE] [--assets DIR]"
    echo "  Builds the public release into dist/release/: the patch set, the launcher for"
    echo "  Linux, Windows and macOS, the phone installer APK in android/ when an official"
    echo "  Balatro APK is given, RELEASE.md and SHA256SUMS.txt. Nothing from the vanilla game goes in."
    echo "  --mobile-apk FILE    the official Balatro APK (base.apk from Google Play), same as BALATRO_MOBILE_APK"
    echo "  --installer-key FILE PKCS12 key that signs the phone installer (password in FILE.pass), same as INSTALLER_KEYSTORE"
    echo "  --launcher-only  only the patch set, the update feed and launcher.love (for tests)"
    echo "  --changelog FILE text, or JSON {\"en\": ..., \"fr\": ..., \"es\": ...}, put in feed.json"
    echo "  --assets DIR     build the patch set from another assets folder (update tests)"
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="$repo/dist/release"
vanilla="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
downloads="${LOVE_DOWNLOADS:-$HOME/.local/state/balatro-night/downloads}"
launcher_only=0
changelog=""
assets="$repo/assets"
while (( $# )); do
    case "$1" in
        --launcher-only) launcher_only=1 ;;
        --changelog) changelog="$(realpath "$2")"; shift ;;
        --assets) assets="$(realpath "$2")"; shift ;;
        --out) out="$2"; shift ;;
        --vanilla) vanilla="$2"; shift ;;
        --mobile-apk) export BALATRO_MOBILE_APK="$(realpath -m "$2")"; shift ;;
        --installer-key) export INSTALLER_KEYSTORE="$(realpath -m "$2")"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

for tool in python3 zip unzip; do
    command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }
done
[[ -f "$vanilla" ]] || { echo "No vanilla Balatro at $vanilla (set BALATRO_EXE)"; exit 1; }
mobile="${BALATRO_MOBILE_APK:-$repo/.night/official-base.apk}"
old_other=()
old_vanilla=()
for old in ${BALATRO_MOBILE_OLD:-}; do
    old_other+=(--other "$old")
    old_vanilla+=(--vanilla "$old")
done
[[ -f "$mobile" ]] || { echo "No official mobile Balatro at $mobile (set BALATRO_MOBILE_APK): the release is checked against it too"; exit 1; }

out="$(realpath -m "$out")"
case "$out" in
    /|"$HOME"|"$repo"|"$repo/assets"|"$repo/tools") echo "Refusing to clear $out"; exit 1 ;;
esac
app="Balatro Overhaul Launcher"
build="$out/.build"
rm -rf "$out"
mkdir -p "$out" "$build"

results_src="${BOTLATRO_RESULTS:-$HOME/botlatro-sim-main/RESULTS.md}"
if [[ -f "$results_src" ]]; then
    python3 -I "$here/../bot/botlatro_results.py" "$results_src" "$assets/bot/results.lua" || { echo "Bot-latro results could not be read from $results_src"; exit 1; }
fi

echo "=== 1 patch set ==="
python3 -B "$here/patcher/make_patch.py" --vanilla "$vanilla" --other "$mobile" "${old_other[@]}" --assets "$assets" \
    --exclude "$here/EXCLUDE.txt" --out "$out/patchset"
python3 -B "$here/patcher/check_patch.py" --vanilla "$vanilla" --vanilla "$mobile" "${old_vanilla[@]}" "$out/patchset"
version="$(sed -n 's/^  overhaul_version = "\(.*\)",$/\1/p' "$out/patchset/manifest.lua")"
[[ -n "$version" ]] || version="dev"
name="$(sed -n 's/^  overhaul_name = "\(.*\)",$/\1/p' "$out/patchset/manifest.lua")"
[[ -n "$name" ]] || name="$version"
display="$(echo "$name" | grep -o '^[0-9][0-9.]*' || true)"
[[ -n "$display" ]] || display="$version"
code_args=()
[[ "$version" =~ ^[0-9]+$ ]] && code_args=(--version-code "$((version * 10000))")

echo "=== 1b update feed ==="
(cd "$out/patchset" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -q -9 -X -D "$out/patchset-$version.zip" -@)
python3 -B "$here/patcher/make_feed.py" --manifest "$out/patchset/manifest.lua" --zip "$out/patchset-$version.zip" \
    --changelog "$changelog" --out "$out/feed.json"

echo "=== 2 launcher.love ==="
stage="$build/launcher"
mkdir -p "$stage/patcher"
cp "$here/launcher/"*.lua "$stage/"
cp "$here/patcher/apply.lua" "$here/patcher/zipread.lua" "$here/patcher/find.lua" "$stage/patcher/"
cp "$repo/assets/https.lua" "$stage/https.lua"
cp "$assets/functions/save_io.lua" "$stage/save_io.lua"
cp "$repo/assets/smods/libs/json/json.lua" "$stage/json.lua"
mkdir -p "$stage/tunnel"
cp "$repo/linux/tls_tunnel.py" "$stage/tunnel/tls_tunnel.py"
cp -r "$out/patchset" "$stage/patchset"
if [[ -d "$here/android/launcher" ]]; then
    cp -r "$here/android/launcher" "$stage/android"
    mkdir -p "$stage/android/patcher"
    python3 -B "$here/android/make_apk.py" phone-tree --out "$stage/android/bootstrap"
    cp "$here/patcher/love_ctx.lua" "$stage/android/patcher/"
    python3 -B "$here/android/make_apk.py" runtime --version-name "$name" "${code_args[@]}" --out "$stage/android/runtime.apk" >/dev/null \
        || { echo "The Android runtime for the launcher's APK maker failed"; exit 1; }
fi
(cd "$stage" && zip -q -r -9 -X "$out/launcher.love" .)
cp "$out/launcher.love" "$build/launcher.love"

if (( launcher_only )); then
    echo "Built $out/launcher.love ($(du -h "$out/launcher.love" | cut -f1))"
    exit 0
fi

for f in love-11.5-x86_64.AppImage love-11.5-win64.zip love-11.5-macos.zip; do
    [[ -f "$downloads/$f" ]] || { echo "Missing $downloads/$f"; exit 1; }
done
command -v 7z >/dev/null || { echo "Missing 7z (needed to unpack the LÖVE AppImage)"; exit 1; }

echo "=== 3 Linux ==="
lin="$build/linux/$app"
mkdir -p "$lin"
7z x -y -o"$lin" "$downloads/love-11.5-x86_64.AppImage" >/dev/null
rm -f "$lin/AppRun" "$lin/love.desktop" "$lin/.DirIcon"
cat > "$lin/AppRun" <<'EOF'
#!/bin/sh
if [ -z "$APPDIR" ]; then
    APPDIR="$(dirname "$(readlink -f "$0")")"
fi
export APPDIR
export LD_LIBRARY_PATH="$APPDIR/lib/:$LD_LIBRARY_PATH"
if [ -z "$XDG_DATA_DIRS" ]; then
    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"
fi
export XDG_DATA_DIRS="$APPDIR/share/:$XDG_DATA_DIRS"
if [ "$1" = "--overhaul-run" ]; then
    shift
    exec "$APPDIR/bin/love" "$@"
fi
exec "$APPDIR/bin/love" --fused "$APPDIR/launcher.love" "$@"
EOF
chmod 755 "$lin/AppRun"
cp "$build/launcher.love" "$lin/launcher.love"
cp "$here/launcher/icon/launcher_256.png" "$lin/.DirIcon"
cp "$here/launcher/icon/launcher_256.png" "$lin/balatro-overhaul-launcher.png"
cat > "$lin/balatro-overhaul-launcher.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Balatro Overhaul Launcher
Exec=balatro-overhaul-launcher
Icon=balatro-overhaul-launcher
Categories=Game;
EOF
cat > "$lin/balatro-overhaul-launcher" <<'EOF'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/AppRun" "$@"
EOF
chmod 755 "$lin/balatro-overhaul-launcher"
cat > "$lin/README.txt" <<EOF
Balatro Overhaul Launcher $name (Linux x86_64)

Run ./balatro-overhaul-launcher (or double click it). It finds Balatro in your
Steam library, checks it, and builds the Overhaul in ~/.local/share/BalatroOverhaulLauncher.
You need your own copy of Balatro. This folder holds no part of the game.
Runs on LÖVE 11.5 (zlib licence, see share/ and the LÖVE licence at love2d.org).
EOF
linux_tar="BalatroOverhaulLauncher-$display-linux-x86_64.tar.gz"
cp "$here/github/public/LICENSE" "$here/github/public/THIRD_PARTY_NOTICES.md" "$lin/"
(cd "$build/linux" && tar -czf "$out/$linux_tar" --owner=0 --group=0 "$app")
if command -v mksquashfs >/dev/null; then
    offset="$(python3 -B - "$downloads/love-11.5-x86_64.AppImage" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read(64)
shoff, = struct.unpack_from("<Q", d, 0x28)
shentsize, shnum = struct.unpack_from("<HH", d, 0x3A)
print(shoff + shentsize * shnum)
EOF
)"
    head -c "$offset" "$downloads/love-11.5-x86_64.AppImage" > "$build/runtime"
    mksquashfs "$lin" "$build/app.squashfs" -root-owned -noappend -comp gzip -quiet
    cat "$build/runtime" "$build/app.squashfs" > "$out/BalatroOverhaulLauncher-$display-x86_64.AppImage"
    chmod 755 "$out/BalatroOverhaulLauncher-$display-x86_64.AppImage"
else
    echo "mksquashfs not found: Linux ships as $linux_tar (an unpacked AppImage folder)"
fi

echo "=== 4 Windows ==="
win="$build/windows/$app"
mkdir -p "$build/windows"
unzip -q "$downloads/love-11.5-win64.zip" -d "$build/windows"
mv "$build/windows/love-11.5-win64" "$win"
rm -f "$win/lovec.exe" "$win/changes.txt" "$win/readme.txt"
base_exe="$win/love.exe"
rcedit="${RCEDIT:-$(command -v rcedit || true)}"
if [[ -n "$rcedit" ]]; then
    base_exe="$build/launcher_base.exe"
    cp "$win/love.exe" "$base_exe"
    numeric="$(echo "$display" | grep -o '[0-9]\+' | head -4 | paste -sd. -)"
    while [[ "$(echo "$numeric" | tr -cd . | wc -c)" -lt 3 ]]; do numeric="$numeric.0"; done
    $rcedit "$base_exe" --set-file-version "$numeric" --set-product-version "$numeric" \
        --set-version-string ProductName "Balatro Overhaul Launcher" \
        --set-version-string FileDescription "Balatro Overhaul Launcher" \
        --set-version-string CompanyName "Balatro Overhaul" \
        --set-version-string LegalCopyright "Balatro Overhaul fan mod. LOVE 11.5, zlib licence." \
        --set-version-string OriginalFilename "$app.exe" \
        --set-version-string InternalName "BalatroOverhaulLauncher" \
        --application-manifest "$here/launcher/windows/launcher.manifest" \
        || { echo "rcedit failed, the launcher keeps LOVE's version info"; base_exe="$win/love.exe"; }
else
    echo "No rcedit (set RCEDIT): the Windows launcher keeps LOVE's version info and manifest"
fi
if [[ "$base_exe" == "$win/love.exe" ]]; then
    base_exe="$build/launcher_base.exe"
    cp "$win/love.exe" "$base_exe"
fi
python3 -B "$here/launcher/windows/set_exe_icon.py" "$base_exe" "$here/launcher/icon/launcher.ico" \
    || echo "The Windows launcher keeps LOVE's icon"
cat "$base_exe" "$build/launcher.love" > "$win/$app.exe"
cat > "$win/README.txt" <<EOF
Balatro Overhaul Launcher $name (Windows 64 bit)

Double click "$app.exe". It finds Balatro in your Steam library, checks it, and
builds the Overhaul in %APPDATA%\\BalatroOverhaulLauncher. love.exe in this folder
runs the Overhaul, keep it next to the launcher.
Windows may warn about an unknown publisher: More info > Run anyway.
You need your own copy of Balatro. This folder holds no part of the game.
Runs on LÖVE 11.5 (zlib licence, license.txt).
EOF
sed -i 's/$/\r/' "$win/README.txt"
win_zip="BalatroOverhaulLauncher-$display-windows-x64.zip"
cp "$here/github/public/LICENSE" "$here/github/public/THIRD_PARTY_NOTICES.md" "$win/"
(cd "$build/windows" && zip -q -r -9 -X "$out/$win_zip" "$app")

echo "=== 5 macOS ==="
mac="$build/macos"
mkdir -p "$mac"
unzip -q "$downloads/love-11.5-macos.zip" -d "$mac/runtime"
mv "$mac/runtime/love.app" "$mac/$app.app"
rm -rf "$mac/runtime"
mkdir -p "$mac/$app.app/Contents/Resources/runtime"
unzip -q "$downloads/love-11.5-macos.zip" -d "$mac/$app.app/Contents/Resources/runtime"
rm -rf "$mac/$app.app/Contents/Resources/runtime/__MACOSX"
cp "$build/launcher.love" "$mac/$app.app/Contents/Resources/launcher.love"
cp "$here/launcher/icon/launcher.icns" "$mac/$app.app/Contents/Resources/OS X AppIcon.icns"
python3 -B - "$mac/$app.app/Contents/Info.plist" "$display" <<'EOF'
import plistlib, sys
path, version = sys.argv[1], sys.argv[2]
with open(path, "rb") as f:
    p = plistlib.load(f)
p["CFBundleIdentifier"] = "com.balatrooverhaul.launcher"
p["CFBundleName"] = "Balatro Overhaul Launcher"
p["CFBundleDisplayName"] = "Balatro Overhaul Launcher"
p["CFBundleShortVersionString"] = version
p.pop("UTExportedTypeDeclarations", None)
p.pop("CFBundleDocumentTypes", None)
with open(path, "wb") as f:
    plistlib.dump(p, f)
EOF
rm -rf "$mac/$app.app/Contents/_CodeSignature"
cat > "$mac/READ ME FIRST.txt" <<EOF
Balatro Overhaul Launcher $name (macOS)

1. Drag "$app.app" to Applications.
2. The app is not signed by Apple: right click it, pick Open, then Open again.
   If macOS says it is damaged, open Terminal and run:
   xattr -cr "/Applications/$app.app"
3. The launcher finds Balatro in your Steam library, checks it, and builds the
   Overhaul in ~/Library/Application Support/BalatroOverhaulLauncher.

You need your own copy of Balatro. This app holds no part of the game.
Runs on LÖVE 11.5 (zlib licence, Contents/Resources/license.txt).
EOF
mac_zip="BalatroOverhaulLauncher-$display-macos.zip"
cp "$here/github/public/LICENSE" "$here/github/public/THIRD_PARTY_NOTICES.md" "$mac/"
(cd "$mac" && zip -q -r -9 -y -X "$out/$mac_zip" "$app.app" "READ ME FIRST.txt" LICENSE THIRD_PARTY_NOTICES.md)

echo "=== 6 Android maker ==="
if [[ -f "$here/android/pack.sh" ]]; then
    PATCH_PC="$out/patchset" OUT="$out/android" OVERHAUL_VERSION="$version" OVERHAUL_DISPLAY="$display" ASSETS="$assets" WORK="$build/android" BALATRO_EXE="$vanilla" bash "$here/android/pack.sh"
else
    echo "No tools/release/android/pack.sh yet: the launcher has no Android maker in this build"
fi

echo "=== 7 docs and checksums ==="
cp "$here/github/public/LICENSE" "$here/github/public/THIRD_PARTY_NOTICES.md" "$out/"
for doc in RELEASE.md CHANGELOG.md; do
    if [[ -f "$here/$doc" ]]; then
        cp "$here/$doc" "$out/$doc"
    fi
done
if [[ -d "$repo/LICENSES" ]]; then
    cp -r "$repo/LICENSES" "$out/LICENSES"
fi
allow="$(mktemp)"
cat "$win/license.txt" "$repo/LICENSES/"*.txt > "$allow"
rm -rf "$build"
(cd "$out" && find . -type f -name 'BalatroOverhaulLauncher-*' -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum | sed 's#  .*/#  #' > SHA256SUMS.txt)

echo "=== 8 vanilla check ==="
mapfile -t checked < <(find "$out" -mindepth 1 -maxdepth 1 ! -name android | LC_ALL=C sort)
python3 -B "$here/patcher/check_patch.py" --vanilla "$vanilla" --vanilla "$mobile" "${old_vanilla[@]}" --allow "$allow" "${checked[@]}" || { rm -f "$allow"; exit 1; }
rm -f "$allow"
echo "Built $out ($(du -sh "$out" | cut -f1))"

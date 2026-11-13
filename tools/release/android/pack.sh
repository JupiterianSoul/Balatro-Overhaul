#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
out="${OUT:-$repo/dist/release/android}"
assets="${ASSETS:-$repo/assets}"
common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
checkout="$repo"
if [[ "$(basename "$common")" == ".git" && -d "$common" ]]; then
    checkout="$(dirname "$common")"
fi
official="${BALATRO_MOBILE_APK:-}"
if [[ -z "$official" ]]; then
    official="$repo/.night/official-base.apk"
    [[ -f "$official" || ! -f "$checkout/.night/official-base.apk" ]] || official="$checkout/.night/official-base.apk"
fi
keystore="${INSTALLER_KEYSTORE:-$checkout/.night/android-installer/installer-test.p12}"
if [[ -n "${WORK:-}" ]]; then
    work="$WORK"
else
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
fi

if [[ ! -f "$official" ]]; then
    if [[ -n "${BALATRO_MOBILE_APK:-}" ]]; then
        echo "No official Balatro APK at $official (BALATRO_MOBILE_APK or --mobile-apk)"
        exit 1
    fi
    echo "No official Balatro APK at $official (set BALATRO_MOBILE_APK): no Android installer in this build"
    exit 0
fi
mkdir -p "$out" "$work"
patch="$work/patch-mobile"

pc_copy="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
other=()
[[ -f "$pc_copy" ]] && other=(--other "$pc_copy")
old_checks=()
for old in ${BALATRO_MOBILE_OLD:-}; do
    [[ -f "$old" ]] || { echo "No older official APK at $old (BALATRO_MOBILE_OLD)"; exit 1; }
    other+=(--other "$old")
    old_checks+=(--vanilla "$old")
done
python3 -B "$repo/tools/release/patcher/make_patch.py" --vanilla "$official" "${other[@]}" --assets "$assets" \
    --exclude "$repo/tools/release/EXCLUDE.txt" --out "$patch"
version="$(sed -n 's/^  overhaul_version = "\(.*\)",$/\1/p' "$patch/manifest.lua")"
[[ -n "$version" ]] || version="${OVERHAUL_VERSION:-dev}"
grep -q '^  game_version = ".*\[M\]",$' "$patch/manifest.lua" || { echo "$official is not the official mobile Balatro"; exit 1; }
name="$(sed -n 's/^  overhaul_name = "\(.*\)",$/\1/p' "$patch/manifest.lua")"
display="$(echo "$name" | grep -o '^[0-9][0-9.]*' || true)"
[[ -n "$display" ]] || display="${OVERHAUL_DISPLAY:-$version}"
apk_name="BalatroOverhaulLauncher-$display-android.apk"

pc_args=()
[[ -n "${PATCH_PC:-}" && -f "$PATCH_PC/manifest.lua" ]] && pc_args=(--patch-pc "$PATCH_PC")
python3 -B "$here/make_apk.py" installer --patch "$patch" "${pc_args[@]}" --out "$work/apk" --work "$work" --keystore "$keystore"
mv "$work/apk/BalatroOverhaul-installer.apk" "$out/$apk_name"
python3 -B "$here/make_apk.py" zip --patch "$patch" --out "$out/android-patch-$version.zip"
python3 -B "$here/make_apk.py" inspect "$out/$apk_name" > "$work/inspect.json"
grep -q '"package": "com.jupiteriansoul.balatrooverhaul.phone"' "$work/inspect.json" || { echo "installer package is wrong"; exit 1; }
grep -q '"signature_ok": true' "$work/inspect.json" || { echo "installer is not signed"; exit 1; }
grep -q '"aligned": true' "$work/inspect.json" || { echo "installer is not aligned"; exit 1; }
apksigner="${APKSIGNER:-$(command -v apksigner || true)}"
if [[ -n "$apksigner" ]]; then
    cert="$("$apksigner" verify --print-certs "$out/$apk_name" 2>/dev/null | sed -n 's/^.*Signer.* certificate SHA-256 digest: //p' | head -1)"
    echo "Installer signed with $keystore (certificate SHA-256 $cert)"
    echo "Every later installer must be signed with this key, or phones refuse the update"
fi

python3 -B "$repo/tools/release/patcher/check_patch.py" --vanilla "$official" "${old_checks[@]}" "$out"
steam="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
if [[ -f "$steam" ]]; then
    for f in "$out"/*; do
        python3 -B "$repo/tools/release/patcher/check_patch.py" --vanilla "$steam" "$f" > "$work/steam_check.txt" || true
        count="$(sed -n 's/^FAIL: \([0-9]*\) problems$/\1/p' "$work/steam_check.txt")"
        if [[ -n "$count" ]]; then
            cat "$work/steam_check.txt"
            echo "$(basename "$f") holds Steam Balatro content"
            exit 1
        elif ! grep -q '^OK:' "$work/steam_check.txt"; then
            cat "$work/steam_check.txt"
            exit 1
        fi
    done
fi
rm -rf "$patch" "$work/apk"
echo "Android: $(cd "$out" && ls)"

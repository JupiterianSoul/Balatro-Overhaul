#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
dest="$(realpath -m "${1:?usage: export_public.sh DEST_CLONE PATCHSET_DIR}")"
patchset="$(realpath "${2:?usage: export_public.sh DEST_CLONE PATCHSET_DIR}")"
vanilla="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
mobile="${BALATRO_MOBILE_APK:?set BALATRO_MOBILE_APK}"
[[ -d "$dest/.git" ]] || { echo "DEST must be a clone of the public repo"; exit 1; }
[[ -f "$patchset/manifest.lua" ]] || { echo "PATCHSET has no manifest.lua"; exit 1; }

dirs=(server linux tools/release tools/bot tools/lang tools/replay tools/forge_tests tools/ui_tests tools/rules tools/score_preview tools/stats_tests tools/shop_tests tools/mp_probe tools/mp_test)
for d in game server launcher tools linux; do rm -rf "$dest/$d"; done
for d in "${dirs[@]}"; do
    git -C "$repo" ls-files -z -- "$d" | while IFS= read -r -d '' f; do
        case "$f" in
            */node_modules/*|*.p12|*.pem|*.key|*.env|*/.env*|tools/release/github/*|*/dist/*|*.apk|*.exe|*.dll) continue ;;
        esac
        mkdir -p "$dest/$(dirname "$f")"
        cp "$repo/$f" "$dest/$f"
    done
done
skip=(tools/mp_test/driver.lua tools/bot/harness_main.lua tools/score_preview/sandbox_test.lua tools/forge_tests/play_demo.lua tools/forge_tests/kinds_demo.lua tools/replay/input_mix.lua tools/forge_tests/solo_demo.lua tools/forge_tests/room_demo.lua tools/forge_tests/more_demo.lua tools/score_preview/mp_joker_info_test.lua tools/replay/test_replay.lua tools/release/test_release_info.lua tools/release/android/icon/draw/conf.lua tools/lang/vanilla_names.lua tools/lang/loc_audit.lua tools/lang/lang_sweep.lua tools/forge_tests/pixel_pass_demo.lua tools/forge_tests/enh_demo.lua tools/stats_tests/test_stats.lua tools/ui_tests/emotes_render_test.lua tools/ui_tests/moveable_dupe_test.lua tools/ui_tests/mp_kit_test.lua)
for f in "${skip[@]}"; do rm -f "$dest/$f"; done
mkdir -p "$dest/game"
cp -r "$patchset/." "$dest/game/"
cat > "$dest/game/README.md" <<'DOC'

This folder is the Overhaul's patch set, the same one the launcher applies to your own copy of Balatro.

- `files/`: files that exist only in the Overhaul, in full.
- `patches/`: edits to Balatro's own files. They hold only the Overhaul's lines and point at the original lines, so none of Balatro's code is here.
- `images/`, `lines/`, `manifest.lua`: the rest of the patch format. `tools/release/patcher` reads and applies it.

Balatro belongs to LocalThunk and Playstack and is not included. Build the mod from your own copy with the launcher, or read `tools/release/LAUNCHER.md`.
DOC

echo "=== secret scan ==="
if grep -rIEn --exclude-dir=.git --exclude=index.lua --exclude=crash.test.ts "(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|SUPABASE_[A-Z_]*KEY *= *[A-Za-z0-9])" "$dest" | head -20 | tee /tmp/export_secrets.txt | grep -q .; then
    echo "SECRETS FOUND, see above"; exit 1
fi
find "$dest" -type f \( -name '*.env' -o -name '.env*' -o -name '*.p12' -o -name '*.jks' -o -name '*.pem' \) -not -path '*/.git/*' | head -5 | tee /tmp/export_keyfiles.txt | grep -q . && { echo "KEY FILES FOUND"; exit 1; }
echo "none"

echo "=== vanilla check ==="
allow="$(mktemp)"
cat "$repo/LICENSES/"*.txt > "$allow"
python3 -B "$repo/tools/release/patcher/check_patch.py" --vanilla "$vanilla" --vanilla "$mobile" --allow "$allow" "$dest/game" "$dest/server" "$dest/tools" "$dest/linux"
rm -f "$allow"
echo "exported to $dest"

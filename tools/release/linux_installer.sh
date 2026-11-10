#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
mods_from="${MODS_FROM:-$HOME/.local/share/love/Overhaul/mods}"
love_url="https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage"
love_sha="65a673406431eff7167a15a032bf7a2e4ba50108e091eb7b176465831f9b5e00"
cache="$repo/dist/cache"
appimage="$cache/love-11.5-x86_64.AppImage"
out="${1:-$repo/dist/BalatroOverhaul-linux-install.sh}"

mkdir -p "$cache"
if [[ ! -f "$appimage" ]] || [[ "$(sha256sum "$appimage" | cut -d' ' -f1)" != "$love_sha" ]]; then
    curl -fsSL -o "$appimage" "$love_url"
fi
[[ "$(sha256sum "$appimage" | cut -d' ' -f1)" == "$love_sha" ]] || { echo "LÖVE AppImage checksum mismatch"; exit 1; }

(cd "$repo" && PERF_LOG="${PERF_LOG:-0}" bash build_linux.sh)

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/app" "$stage/mods"
cp -a "$repo/dist/linux/." "$stage/app/"
cp "$appimage" "$stage/app/love.AppImage"
chmod 755 "$stage/app/love.AppImage"

mod_count=0
if [[ "${WITH_MODS:-1}" == "1" && -f "$mods_from/enabled.txt" ]]; then
    while read -r id; do
        [[ -n "$id" && -d "$mods_from/$id" ]] || continue
        cp -a "$mods_from/$id" "$stage/mods/$id"
        echo "$id" >> "$stage/mods/enabled.txt"
        mod_count=$((mod_count + 1))
    done < "$mods_from/enabled.txt"
    if (( mod_count > 0 )); then
        if [[ -f "$mods_from/session.txt" ]]; then cp "$mods_from/session.txt" "$stage/mods/session.txt"; else echo modded > "$stage/mods/session.txt"; fi
    fi
fi

cat > "$out" <<'HEADER'
#!/usr/bin/env bash
set -euo pipefail
app_id=balatro-overhaul
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
app_dir="$data_home/$app_id"
save_dir="$data_home/love/Overhaul"
echo "Installing Balatro Overhaul into $app_dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
line=$(awk '/^__PAYLOAD_BELOW__$/ {print NR + 1; exit 0}' "$0")
tail -n +"$line" "$0" | tar -xz -C "$tmp"
mkdir -p "$app_dir" "$HOME/.local/bin" "$data_home/applications" "$data_home/icons/hicolor/192x192/apps"
rm -rf "$app_dir/love"
cp -a "$tmp/app/." "$app_dir/"
(cd "$app_dir" && ./love.AppImage --appimage-extract > /dev/null && rm -rf love && mv squashfs-root love && rm -f love.AppImage)
ln -sf "$app_dir/$app_id" "$HOME/.local/bin/$app_id"
cp "$app_dir/$app_id.png" "$data_home/icons/hicolor/192x192/apps/$app_id.png"
cat > "$data_home/applications/$app_id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Balatro Overhaul
Exec=$app_dir/$app_id
Icon=$app_id
Categories=Game;
Terminal=false
EOF
if [[ -f "$tmp/mods/enabled.txt" ]]; then
    mkdir -p "$save_dir/mods"
    [[ -f "$save_dir/mods/enabled.txt" ]] && cp "$save_dir/mods/enabled.txt" "$save_dir/mods/enabled.txt.bak"
    while read -r id; do
        [[ -n "$id" ]] || continue
        rm -rf "$save_dir/mods/$id"
        cp -a "$tmp/mods/$id" "$save_dir/mods/$id"
        echo "Mod: $id"
    done < "$tmp/mods/enabled.txt"
    cp "$tmp/mods/enabled.txt" "$save_dir/mods/enabled.txt"
    [[ -f "$tmp/mods/session.txt" ]] && cp "$tmp/mods/session.txt" "$save_dir/mods/session.txt"
fi
command -v python3 > /dev/null || echo "Note: python3 is missing, multiplayer needs it (sudo apt install python3)"
echo "Done. Start Balatro Overhaul from the app menu, or run: $app_dir/$app_id"
exit 0
__PAYLOAD_BELOW__
HEADER

tar -czf - -C "$stage" app mods >> "$out"
chmod 755 "$out"
echo "Wrote $out ($(du -h "$out" | cut -f1)), mods: $mod_count, monitor: ${PERF_LOG:-0}"

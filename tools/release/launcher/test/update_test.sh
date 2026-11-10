#!/usr/bin/env bash
set -uo pipefail
export OVERHAUL_NO_SAVE_SCAN=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
rel="${RELEASE_DIR:-$repo/dist/release}"
work="${UPD_DIR:-$repo/.night/upd}"
port="${QA_PORT:-38851}"
dead_port="${MP_TEST_PORT:-38871}"
vanilla="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
case "$work" in
    "$repo"/.night/*) ;;
    *) echo "UPD_DIR must be under $repo/.night"; exit 1 ;;
esac
[[ -f "$rel/launcher.love" && -f "$rel/feed.json" ]] || { echo "Run tools/release/pack_overhaul.sh --launcher-only first"; exit 1; }
if [[ -z "${UPD_NETNS:-}" ]] && command -v unshare >/dev/null && unshare -rn true 2>/dev/null; then
    UPD_NETNS=1 exec unshare -rn sh -c 'ip link set lo up 2>/dev/null; exec bash "$0" "$@"' "${BASH_SOURCE[0]}" "$@"
fi
fail=0
say() { echo "upd: $*"; }
check() {
    if grep -q -- "$2" "$work/$1.txt"; then
        say "ok   $1: $(grep -m1 -- "$2" "$work/$1.txt" | cut -c1-110)"
    else
        say "FAIL $1 (wanted: $2)"
        sed 's/^/      /' "$work/$1.txt" | tail -6
        fail=1
    fi
}

rm -rf "$work"
mkdir -p "$work/srv/new" "$work/srv/older" "$work/srv/broken" "$work/srv/format2" "$work/data"
export XDG_DATA_HOME="$work/data"
save="$XDG_DATA_HOME/love/BalatroOverhaulLauncher"
game="$save/Overhaul"
old_version="$(sed -n 's/^  overhaul_version = "\(.*\)",$/\1/p' "$rel/patchset/manifest.lua")"

new_version="${NEW_VERSION:-99}"
cp -a --reflink=auto "$repo/assets" "$work/assets_new"
rm "$work/assets_new/globals.lua"
sed "s/^OVERHAUL_VERSION = .*/OVERHAUL_VERSION = '$new_version'/" "$repo/assets/globals.lua" > "$work/assets_new/globals.lua"
python3 -B "$repo/tools/release/patcher/make_patch.py" --vanilla "$vanilla" --assets "$work/assets_new" \
    --exclude "$repo/tools/release/EXCLUDE.txt" --out "$work/new_patchset" | tail -1
zipf="$work/srv/new/patchset-$new_version.zip"
(cd "$work/new_patchset" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -q -9 -X -D "$zipf" -@)
printf '{"en": "Test update %s", "fr": "Mise à jour de test %s", "es": "Actualización de prueba %s"}\n' "$new_version" "$new_version" "$new_version" > "$work/changelog.json"
python3 -B "$repo/tools/release/patcher/make_feed.py" --manifest "$work/new_patchset/manifest.lua" --zip "$zipf" \
    --changelog "$work/changelog.json" --out "$work/srv/new/feed.json" | sed 's/^/upd: /'
cp "$zipf" "$work/srv/broken/"
python3 -B - "$work/srv/broken/patchset-$new_version.zip" <<'EOF'
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
d[len(d) // 2] ^= 0xFF
open(p, "wb").write(bytes(d))
EOF
cp "$work/srv/new/feed.json" "$work/srv/broken/feed.json"
python3 -B "$repo/tools/release/patcher/make_feed.py" --manifest "$rel/patchset/manifest.lua" --zip "$rel/patchset-"*.zip \
    --version 2.4 --url "patchset-old.zip" --out "$work/srv/older/feed.json" > /dev/null
python3 -B - "$work/srv/new/feed.json" "$work/srv/format2/feed.json" "$(( $(sed -n 's/^P.FORMAT = \([0-9]*\)$/\1/p' "$repo/tools/release/launcher/feed.lua") + 1 ))" <<'EOF'
import json, sys
f = json.load(open(sys.argv[1]))
f["latest"]["patch_format"] = int(sys.argv[3])
f["page"] = "https://example.invalid/overhaul"
json.dump(f, open(sys.argv[2], "w"))
EOF
cp "$zipf" "$work/srv/format2/"

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/srv" > "$work/http.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null' EXIT
for _ in $(seq 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), 0.2)" 2>/dev/null && break
    sleep 0.1
done

launcher() {
    local name="$1" feed="$2"
    shift 2
    LAUNCHER_LOVE="${LAUNCHER_LOVE:-$rel/launcher.love}" OVERHAUL_FEED="$feed" OVERHAUL_LAUNCHER_CMD="$work/fake_launcher.sh" TMO=300 \
        bash "$here/run_launcher.sh" --cli "$@" > "$work/$name.txt" 2>&1
    echo "rc=$?" >> "$work/$name.txt"
}
feed() { echo "http://127.0.0.1:$port/$1/feed.json"; }

launcher install "$(feed none)" install
check install "^OK installed $old_version,"
launcher older "$(feed older)" update
check older "^OK You have the latest Overhaul ($old_version)"
launcher offline "http://127.0.0.1:$dead_port/feed.json" update
check offline "^OK Could not check for updates"
launcher broken "$(feed broken)" update
check broken "^FAIL The update download is damaged"
check broken "rc=6"
grep -q "OVERHAUL_VERSION = '$old_version'" "$game/globals.lua" && say "ok   broken: the installed $old_version is untouched" || { say "FAIL broken changed the install"; fail=1; }
[[ ! -e "$save/Overhaul.new" ]] && say "ok   broken: no staging folder left" || { say "FAIL staging folder left"; fail=1; }
launcher format2 "$(feed format2)" update
check format2 "^FAIL Overhaul $new_version needs a newer launcher"
launcher new "$(feed new)" update
check new "^update $new_version http://127.0.0.1:$port/new/patchset-$new_version.zip"
check new "^OK installed $new_version, 751 files\|^OK installed $new_version, 7[0-9][0-9] files"
grep -q "OVERHAUL_VERSION = '$new_version'" "$game/globals.lua" && say "ok   new: installed globals.lua says $new_version" || { say "FAIL new: globals.lua not updated"; fail=1; }
python3 -B "$repo/tools/release/patcher/roundtrip_check.py" "$game" --assets "$work/assets_new" --manifest "$work/new_patchset/manifest.lua" > "$work/roundtrip.txt" 2>&1
check roundtrip "^OK"
ls "$save/updates" > "$work/updates_dir.txt"
check updates_dir "^patchset-$new_version.zip$"
launcher restart "$(feed none)" check
check restart "^launcher: Overhaul $new_version for Balatro"
launcher again "$(feed new)" update
check again "^OK You have the latest Overhaul ($new_version)"
cp "$save/overhaul_launcher_link.lua" "$work/link.txt"
check link "feed\"]=\"http://127.0.0.1:$port/new/feed.json\""
check link "fake_launcher.sh"

if (( fail )); then
    say "FAIL"
    exit 1
fi
say "OK"

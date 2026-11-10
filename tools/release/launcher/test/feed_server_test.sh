#!/usr/bin/env bash
set -uo pipefail
export OVERHAUL_NO_SAVE_SCAN=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
rel="${RELEASE_DIR_IN:-$repo/dist/release}"
work="${UPD_DIR:-$repo/.night/feedsrv}"
port="${QA_PORT:-38851}"
dead_port="${MP_TEST_PORT:-38871}"
steps="${FEED_STEPS:-launcher ingame}"
vanilla="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
case "$work" in
    "$repo"/.night/*) ;;
    *) echo "UPD_DIR must be under $repo/.night"; exit 1 ;;
esac
[[ -f "$rel/launcher.love" && -f "$rel/feed.json" ]] || { echo "Run tools/release/pack_overhaul.sh --launcher-only first (RELEASE_DIR_IN=its --out)"; exit 1; }
if [[ -z "${UPD_NETNS:-}" ]] && command -v unshare >/dev/null && unshare -rn true 2>/dev/null; then
    UPD_NETNS=1 exec unshare -rn sh -c 'ip link set lo up 2>/dev/null; exec bash "$0" "$@"' "${BASH_SOURCE[0]}" "$@"
fi
fail=0
say() { echo "feedsrv: $*"; }
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
mkdir -p "$work/pub" "$work/data"
export XDG_DATA_HOME="$work/data"
save="$XDG_DATA_HOME/love/BalatroOverhaulLauncher"
game="$save/Overhaul"
old_version="$(sed -n 's/^  overhaul_version = "\(.*\)",$/\1/p' "$rel/patchset/manifest.lua")"
new_version="${NEW_VERSION:-99}"

cp -a --reflink=auto "$repo/assets" "$work/assets_new"
rm "$work/assets_new/globals.lua"
sed "s/^OVERHAUL_VERSION = .*/OVERHAUL_VERSION = '$new_version'/" "$repo/assets/globals.lua" > "$work/assets_new/globals.lua"
python3 -B "$repo/tools/release/patcher/make_patch.py" --vanilla "$vanilla" --assets "$work/assets_new" \
    --exclude "$repo/tools/release/EXCLUDE.txt" --out "$work/new_patchset" | tail -1 | sed 's/^/feedsrv: /'
mkdir -p "$work/pack_new"
(cd "$work/new_patchset" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -q -9 -X -D "$work/pack_new/patchset-$new_version.zip" -@)
printf '{"en": "Test update %s", "fr": "Mise à jour de test %s", "es": "Actualización de prueba %s"}\n' "$new_version" "$new_version" "$new_version" > "$work/changelog.json"
python3 -B "$repo/tools/release/patcher/make_feed.py" --manifest "$work/new_patchset/manifest.lua" --zip "$work/pack_new/patchset-$new_version.zip" \
    --changelog "$work/changelog.json" --out "$work/pack_new/feed.json" | sed 's/^/feedsrv: /'

srv=""
server() {
    [[ -n "$srv" ]] && { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; }
    PORT="$port" RELEASE_DIR="$work/pub" bun run "$repo/server/src/index.ts" >> "$work/server.log" 2>&1 &
    srv=$!
    for _ in $(seq 100); do
        python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), 0.2)" 2>/dev/null && return 0
        sleep 0.1
    done
    say "FAIL the server did not start"
    tail -5 "$work/server.log"
    exit 1
}
trap '[[ -n "$srv" ]] && kill "$srv" 2>/dev/null' EXIT
publish() {
    local name="$1"
    shift
    bun "$repo/tools/release/publish_feed.ts" --to "$work/pub" "$@" > "$work/$name.txt" 2>&1
    echo "rc=$?" >> "$work/$name.txt"
    server
}
feed="http://127.0.0.1:$port/release/feed.json"

printf '#!/bin/sh\necho "$@" >> "%s/calls.log"\n' "$work" > "$work/recorder.sh"
chmod 755 "$work/recorder.sh"
launcher() {
    local name="$1" url="$2"
    shift 2
    LAUNCHER_LOVE="${LAUNCHER_LOVE:-$rel/launcher.love}" OVERHAUL_FEED="$url" OVERHAUL_LOVE="$work/recorder.sh" TMO=300 \
        bash "$here/run_launcher.sh" --cli "$@" > "$work/$name.txt" 2>&1
    echo "rc=$?" >> "$work/$name.txt"
}

server
curl -s -o /dev/null -w '%{http_code}\n' "$feed" > "$work/empty.txt"
check empty "^404$"
launcher install "$feed" install
check install "^OK installed $old_version,"
mkdir -p "$XDG_DATA_HOME/love/Overhaul/1"
head -c 4096 /dev/urandom > "$XDG_DATA_HOME/love/Overhaul/1/profile.jkr"
save_sum="$(sha256sum < "$XDG_DATA_HOME/love/Overhaul/1/profile.jkr")"

if [[ " $steps " == *" launcher "* ]]; then
    launcher nothing "$feed" update
    check nothing "^OK Could not check for updates"
    publish pub_same --from "$rel"
    check pub_same "feed.json now offers Overhaul $old_version"
    launcher same "$feed" update
    check same "^OK You have the latest Overhaul ($old_version)"
    publish pub_again --from "$rel"
    check pub_again "is not newer than the published $old_version"
    launcher offline "http://127.0.0.1:$dead_port/release/feed.json" update
    check offline "^OK Could not check for updates"

    publish pub_new --from "$work/pack_new"
    check pub_new "feed.json now offers Overhaul $new_version"
    cp "$work/pub/patchset-$new_version.zip" "$work/good.zip"
    python3 -B - "$work/pub/patchset-$new_version.zip" <<'EOF'
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
d[len(d) // 2] ^= 0xFF
open(p, "wb").write(bytes(d))
EOF
    launcher broken "$feed" update
    check broken "^FAIL The update download is damaged"
    grep -q "OVERHAUL_VERSION = '$old_version'" "$game/globals.lua" && say "ok   broken: the installed $old_version is untouched" || { say "FAIL broken changed the install"; fail=1; }
    [[ ! -e "$save/Overhaul.new" ]] && say "ok   broken: no staging folder left" || { say "FAIL staging folder left"; fail=1; }
    cp "$work/good.zip" "$work/pub/patchset-$new_version.zip"
    python3 -B - "$work/pub/feed.json" <<'EOF'
import json, sys
f = json.load(open(sys.argv[1]))
f["latest"]["sha256"] = "0" * 64
json.dump(f, open(sys.argv[1], "w"))
EOF
    server
    launcher badsum "$feed" update
    check badsum "^FAIL The update download is damaged"
    rm "$work/pub/patchset-$new_version.zip"
    publish pub_fixed --from "$work/pack_new" --force
    rm "$work/pub/patchset-$new_version.zip"
    launcher missing "$feed" update
    check missing "^FAIL"
    grep -q "OVERHAUL_VERSION = '$old_version'" "$game/globals.lua" && say "ok   missing: the installed $old_version is untouched" || { say "FAIL missing changed the install"; fail=1; }
    publish pub_min --from "$work/pack_new" --force --min-launcher "$(( $(sed -n 's/^P.FORMAT = \([0-9]*\)$/\1/p' "$repo/tools/release/launcher/feed.lua") + 1 ))"
    launcher minlauncher "$feed" update
    check minlauncher "^FAIL Overhaul $new_version needs a newer launcher"

    publish pub_real --from "$work/pack_new" --force
    check pub_real "feed.json now offers Overhaul $new_version"
    launcher new "$feed" update
    check new "^update $new_version http://127.0.0.1:$port/release/patchset-$new_version.zip"
    check new "^OK installed $new_version,"
    grep -q "OVERHAUL_VERSION = '$new_version'" "$game/globals.lua" && say "ok   new: installed globals.lua says $new_version" || { say "FAIL new: globals.lua not updated"; fail=1; }
    python3 -B "$repo/tools/release/patcher/roundtrip_check.py" "$game" --assets "$work/assets_new" --manifest "$work/new_patchset/manifest.lua" > "$work/roundtrip.txt" 2>&1
    check roundtrip "^OK"
    [[ "$(sha256sum < "$XDG_DATA_HOME/love/Overhaul/1/profile.jkr")" == "$save_sum" ]] && say "ok   new: the save is untouched" || { say "FAIL new: the save changed"; fail=1; }
    launcher restart "$feed" check
    check restart "^launcher: Overhaul $new_version for Balatro"
    launcher again "$feed" update
    check again "^OK You have the latest Overhaul ($new_version)"
    grep -q "\"$feed\"" "$save/overhaul_launcher_link.lua" && say "ok   link: the game reads $feed" || { say "FAIL link file"; fail=1; }
fi

if [[ " $steps " == *" ingame "* ]]; then
    d="$work/ingame_data"
    rm -rf "$d"
    mkdir -p "$d"
    XDG_DATA_HOME="$d" LAUNCHER_LOVE="${LAUNCHER_LOVE:-$rel/launcher.love}" OVERHAUL_NO_UPDATE_CHECK=1 bash "$here/run_launcher.sh" --cli install > "$work/ingame_install.txt" 2>&1
    check ingame_install "^OK installed $old_version,"
    rm -f "$work/pub/"*
    publish pub_ingame --from "$work/pack_new"
    mkdir -p "$d/love/Overhaul/1"
    cp "$XDG_DATA_HOME/love/Overhaul/1/profile.jkr" "$d/love/Overhaul/1/profile.jkr"
    cat > "$work/real_launcher.sh" <<EOF
#!/bin/sh
echo "\$@" >> "$work/calls.log"
XDG_DATA_HOME="$d" LAUNCHER_LOVE="$rel/launcher.love" OVERHAUL_FEED="$feed" OVERHAUL_LOVE="$work/recorder.sh" TMO=240 \\
    setsid sh -c 'bash "$here/run_launcher.sh" "\$@" > "$work/ingame_launcher.txt" 2>&1; echo "rc=\$?" >> "$work/ingame_launcher.txt"' sh "\$@" < /dev/null > /dev/null 2>&1 &
EOF
    chmod 755 "$work/real_launcher.sh"
    rm -f "$work/calls.log"
    export LINK_BODY="return {format = 1, feed = \"$feed\", launcher = {\"$work/real_launcher.sh\"}}"
    hook="local d = love.filesystem.getSource():match('^(.*)/[^/]+\$') local f = io.open(d .. '/overhaul_launcher_link.lua', 'wb') f:write(os.getenv('LINK_BODY')) f:close() love.filesystem.load('functions/launcher_update.lua')() OverhaulUpdate.check(true)"
    s="wait:2|lua:G.PROFILES[G.SETTINGS.profile].name = 'Tester'|close|lua:$hook|wait:4|shot:01_menu_update|func:overhaul_update_click|wait:1|shot:02_update_prompt|func:overhaul_update_go|wait:4|quit"
    MENU_OUT="$work/shots" PHONE="${PHONE:-0}" SCREEN="${SCREEN:-1280x720}" bash "$repo/tools/menu_shots/run.sh" ingame plain "$s" > "$work/ingame_game.txt" 2>&1
    for _ in $(seq 240); do
        grep -q "^rc=" "$work/ingame_launcher.txt" 2>/dev/null && break
        sleep 1
    done
    grep -q -- "--update --play" "$work/calls.log" 2>/dev/null && say "ok   ingame: the Update button started the launcher with --update --play" || { say "FAIL ingame: no launcher call"; tail -5 "$work/ingame_game.txt"; fail=1; }
    grep -q "\"$new_version\"" "$d/love/BalatroOverhaulLauncher/install.lua" 2>/dev/null && say "ok   ingame: the launcher installed $new_version" || { say "FAIL ingame: not installed"; tail -5 "$work/ingame_launcher.txt"; fail=1; }
    grep -q "BalatroOverhaulLauncher/Overhaul" "$work/calls.log" 2>/dev/null && say "ok   ingame: the launcher started the updated game" || { say "FAIL ingame: the game was not started again"; fail=1; }
    cmp -s "$XDG_DATA_HOME/love/Overhaul/1/profile.jkr" "$d/love/Overhaul/1/profile.jkr" && say "ok   ingame: the save is untouched" || { say "FAIL ingame: the save changed"; fail=1; }
fi

if (( fail )); then
    say "FAIL"
    exit 1
fi
say "OK"

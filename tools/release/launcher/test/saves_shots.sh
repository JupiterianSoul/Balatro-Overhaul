#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
logic="$repo/.night/saves-gate/logic"
work="$repo/.night/saves-gate/shots"
out="${SHOTS_OUT:-$work/out}"
[[ -d "$logic/fix/steam" ]] || { echo "run saves_test.sh first (it makes the fixtures)"; exit 1; }
rm -rf "$work/stage" "$work/run"
mkdir -p "$work/stage/patcher" "$out"
cp "$here/../"*.lua "$work/stage/"
cp "$here/../../patcher/"{apply,zipread,find}.lua "$work/stage/patcher/"
cp "$repo/assets/functions/save_io.lua" "$work/stage/save_io.lua"
cp "$repo/assets/https.lua" "$work/stage/https.lua"
cp "$repo/assets/smods/libs/json/json.lua" "$work/stage/json.lua"
fix="$logic/fix"
xbox="$(find "$fix/xbox" -name containers.index -printf '%h\n' | head -1)"
run() {
    local tag="$1" size="$2" lang="$3" shots="$4" lock="$5"
    local d="$work/run/$tag"
    rm -rf "$d"
    mkdir -p "$d/xdg/love/Overhaul" "$d/home" "$d/steam"
    cp -r "$fix/steam/Balatro" "$d/steam/Balatro"
    [[ "$lock" == 1 ]] && printf '0 %s\n' "$(date +%s)" > "$d/xdg/love/Overhaul/overhaul_running.lock"
    [[ "$lock" == 1 ]] && printf 'return {}' > "$d/xdg/love/Overhaul/placeholder.jkr" && mkdir -p "$d/xdg/love/Overhaul/1" && cp "$fix/real/1/profile.jkr" "$d/xdg/love/Overhaul/1/"
    local w="${size%x*}" h="${size#*x}"
    env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null \
        HOME="$d/home" XDG_DATA_HOME="$d/xdg" OVERHAUL_NO_SAVE_SCAN=1 OVERHAUL_NO_UPDATE_CHECK=1 \
        OVERHAUL_BALATRO_SAVES="$d/steam/Balatro" OVERHAUL_XBOX_SAVES="$xbox" PICKED="$fix/played.zip" \
        PATH="$fix/bin/z:$PATH" LAUNCHER_SHOT_DIR="$out" LAUNCHER_SHOTS="$shots" LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1 \
        LAUNCHER_LANG="$lang" LAUNCHER_SIZE="$w"x"$h" \
        timeout -k 5 90 xvfb-run -a -s "-screen 0 ${w}x${h}x24" love "$work/stage" > "$d/log.txt" 2>&1
    echo "$tag exit $?"
    grep -iE "error|traceback" "$d/log.txt" | head -5
    for f in "$out"/*.png; do
        case "$(basename "$f")" in saves*) mv "$f" "$out/${tag}_$(basename "$f")" ;; esac
    done
}
for o in land:1280x720 port:720x1280; do
    name="${o%%:*}" size="${o#*:}"
    run "en_${name}" "$size" en "saves,saves+import,saves+out" 0
    run "en_${name}_lock" "$size" en "saves+load" 1
    run "fr_${name}" "$size" fr "saves+import,saves+out" 0
    run "es_${name}" "$size" es "saves+import,saves+out" 0
done
rm -rf "$work/pstage"
cp -r "$work/stage" "$work/pstage"
mv "$work/pstage/core.lua" "$work/pstage/core_pc.lua"
cp "$repo/tools/release/android/phone/core.lua" "$work/pstage/phone_core_src.lua"
cat > "$work/pstage/core.lua" <<'EOF2'
local C = require("core_pc")
C.PHONE = true
C.APP_APK = "BalatroOverhaul.apk"
C.APP_INFO = "app_info.txt"
C.APP = "com.jupiteriansoul.balatrooverhaul"
C.app_info = function() return {name = "2.0.5", code = 1, time = 0, splits = {}} end
C.save_as = function() return false end
C.save_as_result = function() return nil end
local src = love.filesystem.read("phone_core_src.lua")
local body = src:match("(function C%.fake_appsave%(dir, cmd, arg%).-\n    return false\nend)")
assert(loadstring("local C = ...\n" .. body))(C)
C.bridge = function(cmd, arg)
    return C.fake_appsave(os.getenv("OVERHAUL_BRIDGE_FAKE"), cmd, arg)
end
return C
EOF2
python3 -B - "$fix" <<'PY'
import sys, zlib, zipfile
fix = sys.argv[1]
def comp(s):
    c = zlib.compressobj(1, zlib.DEFLATED, -15)
    return c.compress(s.encode()) + c.flush()
keys = lambda p, n: "{" + "".join('["%s_%d"]=true,' % (p, i) for i in range(n)) + "}"
with zipfile.ZipFile(fix + "/phone_pick.zip", "w") as z:
    z.writestr("Balatro/1/profile.jkr", comp('return {["name"]="Steamy",["career_stats"]={["c_wins"]=7,["c_rounds"]=212,},}'))
    z.writestr("Balatro/1/meta.jkr", comp('return {["unlocked"]=%s,["discovered"]=%s,}' % (keys("j_u", 58), keys("j_d", 92))))
    z.writestr("Balatro/1/save.jkr", comp('return {["GAME"]={["round"]=9,["round_resets"]={["ante"]=3,},},}'))
PY
for o in phone_land:1560x720 phone_port:720x1560; do
    name="${o%%:*}" size="${o#*:}"
    for lang in en fr es; do
        for mode in new old; do
            d="$work/run/${name}_${lang}_$mode"
            rm -rf "$d"; mkdir -p "$d/xdg/love/BalatroOverhaulLauncher/1" "$d/home" "$d/bridge/pick" "$d/bridge/app_save/1"
            cp "$fix/real/1/profile.jkr" "$fix/real/1/meta.jkr" "$d/xdg/love/BalatroOverhaulLauncher/1/"
            cp "$fix/real/1/profile.jkr" "$fix/real/1/meta.jkr" "$d/bridge/app_save/1/"
            cp "$fix/phone_pick.zip" "$d/bridge/pick/friend save.zip"
            printf 'friend save.zip' > "$d/bridge/pick_name.txt"
            shots="saves,saves+export,saves+import"
            if [[ "$mode" == old ]]; then : > "$d/bridge/app_old"; shots="saves+export"; fi
            env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null \
                HOME="$d/home" XDG_DATA_HOME="$d/xdg" OVERHAUL_NO_SAVE_SCAN=1 OVERHAUL_NO_UPDATE_CHECK=1 OVERHAUL_BRIDGE_FAKE="$d/bridge" \
                LAUNCHER_SHOT_DIR="$out" LAUNCHER_SHOTS="$shots" LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1 LAUNCHER_LANG="$lang" LAUNCHER_SIZE="$size" \
                timeout -k 5 60 xvfb-run -a -s "-screen 0 ${size}x24" love "$work/pstage" > "$d/log.txt" 2>&1
            echo "${name}_${lang}_$mode exit $? exported=[$(ls "$d/bridge" | grep saved- | tr '\n' ',')]"
            grep -iE "error|traceback" "$d/log.txt" | head -3
            for f in "$out"/saves*.png; do
                [[ -e "$f" ]] && mv "$f" "$out/${name}_${lang}_${mode}_$(basename "$f")"
            done
        done
    done
done
ls "$out"

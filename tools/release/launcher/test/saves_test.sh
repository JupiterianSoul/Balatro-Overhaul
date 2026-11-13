#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
work="$repo/.night/saves-gate/logic"
real_src="${REAL_STEAM:-$HOME/.local/share/Steam/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro}"
rm -rf "$work"
mkdir -p "$work/stage/patcher" "$work/fix/real/1" "$work/fix/xsrc/1" "$work/fix/xsrc/2" "$work/xdg" "$work/home"
fix="$work/fix"
cp "$here/../"*.lua "$work/stage/"
cp "$here/../../patcher/"{apply,zipread,find}.lua "$work/stage/patcher/"
cp "$repo/assets/functions/save_io.lua" "$work/stage/save_io.lua"
cp "$here/saves_check.lua" "$work/stage/main.lua"
cat > "$work/stage/conf.lua" <<'EOF'
love.conf = function(t)
    t.identity = "BalatroOverhaulLauncher"
    t.window = false
    t.modules.audio = false
    t.modules.sound = false
end
EOF
if [[ -f "$real_src/1/profile.jkr" && -f "$real_src/1/meta.jkr" ]]; then
    cp "$real_src/1/profile.jkr" "$real_src/1/meta.jkr" "$fix/real/1/"
    [[ -f "$real_src/1/save.jkr" ]] && cp "$real_src/1/save.jkr" "$fix/real/1/"
    echo "fixture: real Steam save copied from $real_src"
    before_real="$(cd "$real_src" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)"
else
    python3 -B "$here/make_fake_saves.py" "$fix/fake" >/dev/null 2>&1
    cp "$(find "$fix/fake" -path '*/1/profile.jkr' | head -1)" "$fix/real/1/profile.jkr"
    cp "$(find "$fix/fake" -path '*/1/meta.jkr' | head -1)" "$fix/real/1/meta.jkr"
    echo "fixture: no real Steam save here, fake one used"
    before_real=""
fi
[[ -f "$fix/real/1/save.jkr" ]] || printf 'return {}' > "$fix/real/1/save.jkr"
mkdir -p "$fix/steam"
cp -r "$fix/real" "$fix/steam/Balatro"
cp "$fix/real/1/profile.jkr" "$fix/real/1/meta.jkr" "$fix/xsrc/1/"
python3 -B "$here/make_fake_saves.py" "$fix/xfake" >/dev/null 2>&1
cp "$(find "$fix/xfake" -path '*/Roaming/Balatro/2/profile.jkr' | head -1)" "$fix/xsrc/2/profile.jkr"
xbox="$(python3 -B "$here/make_xbox_fixture.py" "$fix/xbox" "$fix/xsrc")"
mkdir -p "$fix/out dir"
mkdir -p "$fix/bin/z" "$fix/bin/k" "$fix/bin/none" "$fix/bin/mac"
picked="$fix/it's a save \$x.zip"
printf '#!/bin/sh\ncase "$*" in *--save*) printf "%%s\\n" "$SAVE_TO"; exit 0;; esac\n: > "%s/zenity_args.txt"\nfor a in "$@"; do printf "%%s\\n" "$a" >> "%s/zenity_args.txt"; done\nprintf "%%s\\n" "$PICKED"\n' "$fix" "$fix" > "$fix/bin/z/zenity"
printf '#!/bin/sh\nprintf "%%s\\n" "$PICKED"\n' > "$fix/bin/k/kdialog"
printf '#!/bin/sh\n: > "%s/osascript_args.txt"\nfor a in "$@"; do printf "%%s\\n" "$a" >> "%s/osascript_args.txt"; done\nprintf "%%s\\n" "$PICKED"\n' "$fix" "$fix" > "$fix/bin/mac/osascript"
chmod +x "$fix/bin/z/zenity" "$fix/bin/k/kdialog" "$fix/bin/mac/osascript"
env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null \
    HOME="$work/home" XDG_DATA_HOME="$work/xdg" OVERHAUL_NO_SAVE_SCAN=1 \
    OVERHAUL_BALATRO_SAVES="$fix/steam/Balatro" OVERHAUL_XBOX_SAVES="$xbox" SAVES_FIX="$fix" PICKED="$picked" SAVE_TO="$fix/out dir/Balatro Overhaul save.zip" \
    PATH="$fix/bin/z:$PATH" \
    timeout -k 5 180 xvfb-run -a love "$work/stage" > "$work/log.txt" 2>&1
rc=$?
grep -E "^(PASS|FAIL|RESULT)|Error|error" "$work/log.txt"
ps_cmd="$(cat "$fix/ps.txt")"
if [[ "$ps_cmd" == 'powershell -NoProfile -NonInteractive -STA -Command "'*'ShowDialog()'*'"' && "$ps_cmd" != *EncodedCommand* && "$ps_cmd" != *pwned* ]]; then
    echo "PASS PowerShell command is plain fixed text"
else
    echo "FAIL PowerShell command"; echo "$ps_cmd"; rc=1
fi
if [[ -n "$before_real" ]]; then
    after_real="$(cd "$real_src" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)"
    if [[ "$before_real" == "$after_real" ]]; then echo "PASS real Steam save folder unchanged"; else echo "FAIL real Steam save changed"; rc=1; fi
fi
echo "saves_test exit $rc"
exit $rc

#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -uo pipefail
export OVERHAUL_NO_SAVE_SCAN="${OVERHAUL_NO_SAVE_SCAN:-1}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
: "${XDG_DATA_HOME:?set XDG_DATA_HOME to a folder under .night/}"
case "$XDG_DATA_HOME" in
    "$repo"/.night/*) ;;
    *) echo "XDG_DATA_HOME must be under $repo/.night"; exit 1 ;;
esac
love_file="${LAUNCHER_LOVE:-$repo/dist/release/launcher.love}"
screen="${SCREEN:-1280x720}"
mkdir -p "$XDG_DATA_HOME"
display=(-a)
if [[ -n "${XVFB_NUM:-}" ]]; then
    display=(-n "$XVFB_NUM")
fi
exec timeout -k 5 "${TMO:-300}" xvfb-run "${display[@]}" -s "-screen 0 ${screen}x24" love "$love_file" "$@"

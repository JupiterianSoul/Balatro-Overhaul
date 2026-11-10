#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
official="${OFFICIAL_ICON:-$HOME/.local/share/love/Overhaul/official_icon.png}"
out="${OUT_DIR:-$repo/tools/release/launcher/icon}"
inst="${INSTALLER_DIR:-$here}"
scratch="${SCRATCH:-$repo/.night/icon_draw}"

[[ -f "$official" ]] || { echo "No original Android icon at $official (set OFFICIAL_ICON)"; exit 1; }
mkdir -p "$out" "$inst" "$scratch/xdg"
export OFFICIAL_ICON="$official" OUT_DIR="$out" INSTALLER_DIR="$inst" XDG_DATA_HOME="$scratch/xdg"
export SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
timeout 120 xvfb-run -a love "$here/draw" 2>&1 | grep -v RTKit || true
ls -la "$out" "$inst" | grep -E "launcher|installer"

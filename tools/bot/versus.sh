#!/usr/bin/env bash
code="${1:?usage: tools/bot/versus.sh ROOMCODE [game dir or .love]}"
game="${2:-$(cd "$(dirname "$0")/../.." && pwd)/assets}"
data="${BOT_DATA:-$HOME/.local/share/balatro-bot}"
mkdir -p "$data"
cfg="${BOT_CONFIG_DIR:-$(ls -d "$HOME"/.local/share/love/*/bot 2>/dev/null | head -1)}"
exec env XDG_DATA_HOME="$data" BOT_VERSUS_CODE="$code" BOT_CONFIG_DIR="$cfg" BOT_VERSUS_WINDOW=1 NO_NAME_PROMPT=1 love "$game"

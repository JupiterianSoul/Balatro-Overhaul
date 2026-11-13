#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="${RF_DIR:-$repo/.night/release_filter}"
mkdir -p "$out"
fail=0

run() {
    local name="$1" release="$2"
    rm -f "$out/$name.txt"
    OVERHAUL_RELEASE="$release" RF_OUT="$out/$name.txt" MENU_OUT="$out" \
        bash "$repo/tools/menu_shots/run.sh" "rf_$name" plain "lua:dofile('$here/release_filter_dump.lua')|quit" > /dev/null 2>&1
    if [[ ! -s "$out/$name.txt" ]]; then
        echo "FAIL $name: no dump (see $out/rf_$name/stdout.txt)"
        fail=1
        return 1
    fi
}

want() {
    local file="$1" pattern="$2" label="$3"
    if grep -qxE "$pattern" "$file"; then
        echo "ok   $label"
    else
        echo "FAIL $label (no line matching '$pattern' in $(basename "$file"))"
        fail=1
    fi
}

none() {
    local file="$1" pattern="$2" label="$3"
    if grep -qE "$pattern" "$file"; then
        echo "FAIL $label:"
        grep -E "$pattern" "$file" | head -5
        fail=1
    else
        echo "ok   $label"
    fi
}

if run release 1; then
    r="$out/release.txt"
    want "$r" "release true" "release build detected"
    want "$r" "sp_jokers 150" "release: 150 jokers in the solo pool"
    none "$r" "^sp_extra " "release: only vanilla jokers in the solo pool"
    none "$r" "^mp_joker .* hidden=true" "release: no MP joker hidden"
    none "$r" "^mp_joker j_mp_[a-z_]+ mp_(mode_)?jokers " "release: no MP joker on an AI art atlas"
    want "$r" "mp_collection_jokers 2[0-9]" "release: MP jokers in the MP collection"
    for k in lilac seer tangerine cobalt gemini random; do
        want "$r" "mp_collection_deck b_mp_$k" "release: $k deck in the MP collection"
    done
    for n in Lilac Seer Tangerine Cobalt Gemini Random; do
        want "$r" "lobby_mp_deck $n Deck" "release: $n Deck in the lobby picker"
    done
    none "$r" "^back b_mp_[a-z]+ mp_decks " "release: no MP deck on the AI art atlas"
    want "$r" "default_mp_jokers true" "release: lobbies start with MP jokers"
    want "$r" "ranked_mp_jokers true" "release: ranked with MP jokers"
    want "$r" "lobby_toggle_shown true" "release: MP jokers toggle shown"
    echo "--- what the release build shows"
    grep -E "^(sp_jokers|mp_collection_|lobby_mp_|back .*omit=nil)" "$r" | sed 's/^/    /'
fi

if run dev 0; then
    d="$out/dev.txt"
    want "$d" "release false" "dev build detected"
    want "$d" "sp_jokers 150" "dev: 150 jokers in the solo pool"
    none "$d" "^mp_joker .* hidden=true" "dev: no MP joker hidden"
    want "$d" "lobby_toggle_shown true" "dev: MP jokers toggle shown"
    want "$d" "default_mp_jokers true" "dev: lobby default unchanged"
    if grep -q "^mp_collection_jokers 0$" "$d"; then echo "FAIL dev: MP collection lost its jokers"; fail=1; else echo "ok   dev: MP collection keeps its jokers"; fi
fi

exit $fail

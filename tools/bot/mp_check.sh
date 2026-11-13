#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="${MP_CHECK_OUT:-/root/chk}"
games="${MP_CHECK_GAMES:-5}"
procs="${MP_CHECK_PROCS:-2}"
level="${MP_CHECK_LEVEL:-easy}"
ante="${MP_CHECK_ANTE:-12}"
mkdir -p "$out"
cd "$repo"
[ "${MP_CHECK_ROLLS:-1000}" = 0 ] || luajit tools/bot/mp_check.lua rolls "${MP_CHECK_ROLLS:-1000}" > "$out/rolls.txt" 2>&1
for ((i = 0; i < procs; i++)); do
    if [ "${MP_CHECK_AB:-1}" = 1 ]; then
        env ${MP_CHECK_OLD_ENV:-MP_CHECK_BUDGET=fast MP_CHECK_NOCAP=1} luajit tools/bot/mp_check.lua games "$games" "$level" $((i * games + 1)) "$ante" > "$out/old_$i.txt" 2>&1 &
    fi
    luajit tools/bot/mp_check.lua games "$games" "$level" $((i * games + 1)) "$ante" > "$out/new_$i.txt" 2>&1 &
done
wait
echo finished > "$out/done"

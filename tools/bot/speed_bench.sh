#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
if [ -n "${SPEED_CPU_QUOTA:-}" ] && [ -z "${SPEED_INNER:-}" ]; then
    exec systemd-run --quiet --scope -p CPUQuota="$SPEED_CPU_QUOTA" env SPEED_INNER=1 bash "$here/speed_bench.sh"
fi
out="${SPEED_OUT:-/root/speed}"
games="${SPEED_GAMES:-10}"
procs="${SPEED_PROCS:-7}"
levels="${SPEED_LEVELS:-easy medium hard}"
mkdir -p "$out"
cd "$repo"
for level in $levels; do
    for ((i = 0; i < procs; i++)); do
        SPEED_TAG="P$i" luajit tools/bot/speed_bench.lua "$level" "$games" $((i * games + 1)) 8 > "$out/$level.$i.txt" 2>&1 &
    done
    wait
    grep -h '^RESULT' "$out/$level".*.txt
done | tee "$out/summary.txt"
echo finished > "$out/done"

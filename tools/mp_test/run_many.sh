#!/usr/bin/env bash
set -uo pipefail

usage() {
    echo "Usage: tools/mp_test/run_many.sh [matches (4)] [parallel (4)] [extra run.sh args]"
    echo "Runs several matches at once, each with its own port, out dir and scopes, then prints a combined summary."
    echo "Env: MP_TEST_PORT_BASE (37800) MP_TEST_MANY_OUT (tools/mp_test/out_many), plus everything run.sh reads."
    echo "At most 4 matches run at once (8 game instances)."
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
n="${1:-4}"
par="${2:-4}"
shift $(( $# > 2 ? 2 : $# ))
[ "$par" -gt 4 ] && par=4
[ "$par" -lt 1 ] && par=1
base="${MP_TEST_PORT_BASE:-37800}"
root="${MP_TEST_MANY_OUT:-$here/out_many}"
rm -rf "$root"
mkdir -p "$root"

pids=()
cleanup() {
    trap - EXIT INT TERM
    for p in "${pids[@]}"; do kill "$p" >/dev/null 2>&1; done
    for _ in $(seq 1 30); do
        alive=0
        for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
        [ "$alive" = 0 ] && break
        sleep 0.5
    done
    for p in "${pids[@]}"; do kill -9 "$p" >/dev/null 2>&1; done
    true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

t0=$(date +%s)
for ((i = 1; i <= n; i++)); do
    while [ "$(jobs -rp | wc -l)" -ge "$par" ]; do sleep 1; done
    name=$(printf "match%02d" "$i")
    MP_TEST_PORT=$((base + i)) MP_TEST_OUT="$root/$name" \
        bash "$here/run.sh" "$@" > "$root/$name.log" 2>&1 &
    pids+=($!)
    echo "[mp_test many] started $name on port $((base + i))"
    sleep 1
done
for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done
echo "[mp_test many] $n matches in $(( $(date +%s) - t0 )) s wall"
python3 "$here/summary.py" "$root" | tee "$root/summary.txt"

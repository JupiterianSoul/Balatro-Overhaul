#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
port="${BOT_LOAD_PORT:-37900}"
out="${BOT_LOAD_OUT:-$here/out_load}"
parties="${BOT_LOAD_PARTIES:-2}"
solo="${BOT_LOAD_SOLO:-1}"
read -r -a levels <<< "${BOT_LOAD_LEVELS:-easy easy}"
rm -rf "$out"
mkdir -p "$out"
bun_cmd=(bun)
command -v bun >/dev/null 2>&1 || bun_cmd=("$HOME/.bun/bin/bun")

(cd "$repo/server" && PORT="$port" LOG_LEVEL=DEBUG BOT_WORKERS="${BOT_WORKERS:-}" exec "${bun_cmd[@]}" run src/index.ts) > "$out/server.log" 2>&1 &
spid=$!
trap 'kill "$spid" 2>/dev/null' EXIT
for _ in $(seq 1 60); do
    grep -q "Balatro MP server on" "$out/server.log" 2>/dev/null && break
    sleep 0.5
done
grep -q "Balatro MP server on" "$out/server.log" || { echo "server failed"; tail -20 "$out/server.log"; exit 1; }

common=(MP_TEST_FLOW=ranked MP_TEST_EXTERNAL_SERVER=1 MP_TEST_PORT="$port" MP_TEST_TIMEOUT="${BOT_LOAD_TIMEOUT:-2400}")
pids=()
for ((i = 1; i <= parties; i++)); do
    env "${common[@]}" MP_TEST_PARTY=br MP_TEST_PARTY_N=1 MP_TEST_BOTS=7 MP_TEST_BOT_LEVEL="${levels[$(( (i - 1) % ${#levels[@]} ))]}" MP_TEST_PARTY_LIVES=4 \
        MP_TEST_PARTY_BLIND_SECONDS=180 MP_TEST_RESULT_WAIT="${BOT_LOAD_RESULT_WAIT:-1800}" \
        MP_TEST_OUT="$out/br$i" bash "$here/run.sh" > "$out/br$i.log" 2>&1 &
    pids+=($!)
    sleep 2
done
if [ "$solo" = 1 ]; then
    env "${common[@]}" MP_TEST_SOLO=1 MP_TEST_BOT_LEVEL="${BOT_LOAD_SOLO_LEVEL:-easy}" MP_TEST_RESULT_WAIT="${BOT_LOAD_RESULT_WAIT:-1800}" \
        MP_TEST_OUT="$out/solo" bash "$here/run.sh" > "$out/solo.log" 2>&1 &
    pids+=($!)
fi
for p in "${pids[@]}"; do wait "$p"; done
kill "$spid" 2>/dev/null
wait "$spid" 2>/dev/null
python3 "$here/bot_load_report.py" "$out/server.log" | tee "$out/report.txt"

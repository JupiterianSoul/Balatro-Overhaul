#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="${MP_TEST_OUT:-$REPO/tools/mp_test/out}/forge_room_mp"
PAYLOAD="${FORGE_ROOM_PAYLOAD:-${MENU_OUT:-$REPO/tools/menu_shots/out}/forge_room_payload.json}"
[ -s "$PAYLOAD" ] || { echo "no payload at $PAYLOAD: run tools/menu_shots/forge_room_flows.sh first"; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
SET="$(python3 -c 'import json,sys; print(json.dumps({"forge_room_on": True, "forge_room": {"raw": open(sys.argv[1]).read()}}))' "$PAYLOAD")"
ARGS=(--no-rematch)
MP_TEST_OUT="$OUT/mp" MP_TEST_SETTINGS="$SET" MP_TEST_TIMEOUT="${MP_TEST_TIMEOUT:-900}" bash "$REPO/tools/mp_test/run.sh" "${ARGS[@]}" > "$OUT/run.txt" 2>&1
rm -rf "$OUT/mp/stage"
R="$OUT/mp/report.txt"
h=$(grep -h "\[FORGE\] room on" "$OUT/mp/host/stdout.log" 2>/dev/null | tail -1)
g=$(grep -h "\[FORGE\] room on" "$OUT/mp/guest/stdout.log" 2>/dev/null | tail -1)
echo "host:  ${h:-no room}"
echo "guest: ${g:-no room}"
grep -h "total steps\|^desyncs" "$R" 2>/dev/null
ok=1
[ -n "$h" ] && [ "$h" = "$g" ] && echo "CHECK same room on host and guest: OK" || { echo "CHECK same room on host and guest: FAIL"; ok=0; }
grep -q "^desyncs: 0" "$R" && echo "CHECK no desync: OK" || { echo "CHECK no desync: FAIL"; ok=0; }
grep -q "failures: 0" "$R" && echo "CHECK match steps: OK" || { echo "CHECK match steps: FAIL"; ok=0; }
sed -n '/== LUA ERRORS ==/,/^$/p' "$R" | grep -q "^none" && echo "CHECK no Lua error: OK" || { echo "CHECK no Lua error: FAIL"; ok=0; }
off_h=$(grep -c "\[FORGE\] room off" "$OUT/mp/host/stdout.log" 2>/dev/null)
echo "room off lines: host ${off_h:-0}"
[ "$ok" = 1 ] && echo "MP ROOM ALL OK" || echo "MP ROOM FAILED"

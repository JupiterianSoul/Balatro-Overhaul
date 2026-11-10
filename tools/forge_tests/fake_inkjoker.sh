#!/usr/bin/env bash
MODE="${FAKE_INKJOKER_MODE:-success}"
STATE="${FAKE_INKJOKER_STATE:-/tmp/fake_inkjoker_state}"
mkdir -p "$STATE"
[ -f "$STATE/mode" ] && MODE="$(cat "$STATE/mode")"
echo "$*" >> "$STATE/calls.log"
cmd="$1"; shift
polls() { cat "$STATE/polls" 2>/dev/null || echo 0; }
case "$cmd" in
  status)
    if [ "$MODE" = busy ]; then echo '{"gpu_busy": "inkjoker-train.service", "jobs": []}'; else echo '{"gpu_busy": null, "jobs": []}'; fi ;;
  generate)
    count=1
    while [ $# -gt 0 ]; do [ "$1" = --count ] && count="$2"; shift; done
    echo "$count" > "$STATE/count"; echo 0 > "$STATE/polls"; rm -f "$STATE/cancelled"
    if [ "$MODE" = failure_start ]; then echo '{"status": "no_model", "kind": "joker"}'; exit 2; fi
    if [ "$MODE" = busy ]; then echo '{"job": 41, "status": "queued", "note": "waiting for inkjoker-train.service"}'; else echo '{"job": 41, "status": "queued", "note": null}'; fi ;;
  job)
    n=$(( $(polls) + 1 )); echo "$n" > "$STATE/polls"
    count=$(cat "$STATE/count" 2>/dev/null || echo 1)
    if [ -f "$STATE/cancelled" ]; then echo '{"job": 41, "status": "cancelled", "done": 0, "count": '"$count"', "cards": []}'; exit 1; fi
    case "$MODE" in
      busy) echo '{"job": 41, "status": "queued", "note": "waiting for inkjoker-train.service", "done": 0, "count": '"$count"', "step": 0, "steps": 0, "cards": []}' ;;
      failure) if [ "$n" -lt 2 ]; then echo '{"job": 41, "status": "running", "done": 0, "count": '"$count"', "step": 3, "steps": 20, "cards": []}'; else echo '{"job": 41, "status": "error", "error": "CUDA out of memory", "done": 0, "count": '"$count"', "cards": []}'; exit 1; fi ;;
      *)
        need=2; [ "$MODE" = slow ] && need=999
        if [ "$n" -lt "$need" ]; then
          echo '{"job": 41, "status": "running", "done": 0, "count": '"$count"', "step": '"$((n * 6))"', "steps": 20, "cards": []}'
        else
          cards=""
          for i in $(seq 1 "$count"); do cards="$cards${cards:+,}{\"key\": \"generated/raw/fake_$i.png\", \"seed\": $i}"; done
          echo '{"job": 41, "status": "done", "done": '"$count"', "count": '"$count"', "step": 20, "steps": 20, "cards": ['"$cards"']}'
        fi ;;
    esac ;;
  cancel)
    touch "$STATE/cancelled"; echo '{"job": '"$1"', "cancelled": true}' ;;
  export)
    key="$1"; out=""
    while [ $# -gt 0 ]; do [ "$1" = --out ] && out="$2"; shift; done
    i=$(echo "$key" | grep -o '[0-9]\+' | tail -1)
    src="${FAKE_INKJOKER_ART:-}/$(( (i - 1) % 4 + 1 )).png"
    mkdir -p "$(dirname "$out")"; cp "$src" "$out" && echo '{"key": "'"$key"'", "file": "'"$out"'"}' ;;
  *) echo '{"status": "unknown"}'; exit 2 ;;
esac

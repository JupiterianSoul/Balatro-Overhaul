#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="${DH_OUT:-$root/.night/drift_hunt}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
jobs="${DH_JOBS:-3}"
reps="${DH_REPS:-1}"
sp_modes="${DH_SP-solo seeded challenge custom daily}"
mp_scen="${DH_MP-nemesis raid teams_bots br_bots}"
port="${DH_PORT:-${MP_TEST_PORT:-37731}}"

usage() {
    echo "Usage: tools/replay/drift_hunt.sh"
    echo "Bots record runs and matches, then watch them back, and the hunter lists the first hand where a playback left the recording."
    echo "SP runs go through tools/replay/sp_modes_full.sh (record and watch in two launches), MP matches through tools/mp_test/replay_check.sh."
    echo "Env: DH_SP ($sp_modes) DH_MP ($mp_scen) DH_REPS ($reps) DH_JOBS ($jobs) DH_PORT (first port, one per job) DH_ANTE (0 = play to the end) DH_OUT ($out)"
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

mkdir -p "$out"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$out/xdg}"
tasks=()
for r in $(seq 1 "$reps"); do
    for m in $sp_modes; do tasks+=("sp $m $r"); done
    for s in $mp_scen; do tasks+=("mp $s $r"); done
done

run_task() {
    local kind=$1 name=$2 r=$3 p=$4
    if [ "$kind" = sp ]; then
        SPM_MODES="$name" SPM_TAG="_dh$r" SPM_SEED="DH${r}SEED" SPM_OUT="$out/sp_${name}_$r" SPM_ANTE="${DH_ANTE:-0}" \
            bash "$here/sp_modes_full.sh" > "$out/sp_${name}_$r.log" 2>&1
    else
        MP_TEST_PORT="$p" REPLAY_CHECK_OUT="$out/mp_${name}_$r" bash "$root/tools/mp_test/replay_check.sh" "$name" > "$out/mp_${name}_$r.log" 2>&1
    fi
}

worker() {
    local w=$1 i
    sleep $((w * 8))
    for ((i = w; i < ${#tasks[@]}; i += jobs)); do
        read -r kind name r <<< "${tasks[$i]}"
        echo "[drift_hunt] $(date +%T) start $kind $name $r"
        run_task "$kind" "$name" "$r" $((port + w))
        echo "[drift_hunt] $(date +%T) done $kind $name $r"
    done
}

for ((w = 0; w < jobs; w++)); do worker "$w" & done
wait

summary="$out/summary.txt"
python3 - "$out" "$reps" "$sp_modes" "$mp_scen" > "$summary" <<'PY'
import os, re, sys
out, reps, sp, mp = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(), sys.argv[4].split()
rows, drifts, diffs, clean, missing = [], 0, 0, 0, 0
def verdict(drifted, resyncs):
    if drifted not in ('nil', 'false', ''):
        return 'DRIFT'
    return 'RESYNC' if resyncs not in ('0', 'nil', '') else 'clean'
for r in range(1, reps + 1):
    for m in sp:
        log = os.path.join(out, 'sp_%s_%d.log' % (m, r))
        txt = open(log, errors='replace').read() if os.path.exists(log) else ''
        pb = re.search(r'PLAYBACK (\S+) done (\S+) drifted (\S+) why (\S+) info (.*?) at (\S+) (\S+) resyncs (\S+) first (.*)', txt)
        same = ('PASS %s' % m) in txt
        if not pb:
            rows.append('sp %-12s %d  MISSING  no playback line (see %s)' % (m, r, log)); missing += 1; continue
        v = verdict(pb.group(3), pb.group(8))
        if v == 'clean' and not same: v = 'DRIFT'
        if v == 'DRIFT': drifts += 1
        elif v == 'RESYNC': diffs += 1
        else: clean += 1
        rows.append('sp %-12s %d  %-7s at %s/%s why=%s resyncs=%s first=%s end_same=%s info=%s' % (m, r, v, pb.group(6), pb.group(7), pb.group(4), pb.group(8), pb.group(9).strip(), same, pb.group(5)[:160]))
    for s in mp:
        rep = os.path.join(out, 'mp_%s_%d' % (s, r), s, 'report.txt')
        txt = open(rep, errors='replace').read() if os.path.exists(rep) else ''
        found = False
        for line in txt.splitlines():
            mm = re.search(r'(PASS|FAIL) replay_playback_(\S+)\s+\(drifted=(\S+) why=(\S+) info=(.*?) at=(\S+) ante=(\S+) resyncs=(\S+) first=(.*)\)$', line)
            if not mm: continue
            found = True
            v = verdict(mm.group(3), mm.group(8))
            if mm.group(1) == 'FAIL' and v != 'DRIFT': v = 'DRIFT'
            if v == 'DRIFT': drifts += 1
            elif v == 'RESYNC': diffs += 1
            else: clean += 1
            rows.append('mp %-12s %d  %-7s %s at %s ante=%s why=%s resyncs=%s first=%s info=%s' % (s, r, v, mm.group(2), mm.group(6), mm.group(7), mm.group(4), mm.group(8), mm.group(9), mm.group(5)[:160]))
        for line in txt.splitlines():
            if 'FAIL replay_no_live_ui' in line:
                rows.append('mp %-12s %d  LIVE_UI %s' % (s, r, line.split('FAIL ', 1)[1][:160]))
                drifts += 1
        if not found:
            rows.append('mp %-12s %d  MISSING  no playback result (see %s)' % (s, r, rep)); missing += 1
print('drift hunt: %d clean, %d resynced (differed, fixed by the hand checkpoint), %d drifted, %d missing' % (clean, diffs, drifts, missing))
for row in rows: print(row)
PY
cat "$summary"
grep -q " 0 drifted, 0 missing" "$summary"

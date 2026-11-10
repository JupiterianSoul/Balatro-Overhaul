import re
import sys
from datetime import datetime
from collections import defaultdict

ts_re = re.compile(r"^(\d{4}-\d\d-\d\dT[\d:.]+)Z")
call_re = re.compile(r"\[DEBUG\]\[BOT\] (\S+) (\S*) (\S+) (\w+) cpu=(\d+)ms worker=(\d+)ms wait=(\d+)ms queue=(\d+)")
pool_re = re.compile(r"\[DEBUG\]\[BOT\] pool (.*)")


def pct(v, q):
    if not v:
        return 0
    v = sorted(v)
    return v[min(len(v) - 1, max(0, int(round(q * len(v) + 0.5)) - 1))]


def main(path):
    cpu, wait = defaultdict(list), defaultdict(list)
    by_party = defaultdict(list)
    span = {}
    pools = []
    counts = defaultdict(int)
    lines = open(path, errors="replace").read().splitlines()
    for line in lines:
        m = call_re.search(line)
        if m:
            step = m.group(4)
            cpu[step].append(int(m.group(5)))
            wait[step].append(int(m.group(7)))
            by_party[(m.group(2), step)].append(int(m.group(5)))
            ts = ts_re.match(line)
            if ts:
                sec = datetime.fromisoformat(ts.group(1)).timestamp()
                lo, hi, tot = span.get(m.group(2), (sec, sec, 0))
                span[m.group(2)] = (min(lo, sec), max(hi, sec), tot + int(m.group(5)))
            continue
        m = pool_re.search(line)
        if m:
            pools.append(m.group(1))
            continue
        for key in ("Ready timeout", "Blind timeout", "Match over", "RANKED", "recorded", "worker exited", "worker failed"):
            if key in line:
                counts[key] += 1
    for step in sorted(cpu):
        c, w = cpu[step], wait[step]
        print(f"{step:8s} n={len(c):4d} cpu mean={sum(c)/len(c):6.0f} p50={pct(c,.5):6d} p95={pct(c,.95):6d} max={max(c):6d}"
              f" | wait mean={sum(w)/len(w):6.0f} p95={pct(w,.95):6d} max={max(w):6d}")
    for (party, step) in sorted(by_party):
        c = by_party[(party, step)]
        if step in ("advance", "hand"):
            print(f"party {party:6s} {step:8s} n={len(c):4d} cpu mean={sum(c)/len(c):6.0f} p95={pct(c,.95):6d} max={max(c):6d}")
    for party in sorted(span):
        lo, hi, tot = span[party]
        if hi > lo:
            print(f"party {party:6s} bot cpu={tot/1000:.0f}s over {(hi-lo)/60:.1f} min = {tot/1000/(hi-lo):.2f} cores")
    busy = defaultdict(list)
    for p in pools:
        for part in p.split(" | "):
            m = re.match(r"w(\d+) bots=(\d+)(?: load=\d+)? busy=(\d+)% cpu=(\d+)%", part)
            if m and int(m.group(2)) > 0:
                busy[int(m.group(1))].append(int(m.group(3)))
    for w in sorted(busy):
        b = busy[w]
        print(f"worker {w}: busy per minute mean={sum(b)/len(b):.0f}% max={max(b)}% minutes={len(b)}")
    for k in ("Ready timeout", "Blind timeout", "Match over", "RANKED", "recorded", "worker exited", "worker failed"):
        print(f"{k}: {counts[k]}")


main(sys.argv[1])

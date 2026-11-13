import json
import os
import re
import sys

root = sys.argv[1]
SECTIONS = ("BUGS FLAGGED BY THE DRIVER", "LUA ERRORS", "MP WARNINGS (client mp_log.warn)", "SERVER ERRORS AND WARNINGS")


def section_lines(text, name):
    m = re.search(r"^== " + re.escape(name) + r" ==\n(.*?)(?=^== |\Z)", text, re.S | re.M)
    if not m:
        return None
    body = [ln for ln in m.group(1).splitlines() if ln.strip()]
    if body == ["none"]:
        return []
    return body


def desync_lines(text):
    m = re.search(r"^== DESYNC CHECK ==\n(.*?)(?=^== |\Z)", text, re.S | re.M)
    if not m:
        return []
    return [ln for ln in m.group(1).splitlines() if ln.startswith("DESYNC")]


rows = []
for name in sorted(os.listdir(root)):
    d = os.path.join(root, name)
    rp = os.path.join(d, "report.txt")
    if not os.path.isdir(d) or not os.path.exists(rp):
        continue
    with open(rp, encoding="utf-8", errors="replace") as f:
        text = f.read()
    secs = None
    sp = os.path.join(d, "shared", "runner_stats.json")
    if os.path.exists(sp):
        try:
            with open(sp) as f:
                secs = json.load(f).get("seconds")
        except Exception:
            pass
    m = re.search(r"total steps: (\d+), failures: (\d+)", text)
    steps, fails = (int(m.group(1)), int(m.group(2))) if m else (0, -1)
    m = re.search(r"desyncs: (\d+)", text)
    desyncs = int(m.group(1)) if m else -1
    m = re.search(r"final host: .*?result=(\S+)", text)
    result = m.group(1) if m else "?"
    sec = {s: section_lines(text, s) for s in SECTIONS}
    timeout = "runner hit the overall timeout" in text
    ok = fails == 0 and desyncs == 0 and not timeout and steps > 0 and all(v == [] for k, v in sec.items() if k != "MP WARNINGS (client mp_log.warn)")
    rows.append((name, ok, secs, steps, fails, desyncs, result, sec, timeout, desync_lines(text)))

print("MP TEST SUMMARY  " + root)
print(f"{'match':<10} {'result':<6} {'secs':>5} {'steps':>5} {'fail':>4} {'desync':>6} {'bugs':>4} {'luaerr':>6} {'warn':>4} {'srv':>4}  host")
for name, ok, secs, steps, fails, desyncs, result, sec, timeout, dl in rows:
    def n(k):
        v = sec[k]
        return "?" if v is None else str(len(v))
    print(f"{name:<10} {'PASS' if ok else 'FAIL':<6} {str(secs):>5} {steps:>5} {fails:>4} {desyncs:>6} {n(SECTIONS[0]):>4} {n(SECTIONS[1]):>6} {n(SECTIONS[2]):>4} {n(SECTIONS[3]):>4}  {result}{'  TIMEOUT' if timeout else ''}")
passed = sum(1 for r in rows if r[1])
times = [r[2] for r in rows if isinstance(r[2], (int, float))]
print("")
print(f"matches: {len(rows)}  passed: {passed}  failed: {len(rows) - passed}" + (f"  seconds per match avg {sum(times) / len(times):.1f} min {min(times)} max {max(times)}" if times else ""))
for name, ok, secs, steps, fails, desyncs, result, sec, timeout, dl in rows:
    if ok:
        continue
    print("")
    print(f"-- {name}")
    for ln in [x for x in open(os.path.join(root, name, "report.txt"), encoding="utf-8", errors="replace").read().splitlines() if "] FAIL " in x][:10]:
        print("   " + ln[:240])
    for ln in dl[:10]:
        print("   " + ln[:240])
    for k in SECTIONS:
        for ln in (sec[k] or [])[:8]:
            print(f"   [{k.split(' ')[0].lower()}] " + ln[:240])

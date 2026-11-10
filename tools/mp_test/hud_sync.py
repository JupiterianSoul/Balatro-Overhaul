import json
import os
import re
import sys

ROW = re.compile(r'^(?P<name>[^=]+)=(?P<score>[^/]*)/(?P<h>[^/]*)/(?P<d>[^*@]*)(?P<me>\*?)@(?P<st>.*):(?P<blind>[^:]*)$')
MAX_DELAY = float(os.environ.get("HUD_SYNC_MAX_DELAY", "5"))
STATUS_GRACE = float(os.environ.get("HUD_SYNC_STATUS_GRACE", "6"))


def parse_rows(text):
    pieces, out = text.split(","), []
    cur = None
    for p in pieces:
        cur = p if cur is None else cur + "," + p
        m = ROW.match(cur)
        if m:
            out.append(m.groupdict())
            cur = None
    return out


def load(path):
    recs = []
    with open(path, errors="replace") as f:
        for line in f:
            if '"what":"hud"' not in line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            m = re.search(r" rows=(.*?)(?= [a-z_]+=|$)", o.get("line", ""))
            if not m:
                continue
            recs.append((float(o["t"]), parse_rows(m.group(1))))
    recs.sort(key=lambda r: r[0])
    return recs


def own_series(recs):
    series = {}
    for t, rows in recs:
        for r in rows:
            if r["me"]:
                series.setdefault(r["name"], []).append((t, (r["score"], r["h"], r["d"]), r["blind"], r["st"]))
    return series


def view(rows, name):
    for r in rows:
        if r["name"] == name:
            return r
    return None


def check(shared, roles):
    logs = {}
    for role in roles:
        p = os.path.join(shared, role + "_events.jsonl")
        if os.path.exists(p):
            logs[role] = load(p)
    owners = {}
    for role, recs in logs.items():
        for name, s in own_series(recs).items():
            owners[name] = (role, s)
    changes = checked = late = lost = 0
    worst = 0.0
    problems = []
    status_bad = 0
    for name, (orole, s) in owners.items():
        segs, cur = [], []
        for x in s:
            if cur and (x[2] != cur[-1][2] or x[0] - cur[-1][0] > 2.5):
                segs.append(cur)
                cur = []
            cur.append(x)
        if cur:
            segs.append(cur)
        for seg in segs:
            seg_end = seg[-1][0]
            for i in range(1, len(seg)):
                t0, tup, blind, _ = seg[i]
                if seg[i - 1][1] == tup:
                    continue
                changes += 1
                later = {x[1] for x in seg[i:]}
                for role, recs in logs.items():
                    if role == orole:
                        continue
                    seen_at = None
                    observable = False
                    for t, rows in recs:
                        if t < t0 - 1.2:
                            continue
                        if t > seg_end + MAX_DELAY + 2:
                            break
                        r = view(rows, name)
                        if r is None or r["blind"] != blind:
                            continue
                        if t >= t0 + MAX_DELAY + 1:
                            observable = True
                        if (r["score"], r["h"], r["d"]) in later:
                            seen_at = t
                            break
                    if seen_at is None and not observable:
                        continue
                    checked += 1
                    if seen_at is None:
                        lost += 1
                        problems.append("LOST %s's %s/%s/%s (blind %s) never reached %s" % (name, tup[0], tup[1], tup[2], blind, role))
                        continue
                    d = max(0.0, seen_at - t0)
                    worst = max(worst, d)
                    if d > MAX_DELAY:
                        late += 1
                        problems.append("LATE %s's %s/%s/%s reached %s after %.1f s" % (name, tup[0], tup[1], tup[2], role, d))
    for role, recs in logs.items():
        bad_since = {}
        for t, rows in recs:
            for r in rows:
                if r["me"] or r["name"] not in owners:
                    continue
                orole, s = owners[r["name"]]
                near = [x for x in s if abs(x[0] - t) <= 1.5]
                if not near:
                    bad_since.pop(r["name"], None)
                    continue
                own_st = near[-1][3]
                if r["blind"] == near[-1][2] and r["st"] != own_st and own_st not in ("nil", "") and r["st"] not in ("nil", ""):
                    bad_since.setdefault(r["name"], (t, r["st"], own_st))
                    since = bad_since[r["name"]]
                    if t - since[0] > STATUS_GRACE:
                        status_bad += 1
                        problems.append("STATUS %s sees %s as '%s' while %s says '%s' for %.0f s" % (role, r["name"], since[1], orole, since[2], t - since[0]))
                        bad_since[r["name"]] = (t + 1e9, since[1], since[2])
                else:
                    bad_since.pop(r["name"], None)
    ok = checked > 0 and late == 0 and lost == 0 and status_bad == 0
    print("hud_sync: players=%d changes=%d checked=%d late=%d lost=%d worst_delay=%.1fs status_mismatch=%d -> %s" % (
        len(owners), changes, checked, late, lost, worst, status_bad, "PASS" if ok else "FAIL"))
    for p in problems[:40]:
        print("  " + p)
    return ok


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: hud_sync.py <MP_TEST_OUT>/shared [roles...]  (needs MP_TEST_HUD=1)")
        sys.exit(2)
    roles = sys.argv[2:] or ["host", "guest"] + ["p%d" % i for i in range(2, 9)]
    sys.exit(0 if check(sys.argv[1], roles) else 1)

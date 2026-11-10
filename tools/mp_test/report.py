import json
import os
import re
import sys
from datetime import datetime

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "out")
ROLES = tuple(os.environ.get("MP_TEST_REPORT_ROLES", "host,guest").split(","))
PARTY_RUN = "guest" not in ROLES


def ts(t):
    try:
        return datetime.fromtimestamp(float(t)).strftime("%H:%M:%S.%f")[:-3]
    except Exception:
        return "??:??:??"


def load(role):
    path = os.path.join(out, "shared", f"{role}_events.jsonl")
    evs = []
    if not os.path.exists(path):
        return evs
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                evs.append(json.loads(line))
            except Exception:
                evs.append({"kind": "unparsable", "raw": line[:300], "t": 0})
    return evs


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


ev = {r: load(r) for r in ROLES}
from collections import defaultdict
ev = defaultdict(list, ev)
lines = []
p = lines.append

p("BALATRO OVERHAUL MULTIPLAYER TEST REPORT")
p(f"generated {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  out={out}")
p("")

p("== STEPS ==")
all_steps = []
for r in ROLES:
    for e in ev[r]:
        if e.get("kind") == "step":
            all_steps.append((e.get("t", 0), r, e))
all_steps.sort(key=lambda x: x[0])
fails = 0
for t, r, e in all_steps:
    ok = e.get("ok")
    if not ok:
        fails += 1
    p(f"{ts(t)} [{r:5}] {'PASS' if ok else 'FAIL'} {e.get('name')}" + (f"  ({e.get('detail')})" if e.get("detail") else ""))
for r in ROLES:
    if not any(e.get("kind") == "done" for e in ev[r]):
        p(f"-- [{r}] driver never reached 'done' (killed, crashed or timed out)")
        fails += 1
if os.path.exists(os.path.join(out, "shared", "runner_events.jsonl")):
    caps = [json.loads(x).get("cap") for x in open(os.path.join(out, "shared", "runner_events.jsonl")) if x.strip()]
    p(f"-- runner hit the overall timeout (hard cap {caps[-1] if caps else '?'} s), match counts as FAIL")
p(f"total steps: {len(all_steps)}, failures: {fails}")
p("")

p("== BUGS FLAGGED BY THE DRIVER ==")
nb = 0
for r in ROLES:
    for e in ev[r]:
        if e.get("kind") in ("bug", "workaround"):
            nb += 1
            p(f"{ts(e.get('t'))} [{r:5}] {e.get('kind').upper()} {e.get('name') or e.get('what')}: {e.get('detail') or e.get('tag') or ''}")
if nb == 0:
    p("none")
p("")

p("== DESYNC CHECK ==")


def sync_points(role):
    res = {}
    for e in ev[role]:
        if e.get("kind") == "sync_point":
            snap = dict(e.get("snap") or {})
            if snap.get("pending_lives") is not None:
                snap["my_lives"] = snap["pending_lives"]
            res.setdefault(e.get("tag"), []).append(snap)
    return res


def own_room(role):
    for e in ev[role]:
        if e.get("kind") == "step" and str(e.get("name", "")).endswith("_room_created"):
            return e.get("detail")
    return None


SEPARATE_ROOMS = not PARTY_RUN and own_room("host") is not None and own_room("guest") is not None and own_room("host") != own_room("guest")
sp = {r: sync_points(r) for r in ROLES}
desyncs = 0
if SEPARATE_ROOMS:
    p("host and guest each played their own room, lives are not compared between them")
PAIRED = ("settled_start_blind", "settled_pvp_resolved", "settled_pvp_result")
tags = [] if PARTY_RUN or SEPARATE_ROOMS else [t for t in sorted(set(sp["host"]) | set(sp["guest"])) if t in PAIRED]
for tag in tags:
    h, g = sp["host"].get(tag, []), sp["guest"].get(tag, [])
    if len(h) != len(g):
        desyncs += 1
        p(f"DESYNC count {tag}: host saw {len(h)}, guest saw {len(g)}")
    for i in range(min(len(h), len(g))):
        a, b = h[i], g[i]
        diffs = []
        if a.get("my_lives") != b.get("opp_lives"):
            diffs.append(f"host.my_lives={a.get('my_lives')} vs guest.opp_lives={b.get('opp_lives')}")
        if a.get("opp_lives") != b.get("my_lives"):
            diffs.append(f"host.opp_lives={a.get('opp_lives')} vs guest.my_lives={b.get('my_lives')}")
        over = a.get("phase") == "match_end" and b.get("phase") == "match_end"
        if a.get("ante") != b.get("ante") and not over and tag in ("settled_start_blind", "settled_pvp_resolved", "settled_pvp_result"):
            diffs.append(f"ante host={a.get('ante')} guest={b.get('ante')}")
        if a.get("m_ante") != b.get("m_ante") and tag in ("settled_start_blind",):
            diffs.append(f"match.current_ante host={a.get('m_ante')} guest={b.get('m_ante')}")
        if a.get("phase") != b.get("phase"):
            diffs.append(f"phase host={a.get('phase')} guest={b.get('phase')}")
        if tag in ("settled_pvp_resolved", "settled_pvp_result"):
            if a.get("my_score") != b.get("opp_score") or a.get("opp_score") != b.get("my_score"):
                diffs.append(f"scores host my/opp={a.get('my_score')}/{a.get('opp_score')} guest my/opp={b.get('my_score')}/{b.get('opp_score')}")
        if diffs:
            desyncs += 1
            p(f"DESYNC {tag} #{i + 1}: " + "; ".join(diffs))
        else:
            p(f"ok     {tag} #{i + 1}: lives host {a.get('my_lives')}/{a.get('opp_lives')} guest {b.get('my_lives')}/{b.get('opp_lives')} ante {a.get('ante')}/{b.get('ante')} phase {a.get('phase')}")


def last_snap(role, tag=None):
    for e in reversed(ev[role]):
        if e.get("kind") == "snap" and (tag is None or e.get("tag") == tag):
            return e
    return {}


fh, fg = last_snap("host", "final"), last_snap("guest", "final")
if fh and fg and not SEPARATE_ROOMS:
    p(f"final host: state={fh.get('state')} phase={fh.get('phase')} lives {fh.get('my_lives')}/{fh.get('opp_lives')} ante={fh.get('ante')} result={fh.get('match_result')}")
    p(f"final guest: state={fg.get('state')} phase={fg.get('phase')} lives {fg.get('my_lives')}/{fg.get('opp_lives')} ante={fg.get('ante')} result={fg.get('match_result')}")
    if fh.get("my_lives") != fg.get("opp_lives") or fh.get("opp_lives") != fg.get("my_lives"):
        desyncs += 1
        p("DESYNC final client lives differ between clients")
    pair = {fh.get("match_result"), fg.get("match_result")}
    if fh.get("match_result") or fg.get("match_result"):
        if pair != {"win", "lose"} and pair != {"draw"}:
            desyncs += 1
            p(f"DESYNC match results host={fh.get('match_result')} guest={fg.get('match_result')}")


def server_lives(role):
    last = None
    for e in ev[role]:
        if e.get("kind") == "dispatch" and e.get("type") in ("lobby_returned", "opponent_returned_to_lobby"):
            break
        if e.get("kind") == "dispatch" and e.get("type") == "match_state_update":
            d = e.get("data") or {}
            if d.get("event") == "rematch_started":
                break
            if d.get("myLives") is not None:
                last = (d.get("myLives"), d.get("oppLives"), d.get("event"))
    return last


sh, sg = server_lives("host"), server_lives("guest")
if sh and sg:
    p(f"last server lives before rematch: host {sh[0]}/{sh[1]} ({sh[2]}), guest {sg[0]}/{sg[1]} ({sg[2]})")
    if not SEPARATE_ROOMS and (sh[0] != sg[1] or sh[1] != sg[0]):
        desyncs += 1
        p("DESYNC server pushed different lives to the two clients")
    for role, srvl, fs in (("host", sh, fh), ("guest", sg, fg)):
        if fs and fs.get("phase") in (None, "none") and fs.get("state") == "MENU":
            p(f"skip   {role} ended on the main menu (the match state is cleared there)")
            continue
        if fs and fs.get("phase") in (None, "none") and srvl[2] == "ascension_resolved":
            p(f"skip   {role} match resolved by the server (draw), the client left the match")
            continue
        if fs and (fs.get("my_lives") != srvl[0] or fs.get("opp_lives") != srvl[1]):
            desyncs += 1
            p(f"DESYNC {role} client shows lives {fs.get('my_lives')}/{fs.get('opp_lives')} but server last sent {srvl[0]}/{srvl[1]}")
swaps = {r: [e for e in ev[r] if e.get("kind") == "swap"] for r in ROLES} if not PARTY_RUN else {}
if any(swaps.values()):
    def by(role, d):
        return {e.get("round"): e for e in swaps.get(role, []) if e.get("dir") == d}
    rounds = sorted(set(by("host", "out")) | set(by("guest", "out")))
    p(f"swaps: {len(rounds)}")
    for rnd in rounds:
        for a, b in (("host", "guest"), ("guest", "host")):
            out_e, in_e, ld = by(a, "out").get(rnd), by(b, "in").get(rnd), by(b, "loaded").get(rnd)
            if ld and ld.get("restored") and not in_e:
                in_e = {"hash": out_e.get("hash") if out_e else None}
            exit_t = [e.get("t") for e in ev[b] if e.get("kind") == "snap" and e.get("tag") == "driver_exit"]
            if out_e and in_e and not ld and exit_t and 0 <= float(exit_t[-1]) - float(in_e.get("t") or 0) < 2:
                p(f"cut    swap {rnd} {a}->{b}: the test ended while the run was loading")
                continue
            if out_e and not in_e and not ld and exit_t and abs(float(exit_t[-1]) - float(out_e.get("t") or 0)) < 2:
                p(f"cut    swap {rnd} {a}->{b}: the test ended while the run was on its way")
                continue
            if not (out_e and in_e and ld):
                desyncs += 1
                p(f"DESYNC swap {rnd} {a}->{b}: out={bool(out_e)} in={bool(in_e)} loaded={bool(ld)}")
                continue
            bad = []
            if out_e.get("hash") != in_e.get("hash"):
                bad.append(f"hash {out_e.get('hash')} vs {in_e.get('hash')}")
            if out_e.get("sig") != ld.get("sig"):
                fo, fl = out_e.get("facts") or {}, ld.get("facts") or {}
                bad.append("state " + ", ".join(f"{k} {fo.get(k)}/{fl.get(k)}" for k in sorted(set(fo) | set(fl)) if fo.get(k) != fl.get(k) and k != "shop"))
            ck = by(b, "check").get(rnd)
            if ck and ck.get("error"):
                bad.append(f"field check failed to run: {ck.get('error')}")
            elif ck and (ck.get("diffs") or 0) > 0:
                lst = ck.get("list") or []
                if isinstance(lst, dict):
                    lst = [lst[k] for k in sorted(lst, key=lambda x: int(x) if str(x).isdigit() else 0) if str(k).isdigit()]
                bad.append(f"{ck.get('diffs')} of {ck.get('fields')} fields differ: " + "; ".join(str(x) for x in lst))
            if bad:
                desyncs += 1
                p(f"DESYNC swap {rnd} {a}->{b}: " + "; ".join(bad))
            else:
                f = out_e.get("facts") or {}
                fc = f"fields {ck.get('fields')} same" if ck else "fields not checked"
                p(f"ok     swap {rnd} {a}->{b}: hash {out_e.get('hash')} ante {f.get('ante')} ${f.get('dollars')} deck {f.get('deck')} {f.get('back')} jokers [{f.get('jokers')}] {fc}")
BOT_SWAP = PARTY_RUN and any(e.get("kind") == "swap" and e.get("dir") == "loaded" and e.get("bot") for r in ROLES for e in ev[r])
if BOT_SWAP:
    for r in ROLES:
        sent = [e for e in ev[r] if e.get("type") == "swap_state" and e.get("kind") == "send"]
        mine = ((sent[0].get("data") or {}).get("facts") or {}).get("owner") if sent else None
        loads = [e for e in ev[r] if e.get("kind") == "swap" and e.get("dir") == "loaded" and not e.get("playback")]
        p(f"bot swaps ({r}): {len(loads)}, own run owner {mine}")
        for e in loads:
            rnd = e.get("round")
            got, want = e.get("sum") or {}, e.get("expect") or {}
            bad = [f"{k} {want.get(k)}/{got.get(k)}" for k in ("owner", "ante", "dollars", "deck", "jokers", "cons", "vouchers", "levels", "tags") if want.get(k) != got.get(k)]
            back = rnd is not None and rnd % 2 == 0
            if back and got.get("owner") != mine: bad.append(f"round {rnd} should give the own run back, owner {got.get('owner')}")
            if not back and got.get("owner") == mine: bad.append(f"round {rnd} gave the own run back instead of the bot's")
            if not e.get("bot"): bad.append("loaded without the bot run")
            if e.get("rdiff"): bad.append(f"{e.get('rdiff')} fields differ from the bot run: {e.get('rdiff_list')}")
            elif e.get("rdiff") is None: bad.append("no field check")
            if bad: p(f"DESYNC bot swap {rnd}: " + "; ".join(bad))
            else: p(f"ok     bot swap {rnd}: every field the same, owner {got.get('owner')} ante {got.get('ante')} ${got.get('dollars')} deck {got.get('deck')} jokers {got.get('jokers')} cons {got.get('cons')} vouchers {got.get('vouchers')} levels +{got.get('levels')} tags {got.get('tags')}")
if "guest" in ROLES or BOT_SWAP:
    for r in ROLES:
        for e in ev[r]:
            if e.get("kind") != "swap" or e.get("dir") != "banner":
                continue
            rnd = e.get("round")
            want = rnd is not None and rnd % 2 == 0
            tag = "playback " if e.get("playback") else ""
            if bool(e.get("own")) != want:
                desyncs += 1
                p(f"DESYNC {tag}banner swap {rnd} ({r}): '{e.get('text')}' owner {e.get('owner')} from {e.get('from')} me {e.get('me')}")
            else:
                p(f"ok     {tag}banner swap {rnd} ({r}): {e.get('text')}")
pswaps = {r: [e for e in ev[r] if e.get("kind") == "swap"] for r in ROLES} if PARTY_RUN and not BOT_SWAP else {}
if any(pswaps.values()):
    outs = {}
    for r in ROLES:
        for e in pswaps[r]:
            if e.get("dir") == "out":
                outs.setdefault((e.get("round"), e.get("hash")), []).append((r, e))
    rounds = sorted({e.get("round") for r in ROLES for e in pswaps[r] if e.get("round") is not None})
    p(f"party swaps: {len(rounds)}")
    for rnd in rounds:
        senders = sorted(r for r in ROLES if any(e.get("dir") == "out" and e.get("round") == rnd for e in pswaps[r]))
        takers = []
        for b in ROLES:
            in_e = next((e for e in pswaps[b] if e.get("dir") == "in" and e.get("round") == rnd), None)
            ld = next((e for e in pswaps[b] if e.get("dir") == "loaded" and e.get("round") == rnd), None)
            if not in_e and not ld:
                continue
            h = (in_e or {}).get("hash")
            src = outs.get((rnd, h), [])
            if ld and ld.get("restored") and not in_e:
                src = [(r, e) for (rr, hh), lst in outs.items() if rr == rnd for (r, e) in lst if e.get("sig") == ld.get("sig")]
            exit_t = [e.get("t") for e in ev[b] if e.get("kind") == "snap" and e.get("tag") == "driver_exit"]
            if in_e and not ld and exit_t and 0 <= float(exit_t[-1]) - float(in_e.get("t") or 0) < 2:
                p(f"cut    party swap {rnd} ->{b}: the test ended while the run was loading")
                continue
            if not (src and ld):
                desyncs += 1
                p(f"DESYNC party swap {rnd} ->{b}: sender={bool(src)} loaded={bool(ld)} hash={h}")
                continue
            a, out_e = src[0]
            takers.append(a)
            if a == b and len(senders) > 1:
                desyncs += 1
                p(f"DESYNC party swap {rnd} {a}->{b}: got its own run back")
                continue
            if out_e.get("sig") != ld.get("sig"):
                fo, fl = out_e.get("facts") or {}, ld.get("facts") or {}
                desyncs += 1
                p(f"DESYNC party swap {rnd} {a}->{b}: state " + ", ".join(f"{k} {fo.get(k)}/{fl.get(k)}" for k in sorted(set(fo) | set(fl)) if fo.get(k) != fl.get(k) and k != "shop"))
                continue
            ck = next((e for e in pswaps[b] if e.get("dir") == "check" and e.get("round") == rnd), None)
            if ck and (ck.get("error") or (ck.get("diffs") or 0) > 0):
                desyncs += 1
                lst = ck.get("list") or []
                if isinstance(lst, dict):
                    lst = list(lst.values())
                p(f"DESYNC party swap {rnd} {a}->{b}: " + (f"field check failed to run: {ck.get('error')}" if ck.get("error") else f"{ck.get('diffs')} of {ck.get('fields')} fields differ: " + "; ".join(str(x) for x in lst)))
                continue
            f = out_e.get("facts") or {}
            fc = f"fields {ck.get('fields')} same" if ck else "fields not checked"
            p(f"ok     party swap {rnd} {a}->{b}: hash {out_e.get('hash')} ante {f.get('ante')} ${f.get('dollars')} deck {f.get('deck')} {f.get('back')} jokers [{f.get('jokers')}] {fc}")
        if len(takers) != len(set(takers)):
            desyncs += 1
            p(f"DESYNC party swap {rnd}: one run went to two players ({', '.join(sorted(takers))})")
p(f"desyncs: {desyncs}")
p("")

capped = os.path.exists(os.path.join(out, "shared", "runner_events.jsonl"))
p("== LUA ERRORS ==")
nerr = 0
for r in ROLES:
    for e in ev[r]:
        if e.get("kind") in ("lua_error", "driver_error"):
            nerr += 1
            p(f"{ts(e.get('t'))} [{r:5}] {e.get('kind')}: {e.get('msg')}")
            if e.get("trace"):
                for tl in str(e.get("trace")).splitlines()[:25]:
                    p(f"        {tl}")
        elif e.get("kind") == "mp_log" and e.get("level") == "error":
            nerr += 1
            p(f"{ts(e.get('t'))} [{r:5}] mp_log.error [{e.get('tag')}] {e.get('msg')}")
    trace = read(os.path.join(out, r, "mp_error_trace.log"))
    if trace.strip():
        p(f"-- [{r}] mp_error_trace.log:")
        for tl in trace.splitlines()[:60]:
            p(f"        {tl}")
        nerr += 1
    dbg = read(os.path.join(out, r, "mp_match_debug.txt"))
    for dl in dbg.splitlines():
        if "ERROR" in dl:
            nerr += 1
            p(f"[{r:5}] mp_match_debug: {dl.strip()}")
    so = read(os.path.join(out, r, "stdout.log")).splitlines()
    for i, sl in enumerate(so):
        low = sl.lower()
        if "boot.lua" in low and "attempt to call a number value" in low:
            continue
        if low.startswith("xio:") and capped:
            continue
        if re.search(r"error loading game: card area 'shop_(jokers|vouchers|booster)' not instantiated before load", low):
            continue
        low = re.sub(r"xio:\s+fatal io error.*$", "", low)
        if ("error" in low or "traceback" in low) and "[mp_test" not in low and "[warn]" not in low:
            nerr += 1
            p(f"[{r:5}] stdout: {sl.strip()[:300]}")
if nerr == 0:
    p("none")
p("")

p("== MP WARNINGS (client mp_log.warn) ==")
nw = 0
for r in ROLES:
    seen = {}
    for e in ev[r]:
        if e.get("kind") == "mp_log" and e.get("level") == "warn":
            k = f"[{e.get('tag')}] {e.get('msg')}"
            seen.setdefault(k, [e.get("t"), 0])
            seen[k][1] += 1
    for k, (t, c) in seen.items():
        nw += 1
        p(f"{ts(t)} [{r:5}] x{c} {k}")
if nw == 0:
    p("none")
p("")

p("== SERVER ERRORS AND WARNINGS ==")
srv = read(os.path.join(out, "server.log")).splitlines()
ns = 0
for sl in srv:
    if re.search(r"\[(WARN|ERROR)\]", sl) or re.search(r"(TypeError|ReferenceError|Unhandled|uncaught|\bat .*\.ts:\d+)", sl):
        ns += 1
        p(sl[:400])
if ns == 0:
    p("none")
p("")

p("== SERVER PVP / MATCH LOG ==")
for sl in srv:
    if re.search(r"\[(PVP|MATCH|ROOM|LIVES|GAME)\]", sl):
        p(sl[:300])
p("")

p("== DISPATCH TIMELINE (incoming messages per client) ==")
for r in ROLES:
    counts = {}
    p(f"-- {r}")
    for e in ev[r]:
        if e.get("kind") == "dispatch":
            ty = e.get("type")
            counts[ty] = counts.get(ty, 0) + 1
            d = dict(e.get("data") or {})
            d.pop("type", None)
            body = json.dumps(d, separators=(",", ":"))
            if len(body) > 220:
                body = body[:220] + "..."
            p(f"{ts(e.get('t'))} {ty} {body}")
    p(f"counts: {json.dumps(counts, sort_keys=True)}")
    dbg = read(os.path.join(out, r, "mp_match_debug.txt"))
    n_dbg = dbg.count("[DISPATCH] type=")
    p(f"mp_match_debug.txt [DISPATCH] lines: {n_dbg}")
p("")

p("== OUTGOING MESSAGES PER CLIENT ==")
for r in ROLES:
    counts = {}
    for e in ev[r]:
        if e.get("kind") == "send":
            counts[e.get("type")] = counts.get(e.get("type"), 0) + 1
    p(f"{r}: {json.dumps(counts, sort_keys=True)}")
p("")

p("== ACTIONS AND STATES ==")
for r in ROLES:
    p(f"-- {r}")
    for e in ev[r]:
        k = e.get("kind")
        if k == "action":
            extra = {x: e[x] for x in e if x not in ("t", "el", "kind", "role", "what")}
            p(f"{ts(e.get('t'))} action {e.get('what')} {json.dumps(extra, separators=(',', ':'))}")
        elif k == "state":
            p(f"{ts(e.get('t'))} state {e.get('state')}")
        elif k == "snap" and e.get("tag") not in ("periodic",):
            p(f"{ts(e.get('t'))} snap {e.get('tag')}: state={e.get('state')} phase={e.get('phase')} lives={e.get('my_lives')}/{e.get('opp_lives')} ante={e.get('ante')} blind={e.get('blind_on_deck')}:{e.get('blind_name')} chips={e.get('chips')}/{e.get('blind_chips')}")

print("\n".join(lines))

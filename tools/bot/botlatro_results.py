import re
import sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "botlatro-sim-main" / "RESULTS.md")
out = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).resolve().parents[2] / "assets" / "bot" / "results.lua")
text = src.read_text()


def lua(v):
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    return "{" + ", ".join("%s = %s" % (k, lua(x)) for k, x in v.items()) + "}"


def section(title):
    m = re.search(r"^## " + re.escape(title) + r".*?$(.*?)(?=^## |\Z)", text, re.S | re.M)
    return m.group(1) if m else ""


def rows(block):
    out = []
    for line in block.splitlines():
        if line.startswith("|") and not re.match(r"^\|[-| ]+\|$", line):
            out.append([c.strip() for c in line.strip("|").split("|")])
    return out[1:] if out else []


def pct(s):
    m = re.search(r"([\d.]+)%", s)
    return float(m.group(1)) if m else None


def num(s):
    m = re.match(r"\s*(\d+)", s)
    return int(m.group(1)) if m else None


version = re.search(r"^# Results: (\S+)", text, re.M).group(1)
gold = section("Gold Stake, all 15 decks")
summary = re.search(r"\*\*(\d+) wins, ([\d.]+)% \(95% interval ([\d.]+)% to ([\d.]+)%\)", gold)
games = re.search(r"(\d+) games, [^\n]*?(\d+) per deck", gold)
decks = [{"deck": r[0], "games": num(r[1]), "wins": num(r[2]), "rate": pct(r[3]), "ante5": pct(r[4]), "ante8": pct(r[5]), "mean": float(r[6])}
         for r in rows(gold) if len(r) >= 7]
ladder_block = section("Every stake")
ladder_deck = re.search(r"Every stake, (\w+) deck", text)
ladder = [{"stake": re.sub(r"^\d+\s+", "", r[0]), "wins": num(r[1]), "rate": pct(r[2]), "ante8": pct(r[3])} for r in rows(ladder_block) if len(r) >= 4]
net = re.search(r"\*\*The net:\*\* (\S+) net was trained on (\d+) (?:of (\S+) own games|games of ([^(]+?)) \((\d+) decisions\)", text)
prev = re.search(r"(w\d+) won (\d+) of the same", gold)
data = {
    "version": version,
    "gold": {"games": int(games.group(1)) if games else None, "per_deck": int(games.group(2)) if games else None,
             "wins": int(summary.group(1)), "rate": float(summary.group(2)), "low": float(summary.group(3)), "high": float(summary.group(4)),
             "prev": prev.group(1) if prev else "", "prev_wins": int(prev.group(2)) if prev else 0},
    "decks": decks,
    "ladder_deck": ladder_deck.group(1) if ladder_deck else "Red",
    "ladder": ladder,
    "train": {"games": int(net.group(2)), "from": (net.group(3) or net.group(4)).strip(), "decisions": int(net.group(5))} if net else {},
}
assert data["decks"] and data["ladder"], "RESULTS.md tables not found"
out.write_text("return " + lua(data) + "\n")
print("%s: %s, Gold %s%% over %s games, %d decks, %d stakes" % (out, version, data["gold"]["rate"], data["gold"]["games"], len(decks), len(ladder)))

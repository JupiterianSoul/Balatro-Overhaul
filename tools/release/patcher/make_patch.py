#!/usr/bin/env python3
import argparse
import difflib
import hashlib
import io
import os
import re
import shutil
import sys
import zipfile

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
STEAM_EXE = os.path.expanduser("~/.local/share/Steam/steamapps/common/Balatro/Balatro.exe")
TEXT_EXT = {".lua", ".fs", ".vs", ".glsl", ".txt", ".md", ".json", ".jkr", ".csv", ".toml",
            ".cfg", ".ini", ".xml", ".html", ".css", ".js", ".ts", ".sh", ".py", ".yml", ".yaml"}
MIN_LINE = 20
FORMAT = 1
EDIT_FORMAT = 2
MIN_EDIT_RATIO = 0.75
MIN_CUT_RATIO = 0.5


def sha(data):
    return hashlib.sha256(data).hexdigest()


def glob_to_regex(pat):
    out = ""
    i = 0
    while i < len(pat):
        c = pat[i]
        if pat.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
            continue
        if pat.startswith("**", i):
            out += ".*"
            i += 2
            continue
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        else:
            out += re.escape(c)
        i += 1
    return out


def read_exclude(path):
    rules = []
    if not os.path.exists(path):
        return rules
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if line.startswith("assets/"):
                line = line[len("assets/"):]
            elif line == "assets":
                line = "**"
            if line.endswith("/"):
                rx = glob_to_regex(line) + ".*"
            else:
                rx = glob_to_regex(line) + "(?:/.*)?"
            rules.append((line, re.compile("^" + rx + "$")))
    return rules


def excluded(rel, rules):
    for _, rx in rules:
        if rx.match(rel):
            return True
    return False


def is_text(rel, data):
    return os.path.splitext(rel)[1].lower() in TEXT_EXT and b"\0" not in data


def split_lines(data):
    n_lf = data.count(b"\n")
    crlf = n_lf > 0 and data.count(b"\r\n") == n_lf
    sep = b"\r\n" if crlf else b"\n"
    final = data.endswith(sep)
    body = data[:-len(sep)] if final else data
    lines = body.split(sep) if (body or final) else []
    return lines, crlf, final


def line_hash(line):
    h = 0x811c9dc5
    for c in line:
        h = ((h ^ c) * 0x01000193) & 0xffffffff
    return h & 0xffffff


def join_lines(lines, crlf, final):
    sep = b"\r\n" if crlf else b"\n"
    out = sep.join(lines)
    if final:
        out += sep
    return out


def pct(s):
    return "".join("%%%02X" % b for b in s) or "-"


def lua_str(s):
    if isinstance(s, bytes):
        s = s.decode("utf-8")
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"' or ch == "\\":
            out.append("\\" + ch)
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_value(v, indent=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, (str, bytes)):
        return lua_str(v)
    if v is None:
        return "nil"
    inner = indent + "  "
    if isinstance(v, list):
        if not v:
            return "{}"
        return "{\n" + ",\n".join(inner + lua_value(x, inner) for x in v) + ",\n" + indent + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = []
        for k in sorted(v):
            parts.append(inner + k + " = " + lua_value(v[k], inner))
        return "{\n" + ",\n".join(parts) + ",\n" + indent + "}"
    raise TypeError(type(v))


class Vanilla:
    def __init__(self, path):
        self.path = path
        self.files = {}
        self.prefix = ""
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for fn in names:
                    full = os.path.join(root, fn)
                    with open(full, "rb") as f:
                        self.files[os.path.relpath(full, path).replace(os.sep, "/")] = f.read()
        else:
            self.zip = zipfile.ZipFile(path)
            names = set(self.zip.namelist())
            if "version.jkr" not in names and "assets/version.jkr" in names:
                self.prefix = "assets/"
            for info in self.zip.infolist():
                if info.is_dir() or not info.filename.startswith(self.prefix):
                    continue
                self.files[info.filename[len(self.prefix):]] = self.zip.read(info.filename)
        ver = self.files.get("version.jkr", b"").split(b"\n")[0].strip()
        self.version = ver.decode("utf-8", "replace")
        self.by_sha = {}
        for p in sorted(self.files):
            self.by_sha.setdefault(sha(self.files[p]), p)
        self.text = {}
        self.corpus = {}
        for p in sorted(self.files):
            data = self.files[p]
            if b"\0" in data:
                continue
            lines, _, _ = split_lines(data)
            self.text[p] = lines
            for i, line in enumerate(lines):
                key = line.strip()
                if len(key) > MIN_LINE and key not in self.corpus:
                    self.corpus[key] = (p, i + 1)


def edit_tokens(src, dst):
    sm = difflib.SequenceMatcher(None, src, dst, autojunk=False)
    toks = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            toks.append("=%d" % (i2 - i1))
            continue
        if i2 > i1:
            toks.append("-%d" % (i2 - i1))
        if j2 > j1:
            toks.append("+" + pct(dst[j1:j2]))
    return ",".join(toks)


class Builder:
    def __init__(self, vanilla, out, others=()):
        self.v = vanilla
        self.out = out
        self.others = list(others)
        self.used = {}
        self.left = []
        self.blob = None
        self.edited = False
        self.stats = {"keep": 0, "copy": 0, "own": 0, "patch": 0, "image": 0, "literal": 0, "refs": 0, "edits": 0}

    def other_hit(self, key):
        if len(key) <= MIN_LINE:
            return None
        for o in self.others:
            hit = o.corpus.get(key)
            if hit:
                return hit
        return None

    def inserts_known(self, cand, key, path):
        sm = difflib.SequenceMatcher(None, cand, key, autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if j2 > j1 and tag != "equal" and key[j1:j2] not in self.v.files[path] and key[j1:j2] not in self.vanilla_text():
                return False
        return True

    def vanilla_text(self):
        if self.blob is None:
            self.blob = b"\n".join(b"\n".join(lines) for _, lines in sorted(self.v.text.items()))
        return self.blob

    def closest(self, key, paths):
        close, cut = (MIN_EDIT_RATIO, None), (MIN_CUT_RATIO, None)
        seen = set()
        for p in paths:
            if p is None or p in seen or p not in self.v.text:
                continue
            seen.add(p)
            for i, line in enumerate(self.v.text[p]):
                cand = line.strip()
                if not cand:
                    continue
                sm = difflib.SequenceMatcher(None, cand, key, autojunk=False)
                floor = min(close[0], cut[0])
                if sm.real_quick_ratio() < floor or sm.quick_ratio() < floor:
                    continue
                r = sm.ratio()
                if r >= MIN_EDIT_RATIO:
                    if close[1] is None or r > close[0]:
                        close = (r, (p, i + 1, cand))
                elif r >= cut[0] and (cut[1] is None or r > cut[0]) and self.inserts_known(cand, key, p):
                    cut = (r, (p, i + 1, cand))
        return close[1] or cut[1]

    def use(self, p):
        if p not in self.used:
            self.used[p] = len(self.used) + 1
        return self.used[p]

    def write(self, rel, data):
        dst = os.path.join(self.out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)

    def literal_ops(self, lines, ops, rel=None, base=None):
        run = []
        for line in lines:
            key = line.strip()
            hit = self.v.corpus.get(key) if len(key) > MIN_LINE else None
            other = None if hit else self.other_hit(key)
            near = self.closest(key, (base, other[0])) if other else None
            if near:
                if run:
                    ops.append(b"l %d" % len(run))
                    ops.extend(run)
                    self.stats["literal"] += len(run)
                    run = []
                lead = line[:len(line) - len(line.lstrip())]
                trail = line[len(line.rstrip()):]
                ops.append(("e %d %d %s %s %s" % (self.use(near[0]), near[1], pct(lead), pct(trail),
                                                  edit_tokens(near[2], key))).encode())
                self.stats["edits"] += 1
                self.edited = True
                continue
            if other:
                self.left.append((rel, other))
            if hit:
                if run:
                    ops.append(b"l %d" % len(run))
                    ops.extend(run)
                    self.stats["literal"] += len(run)
                    run = []
                lead = line[:len(line) - len(line.lstrip())]
                trail = line[len(line.rstrip()):]
                ops.append(("r %d %d %s %s" % (self.use(hit[0]), hit[1], pct(lead), pct(trail))).encode())
                self.stats["refs"] += 1
            else:
                run.append(line)
        if run:
            ops.append(b"l %d" % len(run))
            ops.extend(run)
            self.stats["literal"] += len(run)

    def text_patch(self, rel, data, base):
        lines, crlf, final = split_lines(data)
        ops = [b"BOP %d" % FORMAT, b"eol " + (b"crlf" if crlf else b"lf"), b"final %d" % (1 if final else 0)]
        if base is not None:
            ops.append(b"base %d" % self.use(base))
            blines = self.v.text[base]
            sm = difflib.SequenceMatcher(None, blines, lines, autojunk=False)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag == "equal":
                    ops.append(b"c %d" % (i2 - i1))
                    continue
                if i2 > i1:
                    ops.append(b"s %d" % (i2 - i1))
                if j2 > j1:
                    self.literal_ops(lines[j1:j2], ops, rel, base)
        else:
            ops.append(b"base 0")
            self.literal_ops(lines, ops, rel)
        ops.append(b"end")
        if any(op[:2] == b"e " for op in ops):
            ops[0] = b"BOP %d" % EDIT_FORMAT
        patch = b"\n".join(ops) + b"\n"
        self.write("patches/" + rel + ".bop", patch)
        return "patches/" + rel + ".bop"

    def image_patch(self, rel, data, base):
        own = Image.open(io.BytesIO(data)).convert("RGBA")
        van = Image.open(io.BytesIO(self.v.files[base])).convert("RGBA")
        canvas = Image.new("RGBA", own.size, (0, 0, 0, 0))
        canvas.paste(van.crop((0, 0, min(van.width, own.width), min(van.height, own.height))), (0, 0))
        diff = ImageChops.difference(own, canvas)
        r, g, b, a = diff.split()
        mask = ImageChops.lighter(ImageChops.lighter(r, g), ImageChops.lighter(b, a))
        mask = mask.point(lambda x: 255 if x else 0)
        outside = Image.new("L", own.size, 255)
        outside.paste(0, (0, 0, min(van.width, own.width), min(van.height, own.height)))
        mask = ImageChops.lighter(mask, outside)
        box = mask.getbbox() or (0, 0, 0, 0)
        entry = {"w": own.width, "h": own.height, "x": box[0], "y": box[1],
                 "pixels": sha(own.tobytes())}
        if box[2] > box[0] and box[3] > box[1]:
            keep = Image.new("RGBA", own.size, (0, 0, 0, 0))
            keep.paste(own, (0, 0), mask)
            buf = io.BytesIO()
            keep.crop(box).save(buf, "PNG", optimize=True)
            self.write("images/" + rel + ".own.png", buf.getvalue())
            buf = io.BytesIO()
            mask.crop(box).save(buf, "PNG", optimize=True)
            self.write("images/" + rel + ".mask.png", buf.getvalue())
            entry["own"] = "images/" + rel + ".own.png"
            entry["mask"] = "images/" + rel + ".mask.png"
        return entry

    def add(self, rel, data):
        v = self.v
        e = {"path": rel, "size": len(data), "sha256": sha(data)}
        if v.files.get(rel) == data:
            e["kind"] = "keep"
            e["src"] = self.use(rel)
        elif e["sha256"] in v.by_sha:
            e["kind"] = "copy"
            e["src"] = self.use(v.by_sha[e["sha256"]])
        elif rel in v.text and is_text(rel, data):
            e["kind"] = "patch"
            e["patch"] = self.text_patch(rel, data, rel)
        elif rel in v.files and rel.lower().endswith(".png") and data[:8] == b"\x89PNG\r\n\x1a\n":
            e["kind"] = "image"
            e["src"] = self.use(rel)
            e["image"] = self.image_patch(rel, data, rel)
        elif is_text(rel, data) and any(len(l.strip()) > MIN_LINE and (l.strip() in v.corpus or self.other_hit(l.strip()))
                                        for l in split_lines(data)[0]):
            e["kind"] = "patch"
            e["patch"] = self.text_patch(rel, data, None)
        else:
            e["kind"] = "own"
            e["file"] = "files/" + rel
            self.write(e["file"], data)
        self.stats[e["kind"]] += 1
        return e


def overhaul_version(assets, key="OVERHAUL_VERSION"):
    try:
        with open(os.path.join(assets, "globals.lua"), encoding="utf-8") as f:
            m = re.search(key + r"\s*=\s*['\"]([^'\"]+)", f.read())
            return m.group(1) if m else "?"
    except OSError:
        return "?"


def overhaul_name(args):
    if args.version:
        return args.version
    name = overhaul_version(args.assets, "OVERHAUL_NAME")
    return name if name != "?" else overhaul_version(args.assets)


def collect(assets, rules):
    out = []
    for root, dirs, files in os.walk(assets):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, assets).replace(os.sep, "/")
            if os.path.islink(full) or excluded(rel, rules):
                continue
            out.append(rel)
    return out


def main():
    ap = argparse.ArgumentParser(description="Build the Overhaul patch set from the vanilla game and assets/")
    ap.add_argument("--vanilla", default=STEAM_EXE)
    ap.add_argument("--assets", default=os.path.join(REPO, "assets"))
    ap.add_argument("--exclude", default=os.path.join(REPO, "tools", "release", "EXCLUDE.txt"))
    ap.add_argument("--out", default=os.path.join(REPO, "dist", "release", "patchset"))
    ap.add_argument("--version", default=None)
    ap.add_argument("--other", action="append", default=[],
                    help="the other platform's vanilla Balatro: its lines are shipped only as edits of this one's")
    args = ap.parse_args()

    vanilla = Vanilla(args.vanilla)
    if not vanilla.version:
        sys.exit("No version.jkr in " + args.vanilla)
    rules = read_exclude(args.exclude)
    if os.path.isdir(args.out):
        shutil.rmtree(args.out)
    os.makedirs(args.out)
    b = Builder(vanilla, args.out, [Vanilla(p) for p in args.other])
    entries = []
    for rel in collect(args.assets, rules):
        with open(os.path.join(args.assets, rel), "rb") as f:
            entries.append(b.add(rel, f.read()))
    vlist = [None] * len(b.used)
    for p, i in b.used.items():
        vlist[i - 1] = {"path": p, "sha256": sha(vanilla.files[p]), "size": len(vanilla.files[p])}
        if is_text(p, vanilla.files[p]):
            vlist[i - 1]["lines"] = "lines/%d.txt" % i
            os.makedirs(os.path.join(args.out, "lines"), exist_ok=True)
            with open(os.path.join(args.out, "lines", "%d.txt" % i), "w", encoding="ascii", newline="\n") as f:
                f.write("".join("%06x" % line_hash(l) for l in split_lines(vanilla.files[p])[0]))
    manifest = {
        "format": EDIT_FORMAT if b.edited else FORMAT,
        "name": "Balatro Overhaul",
        "overhaul_version": args.version or overhaul_version(args.assets),
        "overhaul_name": overhaul_name(args),
        "game_version": vanilla.version,
        "vanilla": vlist,
        "files": entries,
    }
    with open(os.path.join(args.out, "manifest.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("return " + lua_value(manifest) + "\n")
    s = b.stats
    print("patch set %s: %d files (keep %d, copy %d, own %d, patch %d, image %d), "
          "%d literal lines, %d vanilla refs, %d line edits, game %s, Overhaul %s"
          % (args.out, len(entries), s["keep"], s["copy"], s["own"], s["patch"], s["image"],
             s["literal"], s["refs"], s["edits"], vanilla.version, manifest["overhaul_version"]))
    if b.left:
        print("%d lines of the other vanilla game are left as they are (no close line in this one)" % len(b.left))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import argparse
import difflib
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

FORMAT = 1
TILE = 16
TEXT_EXT = {".lua", ".fs", ".vs", ".glsl", ".txt", ".json", ".jkr", ".md", ".csv", ".xml", ".ini", ".cfg"}
IMAGE_EXT = {".png"}
SKIP_TOP = {"dexopt"}


def die(msg):
    print("mobile_patch: " + msg, file=sys.stderr, flush=True)
    sys.exit(1)


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Tree:
    def __init__(self, path):
        self.path = Path(path)
        self.zip = None
        self.prefix = ""
        if self.path.is_file():
            self.zip = zipfile.ZipFile(self.path)
            names = set(self.zip.namelist())
            if "assets/main.lua" in names:
                self.prefix = "assets/"
            elif "main.lua" not in names:
                die("%s has no main.lua or assets/main.lua" % path)
        elif not (self.path / "main.lua").is_file():
            die("%s has no main.lua" % path)

    def files(self):
        out = []
        if self.zip:
            for n in self.zip.namelist():
                if n.endswith("/") or not n.startswith(self.prefix):
                    continue
                rel = n[len(self.prefix):]
                if rel.split("/")[0] in SKIP_TOP:
                    continue
                out.append(rel)
        else:
            for root, dirs, files in os.walk(self.path):
                rel_root = os.path.relpath(root, self.path)
                if rel_root == ".":
                    dirs[:] = [d for d in dirs if d not in SKIP_TOP]
                for fn in files:
                    rel = fn if rel_root == "." else os.path.join(rel_root, fn)
                    out.append(rel.replace(os.sep, "/"))
        return sorted(out)

    def read(self, rel):
        if self.zip:
            return self.zip.read(self.prefix + rel)
        return (self.path / rel).read_bytes()


def load_excludes(path):
    pats = []
    if not path:
        return pats
    for line in Path(path).read_text(errors="replace").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("assets/"):
            line = line[len("assets/"):]
        pats.append(line.rstrip("/"))
    return pats


def excluded(rel, pats):
    for p in pats:
        if fnmatch.fnmatch(rel, p) or rel == p or rel.startswith(p + "/"):
            return True
    return False


def split_lines(data):
    lines = data.split(b"\n")
    out = [l + b"\n" for l in lines[:-1]]
    if lines[-1]:
        out.append(lines[-1])
    return out


def norm(line):
    return line.rstrip(b"\n").rstrip(b"\r")


def lua_bytes(b):
    out = ['"']
    for c in b:
        if c == 0x5C:
            out.append("\\\\")
        elif c == 0x22:
            out.append('\\"')
        elif c == 0x0A:
            out.append("\\n")
        elif c == 0x0D:
            out.append("\\r")
        elif c == 0x09:
            out.append("\t")
        elif c < 32 or c == 127:
            out.append("\\%03d" % c)
        else:
            out.append(chr(c) if c < 128 else ("\\%03d" % c))
    out.append('"')
    return "".join(out)


def diff_text(vdata, odata):
    vl = split_lines(vdata)
    ol = split_lines(odata)
    v_crlf = any(l.endswith(b"\r\n") for l in vl)
    o_crlf = any(l.endswith(b"\r\n") for l in ol)
    eol = "lf" if v_crlf and not o_crlf else "keep"
    vn = [norm(l) for l in vl]
    on = [norm(l) for l in ol]
    sm = difflib.SequenceMatcher(None, vn, on, autojunk=False)
    ops = []
    new_lines = 0
    kept = 0
    pending = []

    def flush():
        if pending:
            ops.append(b"".join(pending))
            pending.clear()

    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                vline = vl[i1 + k]
                if eol == "lf" and vline.endswith(b"\r\n"):
                    vline = vline[:-2] + b"\n"
                if vline == ol[j1 + k]:
                    flush()
                    if ops and isinstance(ops[-1], tuple) and ops[-1][1] == i1 + k:
                        ops[-1] = (ops[-1][0], i1 + k + 1)
                    else:
                        ops.append((i1 + k + 1, i1 + k + 1))
                    kept += 1
                else:
                    pending.append(ol[j1 + k])
                    new_lines += 1
        elif tag in ("replace", "insert"):
            pending.extend(ol[j1:j2])
            new_lines += j2 - j1
    flush()
    return ops, eol, kept, new_lines


def apply_text(vdata, ops, eol):
    vl = split_lines(vdata)
    out = []
    for op in ops:
        if isinstance(op, tuple):
            for line in vl[op[0] - 1:op[1]]:
                if eol == "lf" and line.endswith(b"\r\n"):
                    line = line[:-2] + b"\n"
                out.append(line)
        else:
            out.append(op)
    return b"".join(out)


def image_diff(vdata, odata, tiles_dir, rel):
    from PIL import Image
    vim = Image.open(io.BytesIO(vdata)).convert("RGBA")
    oim = Image.open(io.BytesIO(odata)).convert("RGBA")
    vw, vh = vim.size
    ow, oh = oim.size
    vp = vim.load()
    op = oim.load()
    tiles = []
    changed_px = 0
    n = 0
    for ty in range(0, oh, TILE):
        for tx in range(0, ow, TILE):
            tw = min(TILE, ow - tx)
            th = min(TILE, oh - ty)
            tile = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
            mask = Image.new("L", (tw, th), 0)
            tp = tile.load()
            mp = mask.load()
            hit = 0
            for y in range(th):
                for x in range(tw):
                    X, Y = tx + x, ty + y
                    o = op[X, Y]
                    if X < vw and Y < vh and vp[X, Y] == o:
                        continue
                    tp[x, y] = o
                    mp[x, y] = 255
                    hit += 1
            if hit:
                name = "%s.%d" % (rel.replace("/", "__"), n)
                tile.save(tiles_dir / (name + ".png"))
                mask.save(tiles_dir / (name + ".mask.png"))
                tiles.append({"x": tx, "y": ty, "file": name})
                changed_px += hit
                n += 1
    pix = hashlib.sha256(oim.tobytes()).hexdigest()
    return {"w": ow, "h": oh, "tiles": tiles, "pix": pix}, changed_px


def lua_value(v, indent=""):
    if isinstance(v, dict):
        parts = []
        for k in sorted(v):
            parts.append("%s %s=%s" % (indent, k, lua_value(v[k], indent + " ")))
        return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua_value(x, indent) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, bytes):
        return lua_bytes(v)
    return lua_bytes(str(v).encode("utf-8"))


def overhaul_version(tree):
    try:
        text = tree.read("globals.lua").decode("utf-8", "replace")
    except (KeyError, OSError):
        return "0"
    m = re.search(r"OVERHAUL_VERSION\s*=\s*['\"]([0-9][0-9A-Za-z.\-]*)['\"]", text)
    return m.group(1) if m else "0"


def make(args):
    van = Tree(args.vanilla)
    ovh = Tree(args.overhaul)
    pats = load_excludes(args.exclude)
    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    (out / "new").mkdir(parents=True)
    (out / "ops").mkdir()
    (out / "tiles").mkdir()
    vfiles = set(van.files())
    try:
        vversion = van.read("version.jkr").split(b"\n")[0].strip().decode("utf-8", "replace")
    except KeyError:
        vversion = "?"
    entries = []
    stats = {"same": 0, "new": 0, "lines": 0, "image": 0, "kept_lines": 0, "new_lines": 0,
             "leaked_lines": 0, "changed_px": 0, "excluded": 0, "skipped_binary": []}
    vanilla_norm = set()
    for rel in vfiles:
        if os.path.splitext(rel)[1].lower() in TEXT_EXT:
            for l in split_lines(van.read(rel)):
                s = re.sub(rb"\s+", b"", l)
                if len(s) >= 12:
                    vanilla_norm.add(s)
    for idx, rel in enumerate(ovh.files()):
        if excluded(rel, pats):
            stats["excluded"] += 1
            continue
        odata = ovh.read(rel)
        ext = os.path.splitext(rel)[1].lower()
        if rel not in vfiles:
            dst = out / "new" / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(odata)
            entries.append({"path": rel, "kind": "new", "sha": sha(odata)})
            stats["new"] += 1
            continue
        vdata = van.read(rel)
        if vdata == odata:
            entries.append({"path": rel, "kind": "same", "sha": sha(odata)})
            stats["same"] += 1
            continue
        if ext in IMAGE_EXT:
            info, px = image_diff(vdata, odata, out / "tiles", rel)
            info.update(path=rel, kind="image", vsha=sha(vdata))
            entries.append(info)
            stats["image"] += 1
            stats["changed_px"] += px
            continue
        if ext not in TEXT_EXT and b"\0" in odata[:4096]:
            stats["skipped_binary"].append(rel)
            continue
        ops, eol, kept, newl = diff_text(vdata, odata)
        if apply_text(vdata, ops, eol) != odata:
            die("text diff does not round trip for %s" % rel)
        opsname = "%d.lua" % idx
        body = "return {\n" + ",\n".join(
            ("{%d,%d}" % op) if isinstance(op, tuple) else lua_bytes(op) for op in ops) + "\n}\n"
        (out / "ops" / opsname).write_text(body, encoding="latin-1")
        entries.append({"path": rel, "kind": "lines", "vsha": sha(vdata), "sha": sha(odata), "ops": opsname, "eol": eol})
        stats["lines"] += 1
        stats["kept_lines"] += kept
        stats["new_lines"] += newl
        for op in ops:
            if not isinstance(op, tuple):
                for l in split_lines(op):
                    if re.sub(rb"\s+", b"", l) in vanilla_norm:
                        stats["leaked_lines"] += 1
    manifest = {"format": FORMAT, "vanilla_version": vversion, "overhaul_version": overhaul_version(ovh), "files": entries}
    (out / "manifest.lua").write_text("return " + lua_value(manifest) + "\n", encoding="latin-1")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=0) + "\n")
    (out / "stats.json").write_text(json.dumps(stats, indent=1) + "\n")
    print(json.dumps(stats, indent=1))


def apply(args):
    from PIL import Image
    van = Tree(args.vanilla)
    patch = Path(args.patch)
    man = json.loads((patch / "manifest.json").read_text())
    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    for e in man["files"]:
        dst = out / e["path"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        if e["kind"] == "new":
            data = (patch / "new" / e["path"]).read_bytes()
        elif e["kind"] == "same":
            data = van.read(e["path"])
        elif e["kind"] == "lines":
            vdata = van.read(e["path"])
            if sha(vdata) != e["vsha"]:
                die("vanilla %s does not match" % e["path"])
            data = apply_text(vdata, parse_ops(patch / "ops" / e["ops"]), e["eol"])
        else:
            vim = Image.open(io.BytesIO(van.read(e["path"]))).convert("RGBA")
            img = Image.new("RGBA", (e["w"], e["h"]), (0, 0, 0, 0))
            img.paste(vim, (0, 0))
            for t in e["tiles"]:
                tile = Image.open(patch / "tiles" / (t["file"] + ".png")).convert("RGBA")
                mask = Image.open(patch / "tiles" / (t["file"] + ".mask.png")).convert("L")
                region = img.crop((t["x"], t["y"], t["x"] + tile.size[0], t["y"] + tile.size[1]))
                region.paste(tile, (0, 0), mask)
                img.paste(region, (t["x"], t["y"]))
            if hashlib.sha256(img.tobytes()).hexdigest() != e["pix"]:
                die("image %s does not match after patching" % e["path"])
            buf = io.BytesIO()
            img.save(buf, "PNG")
            data = buf.getvalue()
        if e["kind"] != "image" and sha(data) != e["sha"]:
            die("result %s does not match" % e["path"])
        dst.write_bytes(data)
    print("applied %d files to %s" % (len(man["files"]), out))


ZIP_SKIP = {"stats.json"}


def pack(args):
    patch = Path(args.patch)
    if not (patch / "manifest.lua").is_file():
        die("no patch set at %s" % patch)
    man = json.loads((patch / "manifest.json").read_text())
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(patch.rglob("*")):
            rel = f.relative_to(patch).as_posix()
            if f.is_file() and rel not in ZIP_SKIP:
                z.write(f, rel)
    os.replace(tmp, out)
    data = out.read_bytes()
    entry = {"file": out.name, "version": man.get("overhaul_version", "0"), "vanilla_version": man.get("vanilla_version", "?"),
             "size": len(data), "sha256": sha(data)}
    Path(str(out) + ".json").write_text(json.dumps(entry, indent=1) + "\n")
    print(json.dumps(entry, indent=1))


def lua_unescape(s):
    out = bytearray()
    i = 0
    while i < len(s):
        c = s[i]
        if c == 0x5C:
            n = s[i + 1]
            if n in b"0123456789":
                j = i + 1
                while j < len(s) and j < i + 4 and s[j] in b"0123456789":
                    j += 1
                out.append(int(s[i + 1:j]))
                i = j
                continue
            out.append({0x6E: 10, 0x72: 13, 0x74: 9, 0x5C: 0x5C, 0x22: 0x22}[n])
            i += 2
            continue
        out.append(c)
        i += 1
    return bytes(out)


STR_RE = rb'"((?:[^"\\]|\\.)*)"'


def parse_ops(path):
    data = path.read_bytes()
    ops = []
    for m in re.finditer(rb'\{(\d+),(\d+)\}|' + STR_RE, data):
        if m.group(1):
            ops.append((int(m.group(1)), int(m.group(2))))
        else:
            ops.append(lua_unescape(m.group(3)))
    return ops


def main():
    p = argparse.ArgumentParser(description="Overhaul patch set against the mobile game files (no vanilla content inside)")
    sub = p.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make")
    m.add_argument("--vanilla", required=True, help="vanilla game: folder, Balatro.exe, .love or the official APK")
    m.add_argument("--overhaul", required=True, help="the Overhaul game folder")
    m.add_argument("--exclude", help="EXCLUDE.txt (path or glob per line, # reason)")
    m.add_argument("--out", required=True)
    a = sub.add_parser("apply")
    a.add_argument("--vanilla", required=True)
    a.add_argument("--patch", required=True)
    a.add_argument("--out", required=True)
    z = sub.add_parser("zip", help="pack a patch set into one zip for the update feed (prints size and sha256)")
    z.add_argument("--patch", required=True)
    z.add_argument("--out", required=True)
    args = p.parse_args()
    if args.cmd == "make":
        make(args)
    elif args.cmd == "zip":
        pack(args)
    else:
        apply(args)


if __name__ == "__main__":
    main()

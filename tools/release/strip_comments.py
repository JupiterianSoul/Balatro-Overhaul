import argparse, ast, io, os, re, subprocess, sys, tempfile, tokenize, json, zipfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "release", "patcher"))

SKIP_PREFIX = ("assets/smods/", "assets/resources/workshop/", "smali/", "res/", "lib/", "Balatro_Overhaul_PC/", "original/", "Multiplayer-OTHER/", "ICON/")
SKIP_PARTS = ("node_modules/", "/dist/", ".night/")
KEEP_DIRECTIVE = re.compile(r"^\s*(//|/\*)\s*(eslint|@ts-|prettier|istanbul|webpack|<reference|#region|#endregion)", re.I)


def load_vanilla(paths):
    from make_patch import Vanilla
    out = []
    for p in paths:
        if os.path.exists(p):
            out.append(Vanilla(p))
    return out


def vanilla_lines(vans, rel):
    s = set()
    for v in vans:
        data = v.files.get(rel)
        if data is not None:
            for ln in data.decode("utf-8", "replace").replace("\r\n", "\n").split("\n"):
                s.add(ln.rstrip())
    return s


def lua_comment_spans(src):
    spans = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + m.end())
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            spans.append((i, j))
            i = j
        elif c in "\"'":
            q = c
            i += 1
            while i < n and src[i] != q:
                if src[i] == "\\":
                    i += 1
                if i < n and src[i] == "\n":
                    break
                i += 1
            i += 1
        elif c == "[":
            m = re.match(r"\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + m.end())
                i = n if j < 0 else j + len(close)
            else:
                i += 1
        else:
            i += 1
    return spans


def c_comment_spans(src, hash_define=True):
    spans = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            spans.append((i, j))
            i = j
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            spans.append((i, j))
            i = j
        elif c in "\"'":
            q = c
            i += 1
            while i < n and src[i] != q:
                if src[i] == "\\":
                    i += 1
                if i < n and src[i] == "\n":
                    break
                i += 1
            i += 1
        else:
            i += 1
    return spans


def apply_spans(src, spans, keep_line):
    mask = [True] * len(src)
    for a, b in spans:
        for k in range(a, b):
            if src[k] != "\n":
                mask[k] = False
    lines = src.split("\n")
    out = []
    pos = 0
    for ln in lines:
        seg = mask[pos:pos + len(ln)]
        pos += len(ln) + 1
        if all(seg):
            out.append(ln)
            continue
        if keep_line(ln):
            out.append(ln)
            continue
        new = "".join(ch for ch, m in zip(ln, seg) if m).rstrip()
        if new.strip() == "":
            continue
        out.append(new)
    return "\n".join(out)


def strip_lua(src, rel, vans):
    crlf = "\r\n" in src
    text = src.replace("\r\n", "\n")
    van = vanilla_lines(vans, rel)
    spans = lua_comment_spans(text)
    spans = [s for s in spans if not (text[s[0]:s[1]].startswith("#!"))]
    out = apply_spans(text, spans, lambda ln: ln.rstrip() in van)
    return out.replace("\n", "\r\n") if crlf else out


def strip_c(src, rel, vans):
    crlf = "\r\n" in src
    text = src.replace("\r\n", "\n")
    van = vanilla_lines(vans, rel)
    spans = [s for s in c_comment_spans(text) if not KEEP_DIRECTIVE.match(text[s[0]:s[1]])]
    out = apply_spans(text, spans, lambda ln: ln.rstrip() in van)
    return out.replace("\n", "\r\n") if crlf else out


def strip_py(src):
    toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    lines = src.split("\n")
    kill = {}
    for t in toks:
        if t.type == tokenize.COMMENT:
            row, col = t.start
            txt = t.string
            if row <= 2 and (txt.startswith("#!") or "coding" in txt):
                continue
            if re.match(r"#\s*(noqa|type:|pragma|pylint|isort|fmt:)", txt):
                continue
            kill[row] = col
    out = []
    for idx, ln in enumerate(lines, 1):
        if idx in kill:
            new = ln[:kill[idx]].rstrip()
            if new.strip() == "":
                continue
            out.append(new)
        else:
            out.append(ln)
    return "\n".join(out)


def strip_sh(src):
    out = []
    for i, ln in enumerate(src.split("\n")):
        s = ln.strip()
        if s.startswith("#") and not s.startswith("#!") and not s.startswith("# shellcheck"):
            continue
        out.append(ln)
    return "\n".join(out)


def strip_smali(src):
    out = []
    for ln in src.split("\n"):
        if ln.strip().startswith("#"):
            continue
        out.append(ln)
    return "\n".join(out)


def luabc(path_or_text, is_text=True):
    with tempfile.TemporaryDirectory() as d:
        a = os.path.join(d, "a.lua")
        if is_text:
            open(a, "w", encoding="utf-8", newline="").write(path_or_text)
        else:
            a = path_or_text
        r = subprocess.run(["luajit", "-bl", a], capture_output=True)
        if r.returncode != 0:
            return None
        return re.sub(rb"(?m)^-- BYTECODE -- .*$|\s*; a\.lua:\d+", b"", r.stdout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--vanilla", action="append", default=[])
    ap.add_argument("--list", action="store_true")
    ap.add_argument("only", nargs="*")
    a = ap.parse_args()
    vans = load_vanilla(a.vanilla)
    files = subprocess.run(["git", "-C", REPO, "ls-files"], capture_output=True, text=True).stdout.split("\n")
    stats = {"changed": 0, "same": 0, "skipped": 0, "failed": []}
    removed = 0
    for rel in files:
        if not rel or (a.only and not any(rel.startswith(o) for o in a.only)):
            continue
        if rel.startswith(SKIP_PREFIX) or any(p in rel for p in SKIP_PARTS):
            continue
        ext = os.path.splitext(rel)[1].lower()
        if ext not in (".lua", ".ts", ".js", ".py", ".sh", ".java", ".smali", ".fs", ".vs", ".glsl"):
            continue
        path = os.path.join(REPO, rel)
        try:
            raw = open(path, "rb").read().decode("utf-8")
            bom = raw.startswith("\ufeff")
            if bom:
                raw = raw[1:]
        except Exception:
            stats["skipped"] += 1
            continue
        head = "\n".join(l for l in raw.split("\n")[:25] if l.lstrip().startswith(("--", "#", "//", "/*", "*")))
        if re.search(r"Copyright|\(c\) |SPDX|GNU General|Permission is hereby", head) and ext != ".sh":
            stats["skipped"] += 1
            if a.list:
                print("SKIP-LICENSED", rel)
            continue
        rel_game = rel[len("assets/"):] if rel.startswith("assets/") else None
        try:
            if ext == ".lua":
                new = strip_lua(raw, rel_game or rel, vans if rel_game else [])
                ok = luabc(raw) is not None and luabc(raw) == luabc(new)
            elif ext in (".fs", ".vs", ".glsl", ".java"):
                new = strip_c(raw, rel_game or rel, vans if rel_game else [])
                ok = raw.count("{") - raw.count("}") == new.count("{") - new.count("}")
            elif ext == ".py":
                new = strip_py(raw)
                ok = ast.dump(ast.parse(raw)) == ast.dump(ast.parse(new))
            elif ext == ".sh":
                new = strip_sh(raw)
                ok = subprocess.run(["bash", "-n"], input=new, text=True, capture_output=True).returncode == 0
            elif ext == ".smali":
                new = strip_smali(raw)
                ok = True
            else:
                continue
        except Exception as e:
            stats["failed"].append((rel, "error " + str(e)[:80]))
            continue
        if new == raw:
            stats["same"] += 1
            continue
        if not ok:
            stats["failed"].append((rel, "verify"))
            continue
        stats["changed"] += 1
        removed += raw.count("\n") - new.count("\n")
        if a.write:
            open(path, "w", encoding="utf-8", newline="").write(("\ufeff" if bom else "") + new)
    print(json.dumps({"changed": stats["changed"], "same": stats["same"], "skipped": stats["skipped"], "lines_removed": removed, "failed": len(stats["failed"])}))
    for rel, why in stats["failed"][:40]:
        print("FAILED", rel, why)


main()

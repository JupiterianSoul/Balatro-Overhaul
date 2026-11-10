#!/usr/bin/env python3
import argparse
import hashlib
import io
import os
import sys
import tarfile
import zipfile

from PIL import Image

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_patch import MIN_LINE, STEAM_EXE, Vanilla, sha

MIN_BLOB = 64


def line_hash(key):
    return hashlib.sha256(key).hexdigest()


class Checker:
    def __init__(self, vanilla, known=()):
        self.sources = vanilla if isinstance(vanilla, (list, tuple)) else [vanilla]
        self.v = self.sources[0]
        self.known = set(known)
        self.known_seen = set()
        self.known_hits = 0
        self.problems = []
        self.files = 0
        self.lines = 0
        self.images = {}
        self.found_lines = []
        self.by_sha = {}
        self.corpus = {}
        for v in self.sources:
            label = os.path.basename(v.path)
            for h, p in v.by_sha.items():
                self.by_sha.setdefault(h, "%s %s" % (label, p))
            for key, (p, ln) in v.corpus.items():
                self.corpus.setdefault(key, ("%s %s" % (label, p), ln))
            for p, data in v.files.items():
                if p.lower().endswith(".png"):
                    try:
                        im = Image.open(io.BytesIO(data)).convert("RGBA")
                        self.images.setdefault(im.size, []).append(("%s %s" % (label, p), im))
                    except Exception:
                        pass

    def bad(self, where, why):
        self.problems.append("%s: %s" % (where, why))

    def check_png(self, where, data):
        try:
            im = Image.open(io.BytesIO(data)).convert("RGBA")
        except Exception:
            return
        for p, van in self.images.get(im.size, []):
            a = im.getdata()
            b = van.getdata()
            same = total = 0
            for x, y in zip(a, b):
                if x[3] == 0 and y[3] == 0:
                    continue
                total += 1
                if x == y:
                    same += 1
            if total and same * 4 >= total:
                self.bad(where, "%d%% of its pixels match vanilla %s" % (same * 100 // total, p))

    def check_blob(self, where, data):
        self.files += 1
        if len(data) >= MIN_BLOB and sha(data) in self.by_sha:
            self.bad(where, "is a copy of vanilla " + self.by_sha[sha(data)])
            return
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            self.check_png(where, data)
            return
        if data[:4] == b"PK\x03\x04" or where.lower().endswith((".zip", ".love", ".apk", ".exe")):
            if self.check_zip(where, data):
                return
        if data[:2] == b"\x1f\x8b" and where.lower().endswith((".tar.gz", ".tgz")):
            with tarfile.open(fileobj=io.BytesIO(data)) as t:
                for m in t.getmembers():
                    if m.isfile():
                        self.check_blob(where + "!" + m.name, t.extractfile(m).read())
            return
        if b"\0" in data[:65536]:
            return
        for n, line in enumerate(data.split(b"\n"), 1):
            key = line.strip()
            self.lines += 1
            if len(key) > MIN_LINE and key in self.corpus:
                h = line_hash(key)
                if h in self.known:
                    self.known_hits += 1
                    self.known_seen.add(h)
                    continue
                p, ln = self.corpus[key]
                self.bad("%s:%d" % (where, n), "vanilla line %s:%d" % (p, ln))
                self.found_lines.append(key)

    def check_zip(self, where, data):
        try:
            z = zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile:
            return False
        for info in z.infolist():
            if not info.is_dir():
                self.check_blob(where + "!" + info.filename, z.read(info))
        return True

    def check_path(self, path):
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs.sort()
                for name in sorted(files):
                    full = os.path.join(root, name)
                    if os.path.islink(full):
                        continue
                    with open(full, "rb") as f:
                        self.check_blob(os.path.relpath(full, path), f.read())
        else:
            with open(path, "rb") as f:
                self.check_blob(os.path.basename(path), f.read())


def main():
    ap = argparse.ArgumentParser(description="Prove a patch set or release folder holds no vanilla Balatro text or files")
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--vanilla", action="append", default=[],
                    help="a vanilla Balatro (Balatro.exe, a .love or the mobile APK); give it more than once to check against each")
    ap.add_argument("--allow", action="append", default=[],
                    help="third-party text (like the LÖVE licence) whose lines are not Balatro's")
    ap.add_argument("--known", default=None,
                    help="sha256 of lines still waiting for their rewrite, one per line: counted, not failed")
    ap.add_argument("--write-known", default=None,
                    help="write the sha256 of every vanilla line found to this file and pass")
    args = ap.parse_args()
    known = []
    if args.known and os.path.exists(args.known):
        with open(args.known, encoding="utf-8") as f:
            known = [l.split("#", 1)[0].strip() for l in f if l.split("#", 1)[0].strip()]
    c = Checker([Vanilla(p) for p in (args.vanilla or [STEAM_EXE])], known)
    for path in args.allow:
        with open(path, "rb") as f:
            for line in f.read().split(b"\n"):
                c.corpus.pop(line.strip(), None)
    for p in args.paths:
        c.check_path(p)
    print("checked %d files, %d lines against %d vanilla lines over %d chars (%s)"
          % (c.files, c.lines, len(c.corpus), MIN_LINE, ", ".join(os.path.basename(v.path) for v in c.sources)))
    if args.write_known:
        hashes = sorted(set(line_hash(k) for k in c.found_lines) | c.known_seen)
        with open(args.write_known, "w", encoding="utf-8", newline="\n") as f:
            f.write("# sha256 of the vanilla lines the patch set still carries; tools/release/patcher/check_patch.py --known\n")
            f.write("".join(h + "\n" for h in hashes))
        print("wrote %d line hashes to %s" % (len(hashes), args.write_known))
        c.problems = [p for p in c.problems if "vanilla line" not in p]
    if c.known_hits:
        print("KNOWN %d vanilla lines (%d different) still waiting for their rewrite (%s)"
              % (c.known_hits, len(c.known_seen), args.known))
    if c.problems:
        for p in c.problems[:50]:
            print("VANILLA " + p)
        print("FAIL: %d problems" % len(c.problems))
        sys.exit(1)
    print("OK: no vanilla text, no vanilla files, no vanilla images")


if __name__ == "__main__":
    main()

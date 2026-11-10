#!/usr/bin/env python3
import argparse
import io
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_patch import REPO, collect, read_exclude

from PIL import Image


def main():
    ap = argparse.ArgumentParser(description="Compare an installed Overhaul folder with assets/ minus EXCLUDE.txt")
    ap.add_argument("installed")
    ap.add_argument("--assets", default=os.path.join(REPO, "assets"))
    ap.add_argument("--exclude", default=os.path.join(REPO, "tools", "release", "EXCLUDE.txt"))
    ap.add_argument("--manifest", default=None)
    args = ap.parse_args()
    want = collect(args.assets, read_exclude(args.exclude))
    have = collect(args.installed, [])
    images = set()
    if args.manifest:
        with open(args.manifest, encoding="utf-8") as f:
            text = f.read()
        is_image = False
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("kind = "):
                is_image = line == 'kind = "image",'
            elif line.startswith('path = "'):
                if is_image:
                    images.add(line[8:-2])
                is_image = False
    missing = sorted(set(want) - set(have))
    extra = sorted(set(have) - set(want) - {".overhaul_installed"})
    differ, pixel_same = [], []
    for rel in sorted(set(want) & set(have)):
        with open(os.path.join(args.assets, rel), "rb") as f:
            a = f.read()
        with open(os.path.join(args.installed, rel), "rb") as f:
            b = f.read()
        if a == b:
            continue
        if rel.lower().endswith(".png"):
            ia = Image.open(io.BytesIO(a)).convert("RGBA")
            ib = Image.open(io.BytesIO(b)).convert("RGBA")
            if ia.size == ib.size and ia.tobytes() == ib.tobytes():
                pixel_same.append(rel)
                continue
        differ.append(rel)
    print("assets minus excluded: %d files, installed: %d files" % (len(want), len(have)))
    print("byte for byte equal: %d, pixel equal (re-encoded PNG): %d %s"
          % (len(want) - len(missing) - len(differ) - len(pixel_same), len(pixel_same), pixel_same))
    for name, items in (("MISSING", missing), ("EXTRA", extra), ("DIFFERS", differ)):
        for rel in items[:20]:
            print(name + " " + rel)
    if missing or extra or differ:
        print("FAIL")
        sys.exit(1)
    if images and set(pixel_same) - images:
        print("FAIL: pixel-only matches outside the image patches")
        sys.exit(1)
    print("OK: round trip gives back assets/ exactly")


if __name__ == "__main__":
    main()

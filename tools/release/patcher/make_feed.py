#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import sys


def manifest_field(text, name):
    m = re.search(r'^  %s = "(.*)",$' % name, text, re.M)
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser(description="Write the release update feed (feed.json) for a patch set zip.")
    ap.add_argument("--manifest", required=True, help="patchset/manifest.lua")
    ap.add_argument("--zip", required=True, help="the patch set zip the feed points at")
    ap.add_argument("--changelog", default="", help="text file, or JSON {\"en\": ..., \"fr\": ..., \"es\": ...}")
    ap.add_argument("--url", default=None, help="download URL (default: the zip name, next to feed.json)")
    ap.add_argument("--version", default=None, help="override the version (tests)")
    ap.add_argument("--page", default=os.environ.get("RELEASE_PAGE", "https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest"), help="release page for new launchers")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    text = open(a.manifest, encoding="utf-8").read()
    version = a.version or manifest_field(text, "overhaul_version")
    if not version:
        sys.exit("no overhaul_version in %s" % a.manifest)
    data = open(a.zip, "rb").read()
    name = a.version or manifest_field(text, "overhaul_name") or version
    latest = {
        "version": version,
        "name": name,
        "game_version": manifest_field(text, "game_version"),
        "url": a.url or os.path.basename(a.zip),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "patch_format": int((re.search(r"^  format = (\d+),$", text, re.M) or [None, "1"])[1]),
    }
    if a.changelog:
        body = open(a.changelog, encoding="utf-8").read().strip()
        try:
            latest["changelog"] = json.loads(body)
        except ValueError:
            latest["changelog"] = body
    feed = {"format": 1, "latest": latest}
    if a.page:
        feed["page"] = a.page
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(feed, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("feed.json: Overhaul %s, patch set %d bytes" % (version, len(data)))


if __name__ == "__main__":
    main()

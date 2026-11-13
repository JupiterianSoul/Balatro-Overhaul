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


def vnum(s):
    m = re.match(r"\s*(\d+[\d.]*\d|\d+)", s or "")
    return m.group(1) if m else (s or "")


def md_notes(text, name):
    want, notes, lang, inside = vnum(name), {}, None, False
    for line in text.splitlines():
        head = re.match(r"^##\s+([^#].*)$", line)
        sub = re.match(r"^###\s+([A-Za-z]{2})\s*(.*?)\s*$", line)
        if head:
            if inside:
                break
            inside = vnum(head.group(1).split("|")[0].strip()) == want
            lang = None
        elif inside and sub:
            lang = sub.group(1).lower()
            notes[lang] = ["# " + sub.group(2)] if sub.group(2) else []
        elif inside and lang and line.strip():
            notes[lang].append(line)
    return {k: "\n".join(v) for k, v in notes.items() if len(v) > 1}


def main():
    ap = argparse.ArgumentParser(description="Write the release update feed (feed.json) for a patch set zip.")
    ap.add_argument("--manifest", required=True, help="patchset/manifest.lua")
    ap.add_argument("--zip", required=True, help="the patch set zip the feed points at")
    ap.add_argument("--changelog", default="", help="text file, or JSON {\"en\": ..., \"fr\": ..., \"es\": ...}")
    ap.add_argument("--url", default=None, help="download URL (default: the zip name, next to feed.json)")
    ap.add_argument("--version", default=None, help="override the version (tests)")
    ap.add_argument("--page", default=os.environ.get("RELEASE_PAGE", "https://github.com/JupiterianSoul/Balatro-Overhaul/releases/latest"), help="release page for new launchers")
    ap.add_argument("--launcher-build", type=int, help="LAUNCHER_BUILD of the launcher code zips (launcher self-update)")
    ap.add_argument("--launcher-zip", help="launcher-code-<build>.zip (PC launcher code)")
    ap.add_argument("--launcher-phone-zip", help="launcher-code-phone-<build>.zip (phone launcher code)")
    ap.add_argument("--android-apk", help="the phone launcher APK, offered to phones whose launcher APK has an older native level")
    ap.add_argument("--android-native", type=int, help="native level of --android-apk (make_apk.py native)")
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
        if a.changelog.endswith(".md"):
            notes = md_notes(body, name)
            if notes:
                latest["changelog"] = notes
        else:
            try:
                latest["changelog"] = json.loads(body)
            except ValueError:
                latest["changelog"] = body
    def entry(path, name):
        blob = open(path, "rb").read()
        return {"url": name, "size": len(blob), "sha256": hashlib.sha256(blob).hexdigest()}
    if a.launcher_build and a.launcher_zip:
        latest["launcher"] = dict(build=a.launcher_build, **entry(a.launcher_zip, "launcher-code-%d.zip" % a.launcher_build))
        if a.launcher_phone_zip:
            latest["launcher"]["phone"] = entry(a.launcher_phone_zip, "launcher-code-phone-%d.zip" % a.launcher_build)
    if a.android_apk and a.android_native:
        latest["android_apk"] = dict(native=a.android_native, **entry(a.android_apk, "launcher-android-%s.apk" % version))
    feed = {"format": 1, "latest": latest}
    if a.page:
        feed["page"] = a.page
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(feed, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("feed.json: Overhaul %s, patch set %d bytes" % (version, len(data)))


if __name__ == "__main__":
    main()

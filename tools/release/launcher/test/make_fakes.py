#!/usr/bin/env python3
import os
import sys
import zipfile

src = sys.argv[1]
out = sys.argv[2]
z = zipfile.ZipFile(src)
for name, change in (("old", "version"), ("modded", "card")):
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    with zipfile.ZipFile(os.path.join(d, "Balatro.exe"), "w", zipfile.ZIP_DEFLATED) as w:
        for info in z.infolist():
            if info.is_dir():
                continue
            data = z.read(info.filename)
            if change == "version" and info.filename == "version.jkr":
                data = data.replace(b"1.0.1o", b"1.0.1n")
            if change == "card" and info.filename == "card.lua":
                data += b"\n"
            w.writestr(info.filename, data)
os.makedirs(os.path.join(out, "notgame"), exist_ok=True)
with open(os.path.join(out, "notgame", "Balatro.exe"), "wb") as f:
    f.write(b"MZ" + b"\0" * 4096)
print("fakes in", out)

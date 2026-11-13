#!/usr/bin/env python3
import os
import struct
import sys
import uuid


def wstr(s):
    return struct.pack("<I", len(s)) + s.encode("utf-16-le")


def fixed_name(s):
    raw = s.encode("utf-16-le")
    return raw + b"\0" * (128 - len(raw))


def container_file(entries):
    out = struct.pack("<II", 4, len(entries))
    for name, guid in entries:
        out += fixed_name(name) + guid.bytes_le + guid.bytes_le
    return out


def main():
    out, src = sys.argv[1], sys.argv[2]
    user = os.path.join(out, "Packages", "PlayStack.Balatro_fake123", "SystemAppData", "wgs",
                        "000900000ABCDEF0_00000000000000000000000069F80140")
    os.makedirs(os.path.join(user, "t"), exist_ok=True)
    containers = []
    plan = [
        ("1", [("profile.jkr", "1/profile.jkr"), ("meta.jkr", "1/meta.jkr")]),
        ("2/profile.jkr", [("data", "2/profile.jkr")]),
        ("settings.jkr", [("data", None)]),
    ]
    for num, (cname, files) in enumerate(plan, start=3):
        folder = uuid.uuid4()
        fdir = os.path.join(user, folder.hex.upper())
        os.makedirs(fdir, exist_ok=True)
        entries = []
        for fname, rel in files:
            blob = uuid.uuid4()
            data = b"return {}" if rel is None else open(os.path.join(src, rel), "rb").read()
            with open(os.path.join(fdir, blob.hex.upper()), "wb") as f:
                f.write(data)
            entries.append((fname, blob))
        with open(os.path.join(fdir, "container.%d" % num), "wb") as f:
            f.write(container_file(entries))
        containers.append((cname, num, folder))
    idx = struct.pack("<II", 14, len(containers)) + struct.pack("<I", 0)
    idx += wstr("PlayStack.Balatro_fake123!Balatro") + struct.pack("<QI", 133000000000000000, 0)
    idx += wstr("{00000000-0000-0000-0000-000000000000}") + struct.pack("<Q", 0)
    for cname, num, folder in containers:
        idx += wstr(cname) + wstr(cname) + wstr('"0x8DC0000000000000"')
        idx += struct.pack("<B", num) + struct.pack("<I", 0) + folder.bytes_le
        idx += struct.pack("<Q", 133000000000000000) + b"\0" * 16
    with open(os.path.join(user, "containers.index"), "wb") as f:
        f.write(idx)
    print(user)


if __name__ == "__main__":
    main()

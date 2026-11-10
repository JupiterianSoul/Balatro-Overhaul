import struct
import sys


def sections(d):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    n = struct.unpack_from("<H", d, pe + 6)[0]
    optsz = struct.unpack_from("<H", d, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", d, opt)[0]
    dd = opt + (96 if magic == 0x10B else 112)
    rsrc_rva = struct.unpack_from("<I", d, dd + 16)[0]
    secs = []
    for i in range(n):
        o = opt + optsz + i * 40
        vs, va, rs, rp = struct.unpack_from("<IIII", d, o + 8)
        secs.append((va, max(vs, rs), rp))
    return rsrc_rva, secs


def file_off(secs, rva):
    for va, size, rp in secs:
        if va <= rva < va + size:
            return rva - va + rp
    raise ValueError("rva outside sections")


def leaves(d, base, off, path, out):
    nn, ni = struct.unpack_from("<HH", d, base + off + 12)
    for i in range(nn + ni):
        nid, ptr = struct.unpack_from("<II", d, base + off + 16 + i * 8)
        if ptr & 0x80000000:
            leaves(d, base, ptr & 0x7FFFFFFF, path + [nid], out)
        else:
            out.append((path + [nid], base + ptr))


def read_ico(raw):
    count = struct.unpack_from("<H", raw, 4)[0]
    out = {}
    for i in range(count):
        w, h, _, _, _, _, size, off = struct.unpack_from("<BBBBHHII", raw, 6 + i * 16)
        out[w or 256] = raw[off:off + size]
    return out


def main(exe, ico):
    d = bytearray(open(exe, "rb").read())
    pngs = read_ico(open(ico, "rb").read())
    rsrc_rva, secs = sections(d)
    base = file_off(secs, rsrc_rva)
    found = []
    leaves(d, base, 0, [], found)
    icons = {p[1]: e for p, e in found if p[0] == 3}
    done = 0
    for p, e in found:
        if p[0] != 14:
            continue
        g_rva, g_size = struct.unpack_from("<II", d, e)
        g = file_off(secs, g_rva)
        count = struct.unpack_from("<H", d, g + 4)[0]
        for i in range(count):
            o = g + 6 + i * 14
            w = d[o] or 256
            iid = struct.unpack_from("<H", d, o + 12)[0]
            png = pngs.get(w)
            ent = icons.get(iid)
            if not png or ent is None:
                continue
            i_rva, i_size = struct.unpack_from("<II", d, ent)
            if len(png) > i_size:
                continue
            at = file_off(secs, i_rva)
            d[at:at + i_size] = png + b"\0" * (i_size - len(png))
            struct.pack_into("<I", d, ent + 4, len(png))
            struct.pack_into("<HHI", d, o + 4, 1, 32, len(png))
            done += 1
    open(exe, "wb").write(bytes(d))
    print("exe icon: %d images replaced" % done)
    return 0 if done else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))

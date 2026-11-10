import os, re, sys, glob

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MARK = re.compile(r'MOD_TRANSLATIONS\["(fr|es|en-us)"\]|\b(fr|es|en|en_us|de|FR|ES|EN)\s*=\s*\{|\.(fr|es|en)\[|\["(fr|es|en-us|en)"\]\s*=\s*\{')


def lua_quote(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


def lua_unquote(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', '\\': '\\', '"': '"', "'": "'"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def files():
    for p in glob.glob(os.path.join(ROOT, 'assets', '**', '*.lua'), recursive=True):
        if '/localization/' in p or '/smods/' in p or 'node_modules' in p:
            continue
        yield p


PAIR = re.compile(r'\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"|\[\s*\'((?:[^\'\\]|\\.)*)\'\s*\]\s*=\s*\'((?:[^\'\\]|\\.)*)\'')


def lang_at(text, pos):
    line_start = text.rfind('\n', 0, pos) + 1
    line = text[line_start:pos + 1]
    m = re.search(r'(?<![\w])(fr|es)\[', line)
    if m:
        return m.group(1)
    last = None
    for m in MARK.finditer(text, 0, pos):
        last = m
    if not last:
        return None
    return next(g for g in last.groups() if g)


def scan():
    for p in files():
        b = open(p, 'rb').read()
        try:
            t = b.decode('utf-8')
        except UnicodeDecodeError:
            continue
        if 'fr' not in t:
            continue
        marks = [(m.start(), next(g for g in m.groups() if g).lower()) for m in MARK.finditer(t)]
        if not marks:
            continue
        mi, cur = 0, None
        for m in PAIR.finditer(t):
            while mi < len(marks) and marks[mi][0] < m.start():
                cur = marks[mi][1]
                mi += 1
            line_start = t.rfind('\n', 0, m.start()) + 1
            lm = re.search(r'(?<![\w])(fr|es)\[', t[line_start:m.start() + 1])
            lang = lm.group(1) if lm else cur
            if lang not in ('fr', 'es'):
                continue
            q = '"' if m.group(1) is not None else "'"
            k = m.group(1) if m.group(1) is not None else m.group(3)
            v = m.group(2) if m.group(1) is not None else m.group(4)
            yield p, lang, lua_unquote(k), lua_unquote(v), m.start(2) if q == '"' else m.start(4), m.end(2) if q == '"' else m.end(4), q


def apply(edits):
    want = {}
    for lang, k, new in edits:
        want[(lang, k)] = new
    by_file = {}
    hit = set()
    for p, lang, k, v, s, e, q in scan():
        if (lang, k) in want and want[(lang, k)] != v:
            by_file.setdefault(p, []).append((s, e, want[(lang, k)], q))
            hit.add((lang, k))
        elif (lang, k) in want:
            hit.add((lang, k))
    for p, reps in by_file.items():
        t = open(p, 'rb').read().decode('utf-8')
        for s, e, new, q in sorted(reps, reverse=True):
            enc = lua_quote(new) if q == '"' else new.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')
            t = t[:s] + enc + t[e:]
        open(p, 'wb').write(t.encode('utf-8'))
    return by_file, [x for x in want if x not in hit]


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'locate':
        for p, lang, k, v, s, e, q in scan():
            print('%s\t%s\t%s\t%s' % (os.path.relpath(p, ROOT), lang, k.replace('\t', ' ').replace('\n', '\\n'), v.replace('\t', ' ').replace('\n', '\\n')))
    elif cmd == 'apply':
        edits = []
        for line in open(sys.argv[2], encoding='utf-8'):
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) != 3:
                print('BAD', line)
                continue
            edits.append((parts[0], parts[1].replace('\\n', '\n'), parts[2].replace('\\n', '\n')))
        by_file, missing = apply(edits)
        for p, reps in by_file.items():
            print('edited', os.path.relpath(p, ROOT), len(reps))
        for m in missing:
            print('NOT FOUND', m[0], m[1])

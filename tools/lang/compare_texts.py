import sys, re, collections
path = sys.argv[1]
by = collections.defaultdict(dict)
for line in open(path, encoding='utf-8', errors='replace'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 3: continue
    lang, tag, text = p[0], p[1], p[2]
    for part in text.split(' / '):
        part = part.strip()
        if part: by[lang].setdefault(part, tag)
allow = set(l.strip() for l in open(sys.argv[2], encoding='utf-8')) if len(sys.argv) > 2 else set()
en = by.get('en-us', {})
for lang in [l for l in by if l != 'en-us']:
    rows = []
    for t, tag in by[lang].items():
        if t in en and t not in allow and re.search(r'[a-z]{3}', t) and len(re.findall(r'[A-Za-z]{3,}', t)) >= 1:
            rows.append((tag, t))
    rows.sort()
    print('==', lang, len(rows))
    for tag, t in rows: print(lang + '\t' + tag + '\t' + t)

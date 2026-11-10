import re, sys, collections
def parse(path):
    lang = 'en-us'
    res = collections.defaultdict(set)
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.search(r"LS\.set_lang\('([^']+)'\)", line)
        if m:
            lang = m.group(1)
            continue
        m = re.search(r'QAUI (over|edge) (\S+) (.*)$', line)
        if m:
            kind, tag, rest = m.groups()
            rest = re.sub(r'@[-\d.,]+$', '', rest)
            rest = re.sub(r'\(.*\)$', '', rest).strip()
            res[(kind, tag, rest)].add(lang)
    return res
res = parse(sys.argv[1])
rows = [(k, ls) for k, ls in res.items() if 'en-us' not in ls]
rows.sort()
for (kind, tag, rest), ls in rows:
    print('%s\t%s\t%s\t%s' % (kind, ','.join(sorted(ls)), tag, rest[:150]))
print('only_fr_es', len(rows), 'all', len(res), file=sys.stderr)

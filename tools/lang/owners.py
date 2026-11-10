import os, glob, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
src = {}
for p in glob.glob(os.path.join(ROOT, 'assets', '**', '*.lua'), recursive=True):
    if '/localization/' in p or '/smods/' in p or p.endswith('mod_localization.lua'):
        continue
    t = open(p, 'rb').read().decode('utf-8', 'replace')
    src[os.path.relpath(p, os.path.join(ROOT, 'assets'))] = t
def lua_quote(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
keys = set()
for f in sys.argv[1:]:
    for line in open(f, encoding='utf-8'):
        keys.add(line.split('\t')[0])
for k in sorted(keys):
    q1, q2 = '"' + lua_quote(k) + '"', "'" + k.replace("'", "\\'") + "'"
    users = [p for p, t in src.items() if q1 in t or q2 in t]
    print(k + '\t' + ','.join(sorted(users)))

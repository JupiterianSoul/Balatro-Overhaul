import re, sys, os
D = sys.argv[1]
owners = {}
for line in open(sys.argv[2], encoding='utf-8'):
    k, _, u = line.rstrip('\n').partition('\t')
    owners[k] = [x for x in u.split(',') if x]
SKIP_FILES = ('functions/advisor.lua', 'functions/hand_optimizer.lua', 'functions/quests.lua', 'functions/quests_ui.lua',
              'functions/achievements.lua', 'functions/achievements_ui.lua', 'functions/achievements_data.lua',
              'functions/achievements_hooks.lua', 'functions/showcase.lua', 'functions/mod_menu.lua', 'functions/town/town.lua',
              'functions/release_info.lua', 'functions/perf_monitor.lua', 'functions/crash_reports.lua')
SKIP_WORDS = re.compile(r'Town|TOWN|\bMods?\b|\bMODS?\b|Mod [Mm]enu|Advisor|ADVISOR|Optimi[sz]er|OPTIMI|[Cc]hangelog')
def skipped(k):
    u = owners.get(k, [])
    if SKIP_WORDS.search(k):
        return True
    return bool(u) and all(x in SKIP_FILES for x in u)
START = r'(^|(?<=[.!?:]\s)|(?<=^- )|(?<=\()|(?<=\n))'
def cap_aware(v, word, cap, low):
    def rep(m):
        s = m.start()
        pre = v[:s]
        at_start = s == 0 or re.search(r'([.!?:]\s+|^-\s+|^\s+|\(|\n|•\s+)$', pre)
        return cap if at_start else low
    return re.sub(r'\b' + word + r'\b', rep, v)
def fr_rules(v):
    v = re.sub(r'\bDECKS\b', 'JEUX', v)
    v = re.sub(r'\bDECK\b', 'JEU', v)
    v = cap_aware(v, 'Decks', 'Jeux', 'jeux')
    v = cap_aware(v, 'Deck', 'Jeu', 'jeu')
    v = re.sub(r'\bdecks\b', 'jeux', v)
    v = re.sub(r'\bdeck\b', 'jeu', v)
    v = re.sub(r'\bMULT\b', 'MULTI', v)
    v = re.sub(r'\bMult\b(?!\.)', 'Multi', v)
    return v
def es_rules(v):
    v = re.sub(r'\bJOKERS\b', 'COMODINES', v)
    v = re.sub(r'\bJOKER\b', 'COMODÍN', v)
    v = cap_aware(v, 'Jokers', 'Comodines', 'comodines')
    v = cap_aware(v, 'Joker', 'Comodín', 'comodín')
    v = re.sub(r'\bMULT\b', 'MULTI', v)
    v = cap_aware(v, 'Mult', 'Multi', 'multi')
    return v
out = open(sys.argv[3], 'w', encoding='utf-8')
n = {'fr': 0, 'es': 0}
for lang, rules in (('fr', fr_rules), ('es', es_rules)):
    for line in open(os.path.join(D, 'mt_%s.tsv' % lang), encoding='utf-8'):
        k, _, v = line.rstrip('\n').partition('\t')
        if skipped(k):
            continue
        nv = rules(v)
        if nv != v:
            out.write('%s\t%s\t%s\n' % (lang, k, nv))
            n[lang] += 1
print(n)

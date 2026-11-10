import { describe, it, expect } from 'bun:test';
import { filterText, normalizeText, nameIsClean, LEXICONS } from './filter';

const CLEAN: string[] = [
  'class', 'Class', 'CLASS', 'classic joker', 'classes start at nine', 'assassin', 'Assassins Creed', 'assassination', 'Scunthorpe', 'Scunthorpe United won',
  'cocktail', 'cocktail party', 'therapist', 'my therapist said hi', 'therapists', 'analysis', 'analyst', 'assume', 'assistant', 'associate', 'assets',
  'grass', 'bass guitar', 'mass effect', 'passage', 'passenger', 'passport', 'compass', 'embassy', 'harassment', 'hello', 'shell', 'button', 'butter',
  'document', 'Dickens', 'Essex', 'Sussex', 'shiitake', 'shitake mushrooms', 'mishit', 'snigger', 'niggardly', 'niggle', 'cucumber', 'cumulative',
  'raccoon', 'Maine Coon', 'spick and span', 'cocker spaniel', 'peacock', 'Hancock', 'titmouse', 'grape', 'rapeseed', 'arsenal', 'parse', 'sparse',
  'magna cum laude', 'chink in the armor', 'penistone', 'buttress', 'glass joker', 'brass', 'massive', 'massage', 'assess', 'assemble', 'pass the salt',
  "I'll pass", 'Cassandra', 'Hell yeah', 'what the heck', 'oh my god', 'darn it', 'good game', 'gg wp', 'nice hand', 'well played', 'rerolled 3 times',
  'Blueprint and Brainstorm are broken', 'x4 mult', '$50 at ante 8', '1v1 me', '2v2 tonight', 'Red Deck win', 'Lucky Cat', 'Gros Michel', 'Cavendish',
  'Hanging Chad', 'Misprint', 'Mr. Bones', 'The Hanged Man', 'Death card', 'The Tower', 'Wheel of Fortune', 'Wee Joker', 'Hit the Road', 'Ride the Bus',
  'Space Joker', 'Black Hole', 'Burglar', 'Trousers', 'Cryptid', 'Ouija', 'Wraith', 'Sigil', 'Obelisk', 'Egg', 'DNA', 'Hack', 'Mime', 'Baron', 'Bloodstone',
  'classe', 'tasse de cafe', 'calcul mental', 'article de blog', 'vehicule', 'cumul des points', 'reculer', 'dispute', 'fichier', 'technique', 'unique',
  'pique-nique', 'en retard', "j'ai du retard", 'un retard de dix minutes', 'salopette', 'Bitche', 'cul-de-sac', 'assez', 'assiette', 'bassin',
  'bonne partie', 'bien joue', "c'est nul", 'merci beaucoup', 'a bientot', 'je ne comprends pas', 'trop fort', 'passage secret', 'masse de jetons',
  'clase', 'computadora', 'disputa', 'diputado', 'reputacion', 'ridiculo', 'ridículo', 'vehículo', 'músculo', 'espectáculo', 'año', 'mañana', 'niño', 'piña',
  'apenas', 'penetrar', 'pasivo', 'buena partida', 'gracias', 'hasta luego', 'no entiendo', 'muy bien', 'vamos', 'con mucho gusto', 'el joker negro',
  'perro', 'pollo', 'I need 455 chips', 'score 1,234,567,890', '1.234.567.890 points', '1 234 567 890 points', '1234567890', '123456789 chips', '1e308',
  'x1000', '7.5e12', '3.14159265358', '2026-11-02 12:00', '10 20 30 40 50', '12:30:45', 'v1.2.3', 'ante 8 blind 3', 'email me', 'discord is cool',
  'call of duty', 'my name is Bob', '', '   ', '!!!!', '****', '?!?!', '1488', 'a b c d', 'U S A', 'I D K', 'ok.gg', 'wp.gg',
];

describe('filter: innocent text stays clean', () => {
  for (const text of CLEAN) {
    it(`clean: ${JSON.stringify(text)}`, () => {
      const r = filterText(text);
      expect(r.action).toBe('clean');
      expect(r.text).toBe(text);
      expect(r.reasons).toEqual([]);
    });
  }
});

const MASKED: [string, string][] = [
  ['fuck you', '#### you'], ['what the fuck', 'what the ####'], ['This is shit', 'This is ####'], ['you bitch', 'you #####'],
  ['asshole!', '#######!'], ['FUCK', '####'], ['Fuck.', '####.'], ['bullshit', '########'], ['motherfucker', '############'], ['dickhead', '########'],
  ['stfu', '####'], ['gtfo', '####'], ['pussy', '#####'], ['cock', '####'], ['whore', '#####'], ['slut', '####'], ['bastard', '#######'],
  ['wanker', '######'], ['twat', '####'], ['cunt', '####'], ['prick', '#####'], ['douchebag', '#########'], ['piss off', '#### off'],
  ['idiot', '#####'], ['moron', '#####'], ['fucking hell', '####### hell'], ['fucked up', '###### up'], ['shitty joker', '###### joker'],
  ['bitches', '#######'], ['dumbass', '#######'], ['jackass', '#######'], ['you are an ass', 'you are an ###'], ['asses', '#####'],
  ['well, fuck, that was close', 'well, ####, that was close'], ['fuck 😀', '#### 😀'], ['FUCKING', '#######'], ['holy shit lol', 'holy #### lol'],
  ['merde', '#####'], ['putain', '######'], ['quel connard', 'quel #######'], ['salope', '######'], ['ta gueule', '#########'], ['enculé', '######'],
  ['putain de merde', '###### de #####'], ['nique ta mere', '##### ta mere'], ['fdp', '###'], ['ntm', '###'], ['gros con', '########'],
  ['mierda', '######'], ['hijo de puta', '############'], ['qué pendejo', 'qué #######'], ['gilipollas', '##########'], ['cabrón', '######'],
  ['joder', '#####'], ['eres un imbécil', 'eres un #######'], ['hdp', '###'], ['qué mierda', 'qué ######'], ['puto', '####'], ['culo', '####'],
  ['fuuuuuuck', '#########'], ['FUUUUUCK', '########'], ['fück', '####'], ['fúck', '####'], ['ƒuck', '####'], ['ｆｕｃｋ', '####'], ['𝐟𝐮𝐜𝐤', '####'],
  ['ⓕⓤⓒⓚ', '####'], ['fuсk', '####'], ['fυck', '####'], ['ѕhit', '####'], ['fu​ck', '#####'], ['fu­ck', '#####'], ['f‍u‍c‍k', '#######'],
  ['fuk', '###'], ['fck', '###'], ['fvck', '####'], ['phuck', '#####'], ['sh!t', '####'], ['$hit', '####'], ['5h1t', '####'], ['sh1t', '####'], ['shiiit', '######'],
  ['b1tch', '#####'], ['b!tch', '#####'], ['bi7ch', '#####'], ['a$$', '###'], ['@ss', '###'], ['a55', '###'], ['a$$hole', '#######'], ['a55hole', '#######'],
  ['d1ck', '####'], ['c0ck', '####'], ['pu55y', '#####'], ['wh0re', '#####'], ['sl*t', '####'], ['b*tch', '#####'], ['sh*t', '####'], ['f*ck', '####'],
  ['f**k', '####'], ['f***', '####'], ['c*nt', '####'], ['a**hole', '#######'], ['f u c k', '#######'], ['f.u.c.k', '#######'], ['f_u_c_k', '#######'],
  ['f-u-c-k', '#######'], ['f u c k e r', '###########'], ['s h i t', '#######'], ['s.h.i.t', '#######'], ['F U C K', '#######'], ['f u u u c k', '###########'],
  ['you are a f u c k e r', 'you are a ###########'], ['f  u  c  k', '##########'], ['p u t a i n', '###########'], ['m.e.r.d.e', '#########'],
  ['pu7ain', '######'], ['m3rd3', '#####'], ['c0nnard', '#######'], ['mi3rda', '######'], ['p3ndejo', '#######'], ['cabr0n', '######'],
  ['assassinfuck', 'assassin####'], ['classfuck', 'class####'], ['fuckyou', '####you'], ['shutthefuckup', 'shutthe####up'],
];

describe('filter: insults are masked with #', () => {
  for (const [input, expected] of MASKED) {
    it(`masked: ${JSON.stringify(input)}`, () => {
      const r = filterText(input);
      expect(r.action).toBe('masked');
      expect(r.text).toBe(expected);
      expect(r.reasons).toEqual(['insult']);
      expect(Array.from(r.text).length).toBe(Array.from(input).length);
    });
  }
});

const BLOCKED: [string, string][] = [
  ['nigger', 'slur'], ['n1gg3r', 'slur'], ['nigga', 'slur'], ['faggot', 'slur'], ['f4gg0t', 'slur'], ['you retard', 'slur'], ['retarded', 'slur'],
  ['tranny', 'slur'], ['chink', 'slur'], ['spic', 'slur'], ['paki', 'slur'], ['wetback', 'slur'], ['you coon', 'slur'], ['sale juif', 'slur'],
  ['bougnoule', 'slur'], ['sale arabe', 'slur'], ['maricón', 'slur'], ['sudaca', 'slur'], ['negrata', 'slur'], ['joto', 'slur'], ['kkk', 'slur'],
  ['heil hitler', 'slur'], ['white power', 'slur'], ['n i g g e r', 'slur'], ['n.i.g.g.a', 'slur'], ['NIGGER', 'slur'], ['ni**er', 'slur'],
  ['kys', 'threat'], ['KYS', 'threat'], ['kill yourself', 'threat'], ['kill  yourself', 'threat'], ['killyourself', 'threat'], ['k i l l y o u r s e l f', 'threat'],
  ['go die', 'threat'], ['i hope you die', 'threat'], ['i know where you live', 'threat'], ['rapist', 'threat'], ['you are a rapist', 'threat'],
  ['raped', 'threat'], ['hang yourself', 'threat'], ['tue toi', 'threat'], ['suicide toi', 'threat'], ['matate', 'threat'], ['ojala te mueras', 'threat'],
  ['violador', 'threat'], ['se donde vives', 'threat'], ['doxxing', 'threat'], ['pedophile', 'threat'], ['k y s', 'threat'], ['i will find you', 'threat'],
  ['bob@gmail.com', 'pii'], ['mail me at bob@gmail.com', 'pii'], ['john.doe+x@example.org', 'pii'], ['bob (at) gmail (dot) com', 'pii'],
  ['bob at gmail dot com', 'pii'], ['gmail.com', 'pii'], ['call 555 123 4567', 'pii'], ['555-123-4567', 'pii'], ['(555) 123-4567', 'pii'],
  ['+1 555 123 4567', 'pii'], ['+33 6 12 34 56 78', 'pii'], ['06 12 34 56 78', 'pii'], ['06.12.34.56.78', 'pii'], ['0612345678', 'pii'],
  ['612 34 56 78', 'pii'], ['612345678', 'pii'], ['5551234567', 'pii'], ['0 6 1 2 3 4 5 6 7 8', 'pii'], ['07123 456789', 'pii'],
  ['mi numero es 612 345 678', 'pii'], ['my phone 555 123 456', 'pii'], ['call me 123 456 789', 'pii'], ['https://example.com', 'pii'],
  ['visit www.example.com', 'pii'], ['discord.gg/abc', 'pii'], ['http://x.y', 'pii'], ['join t.me/group', 'pii'], ['shop.example.com', 'pii'],
  ['192.168.0.1', 'pii'], ['my ip is 10.0.0.12', 'pii'], ['instagram.com/me', 'pii'],
];

describe('filter: slurs, threats and personal info block the whole message', () => {
  for (const [input, reason] of BLOCKED) {
    it(`blocked ${reason}: ${JSON.stringify(input)}`, () => {
      const r = filterText(input);
      expect(r.action).toBe('blocked');
      expect(r.text).toBe('');
      expect(r.reasons).toContain(reason as never);
    });
  }
});

describe('filter: mixed and structural behaviour', () => {
  it('a slur beats an insult in the same message', () => {
    const r = filterText('fuck you nigger');
    expect(r.action).toBe('blocked');
    expect(r.reasons).toEqual(['slur', 'insult']);
  });

  it('personal info beats an insult', () => {
    expect(filterText('fuck call 555 123 4567').action).toBe('blocked');
  });

  it('several insults are all masked', () => {
    expect(filterText('fuck this shit').text).toBe('#### this ####');
  });

  it('adjacent hits merge into one mask', () => {
    expect(filterText('fuck shit').text).toBe('#### ####');
  });

  it('mask keeps every other character', () => {
    expect(filterText('Hey!  You   fucking   donkey?').text).toBe('Hey!  You   #######   donkey?');
  });

  it('allowlisted words do not hide a glued insult', () => {
    expect(filterText('assassinfuck').action).toBe('masked');
  });

  it('a clean message is returned untouched', () => {
    const r = filterText('Blueprint copies Baron');
    expect(r).toEqual({ action: 'clean', text: 'Blueprint copies Baron', reasons: [] });
  });

  it('is idempotent on masked output', () => {
    const once = filterText('what the fuck is this shit').text;
    expect(filterText(once)).toEqual({ action: 'clean', text: once, reasons: [] });
  });

  it('handles non-string input', () => {
    expect(filterText(undefined as never).action).toBe('clean');
    expect(filterText(5 as never).action).toBe('clean');
  });

  it('survives a very long clean message quickly', () => {
    const t0 = performance.now();
    const r = filterText('a'.repeat(5000));
    expect(r.action).toBe('clean');
    expect(performance.now() - t0).toBeLessThan(500);
  });

  it('survives a pathological run of wildcards quickly', () => {
    const t0 = performance.now();
    filterText(`f${'*'.repeat(190)} x`);
    filterText('*'.repeat(200));
    filterText('f*'.repeat(100));
    expect(performance.now() - t0).toBeLessThan(500);
  });

  it('survives a pathological run of repeated letters quickly', () => {
    const t0 = performance.now();
    expect(filterText(`f${'u'.repeat(190)}ck`).action).toBe('masked');
    filterText('s '.repeat(100));
    expect(performance.now() - t0).toBeLessThan(500);
  });

  it('handles lone surrogates and emoji without throwing', () => {
    expect(() => filterText('\ud83d x \ude00 \u{1F600}\u{1F600}')).not.toThrow();
  });

  it('masks with the same length for astral characters', () => {
    const r = filterText('\u{1F600} fuck \u{1F600}');
    expect(r.text).toBe('\u{1F600} #### \u{1F600}');
  });

  it('a two language message masks both parts', () => {
    expect(filterText('fuck merde').text).toBe('#### #####');
  });
});

describe('filter: normalization', () => {
  const cases: [string, string][] = [
    ['Héllo', 'hello'], ['ÇA va', 'ca va'], ['ñandú', 'nandu'], ['Ｆｕｃｋ', 'fuck'], ['sh1t', 'shit'], ['pаss', 'pass'], ['a​b', 'ab'],
    ['a   b', 'a b'], ['Straße', 'strasse'], ['naïve café', 'naive cafe'], ['$ave', 'save'], ['455', '455'], ['4ss', 'ass'], ['h3ll0', 'hello'],
    ['l33t', 'leet'], ['x4', 'xa'], ['AbC', 'abc'], ['œuf', 'oeuf'], ['ﬁsh', 'fish']
  ];
  for (const [input, expected] of cases) {
    it(`normalizes ${JSON.stringify(input)}`, () => {
      expect(normalizeText(input)).toBe(expected);
    });
  }

  it('collapses long runs of one letter', () => {
    expect(normalizeText('fuuuuuuuuck')).toBe('fuuuuck');
  });

  it('collapses long runs of one symbol', () => {
    expect(normalizeText('a!!!!!!!!b')).toBe('a!!!!b');
  });

  it('leaves digit only tokens alone', () => {
    expect(normalizeText('score 1007 and 4550')).toBe('score 1007 and 4550');
  });
});

describe('filter: names', () => {
  it('accepts normal names', () => {
    for (const n of ['Bob', 'ZOB', 'Jimbo99', 'Bot Lou', 'Marie-Claire', 'Ñoño']) expect(nameIsClean(n)).toBe(true);
  });

  it('rejects names with profanity or slurs', () => {
    for (const n of ['FuckMe', 'xXshitXx', 'n1gger', 'DickHead']) expect(nameIsClean(n)).toBe(false);
  });
});

describe('filter: the word lists', () => {
  const entries: { lang: string; tier: string; kind: string; word: string }[] = [];
  ['en', 'fr', 'es'].forEach((lang, i) => {
    const lex = LEXICONS[i];
    for (const tier of ['insult', 'slur', 'threat'] as const) {
      for (const w of lex[tier].whole) entries.push({ lang, tier, kind: 'whole', word: w });
      for (const w of lex[tier].stem) entries.push({ lang, tier, kind: 'stem', word: w });
    }
  });

  it('has a decent number of entries per language', () => {
    for (const lang of ['en', 'fr', 'es']) expect(entries.filter(e => e.lang === lang).length).toBeGreaterThan(40);
  });

  it('only uses plain lowercase entries', () => {
    for (const e of entries) expect(e.word).toMatch(/^[a-z0-9]+(?: [a-z0-9]+)*\+?$/);
  });

  it('every entry triggers the filter on its own', () => {
    const quiet: string[] = [];
    for (const e of entries) {
      const word = e.word.replace(/\+$/, '');
      if (filterText(word).action === 'clean') quiet.push(`${e.lang}/${e.tier}/${word}`);
    }
    expect(quiet).toEqual([]);
  });

  it('every entry triggers the filter inside a sentence', () => {
    const quiet: string[] = [];
    for (const e of entries) {
      const word = e.word.replace(/\+$/, '');
      if (filterText(`you said ${word} again`).action === 'clean') quiet.push(`${e.lang}/${e.tier}/${word}`);
    }
    expect(quiet).toEqual([]);
  });

  it('every allowlisted word is clean', () => {
    const loud: string[] = [];
    for (const lex of LEXICONS) for (const a of lex.allow) if (filterText(a).action !== 'clean') loud.push(a);
    expect(loud).toEqual([]);
  });

  it('insult entries are masked and slur or threat entries are blocked', () => {
    const wrong: string[] = [];
    for (const e of entries) {
      const word = e.word.replace(/\+$/, '');
      const r = filterText(word);
      if (e.tier === 'insult' && !(r.action === 'masked' || r.action === 'blocked')) wrong.push(word);
      if (e.tier !== 'insult' && r.action !== 'blocked') wrong.push(word);
    }
    expect(wrong).toEqual([]);
  });
});

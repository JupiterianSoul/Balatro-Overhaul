export type FilterAction = 'clean' | 'masked' | 'blocked';
export type FilterReason = 'insult' | 'slur' | 'threat' | 'pii';

export interface FilterResult {
  action: FilterAction;
  text: string;
  reasons: FilterReason[];
}

interface Tier { whole: string[]; stem: string[] }
interface Lexicon { insult: Tier; slur: Tier; threat: Tier; allow: string[] }

const L = (s: string): string[] => s.split(',').map(x => x.trim()).filter(Boolean);

const EN: Lexicon = {
  insult: {
    whole: L(`fuck+, fuk+, fck+, fcuk+, fuq+, fvck+, phuck+, shit+, shite, shyt, bitch+, biatch, bytch, asshole+, arsehole+, ass, asses, asshat+,
      dumbass+, jackass+, smartass+, fatass+, arse, dick+, dickhead+, cock, cocks, cocksucker+, prick+, pussy, pussies, cunt+, twat+, whore+, slut+,
      bastard+, wanker+, wank+, bollocks, bullshit, horseshit, dipshit, shithead+, douche, douchebag+, piss+, tits, titties, penis, dildo+, blowjob+,
      handjob+, jizz, cum, cumshot+, porn+, porno, anal, horny, boner, orgasm+, idiot+, moron+, imbecile+, scumbag+, stfu, gtfo, spaz, motherfucker+,
      mf, milf, nudes`),
    stem: L(`fuck, shit, bitch, cunt, asshole, arsehole, dickhead, cocksuck, jackass, dumbass, bullshit, wanker, whore, masturbat, blowjob, dipshit`),
  },
  slur: {
    whole: L(`nigger+, nigga+, nigg, niggah, faggot+, faggit, fag, fags, fgt, dyke+, tranny, trannies, shemale, retard, retards, retarded, spic, spics,
      spick, chink+, gook+, kikes, wetback+, beaner+, coon, coons, paki, pakis, towelhead+, sandnigger, zipperhead, kkk, heil hitler, sieg heil,
      white power, gas the jews`),
    stem: L(`nigger, nigga, faggot, heilhitler, siegheil, whitepower`),
  },
  threat: {
    whole: L(`kys, kill yourself, kill urself, kill your self, kill ur self, kill yoself, kill yourselves, go die, hope you die, hope u die,
      hope you get cancer, hang yourself, off yourself, neck yourself, slit your wrists, drink bleach, kill your family, kill your mom, kill your mother,
      kill your dad, kill your parents, know where you live, find where you live, i will find you, i ll find you, ill find you, hunt you down irl,
      shoot you irl, shoot up the school, shoot up your school, bomb the school, bomb threat, rape you, rape her, rape him, rape them,
      raped, raping, rapist, rapists, swat you, swatting you, swatted you, doxx+, dox, doxing, pedophile+, paedophile+, paedo, pedofilo, pedofila,
      molester+, molest`),
    stem: L(`rapist, killyourself, pedophil, pedofil, paedophil`),
  },
  allow: L(`class, classic, classics, classes, classy, classify, classical, assassin, assassins, assassinate, assassination, assume, assumes, assumed,
    assist, assistant, associate, assess, asset, assets, assemble, assembly, assure, pass, passes, passage, passenger, passion, passport, mass, massive,
    massage, bass, grass, glass, glasses, brass, compass, embassy, harass, harassment, cocktail, cocktails, cockpit, cockroach, peacock, hancock,
    scunthorpe, therapist, therapists, analysis, analyst, analysts, analytics, shiitake, shitake, mishit, mishits, mishitting, snigger, sniggers,
    sniggered, sniggering, niggardly, niggard, niggle, niggling, cumulative, cumulus, cucumber, document, dickens, dickinson, essex, sussex, middlesex,
    wessex, penistone, buttress, button, butter, hello, shell, raccoon, maine coon, spick and span, spic and span, cocker spaniel, titmouse,
    grape, drape, scrape, therapeutic, rapeseed, arsenal, parse, sparse, cum laude, magna cum laude, summa cum laude, bitche, salopette, salopettes,
    pique nique, cul de sac, assez, assiette, bassin, fichier, technique, unique, compute, computer, computing, dispute, disputes, reputation,
    computadora, computadoras, ridiculo, vehiculo, musculo, espectaculo, obstaculo, particula, spasm, spasms,
    en retard, du retard, un retard, le retard, ce retard, mon retard, ton retard, son retard, de retard, sans retard, avec retard, des retards,
    les retards, petit retard, gros retard, pas de retard, quelques retards, beaucoup de retard, plein de retard, chink in the armor, chink in the armour,
    chink in your armor, chink in my armor, chink in his armor, chink in her armor, chinks in the armor, chinks in the armour,
    analyze, analyse, analyses, canal, canals, banal, analogy, analog, analogue, penitent, scunthorpe united`),
};

const FR: Lexicon = {
  insult: {
    whole: L(`merde+, merdeux, merdique, merdier, putain, putains, pute+, salope+, salaud+, connard+, connasse+, conne, connes, couille+, couillon+,
      bordel, foutre, encule+, enculer, enculez, nique+, niquer, niquent, niquez, ntm, fdp, batard+, batarde, chier, chiant+, chiante, chiants,
      branleur+, branler, branlette+, cul, culs, debile+, abruti+, cretin+, trouduc, trou du cul, petasse+, pouffiasse+, grognasse+, ta gueule,
      te faire foutre, ferme ta gueule, sale con, gros con`),
    stem: L(`putain, merde, enculer, encule, connard, connasse, salope, trouduc`),
  },
  slur: {
    whole: L(`negre+, negresse+, bamboula, bougnoule+, youpin+, youpine, chinetoque+, fiotte+, pede+, gouine+, sale juif, sale arabe, sale noir,
      sale negre, sale chinois, sale blanc, sale race, sale pd`),
    stem: L(`bougnoule, chinetoque`),
  },
  threat: {
    whole: L(`tue toi, tuetoi, tue toi meme, suicide toi, suicidetoi, va te tuer, vas te tuer, va crever, vas crever, je sais ou tu habites,
      je sais ou tu vis, je vais te retrouver, te violer, violeur+, violeurs, pedophile+, va te pendre, pends toi`),
    stem: L(`violeur, suicidetoi, tuetoi`),
  },
  allow: L(`bitche, assassinat, passe, masse, tasse, grasse, calcul, article, cumul, reculer`),
};

const ES: Lexicon = {
  insult: {
    whole: L(`mierda+, mierdas, puta+, putas, puto+, putos, putada+, putero+, hijueputa, hijoeputa, hdp, cabron+, cabrona+, cabrones, pendejo+, pendeja+,
      gilipollas, gilipolla, gilipuertas, imbecil+, idiota+, estupido+, estupida+, cojones, cojon, cono, carajo, verga+, polla+, chingar, chinga, chingada,
      chingado, chingue, chingas, culero+, culera+, culo+, joder, jodete, jodido, jodida, mamada+, mamon+, mamones, lameculos, capullo+, zorra+, pinche+,
      ptm, ctm, malparido+, malparida+, gonorrea, pelotudo+, pelotuda+, vete a la mierda, concha de tu madre, hijo de puta, tu puta madre, la puta madre`),
    stem: L(`mierda, hijueputa, gilipollas, cabron, pendejo, chingad, malparido, lameculos`),
  },
  slur: {
    whole: L(`maricon+, maricones, marica+, maricas, joto+, jotos, trolo+, sudaca+, negrata+, subnormal+, mongolico+, mongolica, bollera+, tortillera+,
      travelo+, sudacas`),
    stem: L(`maricon, negrata`),
  },
  threat: {
    whole: L(`matate, suicidate, muerete, ojala te mueras, ojala que te mueras, andate a morir, vete a morir, se donde vives, se donde vivis,
      voy a violarte, te voy a violar, violador+, violadores, pedofilo+, pedofila+`),
    stem: L(`matate, suicidate, violador`),
  },
  allow: L(`disputa, diputado, reputacion, particulas, pasivo, penetracion`),
};

export const LEXICONS = [EN, FR, ES];

const LOOK_SRC: Record<string, string> = {
  a: 'аАαΑɑᴀ',
  b: 'вВβΒʙ',
  c: 'сСϲϹᴄ',
  d: 'ԁᴅ',
  e: 'еЕёЁεΕᴇ',
  f: 'ꜰ',
  g: 'ɡɢ',
  h: 'нНһΗʜ',
  i: 'іІӏιΙɪı',
  j: 'јЈᴊ',
  k: 'кКκΚᴋ',
  l: 'ʟǀ',
  m: 'мМΜᴍ',
  n: 'ηɴ',
  o: 'оОοΟᴏ',
  p: 'рРρΡᴘ',
  q: 'ԛ',
  r: 'ʀ',
  s: 'ѕЅꜱ',
  t: 'тТτΤᴛ',
  u: 'υμᴜ',
  v: 'νѵᴠ',
  w: 'ԝωᴡ',
  x: 'хХχΧ',
  y: 'уУΥγʏү',
  z: 'ζΖᴢ',
};

const LOOK = new Map<string, string>();
for (const [latin, chars] of Object.entries(LOOK_SRC)) for (const ch of chars) LOOK.set(ch, latin);

const SPECIAL: Record<string, string> = {
  'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'ø': 'o', 'đ': 'd', 'ð': 'd', 'þ': 'th', 'ł': 'l', 'ħ': 'h', 'ŧ': 't', 'ƒ': 'f',
};

const LEET: Record<string, string> = {
  '0': 'o', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's', '8': 'b', '9': 'g', '€': 'e', '¢': 'c', '£': 'l', '¥': 'y',
};

const INVISIBLE = /[­͏؜ᅟᅠ឴឵᠋-᠎​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ]/;
const INVISIBLE_ALL = new RegExp(INVISIBLE.source, 'g');
const MARK = /\p{M}/u;
const SPACE = /[\s\u0000-\u001f\u007f-\u009f]/;

const isLetter = (c: string | undefined): boolean => c !== undefined && c >= 'a' && c <= 'z';
const isAlnum = (c: string | undefined): boolean => c !== undefined && ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'));

function foldChar(ch: string): string {
  const direct = LOOK.get(ch);
  if (direct) return direct;
  let out = '';
  for (const c of ch.normalize('NFKD')) {
    if (MARK.test(c)) continue;
    const m = LOOK.get(c);
    if (m) { out += m; continue; }
    for (const l of c.toLowerCase()) {
      if (MARK.test(l)) continue;
      out += LOOK.get(l) ?? SPECIAL[l] ?? l;
    }
  }
  return out;
}

interface View { chars: string[]; st: number[]; en: number[] }

function fold(text: string): View {
  const chars: string[] = [], st: number[] = [], en: number[] = [];
  let run = 0;
  const push = (c: string, s: number, e: number): void => {
    const last = chars.length - 1;
    if (last >= 0 && chars[last] === c) {
      run++;
      const limit = c === ' ' ? 1 : 4;
      if (run > limit) { en[last] = e; return; }
    } else run = 1;
    chars.push(c); st.push(s); en.push(e);
  };
  for (let i = 0; i < text.length;) {
    const cp = text.codePointAt(i) as number;
    const ch = String.fromCodePoint(cp);
    const next = i + ch.length;
    if (INVISIBLE.test(ch)) {
      if (en.length) en[en.length - 1] = next;
    } else if (SPACE.test(ch)) {
      push(' ', i, next);
    } else {
      const f = foldChar(ch);
      if (f === '') { if (en.length) en[en.length - 1] = next; } else for (const c of f) push(c.length > 1 ? '\u0002' : c, i, next);
    }
    i = next;
  }
  return { chars, st, en };
}

function leetVariants(view: View): string[] {
  const { chars } = view;
  const outA: string[] = [], outB: string[] = [];
  let variant = false;
  let a = 0;
  while (a < chars.length) {
    if (chars[a] === ' ') { outA.push(' '); outB.push(' '); a++; continue; }
    let b = a;
    while (b < chars.length && chars[b] !== ' ') b++;
    let letters = false;
    for (let p = a; p < b; p++) if (isLetter(chars[p])) { letters = true; break; }
    for (let p = a; p < b; p++) {
      const c = chars[p];
      if (!letters) { outA.push(c); outB.push(c); continue; }
      const mapped = LEET[c];
      if (mapped) { outA.push(mapped); outB.push(mapped); continue; }
      if (c === '1') { outA.push('i'); outB.push('l'); variant = true; continue; }
      if ((c === '!' || c === '|') && p > a && p < b - 1 && isAlnum(chars[p - 1]) && isAlnum(chars[p + 1])) {
        outA.push('i'); outB.push(c === '!' ? 'i' : 'l'); variant = variant || c === '|';
        continue;
      }
      outA.push(c); outB.push(c);
    }
    a = b;
  }
  const first = outA.join('');
  return variant ? [first, outB.join('')] : [first];
}

export function normalizeText(text: string): string {
  return leetVariants(fold(text))[0];
}

const SUFFIX = '(?:s|es|ed|er|ers|ing|ings|in|y|ie|ies)?';

function entryPattern(entry: string): string {
  let out = '';
  entry.split(' ').forEach((part, pi) => {
    if (pi > 0) out += '[^a-z]*';
    let i = 0;
    while (i < part.length) {
      const c = part[i];
      let j = i;
      while (j < part.length && part[j] === c) j++;
      out += `[${c}*]{${j - i},}`;
      i = j;
    }
  });
  return out;
}

interface Matchers { whole: RegExp | null; stem: RegExp | null; any: RegExp | null }

function buildMatchers(tier: Tier): Matchers {
  const wholeAlts = tier.whole.map(e => {
    const inflect = e.endsWith('+');
    return entryPattern(inflect ? e.slice(0, -1) : e) + (inflect ? SUFFIX : '');
  });
  const stemAlts = tier.stem.map(e => entryPattern(e));
  const anyAlts = wholeAlts.concat(stemAlts);
  return {
    whole: wholeAlts.length ? new RegExp(`(?<![a-z])(?:${wholeAlts.join('|')})(?![a-z])`, 'g') : null,
    stem: stemAlts.length ? new RegExp(`(?:${stemAlts.join('|')})`, 'g') : null,
    any: anyAlts.length ? new RegExp(`(?:${anyAlts.join('|')})`, 'g') : null,
  };
}

function joinTiers(pick: (l: Lexicon) => Tier): Tier {
  return {
    whole: LEXICONS.flatMap(l => pick(l).whole),
    stem: LEXICONS.flatMap(l => pick(l).stem),
  };
}

const MATCHERS: Record<'insult' | 'slur' | 'threat', Matchers> = {
  insult: buildMatchers(joinTiers(l => l.insult)),
  slur: buildMatchers(joinTiers(l => l.slur)),
  threat: buildMatchers(joinTiers(l => l.threat)),
};

const ALLOW = new RegExp(
  `(?<![a-z])(?:${[...new Set(LEXICONS.flatMap(l => l.allow))].map(e => e.split(' ').join('[^a-z]+')).join('|')})(?![a-z])`,
  'g',
);

function neutralize(v: string): string {
  return v.replace(ALLOW, m => '\u0001'.repeat(m.length));
}

interface Hit { reason: 'insult' | 'slur' | 'threat'; a: number; b: number }

function scanPlain(v: string, view: View, hits: Hit[]): void {
  for (const reason of ['insult', 'slur', 'threat'] as const) {
    const m = MATCHERS[reason];
    for (const re of [m.whole, m.stem]) {
      if (!re) continue;
      re.lastIndex = 0;
      for (const x of v.matchAll(re)) {
        const real = (x[0].match(/[a-z]/g) ?? []).length;
        if (real === 0 || (reason !== 'insult' && x[0].includes('*') && real < 3)) continue;
        hits.push({ reason, a: view.st[x.index as number], b: view.en[(x.index as number) + x[0].length - 1] });
      }
    }
  }
}

function scanSpaced(v: string, view: View, hits: Hit[]): void {
  const runs: { s: string; idx: number[]; last: number }[] = [];
  let cur: { s: string; idx: number[]; last: number } | null = null;
  for (let p = 0; p < v.length; p++) {
    if (!isLetter(v[p])) continue;
    const alone = !isLetter(v[p - 1]) && !isLetter(v[p + 1]);
    if (alone) {
      if (cur && p - cur.last <= 4) { cur.s += v[p]; cur.idx.push(p); cur.last = p; } else {
        if (cur) runs.push(cur);
        cur = { s: v[p], idx: [p], last: p };
      }
    } else if (cur) { runs.push(cur); cur = null; }
  }
  if (cur) runs.push(cur);
  for (const run of runs) {
    if (run.idx.length < 3) continue;
    for (const reason of ['insult', 'slur', 'threat'] as const) {
      const re = MATCHERS[reason].any;
      if (!re) continue;
      re.lastIndex = 0;
      for (const x of run.s.matchAll(re)) {
        const first = run.idx[x.index as number], last = run.idx[(x.index as number) + x[0].length - 1];
        hits.push({ reason, a: view.st[first], b: view.en[last] });
      }
    }
  }
}

const PHONE_WORDS = /(?<![a-z])(?:phone|tel|telephone|telefono|telefon|mobile|movil|portable|cell|whatsapp|wasap|wsp|sms|call|llama|llamame|appelle|appel|numero|number|num|contact)(?![a-z])/;
const EMAIL = [
  /[a-z0-9._%+\-]{1,64}@[a-z0-9\-]{1,63}(?:\.[a-z0-9\-]{2,24}){1,3}/,
  /[a-z0-9._%+\-]{1,64}\s*(?:\(at\)|\[at\]|\{at\})\s*[a-z0-9\-]{1,63}/,
  /(?<![a-z])[a-z0-9._\-]{2,64}\s+at\s+[a-z0-9\-]{2,30}\s+dot\s+[a-z]{2,10}(?![a-z])/,
  /(?<![a-z])(?:gmail|googlemail|hotmail|outlook|yahoo|icloud|protonmail|aol|gmx|yandex|wanadoo|laposte|sfr)\s*(?:\.|dot|\(dot\)|\[dot\])\s*(?:com|fr|es|net|org|co|de|it|uk|ru|me|io)(?![a-z])/,
];
const URL_RE = [
  /https?:\/\/\S+/,
  /(?<![a-z0-9])www\.[a-z0-9\-]{2,}/,
  /(?<![a-z0-9])(?:discord(?:app)?\.(?:gg|com)|t\.me|wa\.me|bit\.ly|tinyurl\.com|youtu\.be|snapchat\.com|instagram\.com|tiktok\.com|facebook\.com|fb\.me|twitter\.com|paypal\.me|twitch\.tv|reddit\.com|steamcommunity\.com)(?![a-z0-9])/,
  /(?<![a-z0-9.])(?:[a-z0-9\-]+\.)*[a-z0-9][a-z0-9\-]{2,}\.(?:com|net|org|io|tv|xyz|ru|cn|tk)(?![a-z0-9])/,
];
const IPV4 = /(?<![\d.])(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?![\d.]*\d)/;
const PHONES = [
  /\+\d{1,3}[\s.\-()]*\d[\d\s.\-()]{6,16}\d/,
  /(?<![\d.,])0[1-9](?:[\s.\-]?\d{2}){4}(?!\d)/,
  /(?<![\d.,])(?:1[\s.\-]?)?\(?[2-9]\d{2}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}(?!\d)/,
  /(?<![\d.,])[6-9]\d{2}[\s.\-]?\d{2}[\s.\-]?\d{2}[\s.\-]?\d{2}(?!\d)/,
  /(?<![\d.,])0\d{3,4}[\s.\-]?\d{3}[\s.\-]?\d{3,4}(?!\d)/,
  /(?<![\d.,])(?:\d[\s.\-]){8,14}\d(?!\d)/,
];
const DIGIT_RUN = /(?<![\d])\d[\d\s.\-()]{7,24}\d(?![\d])/g;

function distinctDigits(s: string): number {
  return new Set(s.replace(/\D/g, '')).size;
}

function hasPii(raw: string): boolean {
  const t = raw.normalize('NFKC').replace(INVISIBLE_ALL, '').toLowerCase();
  const plain = t.normalize('NFKD').replace(/\p{M}/gu, '');
  for (const re of EMAIL) if (re.test(plain)) return true;
  for (const re of URL_RE) if (re.test(plain)) return true;
  if (IPV4.test(plain)) return true;
  for (const re of PHONES) {
    const m = re.exec(plain);
    if (!m) continue;
    const digits = m[0].replace(/\D/g, '');
    if (digits.length < 9 || digits.length > 15) continue;
    if (/^(?:19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}/.test(m[0])) continue;
    if (distinctDigits(m[0]) < 4) continue;
    return true;
  }
  if (PHONE_WORDS.test(plain)) {
    for (const m of plain.matchAll(DIGIT_RUN)) {
      const digits = m[0].replace(/\D/g, '');
      if (digits.length >= 9 && digits.length <= 15 && distinctDigits(m[0]) >= 3) return true;
    }
  }
  return false;
}

export function filterText(input: string): FilterResult {
  const text = typeof input === 'string' ? input : '';
  if (text.trim() === '') return { action: 'clean', text, reasons: [] };
  const hits: Hit[] = [];
  const view = fold(text);
  for (const variant of leetVariants(view)) {
    const v = neutralize(variant);
    scanPlain(v, view, hits);
    scanSpaced(v, view, hits);
  }
  const reasons = new Set<FilterReason>(hits.map(h => h.reason));
  if (hasPii(text)) reasons.add('pii');
  const order: FilterReason[] = ['slur', 'threat', 'pii', 'insult'];
  const list = order.filter(r => reasons.has(r));
  if (list.some(r => r !== 'insult')) return { action: 'blocked', text: '', reasons: list };
  if (hits.length === 0) return { action: 'clean', text, reasons: [] };
  const ranges = hits.map(h => [h.a, h.b] as [number, number]).sort((x, y) => x[0] - y[0] || y[1] - x[1]);
  const merged: [number, number][] = [];
  for (const r of ranges) {
    const last = merged[merged.length - 1];
    if (last && r[0] <= last[1]) last[1] = Math.max(last[1], r[1]); else merged.push([r[0], r[1]]);
  }
  let out = '';
  let pos = 0;
  for (const [a, b] of merged) {
    out += text.slice(pos, a) + '#'.repeat(Array.from(text.slice(a, b)).length);
    pos = b;
  }
  out += text.slice(pos);
  return { action: 'masked', text: out, reasons: list };
}

export function nameIsClean(name: string): boolean {
  return filterText(name).action === 'clean';
}

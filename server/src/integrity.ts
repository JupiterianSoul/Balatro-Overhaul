export interface Flag { code: string; detail: string }

export interface ModRef { id: string; version?: string }

export const BASE_ALLOWED_MODS = ['Balatro', 'Steamodded', 'Lovely'];
export const HANDS_MAX = 30;
export const DISCARDS_MAX = 30;

export function allowedMods(extra: string | undefined = process.env.RANKED_ALLOWED_MODS): Set<string> {
  const out = new Set(BASE_ALLOWED_MODS);
  for (const id of (extra ?? '').split(/[\s,]+/)) if (id) out.add(id);
  return out;
}

export function blockedMods(mods: ModRef[] | undefined, allow: Set<string> = allowedMods()): string[] {
  const out: string[] = [];
  for (const m of mods ?? []) if (m && typeof m.id === 'string' && !allow.has(m.id) && !out.includes(m.id)) out.push(m.id);
  return out;
}

const SCORE_RE = /^\s*(?:\+?(?:\d+(?:\.\d*)?|\.\d+)(?:e\+?\d+)?|inf(?:inity)?|naneinf|e+\d+(?:\.\d*)?(?:#\d+)?)\s*$/i;

export function scoreOk(v: unknown): boolean {
  if (typeof v === 'number') return Number.isFinite(v) && v >= 0;
  if (typeof v === 'string') return v.length <= 64 && SCORE_RE.test(v);
  return false;
}

export function scoreText(v: unknown): string {
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : '0';
  if (typeof v === 'string' && scoreOk(v)) return v.trim();
  return '0';
}

export function scoreLog10(v: unknown): number {
  if (!scoreOk(v)) return 0;
  if (typeof v === 'number') return v > 0 ? Math.log10(v) : 0;
  const s = String(v).trim().toLowerCase();
  if (/^(inf|infinity|naneinf)$/.test(s) || s.startsWith('e')) return Infinity;
  const m = /^\+?(\d*)(?:\.(\d*))?(?:e\+?(\d+))?$/.exec(s);
  if (!m) return 0;
  const exp = Number(m[3] ?? 0);
  const intPart = (m[1] ?? '').replace(/^0+/, '');
  if (intPart.length > 0) {
    const digits = intPart + (m[2] ?? '');
    return exp + intPart.length - 1 + Math.log10(Number(`${digits[0]}.${digits.slice(1, 15) || '0'}`));
  }
  const frac = m[2] ?? '';
  const n = Number(`0.${frac || '0'}`);
  return n > 0 ? exp + Math.log10(n) : 0;
}

export function plausibleLog10(ante: number): number {
  return 3 + 2.5 * Math.max(1, Math.floor(Number(ante) || 1));
}

export interface Track { ante: number | null; hands: number | null; discards: number | null; implausible: Set<number> }

export function newTrack(): Track { return { ante: null, hands: null, discards: null, implausible: new Set() }; }

function countOk(v: unknown, max: number): boolean {
  return typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= max;
}

function countOf(msg: Record<string, unknown>, keys: string[]): unknown {
  for (const k of keys) if (msg[k] !== undefined) return typeof msg[k] === 'string' && /^\d+$/.test(msg[k] as string) ? Number(msg[k]) : msg[k];
  return undefined;
}

export interface Verdict { reject: boolean; flags: Flag[] }

const SCORE_TYPES = new Set(['blind_finished', 'play_hand', 'live_stat']);

export function checkMessage(track: Track, msg: Record<string, unknown>): Verdict {
  const flags: Flag[] = [];
  let reject = false;
  const t = msg.type;
  if (t === 'blind_entered' && typeof msg.ante === 'number' && Number.isFinite(msg.ante)) {
    if (track.ante !== null && msg.ante > track.ante + 1) {
      flags.push({ code: 'ante_jump', detail: `${track.ante} to ${msg.ante}` });
      reject = true;
    } else {
      track.ante = msg.ante;
    }
  }
  if (typeof t === 'string' && SCORE_TYPES.has(t)) {
    if (msg.score !== undefined && !scoreOk(msg.score)) {
      flags.push({ code: 'bad_score', detail: String(msg.score).slice(0, 40) });
      reject = true;
    }
    const hands = countOf(msg, ['hands_left', 'hands']);
    if (hands !== undefined) {
      if (!countOk(hands, HANDS_MAX)) { flags.push({ code: 'hands_max', detail: String(hands).slice(0, 20) }); reject = true; }
      else track.hands = hands as number;
    }
    const discards = countOf(msg, ['discards_left', 'discards']);
    if (discards !== undefined) {
      if (!countOk(discards, DISCARDS_MAX)) { flags.push({ code: 'discards_max', detail: String(discards).slice(0, 20) }); reject = true; }
      else track.discards = discards as number;
    }
    const ante = typeof msg.ante === 'number' && Number.isFinite(msg.ante) ? msg.ante : track.ante ?? 1;
    if (!reject && msg.score !== undefined && scoreLog10(msg.score) > plausibleLog10(ante) && !track.implausible.has(ante)) {
      track.implausible.add(ante);
      flags.push({ code: 'implausible_score', detail: `${scoreText(msg.score)} at ante ${ante}` });
    }
  }
  return { reject, flags };
}

export function lifeGainAllowed(settings: Record<string, unknown> | undefined, kind: string): boolean {
  const s = settings ?? {};
  if (s.life_steal === true) return true;
  if (kind === 'party') {
    const pk = String(s.party_kind ?? '');
    if (pk === 'teams' || pk === 'raid') return true;
  }
  const rules = s.rules && typeof s.rules === 'object' ? s.rules as Record<string, unknown> : {};
  return rules.life_gain === true || (typeof rules.extra_lives === 'number' && rules.extra_lives > 0);
}

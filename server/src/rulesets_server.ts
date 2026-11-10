export interface Bans { jokers: string[]; consumables: string[]; vouchers: string[]; blinds: string[]; tags: string[] }

export interface Ruleset {
  id: string;
  name: string;
  desc: string;
  mode: string;
  settings: Record<string, unknown>;
  bans: Bans;
  reworks: string[];
  layers: string[];
  locked: boolean;
  base?: string;
}

export interface PresetEntry { id: string; name: string; desc: string; mode: string; settings: Record<string, unknown>; bans?: Partial<Bans>; reworks?: string[]; weight?: number }
export interface LayerEntry { id: string; group: string; weight?: number }
export interface DailyPool { presets: PresetEntry[]; layers: LayerEntry[]; decks: string[]; layerCount: { daily: number; weekly: number } }

export type DailyKind = 'daily' | 'weekly';

export interface DailyRuleset { kind: DailyKind; key: string; seed: string; ends_at: number; ruleset: Ruleset }

export const NEMESIS_BLIND = 'bl_mp_nemesis';
const DAY_MS = 86_400_000;
const SEED_CHARS = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ';

export function emptyBans(): Bans { return { jokers: [], consumables: [], vouchers: [], blinds: [], tags: [] }; }

export const BALANCED_REWORKS = ['j_hanging_chad', 'j_bloodstone', 'm_glass'];
export const EXPANDED_REWORKS = ['j_hanging_chad', 'j_bloodstone', 'm_glass', 'j_ticket', 'j_selzer', 'j_turtle_bean', 'c_ouija'];
const NO_JUSTICE: Partial<Bans> = { consumables: ['c_justice'] };

export const RANKED_RULESET: Ruleset = {
  id: 'ranked',
  name: 'Ranked',
  desc: 'The same fixed rules for every ranked match.',
  mode: 'nemesis',
  settings: {
    mode: 'nemesis', starting_lives: 4, pvp_start_round: 2, showdown_starting_antes: 1, win_ante: false, stake: 1, deck: 'Red Deck',
    different_decks: false, different_seeds: false, custom_seed: 'random', gold_on_life_loss: true, no_gold_on_round_loss: false,
    death_on_round_loss: true, pvp_win_money: 0, life_steal: false, timer: true, timer_base_seconds: 150, timer_increment_seconds: 0,
    timer_forgiveness: 1, pvp_countdown_seconds: 3, the_order: true, balance_enabled: true, multiplayer_jokers: true, normal_bosses: false,
    allow_advisor: false, allow_hand_optimizer: false, allow_score_preview: false, per_player_jokers: false, my_starting_jokers: [], rules: {},
    allow_fast_speed: false, allow_score_speed: false, allow_skip_score: false, show_seed: false,
    spectate: true, spectate_jokers: false, hide_opp_score: true, layers: [], ruleset_id: 'ranked',
  },
  bans: { ...emptyBans(), consumables: ['c_justice'] },
  reworks: BALANCED_REWORKS.slice(),
  layers: [],
  locked: true,
};

export const DAILY_POOL: DailyPool = {
  presets: [
    { id: 'nemesis_classic', name: 'Classic', desc: 'Our standard MP rules, no reworks', mode: 'nemesis', settings: {} },
    { id: 'nemesis_balanced', name: 'Balanced', desc: 'MP balance reworks, Justice banned', mode: 'nemesis', settings: { the_order: true }, bans: NO_JUSTICE, reworks: BALANCED_REWORKS, weight: 1.5 },
    { id: 'nemesis_vanilla', name: 'Vanilla', desc: 'Plain Balatro cards, no MP jokers or reworks', mode: 'nemesis', settings: { multiplayer_jokers: false, the_order: false }, weight: 0.7 },
    { id: 'nemesis_traditional', name: 'Slow burn', desc: 'Balanced plus more reworks, no timer', mode: 'nemesis', settings: { timer: false, the_order: true }, bans: NO_JUSTICE, reworks: EXPANDED_REWORKS },
    { id: 'faceoff_balanced', name: 'Balanced', desc: 'MP balance reworks, Justice banned', mode: 'faceoff', settings: { the_order: true }, bans: NO_JUSTICE, reworks: BALANCED_REWORKS, weight: 0.7 },
    { id: 'faceoff_duel', name: 'Quick duel', desc: 'Two lives, ends at ante 4, a head start', mode: 'faceoff', settings: { starting_lives: 2, win_ante: 4, rules: { hand_level: 2, dollars: 8 } }, weight: 0.7 },
  ],
  layers: [
    { id: 'clock_blitz', group: 'timer', weight: 0.5 },
    { id: 'clock_pressure', group: 'timer', weight: 0.5 },
    { id: 'clock_relaxed', group: 'timer', weight: 0.5 },
    { id: 'glass_sturdy', group: 'glass' },
    { id: 'glass_fragile', group: 'glass' },
    { id: 'econ_inflation', group: 'econ_inflation' },
    { id: 'econ_no_interest', group: 'econ_no_interest', weight: 0.7 },
    { id: 'econ_discard_tax', group: 'econ_discard_tax' },
    { id: 'econ_frugal', group: 'econ_frugal' },
    { id: 'econ_spartan', group: 'econ_spartan', weight: 0.7 },
    { id: 'shop_bigger', group: 'shop_size' },
    { id: 'shop_tight', group: 'shop_size', weight: 0.7 },
    { id: 'shop_mystery', group: 'shop_mystery' },
    { id: 'shared_pockets', group: 'shared_pockets' },
    { id: 'score_wobble', group: 'score_wobble' },
    { id: 'no_red_seals', group: 'no_red_seals' },
    { id: 'no_gambling', group: 'no_gambling' },
    { id: 'small_world', group: 'small_world', weight: 1.5 },
    { id: 'face_down', group: 'face_down', weight: 0.7 },
    { id: 'all_eternal', group: 'all_eternal', weight: 0.5 },
  ],
  decks: ['Red Deck', 'Blue Deck', 'Yellow Deck', 'Green Deck', 'Black Deck', 'Magic Deck', 'Nebula Deck', 'Ghost Deck', 'Abandoned Deck', 'Checkered Deck', 'Zodiac Deck', 'Painted Deck', 'Anaglyph Deck', 'Plasma Deck', 'Erratic Deck'],
  layerCount: { daily: 1, weekly: 2 },
};

let pool: DailyPool = DAILY_POOL;

export function setDailyPool(p: DailyPool): void { pool = p; }

function clone<T>(v: T): T { return JSON.parse(JSON.stringify(v)) as T; }

function withoutNemesis(r: Ruleset): Ruleset {
  r.bans.blinds = r.bans.blinds.filter(b => b !== NEMESIS_BLIND);
  return r;
}

export function rankedRuleset(): Ruleset { return withoutNemesis(clone(RANKED_RULESET)); }

export function rankedSettings(): Record<string, unknown> { return clone(RANKED_RULESET.settings); }

export function hashString(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h >>> 0;
}

export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pickWeighted<T extends { weight?: number }>(list: T[], rand: () => number): T | null {
  const total = list.reduce((a, x) => a + Math.max(0, x.weight ?? 1), 0);
  if (list.length === 0 || total <= 0) return null;
  let x = rand() * total;
  for (const it of list) { x -= Math.max(0, it.weight ?? 1); if (x < 0) return it; }
  return list[list.length - 1];
}

export function isoWeek(at: number): { year: number; week: number; start: number } {
  const d = new Date(at);
  const day = (d.getUTCDay() + 6) % 7;
  const start = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - day);
  const thursday = new Date(start + 3 * DAY_MS);
  const year = thursday.getUTCFullYear();
  const week = Math.floor((thursday.getTime() - Date.UTC(year, 0, 1)) / DAY_MS / 7) + 1;
  return { year, week, start };
}

export function dailyKey(kind: DailyKind, at: number): { key: string; ends_at: number } {
  const d = new Date(at);
  if (kind === 'weekly') {
    const w = isoWeek(at);
    return { key: `${w.year}-W${String(w.week).padStart(2, '0')}`, ends_at: w.start + 7 * DAY_MS };
  }
  const y = d.getUTCFullYear(), m = d.getUTCMonth(), day = d.getUTCDate();
  return { key: `${y}-${String(m + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`, ends_at: Date.UTC(y, m, day + 1) };
}

export function dailyRuleset(kind: DailyKind, at: number, p: DailyPool = pool): DailyRuleset {
  const { key, ends_at } = dailyKey(kind, at);
  const rand = seededRandom(hashString(`${kind}:${key}`));
  const seed = Array.from({ length: 8 }, () => SEED_CHARS[Math.floor(rand() * SEED_CHARS.length)]).join('');
  const preset = pickWeighted(p.presets, rand) ?? { id: 'classic', name: 'Classic', desc: '', mode: 'nemesis', settings: {} };
  const deck = p.decks.length > 0 ? p.decks[Math.floor(rand() * p.decks.length)] : undefined;
  const want = Math.max(0, kind === 'weekly' ? p.layerCount.weekly : p.layerCount.daily);
  const layers: string[] = [];
  const groups = new Set<string>();
  let left = p.layers.slice();
  while (layers.length < want && left.length > 0) {
    const l = pickWeighted(left, rand);
    if (!l) break;
    layers.push(l.id);
    groups.add(l.group);
    left = left.filter(x => x !== l && !groups.has(x.group));
  }
  const id = `${kind}-${key}`;
  const settings: Record<string, unknown> = { ...clone(preset.settings), mode: preset.mode, layers, ruleset_id: id, custom_seed: seed };
  if (deck) settings.deck = deck;
  const bans: Bans = { ...emptyBans(), ...clone(preset.bans ?? {}) };
  const ruleset: Ruleset = withoutNemesis({
    id, name: preset.name, desc: preset.desc, mode: preset.mode, settings, bans, reworks: clone(preset.reworks ?? []), layers, locked: true, base: preset.id,
  });
  return { kind, key, seed, ends_at, ruleset };
}

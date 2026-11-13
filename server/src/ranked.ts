import { MemoryStore, type PlayerRow, type RankedStore, type HistoryRow } from './ranked_store';

export const RANK_NAMES = ['Stone', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Foiled', 'Holographic', 'Polychromed', 'Negative', 'TRUE JIMBO'] as const;
export const TIER_RP = 100;
export const RANK_RP = 300;
export const LEGEND_RANK = 9;
export const LEGEND_RP = LEGEND_RANK * RANK_RP;
export const LOSS_MUL = [0.25, 0.4, 0.55, 0.7, 0.85, 1, 1, 1, 1, 1.1];
export const MIN_ANTE = 2;

export type Mode = '1v1' | 'br' | 'teams' | 'raid';
export type Result = 'win' | 'lose' | 'draw';
export const CASUAL_RATED = false;

export interface RankInfo { rank: number; tier: number; name: string; floor: number; next: number | null }

export function rankOf(rp: number): RankInfo {
  const v = Math.max(0, Math.floor(rp));
  if (v >= LEGEND_RP) return { rank: LEGEND_RANK, tier: 0, name: RANK_NAMES[LEGEND_RANK], floor: LEGEND_RP, next: null };
  const rank = Math.floor(v / RANK_RP);
  const step = Math.floor((v % RANK_RP) / TIER_RP);
  const floor = rank * RANK_RP + step * TIER_RP;
  return { rank, tier: 3 - step, name: RANK_NAMES[rank], floor, next: floor + TIER_RP };
}

export interface SeatIn {
  pkey?: string;
  name: string;
  bot: boolean;
  placement: number;
  result: Result;
  ante: number;
  score: number;
  team?: number;
  pid?: number;
}

export interface MatchIn {
  id: string;
  mode: Mode;
  at: number;
  seats: SeatIn[];
  held?: boolean;
}

export interface Line { k: string; v: number }

export interface DeltaOut { delta: number; lines: Line[]; botFactor: number; counted: boolean; reason: string | null }

export function botFactor(m: MatchIn, me: SeatIn): number {
  const opps = m.mode === 'raid' ? m.seats.filter(s => s !== me) : m.seats.filter(s => s !== me && (m.mode !== 'teams' || s.team !== me.team));
  if (opps.length === 0) return 0.5;
  const humans = opps.filter(s => !s.bot).length;
  return 0.5 + 0.5 * (humans / opps.length);
}

export function placementPoints(m: MatchIn, me: SeatIn): number {
  if (me.result === 'draw') return 0;
  if (m.mode === 'raid') return me.result === 'win' ? 18 : -10;
  if (m.mode === 'br') {
    const n = m.seats.length;
    if (n <= 1) return 0;
    const frac = (n - Math.min(n, Math.max(1, me.placement))) / (n - 1);
    return Math.round(-20 + 44 * frac);
  }
  return me.result === 'win' ? 24 : -20;
}

export function anteBonus(ante: number): number { return Math.max(0, Math.min(8, Math.floor(ante) - 1)); }

export function scoreBonus(score: number): number {
  if (!(score > 0)) return 0;
  return Math.max(0, Math.min(5, Math.floor(Math.log10(score)) - 3));
}

export function streakBonus(streak: number): number { return Math.min(10, Math.max(0, streak) * 2); }

export function computeDelta(m: MatchIn, me: SeatIn, rp: number, streak: number): DeltaOut {
  const f = botFactor(m, me);
  const maxAnte = Math.max(...m.seats.map(s => s.ante || 0));
  if (maxAnte < MIN_ANTE) return { delta: 0, lines: [], botFactor: f, counted: false, reason: 'short' };
  const base = placementPoints(m, me);
  const ante = anteBonus(me.ante);
  const score = scoreBonus(me.score);
  const won = me.result === 'win' || (m.mode === 'br' && me.placement === 1);
  const strk = won ? streakBonus(streak) : 0;
  const placeLine = base < 0 ? Math.round(base * LOSS_MUL[rankOf(rp).rank]) : base;
  const anteLine = base < 0 ? Math.floor(ante / 2) : ante;
  const scoreLine = base < 0 ? Math.floor((ante + score) / 2) - anteLine : score;
  const sum = placeLine + anteLine + scoreLine + strk;
  const raw = base < 0 ? Math.min(0, sum) : sum;
  const scaled = Math.round(sum * f) + 0;
  const delta = Math.max(-rp, Math.round(raw * f)) + 0;
  const lines: Line[] = [
    { k: 'placement', v: placeLine },
    { k: 'ante', v: anteLine },
    { k: 'score', v: scoreLine },
    { k: 'streak', v: strk },
    { k: 'bots', v: Math.round(f * 100) },
  ];
  if (delta !== scaled) lines.push({ k: 'floor', v: delta - scaled });
  return { delta, lines, botFactor: f, counted: true, reason: null };
}

export function xpGain(me: SeatIn, f: number): number {
  const base = 60 + Math.min(140, 15 * Math.max(0, me.ante - 1)) + (me.result === 'win' || me.placement === 1 ? 40 : 0);
  return Math.round(base * f);
}

export function xpNeed(level: number): number { return Math.min(1500, 300 + 50 * (Math.max(1, level) - 1)); }

export function addXp(level: number, xp: number, gain: number): { level: number; xp: number; ups: number } {
  let l = Math.max(1, level), x = Math.max(0, xp) + Math.max(0, gain), ups = 0;
  while (x >= xpNeed(l) && ups < 50) { x -= xpNeed(l); l++; ups++; }
  return { level: l, xp: x, ups };
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const QUARTER_NAMES = ['Winter', 'Spring', 'Summer', 'Autumn'];
export const LEGACY_CUTOFF = '2026-11';
const SEASON_ID_RE = /^[0-9]{4}-(?:[0-9]{2}|Q[1-4])$/;

export interface Season { id: string; name: string; starts: number; ends: number; year: number; quarter: number }

export function seasonAt(at: number): Season {
  const d = new Date(at);
  const y = d.getUTCFullYear(), q = Math.floor(d.getUTCMonth() / 3);
  return {
    id: `${y}-Q${q + 1}`,
    name: `${QUARTER_NAMES[q]} ${y}`,
    starts: Date.UTC(y, q * 3, 1),
    ends: Date.UTC(y, q * 3 + 3, 1),
    year: y,
    quarter: q + 1,
  };
}

export function seasonLabel(id: string): string | null {
  const q = /^([0-9]{4})-Q([1-4])$/.exec(id);
  if (q) return `${QUARTER_NAMES[Number(q[2]) - 1]} ${q[1]}`;
  const m = /^([0-9]{4})-([0-9]{2})$/.exec(id);
  if (m && MONTHS[Number(m[2]) - 1]) return `${MONTHS[Number(m[2]) - 1]} ${m[1]}`;
  return null;
}

export function quarterOfMonth(id: string): string | null {
  const m = /^([0-9]{4})-([0-9]{2})$/.exec(id);
  if (!m || Number(m[2]) < 1 || Number(m[2]) > 12) return null;
  return seasonAt(Date.UTC(Number(m[1]), Number(m[2]) - 1, 1)).id;
}

export function softReset(rp: number): number { return Math.max(0, Math.floor(rp) - RANK_RP); }

export type Slot = 'title' | 'flame' | 'burst' | 'back' | 'celebration' | 'badge' | 'cframe' | 'jframe';
export const SLOTS: Slot[] = ['badge', 'title', 'back', 'cframe', 'jframe', 'flame', 'burst', 'celebration'];
export type Rarity = 'common' | 'uncommon' | 'rare' | 'legendary';

export interface Item { id: string; type: Slot; name: string; rarity: Rarity; value: string | number; source: 'rank' | 'pack' | 'season' }

const RANK_TITLES = ['Bedrock', 'Bronze Nerves', 'Silver Tongue', 'Golden Touch', 'Platinum Standard', 'Foiled Again', 'Holo Hero', 'Prismatic', 'Negative Space', 'The Real Jimbo'];
const RANK_SHADERS = ['stone', 'voucher', 'hologram', 'voucher', 'booster', 'foil', 'holo', 'polychrome', 'negative', 'jimbo'];
const RANK_FRAMES = ['9e9ea8', 'b8794a', 'c4ccd6', 'eab840', 'd9e6ee', '99c2f5', 'f08fd1', 'c79eff', '8c6bbf', 'fda300'];
const RANK_FLAMES = ['8a8f99', 'c27a45', 'cdd5de', 'e9b847', 'e3f0f7', '9ad6ff', 'ff8ad8', 'c48bff', '3c2f4f', 'fda200'];

const PACK_ITEMS: Item[] = [
  ['t_highcard', 'title', 'High Card Hero', 'common'], ['t_shoplifter', 'title', 'Shoplifter', 'common'], ['t_chips', 'title', 'Chip Stacker', 'common'],
  ['t_reroll', 'title', 'Reroll Addict', 'common'], ['t_discard', 'title', 'Discard Pile', 'common'], ['t_flush', 'title', 'Flush Rush', 'common'],
  ['t_pair', 'title', 'Pair of Kings', 'common'], ['t_interest', 'title', 'Interest Earner', 'common'],
  ['f_ember', 'flame', 'Ember Flame', 'uncommon', 'ff9a3c'], ['f_mint', 'flame', 'Mint Flame', 'uncommon', '4bc292'], ['f_violet', 'flame', 'Violet Flame', 'uncommon', '8867a5'],
  ['f_ice', 'flame', 'Ice Flame', 'uncommon', '8bd3ff'], ['b_coin', 'burst', 'Coin Burst', 'uncommon', 'f5b143'], ['b_ruby', 'burst', 'Ruby Burst', 'uncommon', 'fe5f55'],
  ['b_sapphire', 'burst', 'Sapphire Burst', 'uncommon', '009dff'],
  ['k_foil', 'back', 'Foil Sleeve', 'rare', 'foil'], ['k_holo', 'back', 'Holo Sleeve', 'rare', 'holo'], ['k_poly', 'back', 'Polychrome Sleeve', 'rare', 'polychrome'],
  ['c_confetti', 'celebration', 'Confetti', 'rare', 'confetti'], ['c_coins', 'celebration', 'Coin Shower', 'rare', 'coins'], ['c_stars', 'celebration', 'Star Burst', 'rare', 'stars'],
  ['k_negative', 'back', 'Negative Sleeve', 'legendary', 'negative'], ['f_rainbow', 'flame', 'Rainbow Flame', 'legendary', 'rainbow'], ['t_jimbo', 'title', "Jimbo's Favourite", 'legendary'],
].map(([id, type, name, rarity, value]) => ({ id, type: type as Slot, name, rarity: rarity as Rarity, value: value ?? name, source: 'pack' as const }));

function rankItems(r: number): Item[] {
  const name = RANK_NAMES[r];
  return [
    { id: `rt_${r}`, type: 'title', name: RANK_TITLES[r], rarity: 'rare', value: RANK_TITLES[r], source: 'rank' },
    { id: `rk_${r}`, type: 'back', name: `${name} Sleeve`, rarity: 'rare', value: RANK_SHADERS[r], source: 'rank' },
    { id: `rf_${r}`, type: 'flame', name: `${name} Flame`, rarity: 'rare', value: RANK_FLAMES[r], source: 'rank' },
    { id: `rb_${r}`, type: 'badge', name: `${name} Badge`, rarity: 'rare', value: r, source: 'rank' },
    { id: `rc_${r}`, type: 'cframe', name: `${name} Card Frame`, rarity: 'rare', value: RANK_FRAMES[r], source: 'rank' },
    { id: `rj_${r}`, type: 'jframe', name: `${name} Joker Frame`, rarity: 'rare', value: RANK_FRAMES[r], source: 'rank' },
  ];
}

export const CATALOG: Item[] = [...Array.from({ length: 10 }, (_, r) => rankItems(r)).flat(), ...PACK_ITEMS];
const CATALOG_BY_ID = new Map(CATALOG.map(i => [i.id, i]));

export function itemInfo(id: string): Item | null {
  const fixed = CATALOG_BY_ID.get(id);
  if (fixed) return fixed;
  const m = /^s([0-9]{4}-(?:[0-9]{2}|Q[1-4]))_(b|k)_([0-9])$/.exec(id);
  if (!m) return null;
  const r = Number(m[3]);
  const label = seasonLabel(m[1]) ?? m[1];
  return m[2] === 'b'
    ? { id, type: 'badge', name: `${label} ${RANK_NAMES[r]} Badge`, rarity: 'legendary', value: r, source: 'season' }
    : { id, type: 'back', name: `${label} Sleeve`, rarity: 'legendary', value: RANK_SHADERS[r], source: 'season' };
}

export function rankUnlocks(fromBest: number, toRank: number): string[] {
  const out: string[] = [];
  for (let r = Math.max(0, fromBest + 1); r <= toRank; r++) out.push(...rankItems(r).map(i => i.id));
  return out;
}

export const RARITY_WEIGHTS: Record<Rarity, number> = { common: 60, uncommon: 28, rare: 10, legendary: 2 };
export const DUPE_XP: Record<Rarity, number> = { common: 25, uncommon: 50, rare: 100, legendary: 250 };
export const PACK_SIZE = 3;

export function rollPackItem(rand: () => number): Item {
  const total = Object.values(RARITY_WEIGHTS).reduce((a, b) => a + b, 0);
  let x = rand() * total;
  let rarity: Rarity = 'common';
  for (const [k, w] of Object.entries(RARITY_WEIGHTS) as [Rarity, number][]) { if (x < w) { rarity = k; break; } x -= w; }
  const pool = PACK_ITEMS.filter(i => i.rarity === rarity);
  return pool[Math.min(pool.length - 1, Math.floor(rand() * pool.length))];
}

const CODE_CHARS = 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
export function newRecoveryCode(rand: () => number = Math.random): string {
  const parts: string[] = [];
  for (let p = 0; p < 3; p++) parts.push(Array.from({ length: 4 }, () => CODE_CHARS[Math.floor(rand() * CODE_CHARS.length)]).join(''));
  return parts.join('-');
}
export function cleanRecoveryCode(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (s.length !== 12 || [...s].some(c => !CODE_CHARS.includes(c))) return null;
  return `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8)}`;
}

interface State {
  row: PlayerRow;
  unlocks: Map<string, string>;
  equipped: Record<string, string>;
  last: Record<string, unknown> | null;
}

export interface Badge { r: number; t: number; n: number | null; title: string | null; badge: string | null }

export class RankedService {
  private cache = new Map<string, State>();
  private loading = new Map<string, Promise<State>>();
  private deferred = new Map<string, ((s: State) => void)[]>();
  private board: { at: number; season: string; rows: PlayerRow[] } | null = null;

  onSeasonEnd?: (pkey: string, info: { season: string; peak: number; rp: number; rank: number; rewards: string[] }) => void;

  constructor(public store: RankedStore, public now: () => number = () => Date.now(), public rand: () => number = Math.random, private log: (level: string, msg: string) => void = () => undefined) {}

  cached(pkey: string): State | null { return this.cache.get(pkey) ?? null; }
  cacheSize(): number { return this.cache.size; }
  clearCache(): void { this.cache.clear(); this.loading.clear(); }

  async load(pkey: string, name?: string): Promise<State> {
    const hit = this.cache.get(pkey);
    if (hit) { this.touch(hit, name); return hit; }
    const going = this.loading.get(pkey);
    if (going) return going;
    const p = this.fetchState(pkey, name).finally(() => this.loading.delete(pkey));
    this.loading.set(pkey, p);
    return p;
  }

  prefetch(pkey: string | undefined, name?: string): void {
    if (!pkey) return;
    this.load(pkey, name).catch(e => this.log('WARN', `ranked prefetch failed: ${String(e).slice(0, 120)}`));
  }

  private async fetchState(pkey: string, name?: string): Promise<State> {
    const row = await this.store.getPlayer(pkey);
    const [unl, eq] = row ? await Promise.all([this.store.getUnlocks(pkey), this.store.getEquipped(pkey)]) : [[], {}];
    const now = this.now();
    const season = seasonAt(now);
    const st: State = {
      row: row ?? {
        pkey, name: name ?? '', rp: 0, rank: 0, peak_rp: 0, best_rank: -1, season: season.id, xp: 0, level: 1, packs: 0, streak: 0,
        recovery: newRecoveryCode(this.rand), created: now, last_seen: now, matches: 0, wins: 0,
      },
      unlocks: new Map(unl.map(u => [u.item, u.source])),
      equipped: eq,
      last: null,
    };
    const existing = this.cache.get(pkey);
    if (existing) return existing;
    this.cache.set(pkey, st);
    if (!row) {
      this.grantRank(st, 0, now);
      this.store.savePlayer(st.row);
    } else {
      for (const id of rankUnlocks(-1, st.row.best_rank)) if (!st.unlocks.has(id)) this.unlock(st, id, 'rank');
    }
    this.touch(st, name);
    const waiting = this.deferred.get(pkey);
    if (waiting) { this.deferred.delete(pkey); for (const fn of waiting) fn(st); }
    return st;
  }

  private touch(st: State, name?: string): void {
    if (name && name !== st.row.name) st.row.name = name;
    st.row.last_seen = this.now();
    this.rollSeason(st);
  }

  rollSeason(st: State): boolean {
    const s = seasonAt(this.now());
    if (st.row.season === s.id) return false;
    let prev = st.row.season;
    const quarter = /^[0-9]{4}-[0-9]{2}$/.test(prev) && prev >= LEGACY_CUTOFF ? quarterOfMonth(prev) : null;
    if (quarter === s.id) {
      st.row.season = s.id;
      this.store.ensureSeason(s.id, s.starts, s.ends, s.name);
      this.store.savePlayer(st.row);
      return true;
    }
    if (quarter) prev = quarter;
    const peak = rankOf(st.row.peak_rp).rank;
    const ended = st.row.matches > 0 && SEASON_ID_RE.test(prev);
    const rewards = ended ? [`s${prev}_b_${peak}`, `s${prev}_k_${peak}`] : [];
    for (const id of rewards) this.unlock(st, id, 'season');
    st.row.rp = softReset(st.row.rp);
    st.row.rank = rankOf(st.row.rp).rank;
    st.row.peak_rp = st.row.rp;
    st.row.season = s.id;
    this.store.ensureSeason(s.id, s.starts, s.ends, s.name);
    this.store.savePlayer(st.row);
    if (ended) {
      try { this.onSeasonEnd?.(st.row.pkey, { season: prev, peak, rp: st.row.rp, rank: st.row.rank, rewards }); } catch (e) { this.log('WARN', `season end hook failed: ${String(e).slice(0, 120)}`); }
    }
    return true;
  }

  private unlock(st: State, id: string, source: string): boolean {
    if (st.unlocks.has(id)) return false;
    st.unlocks.set(id, source);
    this.store.addUnlock(st.row.pkey, id, source, this.now());
    return true;
  }

  private grantRank(st: State, rank: number, _at: number): string[] {
    const got: string[] = [];
    if (rank <= st.row.best_rank) return got;
    for (const id of rankUnlocks(st.row.best_rank, rank)) if (this.unlock(st, id, 'rank')) got.push(id);
    st.row.best_rank = rank;
    return got;
  }

  testSet(st: State, v: { rp?: number; packs?: number; xp?: number; level?: number; all?: boolean }, at: number): string[] {
    const r = st.row;
    if (v.rp !== undefined) { r.rp = Math.max(0, Math.floor(v.rp)); r.rank = rankOf(r.rp).rank; r.peak_rp = Math.max(r.peak_rp, r.rp); }
    if (v.packs !== undefined) r.packs = Math.max(0, Math.floor(v.packs));
    if (v.level !== undefined) r.level = Math.max(1, Math.floor(v.level));
    if (v.xp !== undefined) r.xp = Math.max(0, Math.floor(v.xp));
    const got = this.grantRank(st, r.rank, at);
    if (v.all) for (const it of CATALOG) if (this.unlock(st, it.id, it.source)) got.push(it.id);
    this.store.savePlayer(r);
    this.board = null;
    return got;
  }

  async adjust(pkey: string, delta: number): Promise<void> {
    const st = await this.load(pkey);
    this.rollSeason(st);
    const r = st.row;
    r.rp = Math.max(0, r.rp + Math.round(Number(delta) || 0));
    r.rank = rankOf(r.rp).rank;
    if (delta > 0) { r.peak_rp = Math.max(r.peak_rp, r.rp); this.grantRank(st, r.rank, this.now()); }
    this.store.savePlayer(r);
    this.board = null;
  }

  async recordMatch(m: MatchIn): Promise<Map<string, Record<string, unknown>>> {
    const out = new Map<string, Record<string, unknown>>();
    const humans = m.seats.filter(s => s.pkey && !s.bot);
    const season = seasonAt(m.at);
    this.store.ensureSeason(season.id, season.starts, season.ends, season.name);
    const rows: Parameters<RankedStore['saveMatch']>[1] = [];
    for (const seat of humans) {
      const pkey = seat.pkey as string;
      let st: State | null = null;
      try { st = await this.load(pkey, seat.name); } catch (e) {
        this.log('WARN', `ranked load failed for a player, result deferred: ${String(e).slice(0, 120)}`);
        const list = this.deferred.get(pkey) ?? [];
        list.push(s => {
          const late: Parameters<RankedStore['saveMatch']>[1] = [];
          this.apply(s, m, seat, late);
          if (late.length > 0) this.store.saveMatch({ id: m.id, mode: m.mode, at: m.at, season: season.id }, late);
        });
        this.deferred.set(pkey, list);
        continue;
      }
      const res = this.apply(st, m, seat, rows);
      out.set(pkey, res);
    }
    if (rows.length > 0) this.store.saveMatch({ id: m.id, mode: m.mode, at: m.at, season: season.id }, rows);
    this.board = null;
    return out;
  }

  private apply(st: State, m: MatchIn, seat: SeatIn, rows?: Parameters<RankedStore['saveMatch']>[1]): Record<string, unknown> {
    this.rollSeason(st);
    const r = st.row;
    const before = { rp: r.rp, ...rankOf(r.rp) };
    const d0 = computeDelta(m, seat, r.rp, r.streak);
    const d = m.held ? { ...d0, delta: 0, counted: false, reason: 'held', lines: [] } : d0;
    const won = seat.result === 'win' || (m.mode === 'br' && seat.placement === 1);
    const xpBefore = { xp: r.xp, level: r.level };
    let gain = 0, packs = 0;
    const unlocks: string[] = [];
    if (d.counted) {
      r.rp = Math.max(0, r.rp + d.delta);
      r.rank = rankOf(r.rp).rank;
      r.peak_rp = Math.max(r.peak_rp, r.rp);
      r.matches++;
      if (won) { r.wins++; r.streak++; } else if (seat.result !== 'draw') r.streak = 0;
      gain = xpGain(seat, d.botFactor);
      const lv = addXp(r.level, r.xp, gain);
      r.level = lv.level; r.xp = lv.xp; packs = lv.ups; r.packs += lv.ups;
      unlocks.push(...this.grantRank(st, r.rank, m.at));
      this.store.savePlayer(r);
      rows?.push({ match_id: m.id, pkey: r.pkey, placement: seat.placement, players: m.seats.length, result: seat.result, ante: seat.ante, score: Math.min(1e15, Math.max(0, Math.round(seat.score) || 0)), rp_delta: d.delta, xp: gain, bot_factor: d.botFactor });
    }
    const after = { rp: r.rp, ...rankOf(r.rp) };
    const res: Record<string, unknown> = {
      type: 'ranked_result', match: m.id, match_id: m.id, held: m.held === true, mode: m.mode, placement: seat.placement, players: m.seats.length, result: seat.result,
      counted: d.counted, reason: d.reason, lines: d.lines, delta: d.counted ? d.delta : 0, botFactor: d.botFactor,
      before: { rp: before.rp, rank: before.rank, tier: before.tier, floor: before.floor, next: before.next },
      after: { rp: after.rp, rank: after.rank, tier: after.tier, floor: after.floor, next: after.next },
      promoted: after.rank > before.rank || (after.rank === before.rank && after.tier < before.tier),
      demoted: after.rank < before.rank || (after.rank === before.rank && after.tier > before.tier),
      xp: { gain, before: xpBefore.xp, after: r.xp, levelBefore: xpBefore.level, levelAfter: r.level, needBefore: xpNeed(xpBefore.level), need: xpNeed(r.level) },
      packs, totalPacks: r.packs, streak: r.streak, unlocks: unlocks.map(id => itemInfo(id)).filter(Boolean),
      season: seasonAt(m.at).id,
    };
    st.last = res;
    return res;
  }

  openPack(st: State): { items: { item: Item; dupe: boolean; xp: number }[]; levelUps: number } | null {
    if (st.row.packs <= 0) return null;
    st.row.packs--;
    const items: { item: Item; dupe: boolean; xp: number }[] = [];
    let dupeXp = 0;
    for (let i = 0; i < PACK_SIZE; i++) {
      const it = rollPackItem(this.rand);
      const dupe = !this.unlock(st, it.id, 'pack') || items.some(x => x.item.id === it.id);
      const xp = dupe ? DUPE_XP[it.rarity] : 0;
      dupeXp += xp;
      items.push({ item: it, dupe, xp });
    }
    const lv = addXp(st.row.level, st.row.xp, dupeXp);
    st.row.level = lv.level; st.row.xp = lv.xp; st.row.packs += lv.ups;
    this.store.savePlayer(st.row);
    return { items, levelUps: lv.ups };
  }

  equip(st: State, slot: string, item: string | null): boolean {
    if (!SLOTS.includes(slot as Slot)) return false;
    if (item !== null) {
      const info = itemInfo(item);
      if (!info || info.type !== slot || !st.unlocks.has(item)) return false;
      st.equipped[slot] = item;
    } else {
      delete st.equipped[slot];
    }
    this.store.setEquipped(st.row.pkey, slot, item);
    return true;
  }

  async leaderboard(limit = 50): Promise<PlayerRow[]> {
    const s = seasonAt(this.now());
    if (this.board && this.board.season === s.id && this.now() - this.board.at < 60_000) return this.board.rows;
    let rows: PlayerRow[];
    try { rows = await this.store.leaderboard(s.id, limit); } catch (e) {
      this.log('WARN', `ranked leaderboard read failed: ${String(e).slice(0, 120)}`);
      rows = [...this.cache.values()].map(x => x.row).filter(r => r.season === s.id && r.matches > 0).sort((a, b) => b.rp - a.rp).slice(0, limit);
    }
    const fresh = rows.map(r => this.cache.get(r.pkey)?.row ?? r).sort((a, b) => b.rp - a.rp || a.created - b.created);
    this.board = { at: this.now(), season: s.id, rows: fresh };
    return fresh;
  }

  legendNo(pkey: string): number | null {
    const st = this.cache.get(pkey);
    if (!st || st.row.rp < LEGEND_RP || !this.board) return null;
    const i = this.board.rows.findIndex(r => r.pkey === pkey);
    return i >= 0 ? i + 1 : null;
  }

  badge(pkey: string | undefined): Badge | null {
    if (!pkey) return null;
    const st = this.cache.get(pkey);
    if (!st) return null;
    const ri = rankOf(st.row.rp);
    const title = st.equipped.title ? itemInfo(st.equipped.title) : null;
    return { r: ri.rank, t: ri.tier, n: this.legendNo(pkey), title: title ? String(title.value) : null, badge: st.equipped.badge ?? null };
  }

  profilePayload(st: State): Record<string, unknown> {
    const r = st.row;
    const ri = rankOf(r.rp);
    const s = seasonAt(this.now());
    return {
      type: 'ranked_profile',
      store: this.store.kind,
      profile: {
        name: r.name, rp: r.rp, rank: ri.rank, tier: ri.tier, floor: ri.floor, next: ri.next, legendNo: this.legendNo(r.pkey),
        peakRp: r.peak_rp, peakRank: rankOf(r.peak_rp).rank, bestRank: r.best_rank, xp: r.xp, level: r.level, xpNeed: xpNeed(r.level),
        packs: r.packs, streak: r.streak, matches: r.matches, wins: r.wins,
      },
      season: { id: s.id, name: s.name, year: s.year, quarter: s.quarter, startsAt: s.starts, endsAt: s.ends, secondsLeft: Math.max(0, Math.floor((s.ends - this.now()) / 1000)) },
      unlocks: [...st.unlocks.keys()],
      equipped: st.equipped,
      catalog: [...CATALOG, ...[...st.unlocks.keys()].filter(id => !CATALOG_BY_ID.has(id)).map(id => itemInfo(id)).filter(Boolean)],
      last: st.last,
    };
  }

  historyPayload(rows: HistoryRow[]): Record<string, unknown> {
    return { type: 'ranked_history', matches: rows.map(h => ({ id: h.match_id, mode: h.mode, at: h.at, placement: h.placement, players: h.players, result: h.result, ante: h.ante, score: h.score, delta: h.rp_delta, xp: h.xp, bots: h.bot_factor < 1 })) };
  }
}

export let ranked = new RankedService(new MemoryStore());

export function setRanked(svc: RankedService): void { ranked = svc; }

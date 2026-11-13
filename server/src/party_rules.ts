export type PartyKind = 'br' | 'teams' | 'raid' | 'race';
export type Outcome = 'win' | 'lose' | 'draw';

export const PARTY_KINDS: PartyKind[] = ['br', 'teams', 'raid', 'race'];
export const KIND_MIN: Record<PartyKind, number> = { br: 2, teams: 2, raid: 2, race: 2 };
export const PARTY_MAX = 8;

export interface PartyCfg {
  kind: PartyKind;
  lives: number;
  brLosers: number;
  brTies: 'all' | 'spare';
  brSuddenDeath: boolean;
  teamSize: number;
  teamShare: number;
  teamAuto: boolean;
  raidPerPlayer: number;
  raidScaling: number;
  raidCurve: number;
  raidLives: number;
  raidMvp: number;
  blindSeconds: number;
  raceTarget: number;
}

function int(v: unknown, lo: number, hi: number, d: number): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) return d;
  return Math.min(hi, Math.max(lo, Math.round(v)));
}

export function partyCfg(s: Record<string, unknown> | undefined): PartyCfg {
  const o = s ?? {};
  const kind = PARTY_KINDS.includes(o.party_kind as PartyKind) ? (o.party_kind as PartyKind) : 'br';
  const curve = o.raid_curve === 2 ? 2 : 1;
  return {
    kind,
    lives: int(o.starting_lives, 1, 20, 4),
    brLosers: int(o.br_losers, 1, 3, 1),
    brTies: o.br_ties === 'spare' ? 'spare' : 'all',
    brSuddenDeath: o.br_sudden_death === true,
    teamSize: int(o.team_size, 2, 4, 2),
    teamShare: int(o.team_share, 0, 100, 100),
    teamAuto: o.team_auto !== false,
    raidPerPlayer: int(o.raid_per_player, 50, 800, curve === 2 ? 100 : 250),
    raidScaling: int(o.raid_scaling, 0, 100, curve === 2 ? 0 : 25),
    raidCurve: curve,
    raidLives: int(o.raid_lives, 1, 20, 3),
    raidMvp: int(o.raid_mvp_bonus, 0, 10, 3),
    blindSeconds: int(o.party_blind_seconds, 60, 600, 180),
    raceTarget: int(o.race_target, 1, 12, 4),
  };
}

export const PARTY_BOOL = ['br_sudden_death', 'party_swap', 'team_auto', 'raid_every_blind', 'party_every_blind', 'spectate', 'spectate_jokers', 'spectate_wait'];
export const PARTY_INT: [string, number, number][] = [
  ['br_losers', 1, 3], ['team_size', 2, 4], ['team_share', 0, 100], ['raid_per_player', 50, 800],
  ['raid_scaling', 0, 100], ['raid_lives', 1, 20], ['raid_mvp_bonus', 0, 10], ['party_blind_seconds', 60, 600],
  ['race_target', 1, 12], ['raid_curve', 1, 2],
];

export function cleanPartySettings(s: Record<string, unknown>): void {
  if (s.party_kind !== undefined && !PARTY_KINDS.includes(s.party_kind as PartyKind)) delete s.party_kind;
  if (s.br_ties !== undefined && s.br_ties !== 'all' && s.br_ties !== 'spare') delete s.br_ties;
  for (const k of PARTY_BOOL) if (s[k] !== undefined && typeof s[k] !== 'boolean') delete s[k];
  for (const [k, lo, hi] of PARTY_INT) {
    if (s[k] === undefined) continue;
    if (typeof s[k] !== 'number' || !Number.isFinite(s[k] as number)) { delete s[k]; continue; }
    s[k] = Math.min(hi, Math.max(lo, Math.round(s[k] as number)));
  }
}

const BASE_CHIPS = [300, 800, 2000, 5000, 11000, 20000, 35000, 50000];

export function bossChips(ante: number): number {
  const a = Math.max(1, Math.floor(ante));
  if (a <= 8) return BASE_CHIPS[a - 1] * 2;
  return Math.round(BASE_CHIPS[7] * 2 * Math.pow(1.6, a - 8));
}

export const RAID_CURVE = [3.0, 2.8, 2.3, 1.65, 1.25, 1.05, 1.0, 1.0];

export function raidCurve(cfg: PartyCfg, ante: number): number {
  if (cfg.raidCurve !== 2) return 1;
  const a = Math.min(RAID_CURVE.length, Math.max(1, Math.floor(ante)));
  return RAID_CURVE[a - 1];
}

export function raidTarget(cfg: PartyCfg, players: number, ante: number, blind = 'L'): number {
  const n = Math.max(1, players);
  const part = blind === 'S' ? 0.5 : blind === 'B' ? 0.75 : 1;
  const scale = 1 + (cfg.raidScaling / 100) * Math.max(0, ante - 1);
  return Math.max(1, Math.round(bossChips(ante) * part * n * (cfg.raidPerPlayer / 100) * scale * raidCurve(cfg, ante)));
}

export interface RPlayer {
  pid: number;
  alive: boolean;
  score: number;
  team: number;
  lives: number;
  present?: boolean;
}

export interface Resolution {
  outcome: Record<number, Outcome>;
  lifeLoss: number[];
  teamLoss: number[];
  raidFail: boolean;
  lowest: number | null;
  highest: number | null;
  teamScores: Record<number, number>;
  raidTotal: number;
  raidTarget: number;
}

export function teamScore(scores: number[], share: number): number {
  if (scores.length === 0) return 0;
  const s = [...scores].sort((a, b) => b - a);
  let total = s[0];
  for (let i = 1; i < s.length; i++) total += s[i] * share / 100;
  return Math.round(total);
}

function pickLosers<T extends { score: number }>(list: T[], k: number, ties: 'all' | 'spare'): T[] {
  if (list.length < 2) return [];
  const asc = [...list].sort((a, b) => a.score - b.score);
  const cut = Math.max(1, Math.min(k, asc.length - 1));
  let losers: T[];
  if (ties === 'spare') {
    const safe = asc[cut].score;
    losers = asc.filter(p => p.score < safe);
  } else {
    const at = asc[cut - 1].score;
    losers = asc.filter(p => p.score <= at);
    if (losers.length >= list.length) losers = asc.filter(p => p.score < at);
  }
  if (losers.length >= list.length) return [];
  return losers;
}

export function teamTotals(cfg: PartyCfg, players: RPlayer[], teamLives: Record<number, number>): Record<number, number> {
  const roster = new Map<number, number>();
  const scores = new Map<number, number[]>();
  for (const p of players) {
    if ((teamLives[p.team] ?? 0) <= 0) continue;
    roster.set(p.team, (roster.get(p.team) ?? 0) + 1);
    if (!scores.has(p.team)) scores.set(p.team, []);
    if (p.alive && p.present !== false) scores.get(p.team)!.push(p.score);
  }
  const size = Math.max(0, ...roster.values());
  const out: Record<number, number> = {};
  for (const [team, sc] of scores) {
    if (sc.length === 0) continue;
    const avg = sc.reduce((a, b) => a + b, 0) / sc.length;
    const filled = [...sc];
    while (filled.length < size) filled.push(avg);
    out[team] = teamScore(filled, cfg.teamShare);
  }
  return out;
}

export function resolveParty(cfg: PartyCfg, players: RPlayer[], teamLives: Record<number, number>, ante: number, blind = 'L'): Resolution {
  const alive = players.filter(p => p.alive);
  const ranked = alive.filter(p => p.present !== false);
  const out: Resolution = {
    outcome: {}, lifeLoss: [], teamLoss: [], raidFail: false, lowest: null, highest: null,
    teamScores: {}, raidTotal: 0, raidTarget: 0,
  };
  const pool = cfg.kind === 'raid' ? alive : ranked;
  if (pool.length > 0) {
    const asc = [...pool].sort((a, b) => a.score - b.score);
    out.lowest = asc[0].pid;
    out.highest = asc[asc.length - 1].pid;
  }
  if (cfg.kind === 'br') {
    const losers = pickLosers(ranked, cfg.brLosers, cfg.brTies);
    out.lifeLoss = losers.map(p => p.pid);
    for (const p of ranked) out.outcome[p.pid] = losers.length === 0 ? 'draw' : (out.lifeLoss.includes(p.pid) ? 'lose' : 'win');
    return out;
  }
  if (cfg.kind === 'teams') {
    out.teamScores = teamTotals(cfg, players, teamLives);
    const list = Object.entries(out.teamScores).map(([team, score]) => ({ team: Number(team), score }));
    const losers = pickLosers(list, 1, 'all');
    out.teamLoss = losers.map(t => t.team);
    for (const p of ranked) {
      if (out.teamScores[p.team] === undefined) continue;
      out.outcome[p.pid] = losers.length === 0 ? 'draw' : (out.teamLoss.includes(p.team) ? 'lose' : 'win');
    }
    return out;
  }
  out.raidTotal = alive.reduce((a, p) => a + p.score, 0);
  out.raidTarget = raidTarget(cfg, Math.max(1, ranked.length), ante, blind);
  out.raidFail = out.raidTotal < out.raidTarget;
  for (const p of alive) out.outcome[p.pid] = out.raidFail ? 'lose' : 'win';
  return out;
}

export function balanceTeams(pids: number[], teamSize: number): Record<number, number> {
  const n = pids.length;
  const teams = Math.max(2, Math.ceil(n / Math.max(2, teamSize)));
  const out: Record<number, number> = {};
  pids.forEach((pid, i) => { out[pid] = i % teams; });
  return out;
}

export function teamCount(n: number, teamSize: number): number {
  return Math.max(2, Math.ceil(n / Math.max(2, teamSize)));
}

export function raceCleared(ante: number, blind: string): number {
  const a = Math.max(1, Math.floor(Number(ante) || 1));
  const b = blind === 'S' ? 1 : blind === 'B' ? 2 : blind === 'L' ? 3 : 0;
  return (a - 1) * 3 + b;
}

export interface RaceEntry { pid: number; cleared: number; at: number; alive: boolean; }

export function raceOrder(list: RaceEntry[]): number[] {
  return [...list].sort((a, b) => (b.cleared - a.cleared) || (a.at - b.at) || (a.pid - b.pid)).map(e => e.pid);
}

export function raceWinner(target: number, list: RaceEntry[]): number | null {
  const goal = Math.max(1, target) * 3;
  const done = list.filter(e => e.cleared >= goal);
  if (done.length > 0) return raceOrder(done)[0];
  const alive = list.filter(e => e.alive);
  const out = list.filter(e => !e.alive);
  if (alive.length === 0 && list.length > 0) return raceOrder(list)[0];
  if (alive.length === 1 && out.length > 0) {
    const best = Math.max(...out.map(e => e.cleared));
    if (alive[0].cleared > best) return alive[0].pid;
  }
  return null;
}

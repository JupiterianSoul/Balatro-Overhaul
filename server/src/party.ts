import type { ServerWebSocket } from 'bun';
import { seatFields, seatRoster } from './identity';
import { matchlogs } from './matchlog';
import { versionNameOf } from './updates';
import {
  PARTY_MAX, PartyCfg, partyCfg, cleanPartySettings, resolveParty, raidTarget, teamTotals, balanceTeams, teamCount, PARTY_KINDS, RPlayer,
  KIND_MIN, raceCleared, raceWinner, raceOrder, RaceEntry,
} from './party_rules';
import { newPartySwap, partySwapOn, handlePartySwapState, handlePartySwapApplied, handlePartySwapReady, partyHoldsSnapshot, partySwapStatus, trySwap, type PartySwapState, type PartySwapIO } from './party_swap';

interface WSData {
  roomCode?: string | null;
  partyCode?: string | null;
  name?: string;
  gameVersion?: string;
  mods?: unknown[];
  modsFp?: string;
  rtt?: number | null;
}
type WS = ServerWebSocket<WSData>;
type Msg = Record<string, unknown>;

export interface PartyDeps {
  sendTo: (ws: WS, data: object) => void;
  log: (level: string, tag: string, msg: string) => void;
  claimName: (ws: WS, msg: Msg) => boolean;
  rememberMods: (ws: WS, msg: Msg) => void;
  sanitizeSettings: (raw: unknown) => Record<string, unknown> | null;
  lifeOnRoundLoss: (s: Record<string, unknown>) => boolean;
  finalAnteFor: (s: Record<string, unknown>) => number;
  codeTaken: (code: string) => boolean;
  holdMs: () => number;
  randomSeed: () => string;
  onMatchStart?: (p: Party) => void;
  onMatchOver?: (p: Party) => void;
}

export interface Seat {
  ws: WS | null;
  token: string;
  name: string;
  ready: boolean;
  team: number;
  lives: number;
  alive: boolean;
  score: number | null;
  finished: boolean;
  readyBlind: boolean;
  ante: number;
  blind: string;
  holdDeadline: number | null;
  placement: number | null;
  location: string | null;
  snapshot: Msg | null;
  endReason: string | null;
  result: 'win' | 'lose' | 'draw' | null;
  version: string;
  ended: boolean;
  done: boolean;
  freeDrop: boolean;
  solo: boolean;
  live: Msg | null;
  board: Msg | null;
  spectating: number | null;
  best?: number;
  leftOut?: boolean;
  raceCleared?: number;
  raceAt?: number;
  lostBlinds?: string[];
}

export interface Party {
  code: string;
  id: string;
  visibility: 'public' | 'private';
  hostId: number;
  seats: (Seat | null)[];
  settings: Record<string, unknown>;
  phase: 'lobby' | 'playing' | 'finished';
  mods: unknown[];
  modsFp: string;
  gameVersion: string;
  createdAt: number;
  lastActivity: number;
  pvpAnte: number | null;
  pvpBlind: string;
  pvpStarted: boolean;
  pvpTimer: ReturnType<typeof setTimeout> | null;
  holdTimer: ReturnType<typeof setTimeout> | null;
  teamLives: Record<number, number>;
  raidLives: number;
  seed: string | null;
  finalAnte: number;
  suddenDeath: number;
  outCount: number;
  lastResult: Msg | null;
  lastPvp: number;
  matchId?: string;
  raceGoal?: number;
  raceStart?: number;
  swap?: PartySwapState;
}

export const parties: Record<string, Party> = {};
const socketParty = new WeakMap<WS, string>();

let D!: PartyDeps;
export const partyTiming = { blindMs: 0 };

export function initParty(deps: PartyDeps): void { D = deps; }

const TOKEN_RE = /^[a-f0-9]{32}$/;
const ID_RE = /^[a-f0-9]{12}$/;
const OPEN = 1;

function token(): string { return crypto.randomUUID().replace(/-/g, ''); }

function genCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let c = '';
  do { c = Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join(''); } while (D.codeTaken(c) || parties[c]);
  return c;
}

function live(ws: WS | null): ws is WS { return !!ws && ws.readyState === OPEN; }

function send(seat: Seat | null, data: object): void { if (seat && live(seat.ws)) D.sendTo(seat.ws, data); }

function seatList(p: Party): [number, Seat][] {
  const out: [number, Seat][] = [];
  p.seats.forEach((s, i) => { if (s) out.push([i, s]); });
  return out;
}

function cfgOf(p: Party): PartyCfg { return partyCfg(p.settings); }

export function partyForSocket(ws: WS): Party | null {
  const code = socketParty.get(ws);
  return code && parties[code] ? parties[code] : null;
}

function pidOf(p: Party, ws: WS): number {
  return p.seats.findIndex(s => !!s && s.ws === ws);
}

function attach(p: Party, pid: number, ws: WS): void {
  const s = p.seats[pid]!;
  s.ws = ws;
  s.holdDeadline = null;
  socketParty.set(ws, p.code);
  if (ws.data && typeof ws.data === 'object') ws.data.partyCode = p.code;
}

function detach(p: Party, pid: number): void {
  const s = p.seats[pid];
  if (!s) return;
  if (s.ws) {
    if (socketParty.get(s.ws) === p.code) socketParty.delete(s.ws);
    if (s.ws.data && s.ws.data.partyCode === p.code) s.ws.data.partyCode = null;
  }
  s.ws = null;
}

function newSeat(ws: WS, name: string, lives: number): Seat {
  return {
    ws, token: token(), name, ready: false, team: 0, lives, alive: true, score: null, finished: false, readyBlind: false,
    ante: 1, blind: 'S', holdDeadline: null, placement: null, location: null, snapshot: null, endReason: null, result: null, ended: false, done: false, freeDrop: true, solo: false, live: null, board: null, spectating: null,
    version: String(ws.data?.gameVersion ?? ''),
  };
}

function touch(p: Party): void { p.lastActivity = Date.now(); }

export function roomPayload(p: Party): Msg {
  const now = Date.now();
  const cfg = cfgOf(p);
  return {
    type: 'party_room',
    code: p.code, id: p.id, visibility: p.visibility, hostId: p.hostId, phase: p.phase, maxPlayers: PARTY_MAX,
    kind: cfg.kind, teams: cfg.kind === 'teams' ? teamCount(seatList(p).length, cfg.teamSize) : 0,
    players: seatList(p).map(([pid, s]) => ({
      ...seatFields(p, pid, s), pid, name: s.name, ready: s.ready, team: s.team, connected: live(s.ws), held: s.holdDeadline !== null, bot: isBotWs(s.ws),
      secondsLeft: s.holdDeadline !== null ? Math.max(0, Math.ceil((s.holdDeadline - now) / 1000)) : null,
    })),
  };
}

function broadcastRoom(p: Party): void {
  const msg = roomPayload(p);
  for (const [, s] of seatList(p)) send(s, msg);
}

function nextHost(p: Party): void {
  const cur = p.seats[p.hostId];
  if (cur && live(cur.ws)) return;
  const n = seatList(p).find(([, s]) => live(s.ws) && !isBotWs(s.ws)) ?? seatList(p).find(([, s]) => live(s.ws));
  if (n) p.hostId = n[0];
}

function isBotWs(ws: WS | null): boolean { return !!ws && (ws.data as { bot?: boolean }).bot === true; }

export function partyIsPvp(ws: WS, ante: number, blind: string): boolean {
  const p = partyForSocket(ws);
  return !!p && isPvpBlind(p, ante, blind);
}

export function partyHumans(ws: WS): number {
  const p = partyForSocket(ws);
  if (!p) return -1;
  return seatList(p).filter(([, s]) => !isBotWs(s.ws) && (live(s.ws) || s.holdDeadline !== null)).length;
}

export function partyHostCheck(ws: WS): { party: Party; host: boolean } | null {
  const p = partyForSocket(ws);
  return p ? { party: p, host: pidOf(p, ws) === p.hostId } : null;
}

export function partySockets(p: Party): WS[] { return seatList(p).map(([, s]) => s.ws).filter(w => !!w) as WS[]; }
export function partyNames(p: Party): string[] { return seatList(p).map(([, s]) => s.name); }

function clearTimers(p: Party): void {
  if (p.pvpTimer) { clearTimeout(p.pvpTimer); p.pvpTimer = null; }
  if (p.holdTimer) { clearTimeout(p.holdTimer); p.holdTimer = null; }
}

export function closeParty(p: Party, reason: string): void {
  clearTimers(p);
  for (const [pid, s] of seatList(p)) {
    send(s, { type: 'room_closed', reason, post_match: p.phase === 'finished', party: true });
    detach(p, pid);
  }
  if (parties[p.code] === p) delete parties[p.code];
  D.log('INFO', 'PARTY', `Closed ${p.code}: ${reason}`);
}

function scheduleHold(p: Party): void {
  if (p.holdTimer) { clearTimeout(p.holdTimer); p.holdTimer = null; }
  const ds = seatList(p).map(([, s]) => s.holdDeadline).filter((d): d is number => d !== null);
  if (ds.length === 0) return;
  const wait = Math.max(0, Math.min(...ds) - Date.now());
  p.holdTimer = setTimeout(() => { p.holdTimer = null; onHoldExpired(p); }, wait);
}

function onHoldExpired(p: Party): void {
  if (parties[p.code] !== p) return;
  const now = Date.now();
  for (const [pid, s] of seatList(p)) {
    if (s.holdDeadline === null || s.holdDeadline > now) continue;
    s.holdDeadline = null;
    if (p.phase === 'playing' && s.alive) forfeit(p, pid, 'rejoin_expired');
    else if (p.phase !== 'playing') p.seats[pid] = null;
  }
  if (!seatList(p).some(([, s]) => live(s.ws) || s.holdDeadline !== null)) { closeParty(p, 'room_expired'); return; }
  nextHost(p);
  if (p.phase === 'lobby') broadcastRoom(p);
  else broadcastState(p);
  scheduleHold(p);
}

export function sweepParties(ttlMs: number, now = Date.now()): void {
  for (const p of Object.values(parties)) {
    if (seatList(p).some(([, s]) => s.holdDeadline !== null)) continue;
    if (now - p.lastActivity > ttlMs) closeParty(p, 'room_expired');
  }
}

function aliveSeats(p: Party): [number, Seat][] { return seatList(p).filter(([, s]) => s.alive); }
function raidHeadcount(p: Party): number { return Math.max(1, aliveSeats(p).filter(([, s]) => (live(s.ws) || s.done) && !(s.leftOut && !s.done)).length); }
function anyoneHere(p: Party): boolean { return aliveSeats(p).some(([, s]) => live(s.ws)); }

function rPlayers(p: Party, onlyThisBlind: boolean): RPlayer[] {
  return seatList(p).map(([pid, s]) => ({
    pid, alive: s.alive, team: s.team, lives: s.lives, present: live(s.ws) || s.done,
    score: onlyThisBlind && !atPvp(p, s) ? 0 : (s.score ?? 0),
  }));
}

function poolLives(p: Party, s: Seat): number {
  const k = cfgOf(p).kind;
  if (k === 'teams') return p.teamLives[s.team] ?? 0;
  if (k === 'raid') return p.raidLives;
  return s.lives;
}

function oppAggregate(p: Party, pid: number): { name: string; lives: number; score: number } {
  const cfg = cfgOf(p);
  const me = p.seats[pid]!;
  if (cfg.kind === 'raid') {
    const n = raidHeadcount(p);
    return { name: 'Raid Boss', lives: p.raidLives, score: raidTarget(cfg, n, p.pvpAnte ?? me.ante, p.pvpBlind) };
  }
  if (cfg.kind === 'teams') {
    let best = { team: -1, lives: 0, score: 0 };
    const totals = teamTotals(cfg, rPlayers(p, false), p.teamLives);
    for (const t of Object.keys(p.teamLives).map(Number)) {
      if (t === me.team || (p.teamLives[t] ?? 0) <= 0) continue;
      const sc = totals[t] ?? 0;
      if (best.team < 0 || sc > best.score) best = { team: t, lives: p.teamLives[t], score: sc };
    }
    return { name: 'Team ' + String.fromCharCode(65 + Math.max(0, best.team)), lives: best.lives, score: best.score };
  }
  const rivals = aliveSeats(p).filter(([i]) => i !== pid);
  const top = rivals.reduce((a, [, s]) => Math.max(a, s.score ?? 0), 0);
  return { name: rivals.length === 1 ? rivals[0][1].name : `${rivals.length} rivals`, lives: rivals.length, score: top };
}

export function viewFor(p: Party, pid: number): Msg {
  const cfg = cfgOf(p);
  const me = p.seats[pid];
  const alive = aliveSeats(p);
  const open = p.pvpAnte !== null;
  const inBlind = alive.filter(([, s]) => open && atPvp(p, s));
  const waiting = inBlind.filter(([i, s]) => i !== pid && live(s.ws) && !s.finished).length;
  const mine = me && open && atPvp(p, me) ? (me.score ?? 0) : 0;
  const out: Msg = { kind: cfg.kind, waiting, mine, alive: alive.length, finished: !!me?.finished };
  if (cfg.kind === 'race') out.race = raceView(p);
  if (cfg.kind === 'raid') {
    const n = raidHeadcount(p);
    const ante = p.pvpAnte ?? (me?.ante ?? 1);
    out.n = n;
    out.target = raidTarget(cfg, n, ante, open ? p.pvpBlind : 'L');
    out.total = inBlind.reduce((a, [, s]) => a + (s.score ?? 0), 0);
    out.lives = p.raidLives;
    out.value = out.target;
    return out;
  }
  if (cfg.kind === 'teams') {
    const totals = teamTotals(cfg, rPlayers(p, true), p.teamLives);
    const team = me?.team ?? 0;
    let enemy = -1;
    let best = 0;
    for (const t of Object.keys(p.teamLives).map(Number)) {
      if (t === team || (p.teamLives[t] ?? 0) <= 0) continue;
      const sc = totals[t] ?? 0;
      if (enemy < 0 || sc > best) { enemy = t; best = sc; }
    }
    out.team = team;
    out.teamTotal = totals[team] ?? 0;
    out.teamLives = p.teamLives[team] ?? 0;
    out.enemyTeam = enemy;
    out.enemyTotal = best;
    out.enemyLives = enemy >= 0 ? (p.teamLives[enemy] ?? 0) : 0;
    out.value = best;
    return out;
  }
  const rivals = inBlind.filter(([i]) => i !== pid);
  let low: [number, Seat] | null = null;
  let high: [number, Seat] | null = null;
  for (const r of inBlind) {
    if (!low || (r[1].score ?? 0) < (low[1].score ?? 0)) low = r;
    if (!high || (r[1].score ?? 0) > (high[1].score ?? 0)) high = r;
  }
  let toBeat: number | null = null;
  for (const [, s] of rivals) toBeat = toBeat === null ? (s.score ?? 0) : Math.min(toBeat, s.score ?? 0);
  let best: number | null = null;
  for (const [, s] of rivals) best = best === null ? (s.score ?? 0) : Math.max(best, s.score ?? 0);
  const leader = best !== null && !!me && open && atPvp(p, me) && mine > best;
  out.toBeat = toBeat;
  out.best = best ?? 0;
  out.leader = leader;
  out.value = best ?? 0;
  out.rank = me && open && atPvp(p, me) ? 1 + inBlind.filter(([i, s]) => i !== pid && (s.score ?? 0) > mine).length : null;
  out.ranked = inBlind.length;
  out.lowest = low ? { pid: low[0], name: low[1].name, score: low[1].score ?? 0 } : null;
  out.highest = high ? { pid: high[0], name: high[1].name, score: high[1].score ?? 0 } : null;
  out.lives = me?.lives ?? 0;
  return out;
}

export function statePayload(p: Party, pid: number): Msg {
  const cfg = cfgOf(p);
  const alive = aliveSeats(p);
  const pending = p.pvpAnte !== null;
  const scored = alive.filter(([, s]) => s.score !== null && atPvp(p, s));
  let lowest: Msg | null = null;
  let highest: Msg | null = null;
  if (pending && scored.length > 0) {
    const asc = [...scored].sort((a, b) => (a[1].score ?? 0) - (b[1].score ?? 0));
    lowest = { pid: asc[0][0], name: asc[0][1].name, score: asc[0][1].score };
    const h = asc[asc.length - 1];
    highest = { pid: h[0], name: h[1].name, score: h[1].score };
  }
  const totals = cfg.kind === 'teams' ? teamTotals(cfg, rPlayers(p, true), p.teamLives) : {};
  const teams = cfg.kind === 'teams'
    ? Object.keys(p.teamLives).map(Number).map(t => ({
      team: t, lives: p.teamLives[t], alive: p.teamLives[t] > 0,
      score: totals[t] ?? 0,
    }))
    : [];
  const raid = cfg.kind === 'raid'
    ? { total: scored.reduce((a, [, s]) => a + (s.score ?? 0), 0), target: raidTarget(cfg, raidHeadcount(p), p.pvpAnte ?? (p.seats[pid]?.ante ?? 1), p.pvpBlind), lives: p.raidLives }
    : null;
  return {
    type: 'party_state', kind: cfg.kind, myId: pid, phase: p.phase, pvpAnte: p.pvpAnte, pvpBlind: p.pvpAnte !== null ? p.pvpBlind : null, started: p.pvpStarted,
    view: viewFor(p, pid),
    players: seatList(p).map(([i, s]) => ({
      ...seatFields(p, i, s), pid: i, name: s.name, location: s.location, team: s.team, lives: poolLives(p, s), alive: s.alive, connected: live(s.ws), bot: isBotWs(s.ws),
      score: atPvp(p, s) ? s.score : null, finished: s.finished, placement: s.placement, live: s.alive ? s.live : null,
      ...modeFields(p, i, s),
    })),
    teams, lowest, highest, raid,
    ...modeState(p),
  };
}

function broadcastState(p: Party): void {
  const t = liveTimers.get(p);
  if (t) { clearTimeout(t); liveTimers.delete(p); }
  liveSent.set(p, Date.now());
  for (const [pid, s] of seatList(p)) send(s, statePayload(p, pid));
}

const liveTimers = new Map<Party, ReturnType<typeof setTimeout>>();
const liveSent = new Map<Party, number>();
export const liveTiming = { ms: 1000 };

export const BOARD_MAX = 12000;

function specPayload(p: Party, pid: number, watcher: Seat): Msg {
  const s = p.seats[pid];
  let board = s?.board ?? null;
  if (board && watcher.alive && p.settings?.spectate_jokers === false) board = { ...board, jokers: [], jokers_hidden: true };
  return { type: 'spec_board', ...seatFields(p, pid, s), pid, name: s?.name ?? '?', alive: !!s?.alive, board };
}

export function canWatch(p: Party, w: Seat): boolean {
  if (!w.alive || p.settings?.spectate !== false) return true;
  return p.settings?.spectate_wait === true && !!w.finished && inPvp(p, w);
}

function handleBoard(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  const b = msg.board;
  if (!b || typeof b !== 'object' || JSON.stringify(b).length > BOARD_MAX) return;
  s.board = b as Msg;
  for (const [i, w] of seatList(p)) if (i !== pid && w.spectating === pid && canWatch(p, w)) send(w, specPayload(p, pid, w));
}

function handleSpectate(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  const t = msg.pid === null || msg.pid === undefined ? null : Number(msg.pid);
  if (t === null || !Number.isInteger(t) || t === pid || !p.seats[t]) { s.spectating = null; return; }
  if (!canWatch(p, s)) {
    s.spectating = null;
    send(s, { type: 'spec_board', pid: t, denied: true, board: null });
    return;
  }
  s.spectating = t;
  send(s, specPayload(p, t, s));
}

const LIVE_WHERE = new Set(['blind', 'shop', 'select', 'ready']);
const LIVE_BLIND = new Set(['S', 'B', 'L']);

function num(v: unknown, max: number): number {
  const n = Math.floor(Number(v));
  return Number.isFinite(n) && n >= 0 ? Math.min(n, max) : 0;
}

function handleLiveStat(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  if (!s.alive) return;
  const before = s.live;
  s.live = {
    ante: num(msg.ante, 1e6), blind: LIVE_BLIND.has(String(msg.blind)) ? String(msg.blind) : null,
    hands: num(msg.hands, 99), discards: num(msg.discards, 99), score: parseScore(msg.score),
    where: LIVE_WHERE.has(String(msg.where)) ? String(msg.where) : 'blind',
  };
  const acted = before && before.where === 'blind' && s.live.where === 'blind' && before.ante === s.live.ante && before.blind === s.live.blind
    && (before.hands !== s.live.hands || before.discards !== s.live.discards || before.score !== s.live.score);
  if (acted && p.pvpTimer && p.pvpStarted && inPvp(p, s) && !s.finished) armTimer(p);
  if (liveTimers.has(p)) return;
  const wait = Math.max(0, liveTiming.ms - (Date.now() - (liveSent.get(p) ?? 0)));
  liveTimers.set(p, setTimeout(() => { liveTimers.delete(p); if (parties[p.code] === p) broadcastState(p); }, wait));
}

function matchState(p: Party, pid: number, event?: string): Msg {
  const s = p.seats[pid]!;
  const agg = oppAggregate(p, pid);
  const out = !s.alive || p.phase === 'finished';
  return {
    type: 'match_state_update', event, party: true,
    phase: out ? 'finished' : (atPvp(p, s) ? 'pvp_pending' : 'playing'),
    playerId: pid, currentAnte: s.ante, currentBlind: s.blind, isPvpBlind: atPvp(p, s),
    myLives: poolLives(p, s), myStatus: s.alive ? 'active' : 'eliminated',
    oppName: agg.name, oppLives: agg.lives, oppStatus: 'active', oppBlindFinished: false, oppConnected: true, oppSecondsLeft: null,
    winner: s.result === 'win' ? pid : null, winReason: s.endReason,
    finalAnte: p.finalAnte, suddenDeath: out ? 0 : p.suddenDeath,
  };
}

function broadcastMatch(p: Party, event?: string): void {
  for (const [pid, s] of seatList(p)) if (s.alive || p.phase === 'finished') send(s, matchState(p, pid, event));
}

function partyPlayers(p: Party): number { return seatList(p).filter(([, s]) => live(s.ws) || s.holdDeadline !== null).length; }

export function listEntry(p: Party, fp: string, ver: string): Msg {
  const n = partyPlayers(p);
  const host = p.seats[p.hostId];
  const full = n >= PARTY_MAX;
  const inMatch = p.phase !== 'lobby';
  return {
    id: p.id, name: host ? host.name : '?', players: n, maxPlayers: PARTY_MAX, private: p.visibility === 'private',
    modded: p.mods.length > 0, mods: p.mods, sameMods: p.modsFp === fp, inMatch, full,
    joinable: !full && !inMatch && p.gameVersion === ver, version: p.gameVersion, versionName: versionNameOf(p.gameVersion), sameVersion: p.gameVersion === ver,
    ping: host && live(host.ws) && typeof host.ws.data?.rtt === 'number' ? host.ws.data.rtt : null,
    mode: 'party_' + cfgOf(p).kind, party: true, kind: cfgOf(p).kind, roster: seatRoster(p, p.seats),
    seatHeld: seatList(p).some(([, s]) => !live(s.ws) && s.holdDeadline !== null && (!inMatch || s.alive)),
  };
}

export function listParties(fp: string, ver: string, mine: Party | null): Msg[] {
  return Object.values(parties)
    .filter(p => p !== mine && seatList(p).some(([, s]) => live(s.ws)))
    .map(p => listEntry(p, fp, ver));
}

export function partyNameHeld(key: string): boolean {
  for (const p of Object.values(parties)) {
    for (const [, s] of seatList(p)) if (!live(s.ws) && s.holdDeadline !== null && s.name.toLowerCase() === key) return true;
  }
  return false;
}

function err(ws: WS, reason: string, extra?: Msg): void { D.sendTo(ws, { type: 'party_error', reason, ...(extra ?? {}) }); }

export function validateParty(msg: Msg): string | null {
  const t = msg.type;
  if (t === 'party_create') {
    if (msg.visibility !== undefined && msg.visibility !== 'public' && msg.visibility !== 'private') return 'party_create: invalid visibility';
    if (msg.kind !== undefined && !PARTY_KINDS.includes(msg.kind as never)) return 'party_create: invalid kind';
  }
  if (t === 'party_join') {
    if (msg.id !== undefined && (typeof msg.id !== 'string' || !ID_RE.test(msg.id))) return 'party_join: invalid id';
    if (msg.code !== undefined && (typeof msg.code !== 'string' || !/^[A-Za-z0-9]{4}$/.test(msg.code))) return 'party_join: invalid code';
    if (msg.code === undefined && msg.id === undefined) return 'party_join: missing code';
    if (msg.token !== undefined && (typeof msg.token !== 'string' || !TOKEN_RE.test(msg.token))) return 'party_join: invalid token';
  }
  if ((t === 'party_create' || t === 'party_join') && msg.name !== undefined && (typeof msg.name !== 'string' || msg.name.length > 32)) return `${t}: invalid name`;
  if (t === 'party_ready' && typeof msg.ready !== 'boolean') return 'party_ready: invalid ready';
  if (t === 'party_team' && (!Number.isInteger(msg.pid) || (msg.pid as number) < 0 || (msg.pid as number) >= PARTY_MAX
    || !Number.isInteger(msg.team) || (msg.team as number) < 0 || (msg.team as number) > 3)) return 'party_team: invalid';
  if (t === 'party_kick' && (!Number.isInteger(msg.pid) || (msg.pid as number) < 0 || (msg.pid as number) >= PARTY_MAX)) return 'party_kick: invalid pid';
  return null;
}

function cleanSettings(raw: unknown): Record<string, unknown> | null {
  const s = D.sanitizeSettings(raw);
  if (!s) return null;
  cleanPartySettings(s);
  return s;
}

function handleCreate(ws: WS, msg: Msg): void {
  D.rememberMods(ws, msg);
  if (partyForSocket(ws) || ws.data?.roomCode) { err(ws, 'already_in_room'); return; }
  if (!D.claimName(ws, msg)) return;
  const code = genCode();
  const settings: Record<string, unknown> = { mode: 'attrition', starting_lives: 4, pvp_start_round: 1, party_kind: PARTY_KINDS.includes(msg.kind as never) ? msg.kind : 'br' };
  if (msg.raid_curve === 2) settings.raid_curve = 2;
  const p: Party = {
    code, id: token().slice(0, 12), visibility: msg.visibility === 'public' ? 'public' : 'private', hostId: 0, seats: [],
    settings, phase: 'lobby', mods: ws.data?.mods ?? [], modsFp: ws.data?.modsFp ?? '', gameVersion: ws.data?.gameVersion ?? '',
    createdAt: Date.now(), lastActivity: Date.now(), pvpAnte: null, pvpBlind: 'L', pvpStarted: false, pvpTimer: null, holdTimer: null,
    teamLives: {}, raidLives: 0, seed: null, finalAnte: 8, suddenDeath: 0, outCount: 0, lastResult: null, lastPvp: 0,
  };
  p.seats[0] = newSeat(ws, ws.data?.name || 'Player 1', 4);
  parties[code] = p;
  attach(p, 0, ws);
  D.sendTo(ws, { type: 'party_joined', code, id: p.id, visibility: p.visibility, playerId: 0, host: true, token: p.seats[0]!.token, settings: p.settings, version: p.gameVersion });
  broadcastRoom(p);
  D.log('INFO', 'PARTY', `Created ${code} (${p.visibility}, ${settings.party_kind})`);
}

export function findParty(msg: Msg): Party | null {
  if (typeof msg.id === 'string') return Object.values(parties).find(p => p.id === msg.id) ?? null;
  if (typeof msg.code === 'string') return parties[msg.code.toUpperCase()] ?? null;
  return null;
}

function handleJoin(ws: WS, msg: Msg): void {
  D.rememberMods(ws, msg);
  if (partyForSocket(ws) || ws.data?.roomCode) { err(ws, 'already_in_room'); return; }
  const p = findParty(msg);
  if (!p) { err(ws, typeof msg.id === 'string' ? 'room_gone' : 'invalid_code'); return; }
  const held = typeof msg.token === 'string' ? p.seats.findIndex(s => !!s && s.token === msg.token && !live(s.ws)) : -1;
  if (held < 0) {
    if (p.phase !== 'lobby') { err(ws, 'in_match', { id: p.id }); return; }
    if (partyPlayers(p) >= PARTY_MAX) { err(ws, 'room_full', { id: p.id }); return; }
    if (p.visibility === 'private' && typeof msg.id === 'string' && (typeof msg.code !== 'string' || msg.code.toUpperCase() !== p.code)) {
      err(ws, typeof msg.code === 'string' ? 'invalid_code' : 'code_required', { id: p.id });
      return;
    }
  } else if (p.phase !== 'lobby') {
    err(ws, 'in_match', { id: p.id });
    return;
  }
  if ((ws.data?.gameVersion ?? '') !== p.gameVersion) {
    err(ws, 'version_mismatch', { id: p.id, hostVersion: p.gameVersion, yourVersion: ws.data?.gameVersion ?? '',
      hostVersionName: versionNameOf(p.gameVersion), yourVersionName: versionNameOf(ws.data?.gameVersion) });
    return;
  }
  if ((ws.data?.modsFp ?? '') !== p.modsFp) {
    err(ws, 'mods_mismatch', { id: p.id, hostModded: p.mods.length > 0, hostMods: p.mods, yourMods: ws.data?.mods ?? [] });
    return;
  }
  if (!D.claimName(ws, msg)) return;
  let pid = held;
  if (pid < 0) {
    pid = 0;
    while (p.seats[pid]) pid++;
    p.seats[pid] = newSeat(ws, ws.data?.name || `Player ${pid + 1}`, 4);
    const cfg = cfgOf(p);
    if (cfg.kind === 'teams') {
      const n = teamCount(seatList(p).length, cfg.teamSize);
      const counts = Array.from({ length: n }, (_, t) => seatList(p).filter(([i, s]) => i !== pid && s.team === t).length);
      p.seats[pid]!.team = counts.indexOf(Math.min(...counts));
    }
  } else if (ws.data?.name) {
    p.seats[pid]!.name = ws.data.name;
  }
  attach(p, pid, ws);
  p.seats[pid]!.ready = false;
  scheduleHold(p);
  touch(p);
  D.sendTo(ws, { type: 'party_joined', code: p.code, id: p.id, visibility: p.visibility, playerId: pid, host: pid === p.hostId, token: p.seats[pid]!.token, settings: p.settings, version: p.gameVersion, rejoined: held >= 0 });
  broadcastRoom(p);
  D.log('INFO', 'PARTY', `Joined ${p.code} seat ${pid}${held >= 0 ? ' (held)' : ''}`);
}

function notifyOthers(p: Party, pid: number, event: string): void {
  const s = p.seats[pid];
  if (!s) return;
  for (const [i, o] of seatList(p)) if (i !== pid) send(o, { type: 'party_notice', event, pid, name: s.name, party: true });
}

function leaveLobby(p: Party, pid: number, hold: boolean): void {
  const s = p.seats[pid];
  if (!s) return;
  notifyOthers(p, pid, hold ? 'dropped' : 'left');
  detach(p, pid);
  if (pid === p.hostId) {
    const n = seatList(p).find(([i, o]) => i !== pid && live(o.ws));
    if (!n) { closeParty(p, 'host_left'); return; }
    p.hostId = n[0];
    n[1].ready = false;
    D.log('INFO', 'PARTY', `Host of ${p.code} left, seat ${n[0]} is host now`);
  }
  if (hold) {
    s.holdDeadline = Date.now() + D.holdMs();
    s.ready = false;
    scheduleHold(p);
  } else {
    p.seats[pid] = null;
  }
  touch(p);
  broadcastRoom(p);
}

function leaveAfter(p: Party, pid: number): void {
  notifyOthers(p, pid, 'left');
  detach(p, pid);
  p.seats[pid]!.holdDeadline = null;
  if (!seatList(p).some(([, s]) => live(s.ws) || s.holdDeadline !== null)) { closeParty(p, 'opponent_left'); return; }
  nextHost(p);
  if (p.phase === 'finished') { p.seats[pid] = null; nextHost(p); }
  broadcastState(p);
}

function dropInMatch(p: Party, pid: number, event: 'dropped' | 'menu' = 'dropped'): void {
  const s = p.seats[pid]!;
  notifyOthers(p, pid, event);
  detach(p, pid);
  s.readyBlind = false;
  s.holdDeadline = Date.now() + D.holdMs();
  scheduleHold(p);
  nextHost(p);
  broadcastState(p);
  checkStart(p);
  checkResolve(p);
  D.log('INFO', 'PARTY', `Seat ${pid} ${event === 'menu' ? 'went to the menu in' : 'dropped from'} ${p.code}, held`);
}

function handleLeave(ws: WS, kind: 'leave' | 'menu' | 'close' | 'forfeit'): void {
  const p = partyForSocket(ws);
  if (!p) return;
  const pid = pidOf(p, ws);
  if (pid < 0) return;
  touch(p);
  if (p.phase === 'lobby') { leaveLobby(p, pid, kind === 'close'); return; }
  const s = p.seats[pid]!;
  if (p.phase === 'finished' || !s.alive) { leaveAfter(p, pid); return; }
  if (kind === 'leave' || kind === 'forfeit') {
    notifyOthers(p, pid, 'left');
    s.holdDeadline = null;
    if (!seatList(p).some(([i, o]) => i !== pid && (live(o.ws) || o.holdDeadline !== null))) { closeParty(p, 'opponent_left'); return; }
    forfeit(p, pid, kind === 'forfeit' ? 'forfeited' : 'left');
    detach(p, pid);
    if (p.seats[pid]) p.seats[pid]!.holdDeadline = null;
    return;
  }
  dropInMatch(p, pid, kind === 'menu' ? 'menu' : 'dropped');
}

export function partyCleanup(ws: WS): void { handleLeave(ws, 'close'); }

function handleKick(ws: WS, msg: Msg): void {
  const p = partyForSocket(ws);
  if (!p) return;
  const pid = pidOf(p, ws);
  if (pid < 0) return;
  if (pid !== p.hostId) { err(ws, 'host_only'); return; }
  const target = Number(msg.pid);
  if (!Number.isInteger(target) || target === pid) { err(ws, 'bad_kick'); return; }
  const t = p.seats[target];
  if (!t || !t.ws || !live(t.ws)) { err(ws, 'no_such_player'); return; }
  const tws = t.ws;
  touch(p);
  send(t, { type: 'party_kicked', reason: 'host', party: true });
  D.log('INFO', 'PARTY', `Seat ${target} kicked from ${p.code} by host`);
  handleLeave(tws, 'forfeit');
}

function handleReady(ws: WS, msg: Msg): void {
  const p = partyForSocket(ws);
  if (!p || p.phase !== 'lobby') return;
  const pid = pidOf(p, ws);
  if (pid < 0) return;
  p.seats[pid]!.ready = msg.ready === true;
  broadcastRoom(p);
}

function handleTeam(ws: WS, msg: Msg): void {
  const p = partyForSocket(ws);
  if (!p || p.phase !== 'lobby') return;
  const me = pidOf(p, ws);
  const cfg = cfgOf(p);
  if (me !== p.hostId && (me !== msg.pid || cfg.teamAuto)) return;
  const s = p.seats[msg.pid as number];
  if (!s) return;
  const n = teamCount(seatList(p).length, cfg.teamSize);
  s.team = Math.min(n - 1, msg.team as number);
  broadcastRoom(p);
}

function handleBalance(ws: WS): void {
  const p = partyForSocket(ws);
  if (!p || p.phase !== 'lobby' || pidOf(p, ws) !== p.hostId) return;
  applyBalance(p);
  broadcastRoom(p);
}

function applyBalance(p: Party): void {
  const ids = seatList(p).map(([i]) => i);
  const t = balanceTeams(ids, cfgOf(p).teamSize);
  for (const i of ids) p.seats[i]!.team = t[i];
}

function handleSettings(ws: WS, msg: Msg): void {
  const p = partyForSocket(ws);
  if (!p || pidOf(p, ws) !== p.hostId || p.phase !== 'lobby') return;
  const s = cleanSettings(msg.settings);
  if (!s) return;
  const kindBefore = p.settings.party_kind;
  Object.assign(p.settings, s);
  if (!PARTY_KINDS.includes(p.settings.party_kind as never)) p.settings.party_kind = kindBefore ?? 'br';
  p.settings.mode = 'attrition';
  touch(p);
  for (const [pid, seat] of seatList(p)) if (pid !== p.hostId) send(seat, { type: 'match_settings', settings: p.settings });
  broadcastRoom(p);
}

export function startError(p: Party): string | null {
  const present = seatList(p).filter(([, s]) => live(s.ws));
  if (present.length < Math.max(2, KIND_MIN[cfgOf(p).kind] ?? 2)) return 'not_enough_players';
  if (present.some(([i, s]) => i !== p.hostId && !s.ready)) return 'not_ready';
  const cfg = cfgOf(p);
  if (cfg.kind === 'teams') {
    const teams = new Set(present.map(([, s]) => s.team));
    if (teams.size < 2 && !cfg.teamAuto) return 'need_two_teams';
    if (!cfg.teamAuto) {
      const n = teamCount(present.length, cfg.teamSize);
      const counts = Array.from({ length: n }, (_, t) => present.filter(([, s]) => s.team === t).length);
      if (present.some(([, s]) => s.team >= n)) return 'teams_uneven';
      if (Math.max(...counts) > cfg.teamSize) return 'team_too_big';
      if (Math.min(...counts) !== Math.max(...counts)) return 'teams_uneven';
    }
  }
  return null;
}

function handleStart(ws: WS, msg: Msg): void {
  const p = partyForSocket(ws);
  if (!p || p.phase !== 'lobby' || pidOf(p, ws) !== p.hostId) return;
  const e = startError(p);
  if (e) { err(ws, e); return; }
  for (const [pid, s] of seatList(p)) if (!live(s.ws)) p.seats[pid] = null;
  startMatch(p, typeof msg.seed === 'string' && msg.seed.length > 0 && msg.seed.length <= 16 ? msg.seed : null);
}

export function startMatch(p: Party, seed: string | null): void {
  const cfg = cfgOf(p);
  p.settings.mode = 'attrition';
  const tc = teamCount(seatList(p).length, cfg.teamSize);
  if (cfg.kind === 'teams' && (cfg.teamAuto || new Set(seatList(p).map(([, s]) => s.team)).size < 2 || seatList(p).some(([, s]) => s.team >= tc))) applyBalance(p);
  p.phase = 'playing';
  p.pvpAnte = null;
  p.pvpStarted = false;
  p.suddenDeath = 0;
  p.outCount = 0;
  p.lastResult = null;
  p.lastPvp = 0;
  p.finalAnte = D.finalAnteFor(p.settings);
  p.teamLives = {};
  p.raidLives = cfg.raidLives;
  for (const [, s] of seatList(p)) {
    Object.assign(s, { lives: cfg.lives, alive: true, score: null, finished: false, readyBlind: false, ante: 1, blind: 'S', placement: null, endReason: null, result: null, snapshot: null, ready: false, ended: false, done: false, freeDrop: true, solo: false, live: null, board: null, spectating: null, best: 0, lostBlinds: [] });
    if (cfg.kind === 'teams') p.teamLives[s.team] = cfg.lives;
    if (cfg.kind !== 'teams') s.team = 0;
  }
  setupModes(p, cfg);
  p.swap = partySwapOn(p.settings) ? newPartySwap() : undefined;
  const custom = typeof p.settings.custom_seed === 'string' ? p.settings.custom_seed.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8) : '';
  p.seed = custom && custom !== 'RANDOM' ? custom : (seed ?? D.randomSeed());
  const diff = p.settings.different_seeds === true;
  p.matchId = crypto.randomUUID();
  touch(p);
  for (const [pid, s] of seatList(p)) {
    const mySeed = diff && pid !== p.hostId ? D.randomSeed() : p.seed;
    send(s, { type: 'match_start', seed: mySeed, settings: clientSettings(p), player_name: p.seats[p.hostId]?.name ?? 'Host', party: true, playerId: pid, match_id: p.matchId, players: seatRoster(p, p.seats) });
    send(s, { type: 'match_session', code: p.code, id: p.id, playerId: pid, token: s.token, holdSeconds: Math.round(D.holdMs() / 1000), party: true });
    send(s, matchState(p, pid, 'match_started'));
    send(s, statePayload(p, pid));
  }
  D.onMatchStart?.(p);
  D.log('INFO', 'PARTY', `Started ${p.code}: ${cfg.kind} players=${seatList(p).length}`);
}

function blindPos(ante: number, blind: string): number { return ante * 3 + (blind === 'S' ? 0 : blind === 'B' ? 1 : 2); }
function atPvp(p: Party, s: Seat): boolean { return p.pvpAnte !== null && s.ante === p.pvpAnte && s.blind === p.pvpBlind; }
function inPvp(p: Party, s: Seat): boolean { return atPvp(p, s); }
function stalePvp(p: Party, here: number): boolean { return here <= p.lastPvp || (p.pvpAnte !== null && here < blindPos(p.pvpAnte, p.pvpBlind)); }
function pastPvp(p: Party, s: Seat): boolean { return p.pvpAnte !== null && blindPos(s.ante, s.blind) > blindPos(p.pvpAnte, p.pvpBlind); }
function nextPvp(p: Party): number {
  for (let pos = Math.max(p.lastPvp + 1, blindPos(1, 'S')); pos <= p.lastPvp + 300; pos++) {
    if (isPvpBlind(p, Math.floor(pos / 3), ['S', 'B', 'L'][pos % 3])) return pos;
  }
  return -1;
}
function pvpStart(p: Party): number {
  if (typeof p.settings.pvp_start_round === 'number') return p.settings.pvp_start_round;
  return 1;
}
function clientSettings(p: Party): Record<string, unknown> {
  const out: Record<string, unknown> = { ...p.settings, pvp_start_round: pvpStart(p) };
  if (everyBlind(p)) { out.mode = 'faceoff'; out.showdown_starting_antes = pvpStart(p); }
  if (cfgOf(p).kind === 'race') out.mode = 'race';
  return out;
}
function rejoinSettings(p: Party): Record<string, unknown> {
  const out = clientSettings(p);
  if (out.mode === 'attrition') out.mode = 'nemesis';
  return out;
}
function everyBlind(p: Party): boolean { return p.settings.party_every_blind === true || (cfgOf(p).kind === 'raid' && p.settings.raid_every_blind === true); }

function isPvpBlind(p: Party, ante: number, blind: string): boolean {
  if (cfgOf(p).kind === 'race') return false;
  if (ante < pvpStart(p)) return false;
  return everyBlind(p) ? (blind === 'S' || blind === 'B' || blind === 'L') : blind === 'L';
}

function openPvp(p: Party, ante: number, blind = 'L'): void {
  p.pvpAnte = ante;
  p.pvpBlind = blind;
  p.pvpStarted = false;
  for (const [, o] of aliveSeats(p)) { o.score = null; o.finished = false; o.done = false; o.leftOut = false; if (o.ante !== ante || o.blind !== blind) o.readyBlind = false; }
  armTimer(p);
}

function soloPass(p: Party, pid: number): void {
  const s = p.seats[pid]!;
  s.solo = true;
  send(s, { type: 'start_blind', party: true, solo: true });
}

function handleBlindEntered(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  if (!s.alive) return;
  s.ante = typeof msg.ante === 'number' ? msg.ante : s.ante;
  s.blind = typeof msg.blind === 'string' ? msg.blind : s.blind;
  s.solo = false;
  touch(p);
  if (isPvpBlind(p, s.ante, s.blind)) {
    const here = blindPos(s.ante, s.blind);
    if (stalePvp(p, here)) {
      send(s, matchState(p, pid, 'blind_entered'));
      soloPass(p, pid);
      broadcastState(p);
      return;
    }
    if (p.pvpAnte === null) openPvp(p, s.ante, s.blind);
    else if (atPvp(p, s) && p.pvpStarted && !s.done) { s.leftOut = false; send(s, { type: 'start_blind', party: true }); }
  }
  send(s, matchState(p, pid, 'blind_entered'));
  broadcastState(p);
  checkStart(p);
}


function checkStart(p: Party, force = false): void {
  if (p.pvpAnte === null || p.pvpStarted) return;
  const present = aliveSeats(p).filter(([, s]) => live(s.ws));
  if (present.length === 0) return;
  const due = present.filter(([, s]) => !pastPvp(p, s));
  for (const [pid, s] of present) {
    const rest = due.filter(([i]) => i !== pid);
    send(s, { type: rest.every(([, o]) => o.readyBlind) ? 'opponent_ready_blind' : 'opponent_unready_blind' });
  }
  const inside = due.filter(([, s]) => inPvp(p, s));
  if (force ? inside.length === 0 : (inside.length === 0 || !due.every(([, s]) => s.readyBlind && inPvp(p, s)))) return;
  p.pvpStarted = true;
  for (const [, s] of inside) { s.readyBlind = false; send(s, { type: 'start_blind', party: true }); }
  for (const [, s] of present) if (!inPvp(p, s)) s.leftOut = true;
  armTimer(p);
  broadcastState(p);
}

function armTimer(p: Party): void {
  if (p.pvpTimer) clearTimeout(p.pvpTimer);
  const ms = partyTiming.blindMs > 0 ? partyTiming.blindMs : cfgOf(p).blindSeconds * 1000;
  p.pvpTimer = setTimeout(() => {
    p.pvpTimer = null;
    if (p.pvpAnte === null || parties[p.code] !== p) return;
    if (!anyoneHere(p)) { armTimer(p); return; }
    if (!p.pvpStarted) {
      D.log('WARN', 'PARTY', `Ready timeout in ${p.code}, starting without the stragglers`);
      checkStart(p, true);
      if (!p.pvpStarted) armTimer(p);
      return;
    }
    D.log('WARN', 'PARTY', `Blind timeout in ${p.code}, closing with scores so far`);
    for (const [, s] of aliveSeats(p)) if (!s.finished) { s.finished = true; s.score = s.score ?? 0; }
    checkResolve(p);
  }, ms);
}

function handleReadyBlind(p: Party, pid: number, ready: boolean, msg?: Msg): void {
  const s = p.seats[pid]!;
  if (!s.alive) return;
  if (ready && msg && typeof msg.ante === 'number' && typeof msg.blind === 'string' && isPvpBlind(p, msg.ante, msg.blind)) {
    const here = blindPos(msg.ante, msg.blind);
    const passed = s.solo && s.ante === msg.ante && s.blind === msg.blind;
    s.ante = msg.ante;
    s.blind = msg.blind;
    if (stalePvp(p, here)) {
      s.readyBlind = false;
      if (!passed) soloPass(p, pid);
      broadcastState(p);
      return;
    }
    if (p.pvpAnte === null) openPvp(p, s.ante, s.blind);
    else if (atPvp(p, s) && p.pvpStarted && !s.done) {
      s.leftOut = false;
      s.readyBlind = false;
      send(s, { type: 'start_blind', party: true });
      broadcastState(p);
      return;
    }
  }
  s.readyBlind = ready;
  if (p.pvpAnte === null) return;
  checkStart(p);
}

function liveScores(p: Party, _pid: number): void {
  for (const [i, s] of aliveSeats(p)) {
    const v = viewFor(p, i);
    send(s, { type: 'enemy_info', score: String(v.value ?? 0), hands_left: 0, lives: oppAggregate(p, i).lives, party: true, view: v });
  }
  broadcastState(p);
}

function parseScore(v: unknown): number {
  const n = typeof v === 'number' ? v : parseFloat(String(v ?? '0'));
  return Number.isFinite(n) && n >= 0 ? Math.min(n, 1e300) : 0;
}

function soloDone(p: Party, pid: number): void {
  const s = p.seats[pid]!;
  s.solo = false;
  send(s, {
    type: 'pvp_resolved', party: true, solo: true, result: 'draw', myScore: 0, oppScore: 0, myLives: poolLives(p, s), oppLives: oppAggregate(p, pid).lives,
    matchEnded: false, winner: null, winReason: null, finalPvp: false, finalAnte: p.finalAnte, suddenDeath: p.suddenDeath,
    lowest: null, highest: null, raidTotal: 0, raidTarget: 0,
  });
}

function handlePlayHand(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  if (s.alive && s.solo) {
    const h = typeof msg.hands_left === 'number' ? msg.hands_left : (parseInt(String(msg.hands_left ?? '1')) || 0);
    if (h === 0) soloDone(p, pid);
    return;
  }
  if (!s.alive || !inPvp(p, s) || s.finished || !p.pvpStarted) return;
  s.score = parseScore(msg.score);
  s.best = Math.max(s.best ?? 0, s.score ?? 0);
  const hands = typeof msg.hands_left === 'number' ? msg.hands_left : (parseInt(String(msg.hands_left ?? '1')) || 0);
  if (p.pvpTimer && p.pvpStarted) armTimer(p);
  if (hands === 0) { s.finished = true; s.done = true; }
  liveScores(p, pid);
  if (s.finished) checkResolve(p);
}

function handleBlindFinished(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  if (cfgOf(p).kind === 'race') { raceFinished(p, pid, msg); return; }
  if (s.alive && s.solo) { soloDone(p, pid); return; }
  if (!s.alive || !inPvp(p, s) || s.finished || !p.pvpStarted) return;
  if (msg.ante !== undefined && Number(msg.ante) !== s.ante) return;
  if (msg.blind !== undefined && msg.blind !== s.blind) return;
  s.score = parseScore(msg.score);
  s.best = Math.max(s.best ?? 0, s.score ?? 0);
  s.finished = true;
  s.done = true;
  liveScores(p, pid);
  checkResolve(p);
}

function handleGameOver(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  if (!s.alive) return;
  if (s.solo) { soloDone(p, pid); return; }
  if (inPvp(p, s) && !s.finished) {
    s.score = s.score ?? 0;
    s.finished = true;
    s.done = true;
    liveScores(p, pid);
    checkResolve(p);
    return;
  }
  s.solo = false;
  if (!D.lifeOnRoundLoss(p.settings)) { send(s, matchState(p, pid, 'round_lost')); return; }
  if (typeof msg.ante === 'number' && typeof msg.blind === 'string') {
    const at = `${msg.ante}:${msg.blind}`;
    if ((s.lostBlinds ?? []).includes(at)) { send(s, matchState(p, pid, 'round_lost')); return; }
    (s.lostBlinds ??= []).push(at);
  }
  const cfg = cfgOf(p);
  if (cfg.kind === 'teams') p.teamLives[s.team] = Math.max(0, (p.teamLives[s.team] ?? 0) - 1);
  else if (cfg.kind === 'raid') p.raidLives = Math.max(0, p.raidLives - 1);
  else s.lives = Math.max(0, s.lives - 1);
  afterLifeChange(p, 'life_lost');
}

function checkResolve(p: Party): void {
  if (p.pvpAnte === null || !p.pvpStarted) return;
  const alive = aliveSeats(p);
  if (alive.length === 0 || !anyoneHere(p)) return;
  const waiting = alive.filter(([, s]) => live(s.ws) && !s.finished && !s.leftOut);
  if (waiting.length > 0) return;
  for (const [, s] of alive) if (!s.finished) { s.finished = true; s.score = s.score ?? 0; }
  resolveBlind(p);
}

function placementFor(p: Party): number { return seatList(p).filter(([, s]) => s.alive).length; }

function eliminate(p: Party, pid: number, reason: string, place?: number): void {
  const s = p.seats[pid]!;
  if (!s.alive) return;
  s.placement = place ?? placementFor(p);
  s.alive = false;
  s.result = 'lose';
  s.endReason = reason;
  p.outCount += 1;
}

export function resolveBlind(p: Party): void {
  const cfg = cfgOf(p);
  const ante = p.pvpAnte ?? 1;
  const blindKey = p.pvpBlind;
  const final = ante >= p.finalAnte;
  if (p.pvpTimer) { clearTimeout(p.pvpTimer); p.pvpTimer = null; }
  const satOut: number[] = [];
  const players = seatList(p).map(([pid, s]) => {
    let present = live(s.ws) || s.done;
    if (cfg.kind === 'raid' && s.leftOut && !s.done) present = false;
    if (!present && s.alive && cfg.kind !== 'raid') {
      if (s.freeDrop) { s.freeDrop = false; satOut.push(pid); } else present = true;
    }
    return { pid, alive: s.alive, score: s.score ?? 0, team: s.team, lives: s.lives, present };
  });
  const r = resolveParty(cfg, players, p.teamLives, ante, blindKey);
  for (const pid of r.lifeLoss) p.seats[pid]!.lives = Math.max(0, p.seats[pid]!.lives - 1);
  for (const t of r.teamLoss) p.teamLives[t] = Math.max(0, (p.teamLives[t] ?? 0) - 1);
  if (r.raidFail) p.raidLives = Math.max(0, p.raidLives - 1);
  const scores: Record<number, number> = {};
  for (const x of players) scores[x.pid] = x.score;
  p.lastResult = { ante, kind: cfg.kind, lowest: r.lowest, highest: r.highest, lifeLoss: r.lifeLoss, teamLoss: r.teamLoss, raidFail: r.raidFail, raidTotal: r.raidTotal, raidTarget: r.raidTarget, teamScores: r.teamScores, scores, satOut };
  D.log('INFO', 'PARTY', `Resolved ${p.code} ante ${ante}: ${JSON.stringify(p.lastResult)}`);
  const outcomes = r.outcome;
  const mvp = cfg.kind === 'raid' && r.highest !== null && (players.find(x => x.pid === r.highest)?.score ?? 0) > 0 ? r.highest : null;
  const nameOf = (i: number | null): string | null => (i !== null && p.seats[i] ? p.seats[i]!.name : null);
  const ranked = players.filter(x => x.alive && x.present);
  const rankOf = (i: number): number | null => {
    const me = ranked.find(x => x.pid === i);
    return me ? 1 + ranked.filter(x => x.pid !== i && x.score > me.score).length : null;
  };
  const aggBefore: Record<number, { score: number }> = {};
  for (const [pid] of aliveSeats(p)) aggBefore[pid] = { score: cfg.kind === 'raid' ? r.raidTarget : cfg.kind === 'teams' ? bestEnemyTeam(r.teamScores, p.seats[pid]!.team) : oppAggregate(p, pid).score };
  p.pvpAnte = null;
  p.pvpStarted = false;
  p.lastPvp = Math.max(p.lastPvp, blindPos(ante, p.pvpBlind));
  applyEliminations(p, cfg);
  const over = matchOver(p, cfg, final && !r.raidFail);
  if (!over && final && cfg.kind !== 'raid') p.suddenDeath += 1;
  for (const [pid, s] of seatList(p)) {
    if (outcomes[pid] === undefined) continue;
    const agg = oppAggregate(p, pid);
    const ended = !s.alive || over;
    send(s, {
      type: 'pvp_resolved', party: true,
      result: outcomes[pid], myScore: scores[pid] ?? 0, oppScore: aggBefore[pid]?.score ?? 0,
      myLives: poolLives(p, s), oppLives: agg.lives,
      matchEnded: ended, winner: ended && s.result === 'win' ? pid : null, winReason: ended ? s.endReason : null,
      finalPvp: final, finalAnte: p.finalAnte, suddenDeath: ended ? 0 : p.suddenDeath,
      lowest: r.lowest, highest: r.highest, raidTotal: r.raidTotal, raidTarget: r.raidTarget,
      kind: cfg.kind, blind: blindKey, ante,
      lifeLost: r.lifeLoss.includes(pid) || r.teamLoss.includes(s.team) || (cfg.kind === 'raid' && r.raidFail),
      lowestName: nameOf(r.lowest), lowestScore: r.lowest !== null ? (scores[r.lowest] ?? 0) : null,
      highestName: nameOf(r.highest), highestScore: r.highest !== null ? (scores[r.highest] ?? 0) : null,
      losers: r.lifeLoss.map(i => p.seats[i]?.name ?? '?'),
      rank: rankOf(pid), ranked: ranked.length,
      mvpName: mvp !== null ? nameOf(mvp) : null, mvpScore: mvp !== null ? (scores[mvp] ?? 0) : null, mvpBonus: mvp !== null ? cfg.raidMvp : 0, mvp: mvp === pid,
      myTeam: s.team, teamScores: r.teamScores, teamLives: { ...p.teamLives }, teamLoss: r.teamLoss, raidLives: p.raidLives,
    });
  }
  for (const [, s] of seatList(p)) {
    s.score = null; s.finished = false; s.done = false; s.leftOut = false;
    if (s.ante <= ante) s.readyBlind = false;
  }
  finishOrContinue(p, over, 'pvp_resolved');
  if (!over) reopenPvp(p);
}

function bestEnemyTeam(scores: Record<number, number>, team: number): number {
  let best = 0;
  for (const [t, sc] of Object.entries(scores)) if (Number(t) !== team && sc > best) best = sc;
  return best;
}

function reopenPvp(p: Party): void {
  if (p.pvpAnte !== null || p.phase !== 'playing') return;
  const next = nextPvp(p);
  const first = aliveSeats(p).find(([, s]) => isPvpBlind(p, s.ante, s.blind) && blindPos(s.ante, s.blind) === next);
  if (!first) return;
  openPvp(p, first[1].ante, first[1].blind);
  broadcastState(p);
  checkStart(p);
}

function applyEliminations(p: Party, cfg: PartyCfg): void {
  const place = placementFor(p);
  if (cfg.kind === 'br') {
    const dead = aliveSeats(p).filter(([, s]) => s.lives <= 0);
    for (const [pid] of dead) eliminate(p, pid, 'eliminated', place - dead.length + 1);
    const left = aliveSeats(p);
    if (cfg.brSuddenDeath && left.length === 2) for (const [, s] of left) s.lives = Math.min(s.lives, 1);
  } else if (cfg.kind === 'teams') {
    const dead = aliveSeats(p).filter(([, s]) => (p.teamLives[s.team] ?? 0) <= 0);
    const teamsLeft = new Set(aliveSeats(p).filter(([, s]) => (p.teamLives[s.team] ?? 0) > 0).map(([, s]) => s.team)).size;
    for (const [pid] of dead) eliminate(p, pid, 'team_eliminated', teamsLeft + 1);
  } else if (cfg.kind === 'race') {
    const dead = aliveSeats(p).filter(([, s]) => s.lives <= 0);
    for (const [pid] of dead) eliminate(p, pid, 'eliminated', place - dead.length + 1);
  } else if (p.raidLives <= 0) {
    for (const [pid] of aliveSeats(p)) eliminate(p, pid, 'raid_failed', place);
  }
}

function matchOver(p: Party, cfg: PartyCfg, finalRaid: boolean): boolean {
  const alive = aliveSeats(p);
  if (cfg.kind === 'race') return raceOver(p);
  if (cfg.kind === 'raid') {
    if (alive.length === 0) return true;
    if (finalRaid) { for (const [, s] of alive) { s.result = 'win'; s.endReason = 'raid_cleared'; } return true; }
    return false;
  }
  if (cfg.kind === 'teams') {
    const teams = new Set(alive.map(([, s]) => s.team));
    if (teams.size <= 1) { for (const [, s] of alive) { s.result = 'win'; s.endReason = 'team_won'; s.placement = 1; } return true; }
    return false;
  }
  if (alive.length <= 1) { for (const [, s] of alive) { s.result = 'win'; s.endReason = 'last_standing'; s.placement = 1; } return true; }
  return false;
}

function finishOrContinue(p: Party, over: boolean, event: string): void {
  for (const [pid, s] of seatList(p)) {
    if (s.endReason && !s.alive && !s.ended) {
      s.ended = true;
      send(s, { type: 'match_ended', event, match_id: p.matchId, playerId: pid, result: 'lose', reason: s.endReason, winner: null, myLives: 0, oppLives: oppAggregate(p, pid).lives, placement: s.placement, party: true, players: seatRoster(p, p.seats) });
    }
  }
  if (over) {
    p.phase = 'finished';
    clearTimers(p);
    for (const [pid, s] of seatList(p)) {
      if (!s.alive) continue;
      s.alive = false;
      s.ended = true;
      send(s, { type: 'match_ended', event, match_id: p.matchId, playerId: pid, result: s.result ?? 'draw', reason: s.endReason ?? 'match_over', winner: s.result === 'win' ? pid : null, myLives: poolLives(p, s), oppLives: 0, placement: s.placement, party: true, over: true, players: seatRoster(p, p.seats) });
    }
    for (const [, s] of seatList(p)) s.holdDeadline = null;
    D.log('INFO', 'PARTY', `Match over in ${p.code}`);
    D.onMatchOver?.(p);
  }
  broadcastMatch(p, event);
  broadcastState(p);
  if (!over) checkResolve(p);
  if (!over && p.swap) trySwap(p.swap, swapIO(p));
}

function swapIO(p: Party): PartySwapIO {
  return {
    members: () => aliveSeats(p).filter(([, s]) => !isBotWs(s.ws)).map(([i]) => i),
    name: pid => p.seats[pid]?.name ?? '?',
    send: (pid, payload) => send(p.seats[pid] ?? null, payload),
    setSnapshot: (pid, data, ante) => {
      const s = p.seats[pid];
      if (s) s.snapshot = { data, bytes: data.length, ante, blind: 'Small', seq: s.snapshot?.seq ?? null, at: Date.now() };
    },
    log: (level, text) => D.log(level, 'PARTY_SWAP', `${text} party=${p.code}`),
  };
}

function afterLifeChange(p: Party, event: string): void {
  const cfg = cfgOf(p);
  applyEliminations(p, cfg);
  const over = matchOver(p, cfg, false);
  finishOrContinue(p, over, event);
}

function forfeit(p: Party, pid: number, reason: string): void {
  const s = p.seats[pid]!;
  if (!s.alive) return;
  eliminate(p, pid, reason);
  const cfg = cfgOf(p);
  const over = matchOver(p, cfg, false);
  finishOrContinue(p, over, 'player_left');
  if (!over) { checkStart(p); checkResolve(p); }
}

function handleReturnToLobby(p: Party, pid: number): void {
  if (pid !== p.hostId || p.phase !== 'finished') return;
  p.phase = 'lobby';
  clearTimers(p);
  p.pvpAnte = null;
  for (const [i, s] of seatList(p)) {
    if (!live(s.ws)) { p.seats[i] = null; continue; }
    Object.assign(s, { ready: false, alive: true, placement: null, endReason: null, result: null, score: null, finished: false });
    s.ended = false;
  }
  for (const [i, s] of seatList(p)) {
    send(s, { type: 'lobby_returned', by: pid, rematchCleared: false, settings: p.settings, gameHistory: [], code: p.code, host: i === p.hostId, playerId: i, token: s.token, party: true });
  }
  broadcastRoom(p);
}

function rejoinPayload(p: Party, pid: number): Msg {
  const s = p.seats[pid]!;
  const agg = oppAggregate(p, pid);
  return {
    type: 'rejoin_ok', party: true, match_id: p.matchId, act_seq: matchlogs.actSeq(p, pid), code: p.code, id: p.id, playerId: pid, host: pid === p.hostId, token: s.token, settings: rejoinSettings(p),
    seed: p.seed, myDeck: null, phase: inPvp(p, s) ? 'pvp_pending' : 'playing', mode: cfgOf(p).kind === 'race' ? 'race' : everyBlind(p) ? 'faceoff' : 'attrition', startingLives: cfgOf(p).lives,
    pvpStartAnte: pvpStart(p) - 1,
    finalAnte: p.finalAnte, suddenDeath: p.suddenDeath, currentAnte: s.ante, currentBlind: s.blind, isPvpBlind: inPvp(p, s),
    anteTimer: false, anteTimerBase: 0, anteClock: null,
    me: { name: s.name, lives: poolLives(p, s), status: 'active', location: s.location },
    opp: { name: agg.name, lives: agg.lives, status: 'active', location: null, connected: true, secondsLeft: null },
    pvp: {
      pending: inPvp(p, s), started: p.pvpStarted, paused: false, timerMs: p.pvpTimer ? cfgOf(p).blindSeconds * 1000 : null,
      myReady: s.readyBlind, oppReady: false, myFinished: s.finished, oppFinished: false, myScore: s.score, oppScore: viewFor(p, pid).value ?? 0,
      lastResult: null,
    },
    pvpResults: [], gameHistory: [], snapshot: s.snapshot, swap: partySwapStatus(p.swap, pid),
  };
}

export function handleRejoinMsg(ws: WS, msg: Msg, type: 'check_rejoin' | 'rejoin_match'): boolean {
  const code = typeof msg.code === 'string' ? msg.code : '';
  const p = parties[code];
  if (!p) return false;
  const pid = p.seats.findIndex(s => !!s && s.token === msg.token);
  if (pid < 0) return false;
  const s = p.seats[pid]!;
  const can = p.phase === 'playing' && s.alive;
  if (type === 'check_rejoin' || !can) {
    D.sendTo(ws, {
      type: type === 'check_rejoin' ? 'rejoin_status' : 'rejoin_failed', code, party: true, rejoinable: can, matchOver: !can,
      reason: can ? null : (s.endReason ?? 'match_over'), result: can ? undefined : (s.result ?? 'lose'),
      opponentWaiting: true, opponentName: oppAggregate(p, pid).name, kind: cfgOf(p).kind,
      secondsLeft: s.holdDeadline !== null ? Math.max(0, Math.ceil((s.holdDeadline - Date.now()) / 1000)) : Math.round(D.holdMs() / 1000),
      mode: everyBlind(p) ? 'faceoff' : 'attrition', ante: s.ante,
    });
    return true;
  }
  const cur = partyForSocket(ws);
  if ((cur && cur !== p) || ws.data?.roomCode) {
    D.sendTo(ws, { type: 'rejoin_failed', code, rejoinable: false, matchOver: false, reason: 'already_in_room', opponentWaiting: false });
    return true;
  }
  const old = s.ws;
  if (old && old !== ws) {
    detach(p, pid);
    D.sendTo(old, { type: 'session_replaced' });
    try { old.close(4000, 'session_replaced'); } catch { /* closed */ }
  }
  attach(p, pid, ws);
  scheduleHold(p);
  touch(p);
  D.sendTo(ws, rejoinPayload(p, pid));
  D.sendTo(ws, matchState(p, pid, 'rejoined'));
  broadcastState(p);
  checkStart(p);
  notifyOthers(p, pid, 'rejoined');
  D.log('INFO', 'PARTY', `Seat ${pid} rejoined ${p.code}`);
  return true;
}

function handleAbandon(ws: WS, msg: Msg): boolean {
  const code = typeof msg.code === 'string' ? msg.code : '';
  const p = parties[code];
  if (!p || typeof msg.token !== 'string') return false;
  const pid = p.seats.findIndex(s => !!s && s.token === msg.token);
  if (pid < 0) return false;
  const s = p.seats[pid]!;
  const kind = cfgOf(p).kind;
  if (p.phase === 'playing' && s.alive && !live(s.ws)) {
    touch(p);
    notifyOthers(p, pid, 'left');
    s.holdDeadline = null;
    D.log('INFO', 'PARTY', `Seat ${pid} gave up its held seat in ${p.code}`);
    if (!seatList(p).some(([i, o]) => i !== pid && (live(o.ws) || o.holdDeadline !== null))) closeParty(p, 'opponent_left');
    else { forfeit(p, pid, 'abandoned'); scheduleHold(p); }
  }
  D.sendTo(ws, { type: 'rejoin_status', code, party: true, kind, rejoinable: false, matchOver: true, reason: s.endReason ?? 'abandoned', result: s.result ?? 'lose', opponentWaiting: false });
  return true;
}

const LOBBY_TYPES: Record<string, (ws: WS, msg: Msg) => void> = {
  party_create: handleCreate,
  party_join: handleJoin,
  party_leave: (ws) => handleLeave(ws, 'leave'),
  party_kick: handleKick,
  party_ready: handleReady,
  party_team: handleTeam,
  party_balance: (ws) => handleBalance(ws),
  party_start: handleStart,
};

export const PARTY_TYPES = Object.keys(LOBBY_TYPES);

export function handlePartyMessage(ws: WS, msg: Msg): boolean {
  const t = msg.type as string;
  if (LOBBY_TYPES[t]) { LOBBY_TYPES[t](ws, msg); return true; }
  if (t === 'check_rejoin' || t === 'rejoin_match') return handleRejoinMsg(ws, msg, t);
  const p = partyForSocket(ws);
  if (!p) return t === 'leave_match' && handleAbandon(ws, msg);
  const pid = pidOf(p, ws);
  if (pid < 0) return false;
  touch(p);
  switch (t) {
    case 'match_settings': handleSettings(ws, msg); return true;
    case 'player_name': {
      if (msg.name !== undefined && !D.claimName(ws, msg)) return true;
      if (ws.data?.name) p.seats[pid]!.name = ws.data.name;
      if (p.phase === 'lobby') broadcastRoom(p); else broadcastState(p);
      return true;
    }
    case 'leave_lobby': handleLeave(ws, 'leave'); return true;
    case 'return_to_menu': handleLeave(ws, 'menu'); return true;
    case 'leave_match': handleLeave(ws, 'forfeit'); return true;
    case 'return_to_lobby': handleReturnToLobby(p, pid); return true;
    case 'request_state': send(p.seats[pid], statePayload(p, pid)); if (p.phase !== 'lobby') send(p.seats[pid], matchState(p, pid)); else send(p.seats[pid], roomPayload(p)); return true;
    case 'ping': return false;
    case 'list_rooms': return false;
  }
  if (p.phase !== 'playing') return true;
  switch (t) {
    case 'blind_entered': handleBlindEntered(p, pid, msg); break;
    case 'blind_finished': handleBlindFinished(p, pid, msg); break;
    case 'play_hand': handlePlayHand(p, pid, msg); break;
    case 'game_over': handleGameOver(p, pid, msg); break;
    case 'ready_blind': handleReadyBlind(p, pid, true, msg); break;
    case 'unready_blind': handleReadyBlind(p, pid, false); break;
    case 'set_location':
      if (typeof msg.location !== 'string') break;
      p.seats[pid]!.location = msg.location;
      for (const [i, o] of seatList(p)) if (i !== pid) send(o, { type: 'party_location', location: msg.location, pid, party: true });
      break;
    case 'live_stat': handleLiveStat(p, pid, msg); break;
    case 'spec_board': handleBoard(p, pid, msg); break;
    case 'spectate': handleSpectate(p, pid, msg); break;
    case 'sabotage': relaySabotage(p, pid, msg); break;
    case 'swap_state': if (p.swap) handlePartySwapState(p.swap, pid, msg, swapIO(p)); break;
    case 'swap_applied': if (p.swap) handlePartySwapApplied(p.swap, pid, msg, swapIO(p)); break;
    case 'swap_ready': if (p.swap) handlePartySwapReady(p.swap, pid, msg, swapIO(p)); break;
    case 'save_snapshot':
      if (partyHoldsSnapshot(p.swap, pid)) { D.sendTo(ws, { type: 'snapshot_ack', seq: msg.seq ?? null, stale: true }); break; }
      p.seats[pid]!.snapshot = { data: msg.data, bytes: typeof msg.data === 'string' ? msg.data.length : 0, ante: msg.ante ?? null, blind: msg.blind ?? null, seq: msg.seq ?? null, at: Date.now() };
      D.sendTo(ws, { type: 'snapshot_ack', seq: msg.seq ?? null, bytes: typeof msg.data === 'string' ? msg.data.length : 0 });
      break;
    default: break;
  }
  return true;
}

function modeFields(p: Party, pid: number, s: Seat): Msg {
  const k = cfgOf(p).kind;
  if (k === 'race') return { raceCleared: s.raceCleared ?? 0, raceAt: s.raceAt ?? 0 };
  return {};
}

function modeState(p: Party): Msg {
  const k = cfgOf(p).kind;
  if (k === 'race') return { race: raceView(p) };
  return {};
}

function setupModes(p: Party, cfg: PartyCfg): void {
  p.raceGoal = undefined;
  p.raceStart = undefined;
  const seats = seatList(p);
  if (cfg.kind === 'race') {
    p.raceGoal = cfg.raceTarget;
    p.raceStart = Date.now();
    for (const [, s] of seats) { s.raceCleared = 0; s.raceAt = 0; }
  }
}

function raceEntries(p: Party): RaceEntry[] {
  return seatList(p).map(([pid, s]) => ({ pid, cleared: s.raceCleared ?? 0, at: s.raceAt ?? 0, alive: s.alive }));
}

function raceView(p: Party): Msg {
  const list = raceEntries(p);
  const order = raceOrder(list);
  const target = p.raceGoal ?? cfgOf(p).raceTarget;
  return {
    target, goal: target * 3, started: p.raceStart ?? null,
    players: list.map(e => ({
      ...e, ante: p.seats[e.pid]?.ante ?? 1, blind: p.seats[e.pid]?.blind ?? 'S', name: p.seats[e.pid]?.name ?? '', place: order.indexOf(e.pid) + 1,
    })),
  };
}

function raceFinished(p: Party, pid: number, msg: Msg): void {
  const s = p.seats[pid]!;
  if (!s.alive || p.phase !== 'playing') return;
  const ante = typeof msg.ante === 'number' ? msg.ante : s.ante;
  const blind = typeof msg.blind === 'string' ? msg.blind : s.blind;
  const c = raceCleared(ante, blind);
  if (c <= (s.raceCleared ?? 0)) return;
  s.raceCleared = c;
  s.raceAt = Date.now() - (p.raceStart ?? Date.now());
  s.best = Math.max(s.best ?? 0, parseScore(msg.score));
  const over = raceOver(p);
  finishOrContinue(p, over, over ? 'race_won' : 'race_progress');
}

function raceOver(p: Party): boolean {
  const list = raceEntries(p);
  const win = raceWinner(p.raceGoal ?? cfgOf(p).raceTarget, list);
  if (win === null) return false;
  const order = raceOrder(list.filter(e => e.alive && e.pid !== win));
  for (const [pid, s] of aliveSeats(p)) {
    if (pid === win) { s.result = 'win'; s.endReason = 'race_won'; s.placement = 1; continue; }
    s.result = 'lose';
    s.endReason = 'race_lost';
    s.placement = 2 + order.indexOf(pid);
  }
  const w = p.seats[win];
  if (w && !w.alive) { w.result = 'win'; w.endReason = 'race_won'; w.placement = 1; }
  return true;
}

export function trapRival(p: Party, from: number, to: number): boolean {
  if (from === to) return false;
  const kind = cfgOf(p).kind;
  if (kind === 'raid') return false;
  if (kind === 'teams') return p.seats[from]?.team !== p.seats[to]?.team;
  return true;
}

function leaderFor(p: Party, pid: number): number | null {
  let best: [number, Seat] | null = null;
  for (const r of aliveSeats(p)) {
    if (r[0] === pid || !trapRival(p, pid, r[0]) || isBotWs(r[1].ws)) continue;
    if (!best) { best = r; continue; }
    const a = poolLives(p, r[1]);
    const b = poolLives(p, best[1]);
    if (a > b || (a === b && (r[1].best ?? 0) > (best[1].best ?? 0))) best = r;
  }
  return best ? best[0] : null;
}

export function partyTrapTarget(p: Party, pid: number, want: unknown, id: string): number | null {
  if (cfgOf(p).kind === 'raid') return null;
  let to = typeof want === 'number' ? want : null;
  if (to === null || !p.seats[to] || !p.seats[to]!.alive || !trapRival(p, pid, to) || (id === 'trap_set' && isBotWs(p.seats[to]!.ws))) to = id === 'trap_set' ? leaderFor(p, pid) : null;
  return to;
}

function relaySabotage(p: Party, pid: number, msg: Msg): void {
  const id = typeof msg.sabotage_id === 'string' ? msg.sabotage_id : '';
  if (!id.startsWith('trap_')) return;
  const to = partyTrapTarget(p, pid, msg.to, id);
  if (to === null) return;
  msg.to = to;
  send(p.seats[to], { ...msg, type: 'sabotage', from: pid, from_name: p.seats[pid]!.name, party: true });
}

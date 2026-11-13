export const SWAP_MODE = 'swap';
export const SWAP_TYPES = ['swap_state', 'swap_applied', 'swap_ready'];
export const SWAP_COUNTDOWN = 3;
export const SWAP_FACTS_MAX = 1024;
export const SWAP_RUN_MAX = 96 * 1024;
export const SWAP_B64_MAX = 4 * Math.ceil((512 * 1024) / 3);
const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;
const ROUND_MAX = 999;

export interface SwapSeat {
  swapData?: string | null;
  swapHash?: string | null;
  swapAnte?: number | null;
  swapApplied?: number;
  swapReady?: boolean;
  swapV?: number;
  swapFacts?: Record<string, unknown> | null;
  swapRun?: Record<string, unknown> | null;
}

export interface SwapRecord { round: number; data: [string, string]; hash: [string | null, string | null]; ante: [number | null, number | null]; at: number; run?: [Record<string, unknown> | null, Record<string, unknown> | null] }

export interface SwapMatch {
  mode: string;
  phase?: string;
  swapDone?: number;
  swapLast?: SwapRecord | null;
  swapLog?: { round: number; at: number; bytes: [number, number]; hash: [string | null, string | null] }[];
  players: SwapSeat[];
}

export interface SwapIO {
  send(pid: number, payload: Record<string, unknown>): void;
  setSnapshot(pid: number, data: string, ante: number | null): void;
  names(): [string, string];
  log(level: string, msg: string): void;
}

const isInt = (v: unknown, lo: number, hi: number): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi;

export function isSwap(m: { mode?: unknown } | null | undefined): boolean {
  return !!m && m.mode === SWAP_MODE;
}

export function validateSwap(msg: Record<string, unknown>): string | null {
  if (msg.type === 'swap_state') {
    const d = msg.data;
    if (!isInt(msg.round, 1, ROUND_MAX)) return 'swap_state: invalid round';
    if (typeof d !== 'string' || d.length === 0) return 'swap_state: missing data';
    if (d.length > SWAP_B64_MAX) return 'swap_state: too large';
    if (d.length % 4 !== 0 || !BASE64_RE.test(d)) return 'swap_state: data must be base64';
    if (msg.hash !== undefined && (typeof msg.hash !== 'string' || msg.hash.length > 64)) return 'swap_state: invalid hash';
    if (msg.ante !== undefined && !isInt(msg.ante, 0, ROUND_MAX)) return 'swap_state: invalid ante';
    if (msg.v !== undefined && !isInt(msg.v, 0, 99)) return 'swap_state: invalid v';
    if (msg.facts !== undefined) {
      const f = msg.facts;
      if (!f || typeof f !== 'object' || Array.isArray(f)) return 'swap_state: invalid facts';
      if (JSON.stringify(f).length > SWAP_FACTS_MAX) return 'swap_state: facts too large';
    }
    if (msg.run !== undefined) {
      const r = msg.run;
      if (!r || typeof r !== 'object' || Array.isArray(r)) return 'swap_state: invalid run';
      if (JSON.stringify(r).length > SWAP_RUN_MAX) return 'swap_state: run too large';
    }
  }
  if (msg.type === 'swap_ready') {
    if (!isInt(msg.round, 1, ROUND_MAX)) return 'swap_ready: invalid round';
  }
  if (msg.type === 'swap_applied') {
    if (!isInt(msg.round, 1, ROUND_MAX)) return 'swap_applied: invalid round';
  }
  return null;
}

function runPayload(rec: SwapRecord, pid: number, names: [string, string]): Record<string, unknown> {
  const oid = pid === 0 ? 1 : 0;
  const out: Record<string, unknown> = {
    type: 'swap_run', round: rec.round, data: rec.data[oid], hash: rec.hash[oid], ante: rec.ante[oid],
    from: names[oid], mine: rec.hash[pid], countdown: SWAP_COUNTDOWN,
  };
  const run = rec.run?.[oid];
  if (run) out.bot_run = run;
  return out;
}

function statusPayload(m: SwapMatch, pid: number, round: number, names: [string, string]): Record<string, unknown> {
  const oid = pid === 0 ? 1 : 0;
  const me = m.players[pid] ?? {};
  const op = m.players[oid] ?? {};
  return {
    type: 'swap_status', round, ready: !!me.swapData && !!me.swapReady,
    oppSent: !!op.swapData, oppReady: !!op.swapData && !!op.swapReady,
    oppFacts: op.swapData ? (op.swapFacts ?? null) : null, from: names[oid],
  };
}

function sendStatus(m: SwapMatch, round: number, io: SwapIO): void {
  const names = io.names();
  for (const p of [0, 1]) {
    const seat = m.players[p];
    if (seat && seat.swapData && (seat.swapV ?? 0) >= 2) io.send(p, statusPayload(m, p, round, names));
  }
}

function tryGo(m: SwapMatch, round: number, io: SwapIO): void {
  const a = m.players[0];
  const b = m.players[1];
  if (!a || !b || !a.swapData || !b.swapData || !a.swapReady || !b.swapReady) return;
  const rec: SwapRecord = {
    round,
    data: [a.swapData, b.swapData],
    hash: [a.swapHash ?? null, b.swapHash ?? null],
    ante: [a.swapAnte ?? null, b.swapAnte ?? null],
    at: Date.now(),
  };
  if (a.swapRun || b.swapRun) rec.run = [a.swapRun ?? null, b.swapRun ?? null];
  m.swapDone = round;
  m.swapLast = rec;
  (m.swapLog ??= []).push({ round, at: rec.at, bytes: [rec.data[0].length, rec.data[1].length], hash: rec.hash });
  for (const p of [0, 1]) {
    const seat = m.players[p];
    seat.swapData = null;
    seat.swapHash = null;
    seat.swapAnte = null;
    seat.swapReady = false;
    seat.swapFacts = null;
    seat.swapRun = null;
    io.setSnapshot(p, rec.data[p === 0 ? 1 : 0], rec.ante[p === 0 ? 1 : 0]);
  }
  io.log('INFO', `swap round=${round} done: P0 gets ${rec.hash[1]}, P1 gets ${rec.hash[0]}`);
  const names = io.names();
  for (const p of [0, 1]) io.send(p, runPayload(rec, p, names));
}

export function swapStatus(m: SwapMatch | null | undefined, pid: number): Record<string, unknown> | null {
  if (!m || !isSwap(m)) return null;
  const oid = pid === 0 ? 1 : 0;
  const me = m.players[pid] ?? {};
  const op = m.players[oid] ?? {};
  return {
    done: m.swapDone ?? 0,
    applied: me.swapApplied ?? 0,
    sent: !!me.swapData,
    oppSent: !!op.swapData,
    ante: m.swapLast ? (m.swapLast.ante[pid] ?? m.swapLast.ante[oid] ?? 0) : 0,
    ready: !!me.swapData && !!me.swapReady,
    oppReady: !!op.swapData && !!op.swapReady,
  };
}

export function holdsSnapshot(m: SwapMatch | null | undefined, pid: number): boolean {
  if (!m || !isSwap(m)) return false;
  const me = m.players[pid];
  if (!me) return false;
  return !!me.swapData || (me.swapApplied ?? 0) < (m.swapDone ?? 0);
}

export function handleSwapState(m: SwapMatch, pid: number, msg: Record<string, unknown>, io: SwapIO): void {
  if (!isSwap(m)) { io.send(pid, { type: 'error', reason: 'swap_state: not a swap match' }); return; }
  if (m.phase === 'finished') return;
  const round = msg.round as number;
  const done = m.swapDone ?? 0;
  const oid = pid === 0 ? 1 : 0;
  if (round <= done) {
    const last = m.swapLast;
    if (last && last.round === round) {
      io.log('INFO', `P${pid} swap_state round=${round} already done, resending`);
      io.send(pid, runPayload(last, pid, io.names()));
    }
    return;
  }
  if (round !== done + 1) {
    io.log('DEBUG', `P${pid} swap_state round=${round} ignored, done=${done}`);
    return;
  }
  const me = m.players[pid];
  const op = m.players[oid];
  if (!me || !op) return;
  me.swapData = msg.data as string;
  me.swapHash = typeof msg.hash === 'string' ? msg.hash : null;
  me.swapAnte = typeof msg.ante === 'number' ? msg.ante : null;
  me.swapV = typeof msg.v === 'number' ? msg.v : 0;
  me.swapReady = me.swapV < 2;
  me.swapFacts = msg.facts && typeof msg.facts === 'object' ? msg.facts as Record<string, unknown> : null;
  io.log('INFO', `P${pid} swap_state round=${round} bytes=${me.swapData.length} hash=${me.swapHash} v=${me.swapV}`);
  if (!op.swapData) io.send(oid, { type: 'swap_waiting', round, from: io.names()[pid] });
  sendStatus(m, round, io);
  tryGo(m, round, io);
}

export function handleSwapReady(m: SwapMatch, pid: number, msg: Record<string, unknown>, io: SwapIO): void {
  if (!isSwap(m) || m.phase === 'finished') return;
  const round = msg.round as number;
  if (round !== (m.swapDone ?? 0) + 1) return;
  const me = m.players[pid];
  if (!me || !me.swapData || me.swapReady) return;
  me.swapReady = true;
  io.log('INFO', `P${pid} swap_ready round=${round}`);
  sendStatus(m, round, io);
  tryGo(m, round, io);
}

export function handleSwapApplied(m: SwapMatch, pid: number, msg: Record<string, unknown>, io: SwapIO): void {
  if (!isSwap(m)) return;
  const round = msg.round as number;
  const me = m.players[pid];
  if (!me || round > (m.swapDone ?? 0)) return;
  if (round > (me.swapApplied ?? 0)) me.swapApplied = round;
  io.log('INFO', `P${pid} swap_applied round=${round}`);
}

export interface BotSwapIn { round: number; data: string; hash: string | null; ante: number | null; run: Record<string, unknown>; facts: Record<string, unknown> }

export function handleBotSwapState(m: SwapMatch, botPid: number, d: BotSwapIn, io: SwapIO): boolean {
  if (!isSwap(m) || m.phase === 'finished') return false;
  if (d.round !== (m.swapDone ?? 0) + 1) return false;
  const me = m.players[botPid];
  if (!me) return false;
  me.swapData = d.data;
  me.swapHash = d.hash;
  me.swapAnte = d.ante;
  me.swapV = 2;
  me.swapReady = true;
  me.swapFacts = d.facts;
  me.swapRun = d.run;
  io.log('INFO', `P${botPid} (bot) swap_state round=${d.round} owner=${String(d.facts.owner ?? '?')}`);
  sendStatus(m, d.round, io);
  tryGo(m, d.round, io);
  return true;
}

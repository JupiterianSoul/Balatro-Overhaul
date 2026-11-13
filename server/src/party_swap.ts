export interface PartySwapSeat {
  data: string | null;
  hash: string | null;
  ante: number | null;
  applied: number;
  ready?: boolean;
  v?: number;
}

export interface PartySwapRecord {
  round: number;
  at: number;
  got: Record<number, { from: number; data: string; hash: string | null; ante: number | null }>;
}

export interface PartySwapState {
  done: number;
  last: PartySwapRecord | null;
  seats: Record<number, PartySwapSeat>;
  log: { round: number; at: number; ring: number[] }[];
}

export interface PartySwapIO {
  members(): number[];
  name(pid: number): string;
  send(pid: number, payload: Record<string, unknown>): void;
  setSnapshot(pid: number, data: string, ante: number | null): void;
  log(level: string, msg: string): void;
}

export function partySwapOn(settings: Record<string, unknown> | undefined): boolean {
  const s = settings ?? {};
  return s.party_swap === true && (s.party_kind === undefined || s.party_kind === 'br');
}

export function newPartySwap(): PartySwapState {
  return { done: 0, last: null, seats: {}, log: [] };
}

function seat(st: PartySwapState, pid: number): PartySwapSeat {
  return (st.seats[pid] ??= { data: null, hash: null, ante: null, applied: 0 });
}

function runPayload(st: PartySwapState, pid: number, io: PartySwapIO): Record<string, unknown> | null {
  const rec = st.last;
  const g = rec?.got[pid];
  if (!rec || !g) return null;
  return {
    type: 'swap_run', party: true, round: rec.round, data: g.data, hash: g.hash, ante: g.ante,
    from: io.name(g.from), fromId: g.from, mine: st.seats[pid]?.hash ?? null, countdown: 3,
  };
}

export function ring(members: number[]): number[] {
  return [...members].sort((a, b) => a - b);
}

function waitingPayload(st: PartySwapState, round: number, ids: number[], io: PartySwapIO): Record<string, unknown> {
  const left = ids.filter(id => !st.seats[id]?.data);
  const unready = ids.filter(id => !!st.seats[id]?.data && !st.seats[id]?.ready);
  return { type: 'swap_waiting', party: true, round, waiting: left.map(id => io.name(id)), ready: ids.length - left.length, total: ids.length, from: left.length === 1 ? io.name(left[0]) : null,
    notReady: unready.map(id => io.name(id)), readyIds: ids.filter(id => !!st.seats[id]?.data && !!st.seats[id]?.ready), pressed: ids.length - left.length - unready.length };
}

export function trySwap(st: PartySwapState, io: PartySwapIO): boolean {
  const round = st.done + 1;
  const ids = ring(io.members());
  const sent = Object.entries(st.seats).filter(([, s]) => !!s.data).map(([id]) => Number(id));
  if (sent.length === 0 || ids.length === 0) return false;
  const left = ids.filter(id => !st.seats[id]?.data || !st.seats[id]?.ready);
  if (left.length > 0) {
    const msg = waitingPayload(st, round, ids, io);
    for (const id of ids) if (st.seats[id]?.data) io.send(id, msg);
    return false;
  }
  const rec: PartySwapRecord = { round, at: Date.now(), got: {} };
  const k = ids.length;
  for (let i = 0; i < k; i++) {
    const to = ids[i];
    const from = ids[(i - 1 + k) % k];
    const src = st.seats[from];
    rec.got[to] = { from, data: src.data as string, hash: src.hash, ante: src.ante };
  }
  st.done = round;
  st.last = rec;
  st.log.push({ round, at: rec.at, ring: ids });
  for (const id of ids) io.setSnapshot(id, rec.got[id].data, rec.got[id].ante);
  const out: Record<number, Record<string, unknown> | null> = {};
  for (const id of ids) out[id] = runPayload(st, id, io);
  for (const s of Object.values(st.seats)) { s.data = null; s.ante = null; s.ready = false; }
  io.log('INFO', `party swap round=${round} done: ` + ids.map(id => `P${id} gets P${rec.got[id].from}`).join(', '));
  for (const id of ids) {
    const msg = out[id];
    if (msg) io.send(id, msg);
  }
  return true;
}

export function handlePartySwapState(st: PartySwapState, pid: number, msg: Record<string, unknown>, io: PartySwapIO): void {
  const round = msg.round as number;
  if (round <= st.done) {
    if (st.last && st.last.round === round && st.last.got[pid]) {
      io.log('INFO', `P${pid} party swap_state round=${round} already done, resending`);
      const out = runPayload(st, pid, io);
      if (out) io.send(pid, out);
    }
    return;
  }
  if (round !== st.done + 1) {
    io.log('DEBUG', `P${pid} party swap_state round=${round} ignored, done=${st.done}`);
    return;
  }
  if (!io.members().includes(pid)) return;
  const me = seat(st, pid);
  me.data = msg.data as string;
  me.hash = typeof msg.hash === 'string' ? msg.hash : null;
  me.ante = typeof msg.ante === 'number' ? msg.ante : null;
  me.v = typeof msg.v === 'number' ? msg.v : 0;
  me.ready = me.v < 2;
  io.log('INFO', `P${pid} party swap_state round=${round} bytes=${me.data.length} hash=${me.hash} v=${me.v}`);
  trySwap(st, io);
}

export function handlePartySwapReady(st: PartySwapState, pid: number, msg: Record<string, unknown>, io: PartySwapIO): void {
  const round = msg.round as number;
  if (round !== st.done + 1) return;
  const me = st.seats[pid];
  if (!me || !me.data || me.ready) return;
  me.ready = true;
  io.log('INFO', `P${pid} party swap_ready round=${round}`);
  trySwap(st, io);
}

export function handlePartySwapApplied(st: PartySwapState, pid: number, msg: Record<string, unknown>, io: PartySwapIO): void {
  const round = msg.round as number;
  if (round > st.done) return;
  const me = seat(st, pid);
  if (round > me.applied) me.applied = round;
  io.log('INFO', `P${pid} party swap_applied round=${round}`);
}

export function partyHoldsSnapshot(st: PartySwapState | undefined, pid: number): boolean {
  if (!st) return false;
  const me = st.seats[pid];
  if (!me) return false;
  if (me.data) return true;
  return !!st.last?.got[pid] && me.applied < st.last.round;
}

export function partySwapStatus(st: PartySwapState | undefined, pid: number): Record<string, unknown> | null {
  if (!st) return null;
  const me = st.seats[pid];
  const got = st.last?.got[pid];
  return {
    done: st.done,
    applied: got ? (me?.applied ?? 0) : st.done,
    sent: !!me?.data,
    ante: got?.ante ?? 0,
  };
}

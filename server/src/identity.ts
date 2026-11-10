import { rankOf, ranked } from './ranked';

export type WhoLevel = 'easy' | 'medium' | 'hard';
export interface RankTag { rank: number; tier: number; name: string }
export interface Who { pid?: number; name: string; is_bot: boolean; bot_level?: WhoLevel; rank?: RankTag }
export type WhoFields = Omit<Who, 'pid' | 'name'>;

const LEVELS = new Set<string>(['easy', 'medium', 'hard']);

export function rankTag(rp: unknown): RankTag | undefined {
  if (typeof rp !== 'number' || !Number.isFinite(rp)) return undefined;
  const r = rankOf(rp);
  return { rank: r.rank, tier: r.tier, name: r.name };
}

function rpOf(data: Record<string, unknown>): unknown {
  if (typeof data.rp === 'number') return data.rp;
  if (typeof data.pkey !== 'string') return undefined;
  const st = ranked.cached(data.pkey);
  if (!st || !(st.row.matches > 0)) return undefined;
  data.rp = st.row.rp;
  return data.rp;
}

export function noteRank(ws: unknown, rp: unknown, played = true): void {
  const data = (ws as { data?: Record<string, unknown> } | null | undefined)?.data;
  if (!data || data.bot === true || !played || typeof rp !== 'number' || !Number.isFinite(rp)) return;
  data.rp = rp;
}

export function noteRankResult(ws: unknown, payload: unknown): void {
  const p = payload as { type?: unknown; after?: { rp?: unknown } } | null | undefined;
  if (p?.type === 'ranked_result') noteRank(ws, p.after?.rp);
}

export function whoOf(ws: unknown, pid?: number, fallbackName = ''): Who {
  const s = ws as { data?: Record<string, unknown>; level?: unknown } | null | undefined;
  const data = s?.data ?? {};
  const isBot = data.bot === true;
  const who: Who = { name: typeof data.name === 'string' && data.name !== '' ? data.name : fallbackName, is_bot: isBot };
  if (pid !== undefined) who.pid = pid;
  if (isBot) {
    if (typeof s?.level === 'string' && LEVELS.has(s.level)) who.bot_level = s.level as WhoLevel;
  } else {
    const rank = rankTag(rpOf(data));
    if (rank) who.rank = rank;
  }
  return who;
}

const seen = new WeakMap<object, Map<number, Who>>();

export function whoAt(owner: object, pid: number, ws: unknown, name: string): Who {
  let m = seen.get(owner);
  if (!m) { m = new Map(); seen.set(owner, m); }
  if (ws) {
    const w = whoOf(ws, pid, name);
    if (name) w.name = name;
    m.set(pid, w);
    return w;
  }
  const prev = m.get(pid);
  return prev ? { ...prev, pid, name: name || prev.name } : { pid, name, is_bot: false };
}

export function whoFields(w: Who): WhoFields {
  const out: WhoFields = { is_bot: w.is_bot };
  if (w.bot_level) out.bot_level = w.bot_level;
  if (w.rank) out.rank = w.rank;
  return out;
}

export function seatFields(owner: object, pid: number, seat: { ws: unknown; name: string } | null | undefined): WhoFields {
  return whoFields(whoAt(owner, pid, seat?.ws ?? null, seat?.name ?? ''));
}

export function seatRoster(owner: object, seats: ({ ws: unknown; name: string } | null | undefined)[]): Who[] {
  const out: Who[] = [];
  seats.forEach((s, i) => { if (s) out.push(whoAt(owner, i, s.ws, s.name)); });
  return out;
}

export function roomRoster(room: { sockets: unknown[]; playerNames: string[]; holdDeadline: (number | null)[] }, all = false): Who[] {
  const out: Who[] = [];
  for (let i = 0; i < 2; i++) {
    const ws = room.sockets[i] ?? null;
    const name = room.playerNames[i] ?? '';
    if (!ws && room.holdDeadline[i] == null && !(all && name)) continue;
    out.push(whoAt(room, i, ws, name));
  }
  return out;
}

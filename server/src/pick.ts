export const pickTiming = { ms: 120_000 };
export const RANDOM_PICK = 'random_pick';
export const PICK_MAX_JOKERS = 5;

type Msg = Record<string, unknown>;

export interface Pick {
  id: string;
  pids: number[];
  pool: string[];
  deck: boolean;
  jokers: number;
  ready: Record<number, boolean>;
  decks: Record<number, string | null>;
  picks: Record<number, string[]>;
  rolled: Record<number, boolean>;
  rematch: boolean;
  devs?: number[];
  deadline: number;
  timer: ReturnType<typeof setTimeout> | null;
  done: boolean;
}

export interface PickOpts {
  rematch?: boolean;
  botJokers?: string[];
  rnd?: () => number;
  defaultDeck?: string | null;
  prev?: { decks: Record<number, string | null>; picks: Record<number, string[]> } | null;
  onDone?: (p: Pick) => void;
}

export interface PickRoom {
  code: string;
  ranked?: boolean;
  settings: Record<string, unknown>;
  pick?: Pick | null;
}

export interface PickDeps {
  sendTo: (pid: number, msg: Msg) => void;
  isBot: (pid: number) => boolean;
  connected: (pid: number) => boolean;
  isDev?: (pid: number) => boolean;
  log: (level: string, tag: string, msg: string) => void;
}

export function pickJokers(settings: Record<string, unknown>): number {
  const n = Math.floor(Number(settings.joker_picks) || 0);
  const rules = (settings.rules && typeof settings.rules === 'object' ? settings.rules : {}) as Record<string, unknown>;
  const slots = Number.isFinite(Number(rules.joker_slots)) && rules.joker_slots !== undefined ? Number(rules.joker_slots) : 5;
  const shared = (Array.isArray(rules.starting_jokers) ? rules.starting_jokers.length : 0) + (Number(rules.random_jokers) || 0);
  return Math.max(0, Math.min(PICK_MAX_JOKERS, n, Math.floor(slots - shared)));
}

export function pickDeck(settings: Record<string, unknown>): boolean {
  return settings.different_decks === true;
}

export function wantsPick(room: PickRoom): boolean {
  if (room.ranked) return false;
  return pickDeck(room.settings) || pickJokers(room.settings) > 0;
}

const KEY_RE = /^[A-Za-z0-9_]{1,48}$/;

export const SIM_DECKS = ['b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black', 'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned',
  'b_checkered', 'b_zodiac', 'b_painted', 'b_anaglyph', 'b_plasma', 'b_erratic'];

export function deckKey(name: string): string {
  return name.startsWith('b_') ? name : 'b_' + name.toLowerCase().replace(/ deck$/, '').replace(/[^a-z]/g, '');
}

export function cleanJokerList(list: unknown): string[] {
  if (!Array.isArray(list)) return [];
  const out: string[] = [];
  for (const k of list) {
    if (typeof k === 'string' && KEY_RE.test(k) && !out.includes(k)) out.push(k);
    if (out.length >= 400) break;
  }
  return out;
}

export function botPick(p: Pick, pid: number, botJokers: string[], rnd: () => number = Math.random): void {
  if (p.deck) {
    const real = p.pool.filter(d => d !== RANDOM_PICK);
    const known = real.filter(d => SIM_DECKS.includes(deckKey(d)));
    const from = known.length > 0 ? known : real;
    if (from.length > 0) p.decks[pid] = from[Math.floor(rnd() * from.length)];
  }
  const left = cleanJokerList(botJokers);
  const out: string[] = [];
  while (out.length < p.jokers && left.length > 0) out.push(left.splice(Math.floor(rnd() * left.length), 1)[0]);
  p.picks[pid] = out;
}

export function cleanPool(pool: unknown): string[] {
  if (!Array.isArray(pool)) return [];
  const out: string[] = [];
  for (const d of pool) {
    if (typeof d === 'string' && d.length > 0 && d.length <= 40 && !out.includes(d)) out.push(d);
    if (out.length >= 80) break;
  }
  return out;
}

export function newPick(room: PickRoom, pids: number[], pool: string[], opts: PickOpts = {}): Pick {
  const deck = pickDeck(room.settings);
  const real = pool.filter(d => d !== RANDOM_PICK);
  const lobby = typeof room.settings.deck === 'string' ? room.settings.deck as string : null;
  const fallback = opts.defaultDeck && pool.includes(opts.defaultDeck) ? opts.defaultDeck
    : lobby && pool.includes(lobby) ? lobby : real[0] ?? null;
  const p: Pick = {
    id: crypto.randomUUID().slice(0, 12), pids: [...pids], pool: deck ? pool : [], deck: deck && real.length > 0,
    jokers: pickJokers(room.settings), ready: {}, decks: {}, picks: {}, rolled: {}, rematch: opts.rematch === true,
    deadline: 0, timer: null, done: false,
  };
  for (const pid of pids) {
    p.ready[pid] = false;
    const before = opts.prev?.decks?.[pid];
    p.decks[pid] = p.deck ? (before && pool.includes(before) ? before : fallback) : null;
    const old = opts.prev?.picks?.[pid];
    p.picks[pid] = Array.isArray(old) ? old.slice(0, p.jokers) : [];
  }
  return p;
}

export function resolveRandom(p: Pick, rnd: () => number = Math.random): void {
  if (!p.deck) return;
  const real = p.pool.filter(d => d !== RANDOM_PICK);
  if (real.length === 0) return;
  for (const pid of p.pids) {
    if (p.decks[pid] === RANDOM_PICK) {
      p.decks[pid] = real[Math.floor(rnd() * real.length)];
      p.rolled[pid] = true;
    }
  }
}

export function pickSet(p: Pick, pid: number, msg: Msg): string | null {
  if (p.done) return 'done';
  if (!p.pids.includes(pid)) return 'not_in_pick';
  if (msg.deck !== undefined) {
    if (!p.deck) return 'no_deck_pick';
    if (typeof msg.deck !== 'string' || !p.pool.includes(msg.deck)) return 'bad_deck';
  }
  if (msg.jokers !== undefined) {
    if (!Array.isArray(msg.jokers)) return 'bad_jokers';
    if (msg.jokers.length > p.jokers) return 'too_many_jokers';
    for (const k of msg.jokers) if (typeof k !== 'string' || !KEY_RE.test(k)) return 'bad_jokers';
    if (new Set(msg.jokers).size !== msg.jokers.length) return 'bad_jokers';
  }
  if (msg.ready !== undefined && typeof msg.ready !== 'boolean') return 'bad_ready';
  if (msg.deck !== undefined) p.decks[pid] = msg.deck as string;
  if (msg.jokers !== undefined) p.picks[pid] = [...(msg.jokers as string[])];
  if (msg.ready !== undefined) p.ready[pid] = msg.ready as boolean;
  return null;
}

export interface PickSeat {
  isBot: (pid: number) => boolean;
  connected: (pid: number) => boolean;
}

export function pickAllReady(p: Pick, deps: PickSeat): boolean {
  for (const pid of p.pids) {
    if (p.ready[pid] || deps.isBot(pid) || !deps.connected(pid)) continue;
    return false;
  }
  return true;
}

export function pickView(p: Pick, pid: number, now = Date.now()): Msg {
  const ready: Record<string, boolean> = {};
  for (const q of p.pids) ready[String(q)] = p.ready[q] === true;
  return {
    type: 'pick_state', pick_id: p.id, pids: p.pids, you: pid, ready, deck: p.deck, pool: p.pool, jokers: p.jokers, rematch: p.rematch,
    my_deck: p.decks[pid] ?? null, my_jokers: p.picks[pid] ?? [], ...(p.devs ? { devs: p.devs } : {}),
    seconds: Math.max(0, Math.ceil((p.deadline - now) / 1000)), total_seconds: Math.round(pickTiming.ms / 1000),
  };
}

export function pickResult(p: Pick): Msg {
  const decks: Record<string, string | null> = {};
  const jokers: Record<string, string[]> = {};
  const rolled: Record<string, boolean> = {};
  for (const q of p.pids) { decks[String(q)] = p.decks[q] ?? null; jokers[String(q)] = p.picks[q] ?? []; rolled[String(q)] = p.rolled[q] === true; }
  return { type: 'pick_done', pick_id: p.id, decks, jokers, rolled, rematch: p.rematch };
}

function clear(p: Pick): void { if (p.timer) { clearTimeout(p.timer); p.timer = null; } }

function broadcast(room: PickRoom, deps: PickDeps): void {
  const p = room.pick;
  if (!p) return;
  for (const pid of p.pids) deps.sendTo(pid, p.done ? pickResult(p) : pickView(p, pid));
}

const DONE_HOOKS = new WeakMap<Pick, (p: Pick) => void>();

function finish(room: PickRoom, deps: PickDeps, why: string): void {
  const p = room.pick;
  if (!p || p.done) return;
  clear(p);
  resolveRandom(p);
  p.done = true;
  const parts = p.pids.map(q => `${q}:${p.decks[q] ?? '-'}/${(p.picks[q] ?? []).join('+') || '-'}`);
  deps.log('INFO', 'PICK', `${room.code} done (${why})${p.rematch ? ' rematch' : ''} ${parts.join(' ')}`);
  broadcast(room, deps);
  const hook = DONE_HOOKS.get(p);
  if (hook) { DONE_HOOKS.delete(p); hook(p); }
}

export function startPick(room: PickRoom, deps: PickDeps, pids: number[], pool: unknown, opts: PickOpts = {}): Pick {
  if (room.pick) clear(room.pick);
  const p = newPick(room, pids, cleanPool(pool), opts);
  room.pick = p;
  if (deps.isDev) { const devs = pids.filter(q => deps.isDev!(q)); if (devs.length) p.devs = devs; }
  if (opts.onDone) DONE_HOOKS.set(p, opts.onDone);
  for (const pid of pids) {
    if (!deps.isBot(pid)) continue;
    botPick(p, pid, opts.botJokers ?? [], opts.rnd);
    p.ready[pid] = true;
  }
  p.deadline = Date.now() + pickTiming.ms;
  p.timer = setTimeout(() => {
    p.timer = null;
    if (room.pick !== p || p.done) return;
    finish(room, deps, 'timeout');
  }, pickTiming.ms);
  deps.log('INFO', 'PICK', `${room.code} started${p.rematch ? ' rematch' : ''} deck=${p.deck} jokers=${p.jokers} pool=${p.pool.length}`);
  broadcast(room, deps);
  if (pickAllReady(p, deps)) finish(room, deps, 'ready');
  return p;
}

export function rearmPick(room: PickRoom, deps: PickDeps, left: number | null, onDone?: (p: Pick) => void): void {
  const p = room.pick;
  if (!p) return;
  clear(p);
  if (onDone) DONE_HOOKS.set(p, onDone);
  if (p.done) return;
  const ms = Math.max(0, left ?? pickTiming.ms);
  p.deadline = Date.now() + ms;
  p.timer = setTimeout(() => {
    p.timer = null;
    if (room.pick !== p || p.done) return;
    finish(room, deps, 'timeout');
  }, ms);
}

export function pickAction(room: PickRoom, pid: number, msg: Msg, deps: PickDeps): string | null {
  const p = room.pick;
  if (!p) return 'no_pick';
  if (p.done) { deps.sendTo(pid, pickResult(p)); return 'done'; }
  const e = pickSet(p, pid, msg);
  if (e) { deps.sendTo(pid, { type: 'pick_error', reason: e, pick_id: p.id }); deps.sendTo(pid, pickView(p, pid)); return e; }
  if (pickAllReady(p, deps)) finish(room, deps, 'ready');
  else broadcast(room, deps);
  return null;
}

export function resendPick(room: PickRoom, pid: number, deps: PickDeps): void {
  const p = room.pick;
  if (!p) return;
  deps.sendTo(pid, p.done ? pickResult(p) : pickView(p, pid));
}

export function cancelPick(room: PickRoom): boolean {
  const p = room.pick;
  if (!p) return false;
  clear(p);
  room.pick = null;
  return !p.done;
}

export function pickMyDeck(room: PickRoom, pid: number): string | null {
  const p = room.pick;
  if (!p || !p.done || !p.deck) return null;
  return p.decks[pid] ?? null;
}

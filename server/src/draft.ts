export const DRAFT_DECKS = [
  'Red Deck', 'Blue Deck', 'Yellow Deck', 'Green Deck', 'Black Deck', 'Magic Deck', 'Nebula Deck', 'Ghost Deck',
  'Abandoned Deck', 'Checkered Deck', 'Zodiac Deck', 'Painted Deck', 'Anaglyph Deck', 'Plasma Deck', 'Erratic Deck',
  'Lilac Deck', 'Seer Deck', 'Tangerine Deck', 'Cobalt Deck', 'Gemini Deck',
];

export const draftTiming = { turnMs: 30_000, botMs: 900 };
export const DRAFT_BANS_EACH = 2;

export type DraftPhase = 'ban' | 'done';

export interface Draft {
  id: string;
  pool: string[];
  bans: { pid: number; deck: string }[];
  picks: Record<number, string>;
  order: number[];
  pids: number[];
  phase: DraftPhase;
  turn: number | null;
  deadline: number;
  random: Record<number, number>;
  timer: ReturnType<typeof setTimeout> | null;
  deck: string | null;
}

type Msg = Record<string, unknown>;

export interface DraftRoom {
  code: string;
  ranked?: boolean;
  rankedSeed?: string | null;
  settings: Record<string, unknown>;
  draft?: Draft | null;
}

export interface DraftDeps {
  sendTo: (pid: number, msg: Msg) => void;
  isBot: (pid: number) => boolean;
  connected: (pid: number) => boolean;
  log: (level: string, tag: string, msg: string) => void;
  onDone?: (room: DraftRoom, d: Draft) => void;
}

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

export function seededRandom(seed: string): () => number {
  let a = hash(seed) || 1;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function draftPool(seed: string, size = 7, decks: string[] = DRAFT_DECKS): string[] {
  const rnd = seededRandom('draft:' + seed);
  const list = [...decks];
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [list[i], list[j]] = [list[j], list[i]];
  }
  return list.slice(0, Math.max(3, Math.min(size, list.length)));
}

export function newDraft(seed: string, pids: number[] = [0, 1], bansEach = DRAFT_BANS_EACH, size = pids.length * bansEach + 1): Draft {
  const first = pids.length > 0 ? Math.floor(seededRandom('order:' + seed)() * pids.length) : 0;
  const turns = [...pids.slice(first), ...pids.slice(0, first)];
  const order: number[] = [];
  for (let i = 0; i < bansEach; i++) for (const pid of turns) order.push(pid);
  const d: Draft = {
    id: crypto.randomUUID().slice(0, 12), pool: draftPool(seed, size), bans: [], picks: {}, order, pids: [...pids],
    phase: 'ban', turn: order.length > 0 ? order[0] : null, deadline: 0, random: {}, timer: null, deck: null,
  };
  if (order.length === 0) finishDraft(d, seed);
  return d;
}

function finishDraft(d: Draft, seed: string): void {
  const left = remaining(d);
  const deck = left.length === 1 ? left[0] : left[Math.floor(seededRandom('final:' + seed + d.id)() * left.length)];
  d.deck = deck ?? null;
  for (const pid of d.pids) if (d.deck) d.picks[pid] = d.deck;
  d.phase = 'done';
  d.turn = null;
}

export function remaining(d: Draft): string[] {
  const banned = new Set(d.bans.map(b => b.deck));
  return d.pool.filter(x => !banned.has(x));
}

export function draftAct(d: Draft, pid: number, action: unknown, deck: unknown): string | null {
  if (d.phase === 'done') return 'done';
  if (typeof deck !== 'string') return 'bad_deck';
  if (!remaining(d).includes(deck)) return 'not_in_pool';
  if (action !== 'ban') return 'wrong_phase';
  if (!d.pids.includes(pid)) return 'not_in_draft';
  if (d.turn !== pid) return 'not_your_turn';
  d.bans.push({ pid, deck });
  const next = d.order[d.bans.length];
  if (next === undefined) finishDraft(d, d.id);
  else d.turn = next;
  return null;
}

export function draftAuto(d: Draft, rnd: () => number = Math.random, only?: number): number[] {
  if (d.phase !== 'ban' || d.turn === null || (only !== undefined && only !== d.turn)) return [];
  const pid = d.turn;
  const left = remaining(d);
  if (draftAct(d, pid, 'ban', left[Math.floor(rnd() * left.length)]) !== null) return [];
  d.random[pid] = (d.random[pid] ?? 0) + 1;
  return [pid];
}

export function draftView(d: Draft, pid: number, now = Date.now()): Msg {
  const picks: Record<string, string | null> = {};
  const picked: Record<string, boolean> = {};
  for (const p of d.pids) {
    picked[String(p)] = d.phase === 'done';
    picks[String(p)] = d.phase === 'done' ? d.deck : null;
  }
  return {
    type: 'draft_state', draft_id: d.id, phase: d.phase, pool: d.pool, left: remaining(d), bans: d.bans, picks, picked,
    turn: d.turn, you: pid, seconds: Math.max(0, Math.ceil((d.deadline - now) / 1000)), turn_seconds: Math.round(draftTiming.turnMs / 1000),
    bans_each: d.order.length / Math.max(1, d.pids.length), deck: d.phase === 'done' ? d.deck : null,
  };
}

export function draftDecks(room: { draft?: Draft | null }): Record<string, unknown> {
  const d = room.draft;
  if (!d || d.phase !== 'done' || !d.deck) return {};
  return { deck: d.deck, different_decks: false };
}

export function draftMyDeck(room: { draft?: Draft | null }, _pid: number): string | null {
  const d = room.draft;
  if (!d || d.phase !== 'done') return null;
  return d.deck;
}

export function wantsDraft(room: DraftRoom): boolean {
  return room.ranked === true || room.settings.deck_draft === true;
}

function broadcast(room: DraftRoom, deps: DraftDeps): void {
  const d = room.draft;
  if (!d) return;
  for (const pid of d.pids) deps.sendTo(pid, draftView(d, pid));
  if (d.phase === 'done' && d.deck) {
    const decks: Record<string, string> = {};
    for (const p of d.pids) decks[String(p)] = d.deck;
    for (const pid of d.pids) {
      deps.sendTo(pid, { type: 'draft_done', draft_id: d.id, decks, my_deck: d.deck, ...draftDecks(room), random: d.random[pid] ?? 0 });
    }
  }
}

function clear(d: Draft): void { if (d.timer) { clearTimeout(d.timer); d.timer = null; } }

function arm(room: DraftRoom, deps: DraftDeps): void {
  const d = room.draft;
  if (!d) return;
  clear(d);
  if (d.phase === 'done') { deps.onDone?.(room, d); return; }
  d.deadline = Date.now() + draftTiming.turnMs;
  const bot = d.turn !== null && deps.isBot(d.turn) ? d.turn : null;
  const wait = bot !== null ? Math.min(draftTiming.botMs, draftTiming.turnMs) : draftTiming.turnMs;
  d.timer = setTimeout(() => {
    d.timer = null;
    if (room.draft !== d || d.phase === 'done') return;
    draftAuto(d, Math.random, bot ?? undefined);
    deps.log('INFO', 'DRAFT', `${room.code} ${bot !== null ? 'bot' : 'timeout'} turn, phase=${d.phase}`);
    broadcast(room, deps);
    arm(room, deps);
  }, wait);
}

export function startDraft(room: DraftRoom, deps: DraftDeps, seed?: string | null): Draft {
  if (room.draft) clear(room.draft);
  const d = newDraft(seed || room.rankedSeed || crypto.randomUUID());
  room.draft = d;
  deps.log('INFO', 'DRAFT', `${room.code} started pool=${d.pool.join(',')}`);
  arm(room, deps);
  broadcast(room, deps);
  return d;
}

export function draftAction(room: DraftRoom, pid: number, msg: Msg, deps: DraftDeps): string | null {
  const d = room.draft;
  if (!d) return 'no_draft';
  const e = draftAct(d, pid, msg.action, msg.deck);
  if (e) { deps.sendTo(pid, { type: 'draft_error', reason: e, draft_id: d.id }); deps.sendTo(pid, draftView(d, pid)); return e; }
  arm(room, deps);
  broadcast(room, deps);
  return null;
}

export function cancelDraft(room: DraftRoom, drop = false): void {
  const d = room.draft;
  if (!d) return;
  clear(d);
  if (drop || d.phase !== 'done') room.draft = null;
}

export function resendDraft(room: DraftRoom, pid: number, deps: DraftDeps): void {
  const d = room.draft;
  if (!d) return;
  deps.sendTo(pid, draftView(d, pid));
}

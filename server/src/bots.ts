import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import path from 'node:path';
import { memorySample, rssOfPid } from './memory';
import { deckKey, RANDOM_PICK } from './pick';
import { initBotSocial, onHumanEmote, onSituation, onMatchEnd, botSocial } from './bot_social';

type Msg = Record<string, unknown>;

export const BOT_LEVELS = ['easy', 'medium', 'hard'] as const;
export type BotLevel = typeof BOT_LEVELS[number];
export const BOT_NAMES = ['Bob', 'Lou', 'Mina', 'Otto', 'Ivy', 'Max', 'Zoe', 'Hugo', 'Nina', 'Theo', 'Lena', 'Iris',
  'Axel', 'Rosa', 'Finn', 'Luna', 'Omar', 'Pia', 'Remy', 'Tess', 'Gus', 'Ada', 'Leo', 'Mia'];
const PARTY_PVP_KEYS: Record<string, string> = { raid: 'bl_mp_raid', br: 'bl_mp_royale', teams: 'bl_mp_clash' };
export const LEVEL_COST: Record<BotLevel, number> = { easy: 1, medium: 4, hard: 9 };

export interface BotDeps {
  dispatch: (ws: BotSocket, msg: Msg) => void;
  cleanup: (ws: BotSocket) => void;
  decode: (raw: string) => string | null;
  publish: (topic: string, raw: string) => void;
  isPvp: (ws: BotSocket, ante: number, blind: string) => boolean;
  race?: (ws: BotSocket) => boolean;
  swapOn?: (ws: BotSocket) => boolean;
  humansWith: (ws: BotSocket) => number;
  leave: (ws: BotSocket) => void;
  log: (level: string, tag: string, msg: string) => void;
  chat?: (ws: BotSocket, text: string) => number;
  refuse?: (ws: BotSocket, reason: string) => void;
  debug?: boolean;
}

let D!: BotDeps;
export const botTiming = { beatMs: 350, sweepMs: 5000, waitMs: 15 * 60 * 1000, silentMs: 60 * 1000 };
export const botPace = {
  scale: process.env.BOT_PACE !== undefined && Number.isFinite(Number(process.env.BOT_PACE)) ? Math.max(0, Number(process.env.BOT_PACE)) : 1,
  hand: [3000, 6000] as [number, number], discard: [1800, 3600] as [number, number],
  cash: [2000, 3800] as [number, number], act: [2000, 4500] as [number, number], pick: [1600, 3600] as [number, number],
  select: [1500, 3200] as [number, number], shop: [14000, 24000] as [number, number],
  linger: [2500, 7000] as [number, number], follow: 60000,
};

export function actRange(type: string, from?: string): [number, number] {
  if (type === 'cash_out') return botPace.cash;
  if (type === 'open' || type === 'pick' || from === 'pack') return botPace.pick;
  if (from === 'blind_select' || type === 'select' || type === 'reroll_boss') return botPace.select;
  return botPace.act;
}

export interface ShopAct { type: string; key?: string; cost: number; t: number; spend?: boolean }

export function shopLine(acts: ShopAct[], money: unknown, held: unknown): string {
  const parts = acts.map((a) => {
    const cost = a.cost > 0 ? ` -$${a.cost}` : a.cost < 0 ? ` +$${-a.cost}` : '';
    return `${a.type}${a.key ? ' ' + a.key : ''}${cost}${a.spend ? ' (spend)' : ''} @${(a.t / 1000).toFixed(1)}s`;
  });
  const jokers = Array.isArray(held) ? held.map(String) : [];
  return `${parts.join(', ')} | $${Number(money) || 0}, ${jokers.length} jokers${jokers.length ? ': ' + jokers.join(' ') : ''}`;
}

export function paceMs(range: [number, number], n = 1): number {
  if (botPace.scale <= 0 || n <= 0) return 0;
  let t = 0;
  for (let i = 0; i < n; i++) t += range[0] + Math.random() * (range[1] - range[0]);
  return Math.round(t * botPace.scale);
}
const topics = new Map<string, Set<BotSocket>>();
const allBots = new Set<BotSocket>();
initBotSocial(() => allBots);

export function initBots(deps: BotDeps): void { D = deps; }

export function deliverToBots(topic: string, raw: string, except?: unknown): void {
  const set = topics.get(topic);
  if (!set) return;
  for (const b of [...set]) if (b !== except) b.send(raw);
}

export function isBot(ws: unknown): ws is BotSocket { return ws instanceof BotSocket; }

export function listBots(): BotSocket[] { return [...allBots]; }

interface Pending { resolve: (r: Msg) => void; sent: number; cmd: string; bot: string }
export interface WorkerTiming { ms: number; wait: number; queued: number; cpu: number }
export const workerStats = { calls: 0, workMs: 0, waitMs: 0, cpuMs: 0, maxMs: 0, maxWait: 0 };
const timings = new WeakMap<Msg, WorkerTiming>();
export function timingOf(r: Msg): WorkerTiming | undefined { return timings.get(r); }

class Worker {
  proc: ChildProcessWithoutNullStreams | null = null;
  buf = '';
  next = 1;
  pending = new Map<number, Pending>();
  failed = false;
  freeAt = 0;
  bots = 0;
  load = 0;
  calls = 0;
  cpuMs = 0;
  workMs = 0;
  maxWait = 0;
  draining = false;
  watch: ReturnType<typeof setTimeout> | null = null;
  constructor(public index = 0) {}

  start(): boolean {
    if (this.proc) return true;
    if (this.failed) return false;
    const root = process.env.BOT_LUA_ROOT ?? path.resolve(import.meta.dir, '../../assets');
    const bin = process.env.BOT_LUAJIT ?? 'luajit';
    try {
      const custom = process.env.BOT_WORKER?.split(' ').filter(Boolean);
      const [cmd, ...args] = custom && custom.length ? custom : [bin, path.join(root, 'bot/mp/worker.lua'), root];
      const p = spawn(cmd, args, { cwd: custom ? process.cwd() : root, stdio: ['pipe', 'pipe', 'pipe'] });
      p.on('error', (e) => { D.log('ERROR', 'BOT', `worker failed: ${e.message}`); this.failed = true; this.stop(); });
      p.on('exit', (code) => {
        D.log('WARN', 'BOT', `worker exited ${code}`);
        if (this.proc !== p) return;
        this.proc = null;
        this.flush();
      });
      p.stdin.on('error', (e) => {
        D.log('WARN', 'BOT', `worker ${this.index} pipe: ${e.message}`);
        if (this.proc === p) this.stop();
      });
      p.stdout.setEncoding('utf8');
      p.stdout.on('data', (chunk: string) => this.read(chunk));
      p.stderr.on('data', (chunk: Buffer) => D.log('WARN', 'BOT', `worker: ${chunk.toString().slice(0, 300)}`));
      this.proc = p;
      this.buf = '';
      return true;
    } catch (e) {
      D.log('ERROR', 'BOT', `worker spawn: ${(e as Error).message}`);
      this.failed = true;
      return false;
    }
  }

  read(chunk: string): void {
    this.buf += chunk;
    let i: number;
    while ((i = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, i);
      this.buf = this.buf.slice(i + 1);
      let r: Msg;
      try { r = JSON.parse(line) as Msg; } catch { continue; }
      const p = this.pending.get(r.id as number);
      if (p) {
        this.pending.delete(r.id as number);
        const now = performance.now();
        const begin = Math.max(p.sent, this.freeAt);
        this.freeAt = now;
        const t = { ms: Math.round(now - begin), wait: Math.round(begin - p.sent), queued: this.pending.size, cpu: Number(r.cpu_ms) || 0 };
        this.calls++; this.cpuMs += t.cpu; this.workMs += t.ms;
        if (t.wait > this.maxWait) this.maxWait = t.wait;
        workerStats.calls++; workerStats.workMs += t.ms; workerStats.waitMs += t.wait; workerStats.cpuMs += t.cpu;
        if (t.ms > workerStats.maxMs) workerStats.maxMs = t.ms;
        if (t.wait > workerStats.maxWait) workerStats.maxWait = t.wait;
        timings.set(r, t);
        this.guard();
        p.resolve(r);
      }
    }
  }

  guard(): void {
    if (this.watch) { clearTimeout(this.watch); this.watch = null; }
    if (this.pending.size === 0 || botTiming.silentMs <= 0) return;
    this.watch = setTimeout(() => {
      this.watch = null;
      if (this.pending.size === 0) return;
      const first = this.pending.values().next().value;
      const what = first ? `, oldest ${first.cmd} for ${first.bot} sent ${Math.round(performance.now() - first.sent)}ms ago` : '';
      D.log('ERROR', 'BOT', `worker ${this.index} silent for ${botTiming.silentMs}ms with ${this.pending.size} calls waiting${what}, restarting it`);
      this.stop();
    }, botTiming.silentMs);
  }

  flush(): void {
    const gone = [...this.pending.values()];
    this.pending.clear();
    this.guard();
    for (const p of gone) p.resolve({ ok: false, err: 'worker gone' });
  }

  stop(): void {
    try { this.proc?.kill(); } catch {  }
    this.proc = null;
    this.flush();
    this.freeAt = 0;
  }

  call(cmd: string, args: Msg): Promise<Msg> {
    if (!this.start() || !this.proc) return Promise.resolve({ ok: false, err: 'no worker' });
    const id = this.next++;
    return new Promise((resolve) => {
      this.pending.set(id, { resolve, sent: performance.now(), cmd, bot: String(args.bot ?? '') });
      if (!this.watch) this.guard();
      try { this.proc!.stdin.write(JSON.stringify({ ...args, cmd, id }) + '\n'); } catch { this.stop(); }
    });
  }
}

export function maxWorkers(env = process.env.BOT_WORKERS): number {
  const n = Math.floor(Number(env));
  return env && Number.isFinite(n) && n >= 1 ? Math.min(n, 64) : 3;
}

export const botMemory = {
  budgetMB: Number(process.env.BOT_MEM_BUDGET_MB) > 0 ? Number(process.env.BOT_MEM_BUDGET_MB) : 400,
  workerMB: 70,
  workerMaxMB: Number(process.env.BOT_WORKER_MAX_MB) > 0 ? Number(process.env.BOT_WORKER_MAX_MB) : 140,
  totalMB: (): number => memorySample().totalMB,
  workerRssMB: (pid: number): number => rssOfPid(pid) / 1048576,
};

function markHeavyWorkers(): void {
  for (const w of pool) {
    if (w.draining || !w.proc?.pid) continue;
    if (botMemory.workerRssMB(w.proc.pid) > botMemory.workerMaxMB) w.draining = true;
    if (w.draining && w.bots === 0) retire(w);
  }
}

export function roomForWorker(poolSize: number, max = maxWorkers()): boolean {
  if (poolSize >= max) return false;
  if (poolSize === 0) return true;
  return botMemory.totalMB() + botMemory.workerMB <= botMemory.budgetMB;
}

let pool: Worker[] = [];
let workerIds = 0;
const pinned = new Map<string, { w: Worker; cost: number }>();

export function levelCost(level: unknown): number {
  return BOT_LEVELS.includes(level as BotLevel) ? LEVEL_COST[level as BotLevel] : LEVEL_COST.medium;
}

export function pickWorker(loads: number[]): number {
  let best = 0;
  for (let i = 1; i < loads.length; i++) if (loads[i] < loads[best]) best = i;
  return best;
}

function addWorker(): Worker {
  const w = new Worker(workerIds++);
  pool.push(w);
  return w;
}

function workerFor(bot: unknown, level?: unknown): Worker {
  if (typeof bot !== 'string') return pool[0] ?? addWorker();
  let p = pinned.get(bot);
  if (!p) {
    const cost = levelCost(level);
    markHeavyWorkers();
    const open = pool.filter((x) => !x.draining);
    const pick = open.length ? open : pool;
    const w = open.find((x) => x.bots === 0) ?? (roomForWorker(pool.length) ? addWorker() : pick[pickWorker(pick.map((x) => x.load))]);
    p = { w, cost };
    w.bots++;
    w.load += cost;
    pinned.set(bot, p);
  }
  return p.w;
}

function retire(w: Worker): void {
  if (w.bots > 0) return;
  w.stop();
  pool = pool.filter((x) => x !== w);
}

function unpin(bot: string): Worker | undefined {
  const p = pinned.get(bot);
  if (!p) return undefined;
  pinned.delete(bot);
  p.w.bots = Math.max(0, p.w.bots - 1);
  p.w.load = Math.max(0, p.w.load - p.cost);
  return p.w;
}

export function workerPids(): number[] { return pool.flatMap((w) => (w.proc?.pid ? [w.proc.pid] : [])); }

export function simpleTarget(ante: number, n: number): number {
  const base = [300, 800, 2000, 5000, 11000, 20000, 35000, 50000];
  const a = Math.max(1, Math.floor(ante));
  const chips = a <= 8 ? base[a - 1] : Math.round(50000 * Math.pow(1.6, a - 8));
  return Math.round(chips * ([1, 1.5, 2][n - 1] ?? 2));
}

export function workerPoolStats(): { index: number; bots: number; load: number; calls: number; cpuMs: number; workMs: number; maxWait: number; draining: boolean }[] {
  return pool.map((w) => ({ index: w.index, bots: w.bots, load: w.load, calls: w.calls, cpuMs: w.cpuMs, workMs: w.workMs, maxWait: w.maxWait, draining: w.draining }));
}

let sweepTimer: ReturnType<typeof setInterval> | null = null;
let botCounter = 0;

export function stopBots(): void {
  for (const b of [...allBots]) b.close();
  if (sweepTimer) { clearInterval(sweepTimer); sweepTimer = null; }
  for (const w of pool) w.stop();
  pool = [];
  pinned.clear();
}

let lastPoolLog = 0;
const lastPool = new Map<number, { cpuMs: number; workMs: number }>();

function logPool(): void {
  const now = performance.now();
  if (!D.debug || now - lastPoolLog < 60000) return;
  const span = lastPoolLog ? now - lastPoolLog : 0;
  lastPoolLog = now;
  const parts = pool.map((w) => {
    const prev = lastPool.get(w.index) ?? { cpuMs: 0, workMs: 0 };
    lastPool.set(w.index, { cpuMs: w.cpuMs, workMs: w.workMs });
    const busy = span ? Math.round(((w.workMs - prev.workMs) / span) * 100) : 0;
    const cpu = span ? Math.round(((w.cpuMs - prev.cpuMs) / span) * 100) : 0;
    return `w${w.index} bots=${w.bots} load=${w.load} busy=${busy}% cpu=${cpu}% maxWait=${w.maxWait}ms`;
  });
  for (const w of pool) w.maxWait = 0;
  if (span) D.log('DEBUG', 'BOT', `pool ${parts.join(' | ')}`);
}

function ensureSweep(): void {
  if (sweepTimer) return;
  sweepTimer = setInterval(() => {
    for (const b of [...allBots]) if (D.humansWith(b) === 0) b.leave();
    logPool();
    if (allBots.size === 0 && sweepTimer) { clearInterval(sweepTimer); sweepTimer = null; for (const w of pool) w.stop(); pool = []; pinned.clear(); }
  }, botTiming.sweepMs);
}

export const BOT_KEEP = ['level', 'party', 'settings', 'playing', 'readied', 'voted', 'humanLocs', 'botPids', 'outPids', 'lastKey', 'ranked',
  'pickYou', 'picked', 'myDeck', 'swapAnte', 'swapRound', 'mark', 'simple', 'restarts', 'seed', 'hostRoomJoined'] as const;
export const BOT_SKIP = ['readyState', 'data', 'id', 'runId', 'waiters', 'atSwap'] as const;

export class BotSocket {
  readyState = 1;
  data: Record<string, unknown> & { roomCode: string | null; partyCode?: string | null; name?: string; bot: true };
  level: BotLevel;
  id: string;
  party: boolean;
  runId = 0;
  waiters: { types: string[]; resolve: (m: Msg | null) => void }[] = [];
  hostRoomJoined: Msg | null = null;
  settings: Msg = {};
  playing = false;
  readied = false;
  voted = false;
  humanLocs = new Map<number, string>();
  botPids = new Set<number>();
  outPids = new Set<number>();
  lastKey = '';
  ranked = false;
  pickYou: number | null = null;
  picked: { deck: string | null; jokers: string[] } | null = null;
  myDeck: string | null = null;
  atSwap = false;
  swapAnte = 0;
  swapRound = 0;
  mark: { ante: number; n: number; done: boolean; run?: unknown } | null = null;
  simple = false;
  restarts = 0;
  seed = '';

  constructor(level: BotLevel, host: Record<string, unknown>, party: boolean, name: string) {
    this.level = level;
    this.party = party;
    this.id = `b${++botCounter}`;
    this.data = {
      roomCode: null, partyCode: null, bot: true, name, nameKey: `bot:${this.id}`,
      rl: { msgCount: 0, msgWindowStart: Date.now(), createCount: 0, createWindowStart: Date.now() },
      mods: host.mods ?? [], modsFp: host.modsFp ?? '', gameVersion: host.gameVersion ?? '', rtt: 0,
    };
    allBots.add(this);
    ensureSweep();
    void this.call('warm', {}, 'lobby');
  }

  subscribe(topic: string): void {
    let s = topics.get(topic);
    if (!s) { s = new Set(); topics.set(topic, s); }
    s.add(this);
  }

  unsubscribe(topic: string): void { topics.get(topic)?.delete(this); }

  isSubscribed(topic: string): boolean { return !!topics.get(topic)?.has(this); }

  publish(topic: string, raw: string): void {
    D.publish(topic, raw);
    deliverToBots(topic, raw, this);
  }

  send(raw: string): void {
    if (this.readyState !== 1) return;
    const str = D.decode(raw) ?? raw;
    let m: Msg;
    try { m = JSON.parse(str) as Msg; } catch { return; }
    queueMicrotask(() => this.onServer(m));
  }

  close(): void {
    if (this.readyState !== 1) return;
    this.readyState = 3;
    this.runId++;
    for (const w of this.waiters) w.resolve(null);
    this.waiters = [];
    const w = unpin(this.id);
    if (w && w.bots === 0) retire(w);
    else if (w?.proc) void w.call('drop', { bot: this.id });
    try { D.cleanup(this); } catch (e) { D.log('WARN', 'BOT', `cleanup ${this.id}: ${(e as Error).message}`); }
    for (const s of topics.values()) s.delete(this);
    allBots.delete(this);
  }

  leave(): void {
    if (this.readyState !== 1) return;
    try { D.leave(this); } catch (e) { D.log('WARN', 'BOT', `leave ${this.id}: ${(e as Error).message}`); }
    this.close();
  }

  out(msg: Msg): void {
    if (this.readyState !== 1) return;
    D.dispatch(this, msg);
  }

  wait(types: string[], ms = botTiming.waitMs): Promise<Msg | null> {
    return new Promise((resolve) => {
      const w = { types, resolve };
      this.waiters.push(w);
      setTimeout(() => {
        const i = this.waiters.indexOf(w);
        if (i >= 0) { this.waiters.splice(i, 1); resolve(null); }
      }, ms);
    });
  }

  async waitLive(types: string[], alive: () => boolean): Promise<Msg | null> {
    for (;;) {
      const m = await this.wait(types);
      if (m || !alive()) return m;
    }
  }

  sleep(ms: number): Promise<void> { return new Promise(r => setTimeout(r, ms)); }

  trace(step: string, where: string, r?: Msg): void {
    if (!D.debug) return;
    const t = r ? timingOf(r) : undefined;
    const tm = t ? ` cpu=${t.cpu}ms worker=${t.ms}ms wait=${t.wait}ms queue=${t.queued}` : '';
    D.log('DEBUG', 'BOT', `${this.id} ${String(this.data.partyCode ?? this.data.roomCode ?? '')} ${where} ${step}${tm}`);
  }

  async call(cmd: string, args: Msg, where: string): Promise<Msg> {
    const r = await workerFor(this.id, this.level).call(cmd, { ...args, bot: this.id });
    this.trace(cmd, where, r);
    return r;
  }

  onServer(m: Msg): void {
    const t = m.type as string;
    for (const w of [...this.waiters]) {
      if (w.types.includes(t)) {
        this.waiters.splice(this.waiters.indexOf(w), 1);
        w.resolve(m);
      }
    }
    switch (t) {
      case 'room_joined':
        if (!this.hostRoomJoined) {
          this.hostRoomJoined = m;
          this.out({ type: 'room_joined', player: { name: this.data.name, rank: 1, is_bot: true, bot_level: this.level }, mp_version: m.mp_version ?? 0, version: m.version ?? 'unknown' });
          this.out({ type: 'ready_state', ready: true });
          onSituation(this, 'lobby');
        }
        break;
      case 'room_ready':
        this.out({ type: 'ready_state', ready: true });
        break;
      case 'set_location':
      case 'party_location':
        if (typeof m.pid === 'number' && typeof m.location === 'string') this.humanLocs.set(m.pid, m.location);
        break;
      case 'party_state':
        if (Array.isArray(m.players)) {
          for (const x of m.players as Msg[]) {
            if (typeof x.pid !== 'number') continue;
            if (x.alive === false || x.connected === false) this.outPids.add(x.pid);
            else this.outPids.delete(x.pid);
          }
        }
        break;
      case 'party_room':
        {
          if (Array.isArray(m.players)) for (const x of m.players as Msg[]) if (x.bot === true && typeof x.pid === 'number') this.botPids.add(x.pid);
          const me = Array.isArray(m.players) ? (m.players as Msg[]).find(x => x.name === this.data.name) : null;
          if (me && me.ready === true) this.readied = false;
          else if (me && m.phase === 'lobby' && !this.readied) { this.readied = true; this.out({ type: 'party_ready', ready: true }); onSituation(this, 'lobby'); }
        }
        break;
      case 'pick_state':
        if (typeof m.you === 'number') this.pickYou = m.you;
        break;
      case 'pick_done':
        if (this.pickYou !== null) {
          const me = String(this.pickYou);
          const d = (m.decks && typeof m.decks === 'object' ? (m.decks as Msg)[me] : null);
          const j = (m.jokers && typeof m.jokers === 'object' ? (m.jokers as Msg)[me] : null);
          this.picked = {
            deck: typeof d === 'string' && d !== '' && d !== RANDOM_PICK ? d : null,
            jokers: Array.isArray(j) ? j.filter((k): k is string => typeof k === 'string').slice(0, 5) : [],
          };
        }
        break;
      case 'match_settings':
        if (m.settings && typeof m.settings === 'object') this.settings = m.settings as Msg;
        if (this.settings.forge_room_on === true) { this.refuseMods('forge'); break; }
        this.out({ type: 'ready_state', ready: true });
        break;
      case 'match_start':
      case 'rematch_accepted':
        if (m.settings && typeof m.settings === 'object') this.settings = { ...this.settings, ...(m.settings as Msg) };
        if (t === 'match_start') this.myDeck = typeof m.myDeck === 'string' && m.myDeck !== '' ? m.myDeck : null;
        this.ranked = m.ranked === true || this.settings.ranked === true;
        if (this.settings.forge_room_on === true) { this.refuseMods('forge'); break; }
        this.playing = true;
        this.voted = false;
        this.humanLocs.clear();
        this.outPids.clear();
        this.lastKey = '';
        void this.run(String(m.seed ?? 'BOT'));
        break;
      case 'match_ended':
        this.runId++;
        this.playing = false;
        void this.sendEnd();
        if (!this.party || m.over === true) onMatchEnd(this);
        break;
      case 'social_emote':
        if (typeof m.id === 'string') onHumanEmote(this, String(m.name ?? ''), m.id);
        break;
      case 'match_state_update':
        if (!this.party && this.playing && m.myStatus === 'eliminated') { this.runId++; this.playing = false; }
        break;
      case 'rematch_vote':
        if (!this.party && !this.voted) { this.voted = true; this.out({ type: 'rematch_vote' }); }
        break;
      case 'lobby_returned':
        this.voted = false;
        this.picked = null;
        this.myDeck = null;
        this.out(this.party ? { type: 'party_ready', ready: true } : { type: 'ready_state', ready: true });
        break;
      case 'room_closed':
      case 'room_expired':
      case 'session_replaced':
        this.close();
        break;
      default: break;
    }
  }

  halt(): void { this.runId++; }

  refuseMods(reason: string): void {
    try { D.refuse?.(this, reason); } catch (e) { D.log('WARN', 'BOT', `refuse ${this.id}: ${(e as Error).message}`); }
    this.note(`left: bots cannot play with ${reason === 'forge' ? 'Forge creations' : 'mods'}`);
    this.leave();
  }

  emote(id: string): void { this.out({ type: 'social_emote', id }); }

  chat(text: string): boolean {
    try { return (D.chat?.(this, text) ?? 0) > 0; } catch { return false; }
  }

  humans(): number { return D.humansWith(this); }

  note(msg: string): void { D.log('INFO', 'BOT', `${String(this.data.name ?? this.id)} ${String(this.data.partyCode ?? this.data.roomCode ?? '')} ${msg}`); }

  async sendEnd(): Promise<void> {
    const r = await this.call('end_data', {}, 'end');
    if (r.ok && this.readyState === 1) this.out({ type: 'end_game_data', jokers: r.jokers ?? [], deck: r.deck ?? { cards: [] } });
  }

  async board(where: string): Promise<void> {
    if (!this.party) return;
    const r = await this.call('board', { where }, where);
    if (r.ok && r.board && this.readyState === 1) this.out({ type: 'spec_board', board: r.board });
  }

  loc(location: string): void { this.out({ type: 'set_location', location }); }

  async swapRun(run: Msg | null, name: string, maxMs = botTiming.waitMs): Promise<Msg> {
    const end = Date.now() + maxMs;
    while (!this.atSwap && this.readyState === 1 && this.playing && Date.now() < end) await this.sleep(200);
    if (!this.atSwap) return { ok: false, err: 'bot is not at a swap point' };
    return this.call('swap', { run, name }, 'swap');
  }

  humanPassed(ante: number): void {
    if (this.atSwap && ante > this.swapAnte) this.onServer({ type: 'swap_skip', ante });
  }

  async swapPoint(ante: number, alive: () => boolean): Promise<void> {
    if (!D.swapOn?.(this)) return;
    this.atSwap = true;
    this.swapAnte = ante;
    this.loc('loc_swap');
    try {
      const r = await this.wait(['swap_run', 'swap_skip', 'match_ended']);
      if (r?.type === 'swap_skip') this.note(Number.isFinite(Number(r.ante)) ? `swap skipped: the human is at ante ${String(r.ante)}` : 'swap skipped: the human readied for a PvP blind without swapping');
    } finally {
      this.atSwap = false;
    }
    if (alive()) await this.sleep(paceMs(botPace.select));
  }

  blindKey(ante: number, blind: string, key: unknown): string {
    if (D.isPvp(this, ante, blind)) return this.party ? (PARTY_PVP_KEYS[String(this.settings.party_kind)] ?? 'bl_mp_nemesis') : 'bl_mp_nemesis';
    return typeof key === 'string' ? key : '';
  }

  async pace(since: number, ms: number): Promise<void> {
    const left = since + ms - Date.now();
    if (left > 0) await this.sleep(left);
  }

  async shopAct(act: Msg, t0: number, shop: { at: number; dwell: number; start: number; acts: ShopAct[]; held?: unknown }, alive: () => boolean): Promise<void> {
    const type = String(act.type ?? '');
    let ms = paceMs(actRange(type, typeof act.from === 'string' ? act.from : undefined));
    if (type === 'leave' && shop.at) ms = Math.max(ms, shop.at + shop.dwell - t0);
    await this.pace(t0, ms);
    if (!alive()) return;
    const key = typeof act.key === 'string' ? act.key : undefined;
    if (type === 'leave') {
      shop.held = act.held;
      const waited = await this.keepPace(alive);
      if (!alive()) return;
      if (waited > 0) shop.acts.push({ type: 'wait', key: `${(waited / 1000).toFixed(1)}s`, cost: 0, t: Date.now() - shop.start });
    }
    shop.acts.push({ type, key, cost: Number(act.cost) || 0, t: Date.now() - shop.start, ...(act.spend === true ? { spend: true } : {}) });
    this.trace(`${type}${key ? ' ' + key : ''} $${Number(act.money) || 0} jokers=${Number(act.jokers) || 0}`, `a${Number(act.ante) || 0}`);
    if (this.party && act.phase === 'shop' && type !== 'leave') void this.board('shop');
  }

  humanBehind(): boolean {
    if (!this.lastKey) return false;
    const playing = `loc_playing-${this.lastKey}`;
    for (const [pid, loc] of this.humanLocs) if (!this.botPids.has(pid) && !this.outPids.has(pid) && loc === playing) return true;
    return false;
  }

  async keepPace(alive: () => boolean): Promise<number> {
    if (botPace.scale <= 0 || this.settings.party_kind === 'race' || D.race?.(this) || !this.humanBehind()) return 0;
    const t0 = Date.now();
    const end = t0 + botPace.follow * botPace.scale;
    while (alive() && Date.now() < end && this.humanBehind()) await this.sleep(250);
    if (alive()) await this.sleep(paceMs(botPace.linger));
    return Date.now() - t0;
  }

  async advance(alive: () => boolean): Promise<Msg> {
    const shop = { at: 0, dwell: 0, start: Date.now(), acts: [] as ShopAct[], held: undefined as unknown };
    for (let i = 0; i < 300; i++) {
      const t0 = Date.now();
      const r = await this.call('advance', { stops: true, one: true }, 'shop');
      if (!alive() || !r.ok) return r;
      if (r.act && typeof r.act === 'object') await this.shopAct(r.act as Msg, t0, shop, alive);
      if (!alive()) return r;
      if (r.more) continue;
      if (typeof r.stop !== 'string') {
        if (shop.acts.length) D.log('INFO', 'BOT', `${this.id} ${String(this.data.partyCode ?? this.data.roomCode ?? '')} a${Number(r.ante) || 0} between blinds ${((Date.now() - shop.start) / 1000).toFixed(1)}s: ${shopLine(shop.acts, r.money, shop.held)}`);
        return r;
      }
      const ante = Number(r.ante) || 1;
      const blind = typeof r.blind === 'string' ? r.blind : 'S';
      if (r.stop === 'pack') this.loc('loc_pack');
      else if (r.stop === 'shop') {
        const key = this.blindKey(ante, blind, r.blind_key);
        this.loc(key ? `loc_shop-${key}` : 'loc_shop');
        if (!shop.at) {
          shop.at = Date.now();
          shop.dwell = paceMs(botPace.shop);
          shop.acts.push({ type: 'shop', cost: 0, t: shop.at - shop.start });
          onSituation(this, 'shop', alive);
        }
        if (this.party) {
          this.out({ type: 'live_stat', ante, blind: null, hands: 0, discards: 0, score: 0, where: 'shop' });
          void this.board('shop');
        }
      } else {
        this.loc('loc_selecting');
        if (this.party) this.out({ type: 'live_stat', ante, blind, hands: 0, discards: 0, score: 0, where: 'select' });
      }
    }
    return { ok: false, err: 'too many stops' };
  }

  nextSpot(): { ante: number; n: number } {
    const k = this.mark;
    if (!k) return { ante: 1, n: 1 };
    if (!k.done) return { ante: k.ante, n: k.n };
    return k.n >= 3 ? { ante: k.ante + 1, n: 1 } : { ante: k.ante, n: k.n + 1 };
  }

  repin(): void {
    const w = unpin(this.id);
    if (w && (w.failed || w.bots === 0)) { w.bots = 0; retire(w); }
  }

  async revive(args: Msg, alive: () => boolean): Promise<boolean> {
    const at = this.nextSpot();
    for (let i = 0; i < 2 && alive(); i++) {
      const r = await this.call('resume', { ...args, run: this.mark?.run, ante: at.ante, blind_n: at.n }, 'resume');
      if (!alive()) return false;
      if (r.ok) {
        this.restarts++;
        this.note(`brain restarted on a fresh run at ante ${at.ante} blind ${at.n}`);
        return true;
      }
      D.log('ERROR', 'BOT', `${this.id} resume failed: ${String(r.err)}`);
      this.repin();
    }
    return false;
  }

  async simpleRun(alive: () => boolean): Promise<void> {
    if (!alive()) return;
    let { ante, n } = this.nextSpot();
    this.simple = true;
    this.note(`brain is gone, playing on with the simple brain from ante ${ante} blind ${n}`);
    while (alive()) {
      const blind = ['S', 'B', 'L'][n - 1];
      const target = simpleTarget(ante, n);
      const pvp = D.isPvp(this, ante, blind);
      const key = this.blindKey(ante, blind, n === 1 ? 'bl_small' : n === 2 ? 'bl_big' : '');
      this.lastKey = key;
      this.loc(key ? `loc_shop-${key}` : 'loc_shop');
      await this.sleep(paceMs(botPace.shop));
      if (!alive()) return;
      if (pvp) {
        if (this.party) this.out({ type: 'blind_entered', ante, blind });
        this.loc('loc_ready');
        this.out({ type: 'ready_blind', ante, blind });
        const go = await this.waitLive(['start_blind', 'match_ended', 'pvp_resolved'], alive);
        if (!alive() || !go || go.type === 'match_ended') return;
      }
      this.loc(key ? `loc_playing-${key}` : 'loc_playing');
      if (!(pvp && this.party)) this.out({ type: 'blind_entered', ante, blind });
      const hands = 4;
      if (this.party) this.out({ type: 'live_stat', ante, blind, hands, discards: 3, score: 0, where: 'blind' });
      else if (pvp) this.out({ type: 'play_hand', score: '0', hands_left: hands });
      const settled = pvp ? this.waitLive(['pvp_resolved', 'match_ended'], alive) : null;
      let chips = 0;
      for (let i = 1; i <= hands; i++) {
        await this.sleep(paceMs(botPace.hand) || botTiming.beatMs);
        if (!alive()) return;
        chips += Math.round(target * (0.3 + Math.random() * 0.25));
        const left = !pvp && chips >= target ? 0 : hands - i;
        if (pvp) this.out({ type: 'play_hand', score: String(chips), hands_left: left });
        if (this.party) this.out({ type: 'live_stat', ante, blind, hands: left, discards: 3, score: chips, where: 'blind' });
        if (left === 0) break;
      }
      this.out({ type: 'blind_finished', ante, blind, score: chips });
      this.mark = { ante, n, done: true, run: this.mark?.run };
      if (pvp) {
        const res = await settled;
        if (!alive() || !res || res.type === 'match_ended') return;
      }
      if (n === 3) {
        await this.swapPoint(ante, alive);
        if (!alive()) return;
      }
      n++;
      if (n > 3) { n = 1; ante++; }
    }
  }

  snapshot(): Msg {
    const keep: Msg = {};
    for (const k of BOT_KEEP) keep[k] = (this as unknown as Msg)[k];
    return { ...keep, name: this.data.name ?? '', host: { mods: this.data.mods ?? [], modsFp: this.data.modsFp ?? '', gameVersion: this.data.gameVersion ?? '' } };
  }

  static restore(snap: Msg): BotSocket {
    const level = BOT_LEVELS.includes(snap.level as BotLevel) ? snap.level as BotLevel : 'medium';
    const b = new BotSocket(level, (snap.host && typeof snap.host === 'object' ? snap.host : {}) as Record<string, unknown>, snap.party === true, String(snap.name ?? 'Bot'));
    for (const k of BOT_KEEP) if (k !== 'level' && k !== 'party' && snap[k] !== undefined) (b as unknown as Msg)[k] = snap[k];
    b.hostRoomJoined = b.hostRoomJoined ?? { type: 'room_joined' };
    return b;
  }

  continueRun(): void {
    if (!this.playing) return;
    void this.run(this.seed || 'BOT', this.mark ?? { ante: 1, n: 1, done: false });
  }

  async run(seed: string, from?: { ante: number; n: number; done: boolean; run?: unknown } | null): Promise<void> {
    const my = ++this.runId;
    this.seed = seed;
    const alive = () => this.readyState === 1 && this.runId === my;
    const s = this.settings;
    const rules = (s.rules && typeof s.rules === 'object') ? s.rules as Msg : {};
    const deckName = this.picked?.deck ?? this.myDeck ?? (typeof s.deck === 'string' ? s.deck : (typeof rules.deck === 'string' ? rules.deck : 'Red Deck'));
    const deck = deckKey(deckName);
    const stake = Number(s.stake) || 1;
    const shared = Array.isArray(rules.starting_jokers) ? (rules.starting_jokers as unknown[]).filter((k): k is string => typeof k === 'string').slice(0, 10) : [];
    const jokers = [...shared, ...(this.picked?.jokers ?? [])];
    const randomJokers = Math.max(0, Math.min(5, Math.floor(Number(rules.random_jokers) || 0)));
    const args = { seed, deck, stake, level: this.level, win_ante: 99, ...(jokers.length ? { jokers } : {}), ...(randomJokers ? { random_jokers: randomJokers } : {}) };
    this.mark = from ?? null;
    this.simple = false;
    if (from) {
      this.note(`moved to this server, continuing at ante ${from.ante} blind ${from.n}${from.done ? ' (done)' : ''}`);
      if (!(await this.revive(args, alive))) { await this.simpleRun(alive); return; }
    }
    const made = from ? { ok: true } as Msg : await this.call('new', args, 'start');
    if (!alive()) return;
    if (!from && (jokers.length || randomJokers || this.picked?.deck || this.myDeck)) D.log('INFO', 'BOT', `${this.id} plays its picks: deck=${deck} jokers=${(Array.isArray(made.jokers) ? made.jokers : []).join('+') || '-'} of ${jokers.join('+') || '-'}${randomJokers ? ` +${randomJokers} random` : ''}`);
    if (!from) this.out({ type: 'player_deck', deck: deckName });
    if (!made.ok) {
      D.log('ERROR', 'BOT', `${this.id} new failed: ${made.err}`);
      if (!(await this.revive(args, alive))) { await this.simpleRun(alive); return; }
    }
    let fails = 0;
    while (alive()) {
      const adv = await this.advance(alive);
      if (!alive()) return;
      if (!adv.ok || adv.done) {
        D.log('WARN', 'BOT', `${this.id} brain stopped: ${adv.err ?? 'run over'}`);
        if (++fails > 3 || !(await this.revive(args, alive))) { await this.simpleRun(alive); return; }
        continue;
      }
      const ante = Number(adv.ante);
      const blind = String(adv.blind);
      const at = `a${ante}${blind}`;
      const spot: { ante: number; n: number; done: boolean; run?: unknown } = { ante, n: ['S', 'B', 'L'].indexOf(blind) + 1 || 3, done: false, run: this.mark?.run };
      this.mark = spot;
      void this.call('save', {}, at).then((r) => { if (r.ok && r.run) spot.run = r.run; });
      this.trace('advance', at, adv);
      const pvp = D.isPvp(this, ante, blind);
      const key = this.blindKey(ante, blind, adv.blind_key);
      this.lastKey = key;
      const playing = key ? `loc_playing-${key}` : 'loc_playing';
      const race = !pvp && !this.party && !!D.race?.(this);
      await this.call('pvp', { on: pvp }, at);
      if (!alive()) return;
      const hands0 = Number(adv.hands) || 0;
      const startLive = { type: 'live_stat', ante, blind, hands: hands0, discards: Number(adv.discards) || 0, score: 0, where: 'blind' };
      if (pvp) {
        if (this.party) {
          this.out({ type: 'blind_entered', ante, blind });
          this.out({ ...startLive, where: 'ready' });
        }
        this.loc('loc_ready');
        this.out({ type: 'ready_blind', ante, blind });
        this.trace('ready_blind sent', at);
        const go = await this.waitLive(['start_blind', 'match_ended', 'pvp_resolved'], alive);
        this.trace(`got ${String(go?.type ?? 'nothing')}`, at);
        if (!alive() || !go || go.type === 'match_ended') return;
      }
      this.loc(playing);
      if (!(pvp && this.party)) this.out({ type: 'blind_entered', ante, blind });
      void this.board('blind');
      if (this.party) this.out(startLive);
      else if (pvp && hands0 > 0) this.out({ type: 'play_hand', score: '0', hands_left: hands0 });
      let settledDone = false;
      const settled = pvp ? this.waitLive(['pvp_resolved', 'match_ended'], alive).then((r) => { settledDone = true; return r; }) : null;
      let chips = 0;
      let lost = false;
      let broken = false;
      let last = Date.now();
      const target = Number(adv.target) || 0;
      let next: Promise<Msg> | null = this.call('hand', {}, at);
      for (let i = 0; i < 50 && next; i++) {
        const h = await next;
        next = null;
        if (!alive()) return;
        if (!h.ok) { D.log('WARN', 'BOT', `${this.id} hand failed: ${h.err}`); broken = true; break; }
        if (!h.over) next = this.call('hand', {}, at);
        const think = paceMs(botPace.hand) + paceMs(botPace.discard, Number(h.discards) || 0);
        if (think > 0) await this.pace(last, think);
        else if (i > 0 && (pvp || race) && botTiming.beatMs > 0) await this.sleep(botTiming.beatMs);
        last = Date.now();
        if (!alive()) return;
        const before = chips;
        chips = Number(h.chips) || 0;
        lost = h.lost === true;
        if (target > 0 && chips - before >= target * 0.8) onSituation(this, 'big_hand', alive);
        const left = Number(h.hands_left) || 0;
        if (pvp) this.out({ type: 'play_hand', score: String(Math.floor(chips)), hands_left: left });
        if (this.party && h.board) this.out({ type: 'spec_board', board: h.board });
        if (this.party) this.out({ type: 'live_stat', ante, blind, hands: left, discards: Number(h.discards_left) || 0, score: Math.floor(chips), where: 'blind' });
      }
      if (!alive()) return;
      const score = Math.floor(chips);
      spot.done = true;
      if (!broken) fails = 0;
      if (pvp) {
        this.out({ type: 'blind_finished', ante, blind, score });
        this.trace(`blind_finished score=${score}`, at);
        await this.sleep(0);
        if (!settledDone && alive()) this.loc('loc_wait');
        const waitTimer = setTimeout(() => { if (!settledDone && alive()) onSituation(this, 'waiting', () => alive() && !settledDone); }, Math.round(8000 * botSocial.scale));
        const res = await settled;
        clearTimeout(waitTimer);
        if (!alive() || !res || res.type === 'match_ended') return;
        if (res.result === 'lose') onSituation(this, 'life_lost', alive);
        else if (res.result === 'win') onSituation(this, 'pvp_win', alive);
      } else if (lost) {
        this.out({ type: 'game_over', ante, blind, score });
        onSituation(this, 'life_lost', alive);
      } else {
        this.out({ type: 'blind_finished', ante, blind, score });
        if (blind === 'L') onSituation(this, 'boss', alive);
      }
      if (blind === 'L' && alive()) {
        await this.swapPoint(ante, alive);
        if (!alive()) return;
      }
    }
  }
}

export function botName(_level: BotLevel, taken: (n: string) => boolean): string {
  const free = BOT_NAMES.filter((n) => !taken(n));
  if (free.length) return free[Math.floor(Math.random() * free.length)];
  for (let i = 2; i < 100; i++) {
    const n = `${BOT_NAMES[i % BOT_NAMES.length]} ${i}`;
    if (!taken(n)) return n;
  }
  return `Bot ${botCounter + 1}`;
}

export function botWorkerCall(cmd: string, args: Msg): Promise<Msg> { return workerFor(args.bot, args.level).call(cmd, args); }

import { D1Store, type RankedStore } from './ranked_store';
import { devMark } from './dev';

export const SCORE_TYPES = ['mg_best', 'mg_friends'];
export const SCORE_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS minigame_best (
  pkey TEXT NOT NULL,
  game TEXT NOT NULL,
  score INTEGER NOT NULL,
  low INTEGER NOT NULL DEFAULT 0,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, game)
)`,
];
export const GAME_RE = /^[a-z][a-z0-9_]{0,23}$/;
export const SCORE_MAX = 1_000_000_000;
export const BEST_PER_MIN = 30;
export const BOARD_TOP = 10;
export const BOARD_GAP_MS = 2000;

export interface BestRow { pkey: string; game: string; score: number; low: boolean; at: number }
export interface Ref { pkey: string; code: string; name: string }

export interface ScoreStore {
  init(): Promise<void>;
  bests(pkeys: string[]): Promise<BestRow[]>;
  put(row: BestRow): void;
}

function better(row: BestRow, old: BestRow | undefined): boolean {
  if (!old) return true;
  return row.low ? row.score < old.score : row.score > old.score;
}

export class MemoryScores implements ScoreStore {
  rows = new Map<string, BestRow>();
  async init(): Promise<void> { return; }
  async bests(pkeys: string[]): Promise<BestRow[]> {
    const want = new Set(pkeys);
    return [...this.rows.values()].filter(r => want.has(r.pkey)).map(r => ({ ...r }));
  }
  put(row: BestRow): void {
    const k = `${row.pkey}|${row.game}`;
    const old = this.rows.get(k);
    if (old && old.low !== row.low) { this.rows.set(k, { ...row }); return; }
    if (better(row, old)) this.rows.set(k, { ...row });
  }
}

export class D1Scores implements ScoreStore {
  constructor(private d1: D1Store) {}
  async init(): Promise<void> {
    for (const sql of SCORE_SCHEMA) await this.d1.query(sql);
  }
  async bests(pkeys: string[]): Promise<BestRow[]> {
    const out: BestRow[] = [];
    for (let i = 0; i < pkeys.length; i += 50) {
      const chunk = pkeys.slice(i, i + 50);
      const rows = await this.d1.query(`SELECT pkey, game, score, low, at FROM minigame_best WHERE pkey IN (${chunk.map(() => '?').join(', ')})`, chunk);
      for (const r of rows) out.push({ pkey: String(r.pkey), game: String(r.game), score: Number(r.score), low: Number(r.low) === 1, at: Number(r.at) });
    }
    return out;
  }
  put(row: BestRow): void {
    this.d1.enqueue(`INSERT INTO minigame_best (pkey, game, score, low, at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT (pkey, game) DO UPDATE SET score = excluded.score, low = excluded.low, at = excluded.at
      WHERE excluded.low <> minigame_best.low
        OR (excluded.low = 1 AND excluded.score < minigame_best.score)
        OR (excluded.low = 0 AND excluded.score > minigame_best.score)`,
    [row.pkey, row.game, row.score, row.low ? 1 : 0, row.at]);
  }
}

export function scoreStoreFor(store: RankedStore): ScoreStore {
  if (store instanceof D1Store) return new D1Scores(store);
  return new MemoryScores();
}

export interface ScoreSocket { data: { mgBestAt?: number[]; mgBoardAt?: number } }

export interface ScoreDeps<WS> {
  send(ws: WS, data: object): void;
  friends(pkey: string): Promise<Ref[]>;
  me(pkey: string): Ref;
  onBest?(pkey: string, game: string, score: number): void;
  log?(level: string, msg: string): void;
}

export function cleanScore(msg: Record<string, unknown>): { game: string; score: number; low: boolean } | null {
  const game = msg.game;
  const score = msg.score;
  if (typeof game !== 'string' || !GAME_RE.test(game)) return null;
  if (typeof score !== 'number' || !Number.isInteger(score) || score < 0 || score > SCORE_MAX) return null;
  return { game, score, low: msg.low === true };
}

export class FriendScores<WS extends ScoreSocket> {
  private ready: Promise<void> | null = null;

  constructor(private store: ScoreStore, private deps: ScoreDeps<WS>, private now: () => number = Date.now) {}

  ensure(): Promise<void> {
    if (!this.ready) this.ready = this.store.init().catch(e => { this.ready = null; throw e; });
    return this.ready;
  }

  async handle(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    await this.ensure();
    if (msg.type === 'mg_best') return this.best(ws, me, msg);
    if (msg.type === 'mg_friends') return this.board(ws, me);
  }

  private best(ws: WS, me: string, msg: Record<string, unknown>): void {
    const s = cleanScore(msg);
    if (!s) return;
    const t = this.now();
    const recent = (ws.data.mgBestAt ?? []).filter(x => t - x < 60_000);
    if (recent.length >= BEST_PER_MIN) { ws.data.mgBestAt = recent; return; }
    recent.push(t);
    ws.data.mgBestAt = recent;
    this.store.put({ pkey: me, game: s.game, score: s.score, low: s.low, at: t });
    this.deps.onBest?.(me, s.game, s.score);
  }

  private async board(ws: WS, me: string): Promise<void> {
    const t = this.now();
    if (t - (ws.data.mgBoardAt ?? 0) < BOARD_GAP_MS) return;
    ws.data.mgBoardAt = t;
    const refs = await this.deps.friends(me);
    const who = new Map<string, Ref>();
    for (const r of refs) who.set(r.pkey, r);
    who.set(me, this.deps.me(me));
    const rows = await this.store.bests([...who.keys()]);
    const byGame = new Map<string, BestRow[]>();
    for (const r of rows) {
      const list = byGame.get(r.game) ?? [];
      list.push(r);
      byGame.set(r.game, list);
    }
    const games: Record<string, object[]> = {};
    for (const [game, list] of byGame) {
      const low = list.some(r => r.low);
      list.sort((a, b) => (low ? a.score - b.score : b.score - a.score) || a.at - b.at);
      const out: object[] = [];
      list.forEach((r, i) => {
        const ref = who.get(r.pkey);
        if (!ref || (i >= BOARD_TOP && r.pkey !== me)) return;
        out.push({ rank: i + 1, code: ref.code, name: ref.name, score: r.score, me: r.pkey === me || undefined, ...devMark(r.pkey) });
      });
      games[game] = out;
    }
    this.deps.send(ws, { type: 'mg_friends', games, friends: refs.length });
  }
}

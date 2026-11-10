import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname } from 'node:path';

export const CRASH_MAX_BYTES = 64 * 1024;
export const CRASH_SAMPLE_BYTES = 16 * 1024;
export const CRASH_PER_IP_PER_HOUR = 6;
export const CRASH_GLOBAL_PER_HOUR = 300;
export const CRASH_MAX_GROUPS = 500;
export const CRASH_MAX_PLAYERS = 1000;
export const CRASH_MAX_REPORT_IDS = 200;
const HOUR_MS = 60 * 60 * 1000;
const ISSUE_UPDATE_MS = Number(process.env.CRASH_ISSUE_UPDATE_MS ?? 10 * 60 * 1000);

export interface CrashGroup {
  signature: string;
  message: string;
  frames: string[];
  count: number;
  firstSeen: number;
  lastSeen: number;
  platforms: Record<string, number>;
  versions: Record<string, number>;
  sessions: Record<string, number>;
  modSets: Record<string, number>;
  sample: string;
  issueNumber?: number;
  issueUpdatedAt?: number;
  players?: string[];
  playersBase?: number;
  countBase?: number;
  reportIds?: string[];
  latest?: CrashFields;
  issueSearched?: boolean;
}

export interface CrashFields {
  version: string;
  build: string;
  platform: string;
  os: string;
  mode: string;
  screen: string;
  session: string;
  phase: string;
  blamed: string;
  error: string;
  stack: string;
  actions: string;
  log: string;
}

interface CrashState {
  groups: Map<string, CrashGroup>;
  ipHits: Map<string, number[]>;
  globalHits: number[];
  storePath: string | null;
  loaded: boolean;
}

const state: CrashState = {
  groups: new Map(),
  ipHits: new Map(),
  globalHits: [],
  storePath: process.env.CRASH_STORE_PATH ?? 'data/crashes.json',
  loaded: false,
};

type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;
let fetcher: FetchLike = (input, init) => fetch(input, init);

export function setCrashFetcher(f: FetchLike): void {
  fetcher = f;
}

export function setCrashStorePath(p: string | null): void {
  state.storePath = p;
  state.loaded = false;
  state.groups.clear();
}

export function resetCrashState(): void {
  clearPendingSyncs();
  state.groups.clear();
  state.ipHits.clear();
  state.globalHits = [];
  state.loaded = true;
}

export function crashGroups(): CrashGroup[] {
  loadStore();
  return [...state.groups.values()].sort((a, b) => b.count - a.count);
}

function loadStore(): void {
  if (state.loaded) return;
  state.loaded = true;
  if (!state.storePath) return;
  try {
    const raw = JSON.parse(readFileSync(state.storePath, 'utf8')) as CrashGroup[];
    if (Array.isArray(raw)) for (const g of raw) if (g && typeof g.signature === 'string') state.groups.set(g.signature, g);
  } catch {
    // no store yet
  }
}

function saveStore(): void {
  if (!state.storePath) return;
  try {
    mkdirSync(dirname(state.storePath), { recursive: true });
    const tmp = state.storePath + '.tmp';
    writeFileSync(tmp, JSON.stringify([...state.groups.values()]));
    renameSync(tmp, state.storePath);
  } catch {
    // the store is best effort, the in-memory groups stay
  }
}

export function scrubReport(text: string): string {
  return text
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '<email>')
    .replace(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, '<ip>')
    .replace(/([A-Za-z]:[\\/]+Users[\\/]+)[^\\/\s"']+/gi, '$1<user>')
    .replace(/(\/(?:home|Users)\/)[^/\s"']+/g, '$1<user>')
    .replace(/(\/data\/user\/\d+\/)[^/\s"']+/g, '$1<app>')
    .replace(/(gh[pousr]_|github_pat_)[A-Za-z0-9_]{10,}/g, '<token>')
    .replace(/\b(Bearer|token)\s+[A-Za-z0-9._-]{16,}/gi, '$1 <token>');
}

function section(report: string, name: string): string[] {
  const lines = report.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim() === name);
  if (start < 0) return [];
  const out: string[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i] ?? '';
    if (l.trim() === '') break;
    out.push(l);
  }
  return out;
}

function header(report: string, name: string): string {
  const m = report.match(new RegExp('^' + name + ':\\s*(.*)$', 'm'));
  return m?.[1]?.trim() ?? '';
}

const STACK_END = /^(Last actions:|Log tail:|Report id:|Additional Context:|Balatro Version:|Modded Version:|LÖVE Version:|LOVE Version:)/;

function trimEnd(out: string[]): string[] {
  while (out.length && (out[out.length - 1] ?? '').trim() === '') out.pop();
  return out;
}

function block(report: string, name: string, max = 60): string {
  const lines = report.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim() === name);
  if (start < 0) return '';
  const out: string[] = [];
  for (let i = start + 1; i < lines.length && out.length < max; i++) {
    const l = lines[i] ?? '';
    if (l.trim() === '' || STACK_END.test(l.trim())) break;
    out.push(l.replace(/^ {2}/, ''));
  }
  return trimEnd(out).join('\n');
}

function stackOf(report: string): string {
  const lines = report.split(/\r?\n/);
  const err = lines.findIndex((l) => l.trim() === 'Error:');
  if (err < 0) return '';
  let i = err + 1;
  while (i < lines.length && (lines[i] ?? '').trim() !== '') i++;
  const out: string[] = [];
  for (; i < lines.length && out.length < 60; i++) {
    const l = lines[i] ?? '';
    if (STACK_END.test(l.trim())) break;
    if (out.length === 0 && l.trim() === '') continue;
    out.push(l);
  }
  return trimEnd(out).join('\n');
}

export function crashFields(report: string, raw: Record<string, unknown> = {}): CrashFields {
  const str = (v: unknown) => (typeof v === 'string' ? v : '');
  return {
    version: (str(raw.version) || header(report, 'Overhaul version') || '?').slice(0, 20),
    build: (header(report, 'Build') || str(raw.build) || '?').slice(0, 80),
    platform: (str(raw.platform) || header(report, 'Platform') || '?').slice(0, 40),
    os: (header(report, 'OS') || '?').slice(0, 200),
    mode: (header(report, 'Mode') || '?').slice(0, 300),
    screen: (header(report, 'Screen') || '?').slice(0, 200),
    session: header(report, 'Session') || (raw.modded === true ? 'modded' : raw.modded === false ? 'normal' : '?'),
    phase: header(report, 'Phase') || '?',
    blamed: header(report, 'Blamed mod') || 'none',
    error: section(report, 'Error:').join('\n').slice(0, 2000),
    stack: stackOf(report).slice(0, 6000),
    actions: block(report, 'Last actions:', 30).slice(0, 4000),
    log: block(report, 'Log tail:', 45).slice(0, 6000),
  };
}

export function normalizeMessage(msg: string): string {
  return msg
    .replace(/0x[0-9a-fA-F]+/g, '0x?')
    .replace(/\btable: [0-9a-fx?]+/g, 'table')
    .replace(/<user>|<app>/g, '')
    .replace(/\d+(\.\d+)?/g, 'N')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 300);
}

export function topFrames(report: string, n = 3): string[] {
  const frames: string[] = [];
  const re = /(?:^|[\s'"(])((?:\[[^\]]*\]|[\w./@<>-]+\.lua)):(\d+)/g;
  const errIdx = report.indexOf('\nError:');
  const body = errIdx >= 0 ? report.slice(errIdx) : report;
  const lines = body.split(/\r?\n/).slice(3);
  for (const line of lines) {
    if (/boot\.lua|crash_handler|errhand|xpcall|\[C\]|in function 'handler'/.test(line)) continue;
    re.lastIndex = 0;
    const m = re.exec(line);
    if (m) {
      const f = `${m[1]}:${m[2]}`;
      if (!frames.includes(f)) frames.push(f);
      if (frames.length >= n) break;
    }
  }
  return frames;
}

export function crashSignature(report: string): { signature: string; message: string; frames: string[] } {
  const errLines = section(report, 'Error:');
  const message = normalizeMessage((errLines.join(' ') || report.split(/\r?\n/)[0] || 'unknown').trim());
  const frames = topFrames(report);
  const signature = createHash('sha1').update(message + '\n' + frames.join('\n')).digest('hex').slice(0, 12);
  return { signature, message, frames };
}

function bump(rec: Record<string, number>, key: string, max = 30): void {
  if (!key) return;
  if (rec[key] !== undefined) rec[key] += 1;
  else if (Object.keys(rec).length < max) rec[key] = 1;
}

function allowed(ip: string, now: number): boolean {
  state.globalHits = state.globalHits.filter((t) => now - t < HOUR_MS);
  if (state.globalHits.length >= CRASH_GLOBAL_PER_HOUR) return false;
  const hits = (state.ipHits.get(ip) ?? []).filter((t) => now - t < HOUR_MS);
  if (hits.length >= CRASH_PER_IP_PER_HOUR) {
    state.ipHits.set(ip, hits);
    return false;
  }
  hits.push(now);
  state.ipHits.set(ip, hits);
  state.globalHits.push(now);
  return true;
}

function hashId(id: string): string {
  return createHash('sha1').update('crash-player:' + id).digest('hex').slice(0, 12);
}

export function playerCount(g: CrashGroup): number {
  return (g.playersBase ?? 0) + (g.players?.length ?? 0);
}

export function seenCount(g: CrashGroup): number {
  return (g.countBase ?? 0) + g.count;
}

export function isDuplicate(raw: Record<string, unknown>): boolean {
  loadStore();
  const report = scrubReport(String(raw.report ?? ''));
  const id = header(report, 'Report id');
  if (!id) return false;
  const g = state.groups.get(crashSignature(report).signature);
  return !!g?.reportIds?.includes(id);
}

export function recordCrash(raw: Record<string, unknown>, now = Date.now()): CrashGroup {
  loadStore();
  const report = scrubReport(String(raw.report ?? ''));
  const { signature, message, frames } = crashSignature(report);
  let g = state.groups.get(signature);
  if (!g) {
    if (state.groups.size >= CRASH_MAX_GROUPS) {
      const oldest = [...state.groups.values()].sort((a, b) => a.lastSeen - b.lastSeen)[0];
      if (oldest) state.groups.delete(oldest.signature);
    }
    g = {
      signature, message, frames, count: 0, firstSeen: now, lastSeen: now,
      platforms: {}, versions: {}, sessions: {}, modSets: {}, sample: '',
    };
    state.groups.set(signature, g);
  }
  g.count += 1;
  g.lastSeen = now;
  bump(g.platforms, String(raw.platform ?? (header(report, 'Platform') || '?')).slice(0, 40));
  bump(g.versions, String(raw.version ?? (header(report, 'Overhaul version') || '?')).slice(0, 20));
  bump(g.sessions, raw.modded === true ? 'modded' : raw.modded === false ? 'normal' : header(report, 'Session') || '?');
  const mods = section(report, 'Enabled mods:').map((l) => l.trim()).filter((l) => l && l !== '(none)');
  bump(g.modSets, (mods.length ? mods.join(', ') : 'no mods').slice(0, 400), 20);
  g.sample = report.slice(0, CRASH_SAMPLE_BYTES);
  g.latest = crashFields(report, raw);
  const reportId = header(report, 'Report id');
  if (reportId) g.reportIds = [...(g.reportIds ?? []), reportId].slice(-CRASH_MAX_REPORT_IDS);
  const player = typeof raw.player === 'string' && /^[0-9a-f]{8,32}$/i.test(raw.player) ? hashId(raw.player) : '';
  if (player) {
    g.players = g.players ?? [];
    if (!g.players.includes(player) && g.players.length < CRASH_MAX_PLAYERS) g.players.push(player);
  }
  saveStore();
  return g;
}

function top(rec: Record<string, number>, n = 8): string {
  return Object.entries(rec)
    .sort((a, b) => b[1] - a[1])
    .slice(0, n)
    .map(([k, v]) => `- ${k} (${v})`)
    .join('\n') || '- none';
}

function fence(text: string): string {
  return ['```', (text || '(none)').replace(/```/g, "'''"), '```'].join('\n');
}

function cell(text: string): string {
  return (text || '?').replace(/\|/g, '/').replace(/\r?\n/g, ' ');
}

export function issueBody(g: CrashGroup): string {
  const f = g.latest ?? crashFields(g.sample);
  const count = seenCount(g);
  const players = playerCount(g);
  return [
    `## Crash \`${g.signature}\``,
    '',
    '| Field | Value |',
    '|---|---|',
    `| Seen | **${count}** ${count === 1 ? 'time' : 'times'} by **${players}** ${players === 1 ? 'player' : 'players'} |`,
    `| First seen | ${new Date(g.firstSeen).toISOString()} |`,
    `| Last seen | ${new Date(g.lastSeen).toISOString()} |`,
    `| Version | ${cell(f.version)} |`,
    `| Build | ${cell(f.build)} |`,
    `| Platform | ${cell(f.platform)} |`,
    `| OS | ${cell(f.os)} |`,
    `| Mode | ${cell(f.mode)} |`,
    `| Screen | ${cell(f.screen)} |`,
    `| Session | ${cell(f.session)}, phase ${cell(f.phase)}, blamed mod ${cell(f.blamed)} |`,
    '',
    '### Error',
    fence(f.error || g.message),
    '',
    '### Stack',
    fence(f.stack),
    '',
    '### Last actions',
    fence(f.actions),
    '',
    '### Log tail',
    fence(f.log),
    '',
    '### Top frames',
    g.frames.length ? g.frames.map((fr) => `- \`${fr}\``).join('\n') : '- none',
    '',
    '### Spread',
    '**Platforms**', top(g.platforms),
    '', '**Versions**', top(g.versions),
    '', '**Sessions**', top(g.sessions),
    '', '**Mod sets**', top(g.modSets, 10),
    '',
    '<details><summary>Latest full report</summary>',
    '',
    fence(g.sample),
    '</details>',
  ].join('\n');
}

export function parseIssueCounts(body: string): { count: number; players: number } {
  const m = body.match(/\| Seen \| \*\*(\d+)\*\* times? by \*\*(\d+)\*\* players? \|/);
  return m ? { count: Number(m[1]), players: Number(m[2]) } : { count: 0, players: 0 };
}

const pendingSync = new Map<string, ReturnType<typeof setTimeout>>();

function scheduleSync(g: CrashGroup, waitMs: number): void {
  if (pendingSync.has(g.signature)) return;
  const t = setTimeout(() => {
    pendingSync.delete(g.signature);
    void syncIssue(g);
  }, Math.max(1000, waitMs));
  (t as { unref?: () => void }).unref?.();
  pendingSync.set(g.signature, t);
}

export function clearPendingSyncs(): void {
  for (const t of pendingSync.values()) clearTimeout(t);
  pendingSync.clear();
}

export async function syncIssue(g: CrashGroup, now = Date.now()): Promise<'skipped' | 'created' | 'updated' | 'failed'> {
  const token = process.env.CRASH_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
  if (!token) return 'skipped';
  if (g.issueNumber && g.issueUpdatedAt && now - g.issueUpdatedAt < ISSUE_UPDATE_MS) {
    scheduleSync(g, ISSUE_UPDATE_MS - (now - g.issueUpdatedAt));
    return 'skipped';
  }
  const set = process.env.CRASH_GITHUB_REPO;
  const repo = !set || set === 'JupiterianSoul/Balatro-Overhaul' ? 'JupiterianSoul/Balatro-Overhaul-Source' : set;
  const api = (process.env.CRASH_GITHUB_API ?? 'https://api.github.com').replace(/\/+$/, '');
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'Content-Type': 'application/json',
    'User-Agent': 'balatro-overhaul-server',
  };
  const title = `Crash: ${g.message.slice(0, 90)} [${g.signature}]`;
  try {
    if (!g.issueNumber && !g.issueSearched) {
      const q = encodeURIComponent(`repo:${repo} is:issue in:title "[${g.signature}]"`);
      const found = await fetcher(`${api}/search/issues?q=${q}`, { method: 'GET', headers });
      if (found.ok) {
        g.issueSearched = true;
        const data = (await found.json()) as { items?: { number?: number; title?: string; body?: string }[] };
        const hit = (data.items ?? []).find((it) => typeof it.number === 'number' && (it.title ?? '').includes(`[${g.signature}]`));
        if (hit && typeof hit.number === 'number') {
          g.issueNumber = hit.number;
          const prev = parseIssueCounts(hit.body ?? '');
          g.countBase = prev.count;
          g.playersBase = prev.players;
        }
      }
    }
    if (!g.issueNumber) {
      const res = await fetcher(`${api}/repos/${repo}/issues`, {
        method: 'POST', headers, body: JSON.stringify({ title, body: issueBody(g), labels: ['crash'] }),
      });
      if (!res.ok) return 'failed';
      const data = (await res.json()) as { number?: number };
      if (typeof data.number !== 'number') return 'failed';
      g.issueNumber = data.number;
      g.issueUpdatedAt = now;
      saveStore();
      return 'created';
    }
    const res = await fetcher(`${api}/repos/${repo}/issues/${g.issueNumber}`, {
      method: 'PATCH', headers, body: JSON.stringify({ title, body: issueBody(g) }),
    });
    if (!res.ok) return 'failed';
    g.issueUpdatedAt = now;
    saveStore();
    return 'updated';
  } catch {
    return 'failed';
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

export async function handleCrashRequest(req: Request, ip: string): Promise<Response> {
  if (req.method !== 'POST') return json(405, { ok: false, error: 'method' });
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > CRASH_MAX_BYTES) return json(413, { ok: false, error: 'too_large' });
  let text: string;
  try {
    text = await req.text();
  } catch {
    return json(400, { ok: false, error: 'body' });
  }
  if (Buffer.byteLength(text, 'utf8') > CRASH_MAX_BYTES) return json(413, { ok: false, error: 'too_large' });
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return json(400, { ok: false, error: 'json' });
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return json(400, { ok: false, error: 'json' });
  const obj = raw as Record<string, unknown>;
  if (typeof obj.report !== 'string' || obj.report.trim().length < 10) return json(400, { ok: false, error: 'report' });
  if (isDuplicate(obj)) return json(200, { ok: true, duplicate: true });
  if (!allowed(ip, Date.now())) return json(429, { ok: false, error: 'rate_limited' });
  const g = recordCrash(obj);
  void syncIssue(g);
  return json(200, { ok: true, signature: g.signature, count: seenCount(g), players: playerCount(g) });
}

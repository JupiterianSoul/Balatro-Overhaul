import { S3Client } from 'bun';
import { join } from 'node:path';

export const VERSION_PER_IP_PER_MIN = 30;
export const LINK_SECONDS = 600;
export const MANIFEST_TTL_MS = 60_000;
export const PLATFORMS = ['android', 'linux', 'windows', 'android_patch', 'android_patch_pc'];
const MINUTE_MS = 60_000;

export interface BuildEntry {
  key: string;
  file: string;
  version: string;
  name?: string;
  protocol: number;
  size: number;
  sha256: string;
}

export interface Manifest {
  version: string;
  released: number;
  builds: Record<string, BuildEntry>;
}

export interface UpdateBucket {
  readJson(key: string): Promise<unknown>;
  presign(key: string, seconds: number): string;
}

export function compareVersions(a: string, b: string): number {
  const pa = String(a).split('.').map(n => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

const VERSION_RE = /^\d+(\.\d+){0,3}$/;
const SHA_RE = /^[0-9a-f]{64}$/;

export function parseManifest(raw: unknown): Manifest | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.version !== 'string' || !VERSION_RE.test(r.version)) return null;
  const builds: Record<string, BuildEntry> = {};
  const src = r.builds && typeof r.builds === 'object' ? r.builds as Record<string, unknown> : {};
  for (const p of PLATFORMS) {
    const b = src[p] as Record<string, unknown> | undefined;
    if (!b || typeof b !== 'object') continue;
    if (typeof b.key !== 'string' || !b.key || typeof b.version !== 'string' || !VERSION_RE.test(b.version)) continue;
    if (typeof b.sha256 !== 'string' || !SHA_RE.test(b.sha256) || !(Number(b.size) > 0)) continue;
    builds[p] = {
      key: b.key, file: typeof b.file === 'string' && b.file ? b.file : b.key.split('/').pop() ?? b.key,
      version: b.version, protocol: Number(b.protocol) || 0, size: Number(b.size), sha256: b.sha256,
    };
    const nm = displayName(b.name);
    if (nm) builds[p].name = nm;
  }
  return { version: r.version, released: Number(r.released) || 0, builds };
}

function allowIp(hits: Map<string, number[]>, ip: string, t: number, limit: number): boolean {
  const mine = (hits.get(ip) ?? []).filter(h => t - h < MINUTE_MS);
  if (mine.length >= limit) { hits.set(ip, mine); return false; }
  mine.push(t);
  hits.set(ip, mine);
  if (hits.size > 5000) {
    for (const [k, v] of hits) if (!v.some(h => t - h < MINUTE_MS)) hits.delete(k);
  }
  return true;
}

const knownNames = new Map<string, string>();

function rememberNames(m: Manifest | null): void {
  if (!m) return;
  for (const b of Object.values(m.builds)) if (b.name) knownNames.set(b.version, b.name);
}

export function versionNameOf(version: unknown): string | undefined {
  return typeof version === 'string' && version !== '' ? knownNames.get(version) : undefined;
}

export class UpdateService {
  private cached: { at: number; manifest: Manifest | null } | null = null;
  private loading: Promise<Manifest | null> | null = null;
  private hits = new Map<string, number[]>();

  constructor(private bucket: UpdateBucket | null, private prefix = '', private now: () => number = Date.now,
    private log: (level: string, msg: string) => void = () => undefined) {}

  get configured(): boolean { return this.bucket !== null; }

  async manifest(): Promise<Manifest | null> {
    if (!this.bucket) return null;
    const t = this.now();
    if (this.cached && t - this.cached.at < MANIFEST_TTL_MS) return this.cached.manifest;
    if (!this.loading) {
      const bucket = this.bucket;
      this.loading = bucket.readJson(`${this.prefix}latest.json`)
        .then(raw => {
          const m = raw == null ? null : parseManifest(raw);
          if (raw != null && !m) this.log('WARN', 'latest.json is not a valid manifest');
          rememberNames(m);
          this.cached = { at: this.now(), manifest: m };
          return m;
        })
        .catch(e => {
          this.log('WARN', `manifest read failed: ${String(e).slice(0, 160)}`);
          if (this.cached) this.cached.at = this.now() - MANIFEST_TTL_MS + 10_000;
          return this.cached?.manifest ?? null;
        })
        .finally(() => { this.loading = null; });
    }
    return this.loading;
  }

  allow(ip: string): boolean {
    return allowIp(this.hits, ip, this.now(), VERSION_PER_IP_PER_MIN);
  }

  async handle(req: Request, ip: string): Promise<Response> {
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
    if (req.method !== 'GET') return new Response(JSON.stringify({ error: 'method' }), { status: 405, headers });
    if (!this.allow(ip)) return new Response(JSON.stringify({ error: 'slow_down' }), { status: 429, headers });
    const url = new URL(req.url);
    const platform = url.searchParams.get('platform') ?? '';
    const m = await this.manifest();
    if (!m) return new Response(JSON.stringify({ version: null }), { headers });
    if (!platform) {
      const builds: Record<string, unknown> = {};
      for (const [p, b] of Object.entries(m.builds)) builds[p] = { version: b.version, protocol: b.protocol, size: b.size, sha256: b.sha256, ...(b.name ? { name: b.name } : {}) };
      return new Response(JSON.stringify({ version: m.version, released: m.released, builds }), { headers });
    }
    const b = m.builds[platform];
    if (!b) return new Response(JSON.stringify({ version: m.version, platform, build: null }), { headers });
    const build: Record<string, unknown> = { version: b.version, protocol: b.protocol, size: b.size, sha256: b.sha256, file: b.file };
    if (b.name) build.name = b.name;
    if (url.searchParams.get('link') === '1' && this.bucket) {
      build.url = this.bucket.presign(b.key, LINK_SECONDS);
      build.expires = LINK_SECONDS;
      this.log('INFO', `link ${platform} ${b.version} for ${ip}`);
    }
    return new Response(JSON.stringify({ version: m.version, platform, build }), { headers });
  }
}

class R2Bucket implements UpdateBucket {
  constructor(private client: S3Client) {}
  async readJson(key: string): Promise<unknown> {
    const f = this.client.file(key);
    if (!(await f.exists())) return null;
    return await f.json();
  }
  presign(key: string, seconds: number): string {
    return this.client.presign(key, { expiresIn: seconds, method: 'GET' });
  }
}

export function updatesFromEnv(env: Record<string, string | undefined>, log?: (level: string, msg: string) => void): UpdateService {
  const accountId = env.R2_ACCOUNT_ID || env.CF_ACCOUNT_ID;
  const { R2_ACCESS_KEY_ID: accessKeyId, R2_SECRET_ACCESS_KEY: secretAccessKey, R2_BUCKET: bucket } = env;
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) return new UpdateService(null, '', Date.now, log);
  const client = new S3Client({ accessKeyId, secretAccessKey, bucket, endpoint: `https://${accountId}.r2.cloudflarestorage.com` });
  return new UpdateService(new R2Bucket(client), env.R2_PREFIX ?? '', Date.now, log);
}

export const RELEASE_PER_IP_PER_MIN = 30;
export const LAUNCHER_FORMAT = 1;
const PATCHSET_RE = /^\/release\/patchset-(\d+(?:\.\d+){0,3})\.zip$/;

export interface FeedLatest {
  version: string;
  name?: string;
  game_version?: string;
  url: string;
  size: number;
  sha256: string;
  patch_format: number;
  min_launcher: number;
  changelog?: string | Record<string, string>;
}

export interface ReleaseFeed {
  format: 1;
  latest: FeedLatest;
  page?: string;
}

export const patchsetName = (version: string) => `patchset-${version}.zip`;

export function displayName(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 && v.length <= 40 && !/[\x00-\x1f]/.test(v) ? v : undefined;
}

function level(v: unknown): number | null {
  if (v === undefined || v === null) return 1;
  const n = Number(v);
  return Number.isInteger(n) && n >= 1 && n <= 1000 ? n : null;
}

export function parseFeed(raw: unknown): ReleaseFeed | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  if (Number(r.format) !== 1 || !r.latest || typeof r.latest !== 'object') return null;
  const l = r.latest as Record<string, unknown>;
  if (typeof l.version !== 'string' || !VERSION_RE.test(l.version)) return null;
  const sha = typeof l.sha256 === 'string' ? l.sha256.toLowerCase() : '';
  const size = Number(l.size);
  if (!SHA_RE.test(sha) || !Number.isInteger(size) || size <= 0) return null;
  const pf = level(l.patch_format), ml = level(l.min_launcher);
  if (pf === null || ml === null) return null;
  const latest: FeedLatest = {
    version: l.version, url: patchsetName(l.version), size, sha256: sha,
    patch_format: Math.max(pf, ml), min_launcher: ml,
  };
  if (typeof l.game_version === 'string' && l.game_version) latest.game_version = l.game_version;
  const nm = displayName(l.name);
  if (nm) latest.name = nm;
  if (typeof l.changelog === 'string' && l.changelog) latest.changelog = l.changelog;
  else if (l.changelog && typeof l.changelog === 'object') {
    const c: Record<string, string> = {};
    for (const [k, v] of Object.entries(l.changelog as Record<string, unknown>)) if (/^[a-z]{2}(_[A-Z]{2})?$/.test(k) && typeof v === 'string' && v) c[k] = v;
    if (Object.keys(c).length) latest.changelog = c;
  }
  const feed: ReleaseFeed = { format: 1, latest };
  if (typeof r.page === 'string' && /^https?:\/\/\S+$/.test(r.page)) feed.page = r.page;
  return feed;
}

export interface ReleaseStore {
  readJson(key: string): Promise<unknown>;
  download(key: string): Promise<Response | null>;
}

export class ReleaseService {
  private cached: { at: number; feed: ReleaseFeed | null } | null = null;
  private loading: Promise<ReleaseFeed | null> | null = null;
  private hits = new Map<string, number[]>();

  constructor(private store: ReleaseStore | null, private prefix = '', private now: () => number = Date.now,
    private log: (level: string, msg: string) => void = () => undefined) {}

  get configured(): boolean { return this.store !== null; }

  async feed(): Promise<ReleaseFeed | null> {
    if (!this.store) return null;
    const t = this.now();
    if (this.cached && t - this.cached.at < MANIFEST_TTL_MS) return this.cached.feed;
    if (!this.loading) {
      const store = this.store;
      this.loading = store.readJson(`${this.prefix}release/feed.json`)
        .then(raw => {
          const f = raw == null ? null : parseFeed(raw);
          if (raw != null && !f) this.log('WARN', 'release/feed.json is not a valid feed');
          this.cached = { at: this.now(), feed: f };
          return f;
        })
        .catch(e => {
          this.log('WARN', `feed read failed: ${String(e).slice(0, 160)}`);
          if (this.cached) this.cached.at = this.now() - MANIFEST_TTL_MS + 10_000;
          return this.cached?.feed ?? null;
        })
        .finally(() => { this.loading = null; });
    }
    return this.loading;
  }

  async handle(req: Request, ip: string): Promise<Response> {
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
    const fail = (status: number, error: string) => new Response(JSON.stringify({ error }), { status, headers });
    if (req.method !== 'GET' && req.method !== 'HEAD') return fail(405, 'method');
    const path = new URL(req.url).pathname;
    const zip = PATCHSET_RE.exec(path);
    if (path !== '/release/feed.json' && !zip) return fail(404, 'not_found');
    if (!allowIp(this.hits, ip, this.now(), RELEASE_PER_IP_PER_MIN)) return fail(429, 'slow_down');
    if (!this.store) return fail(404, 'no_release');
    if (!zip) {
      const f = await this.feed();
      if (!f) return fail(404, 'no_release');
      return new Response(req.method === 'HEAD' ? null : JSON.stringify(f), { headers });
    }
    const res = await this.store.download(`${this.prefix}release/${patchsetName(zip[1])}`).catch(e => {
      this.log('WARN', `patch set ${zip[1]} failed: ${String(e).slice(0, 160)}`);
      return null;
    });
    if (!res) return fail(404, 'no_release');
    this.log('INFO', `patch set ${zip[1]} for ${ip}`);
    return res;
  }
}

class R2ReleaseStore implements ReleaseStore {
  constructor(private client: S3Client) {}
  async readJson(key: string): Promise<unknown> {
    const f = this.client.file(key);
    if (!(await f.exists())) return null;
    return await f.json();
  }
  async download(key: string): Promise<Response | null> {
    const url = this.client.presign(key, { expiresIn: LINK_SECONDS, method: 'GET' });
    return new Response(null, { status: 302, headers: { Location: url, 'Cache-Control': 'no-store' } });
  }
}

export class DirReleaseStore implements ReleaseStore {
  constructor(private dir: string) {}
  private path(key: string): string { return join(this.dir, key.replace(/^.*release\//, '')); }
  async readJson(key: string): Promise<unknown> {
    const f = Bun.file(this.path(key));
    if (!(await f.exists())) return null;
    return await f.json();
  }
  async download(key: string): Promise<Response | null> {
    const f = Bun.file(this.path(key));
    if (!(await f.exists())) return null;
    return new Response(f, { headers: { 'Content-Type': 'application/zip', 'Cache-Control': 'public, max-age=300' } });
  }
}

export function releaseFromEnv(env: Record<string, string | undefined>, log?: (level: string, msg: string) => void): ReleaseService {
  if (env.RELEASE_DIR) return new ReleaseService(new DirReleaseStore(env.RELEASE_DIR), '', Date.now, log);
  const accountId = env.R2_ACCOUNT_ID || env.CF_ACCOUNT_ID;
  const { R2_ACCESS_KEY_ID: accessKeyId, R2_SECRET_ACCESS_KEY: secretAccessKey, R2_BUCKET: bucket } = env;
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) return new ReleaseService(null, '', Date.now, log);
  const client = new S3Client({ accessKeyId, secretAccessKey, bucket, endpoint: `https://${accountId}.r2.cloudflarestorage.com` });
  return new ReleaseService(new R2ReleaseStore(client), env.R2_PREFIX ?? '', Date.now, log);
}

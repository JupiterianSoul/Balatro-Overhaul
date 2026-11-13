import { S3Client, $ } from 'bun';
import { copyFileSync, existsSync, mkdirSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { compareVersions, parseFeed, parseManifest, patchsetName, type BuildEntry, type Manifest, type ReleaseFeed } from '../../server/src/updates';

const root = resolve(import.meta.dir, '../..');
export const KEEP = 2;

export interface PublishOpts {
  from: string;
  to: string;
  channel: 'prod' | 'debug';
  minLauncher?: number;
  page?: string;
  force: boolean;
  dryRun: boolean;
  env: Record<string, string | undefined>;
  say: (line: string) => void;
  globals?: string;
}

export interface Target {
  name: string;
  readFeed(): Promise<unknown>;
  putZip(file: string, name: string): Promise<void>;
  putFeed(body: string): Promise<void>;
  list(): Promise<string[]>;
  remove(name: string): Promise<void>;
  readManifest(): Promise<unknown>;
  putBuild(file: string, key: string, name: string): Promise<void>;
  putManifest(body: string): Promise<void>;
  listBuilds(): Promise<string[]>;
  removeBuild(key: string): Promise<void>;
}

function usage(): never {
  console.log(`Usage: bun tools/release/publish_feed.ts [--from DIR] [--to r2|DIR] [--channel prod|debug] [--min-launcher N] [--page URL] [--force] [--dry-run]
  Publishes the launcher update (patchset-<version>.zip and feed.json written by pack_overhaul.sh) so
  https://balatro-overhaul-muliplayer.onrender.com/release/feed.json offers it to launcher installs.
  --from DIR      the pack_overhaul.sh output (default dist/release)
  --to r2         the R2 bucket the server reads (default), keys release/feed.json and release/patchset-<v>.zip
                  (debug channel: under debug/). Needs R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET.
  --to DIR        a folder instead (a server started with RELEASE_DIR=DIR serves it; used by the tests)
  --min-launcher  launchers that read an older feed format are told to download a new launcher
  Refuses a version that is not newer than the published one unless --force. Keeps the last ${KEEP} patch sets.`);
  process.exit(1);
}

export function parseArgs(argv: string[], env: Record<string, string | undefined> = process.env): PublishOpts {
  const o: PublishOpts = { from: join(root, 'dist/release'), to: 'r2', channel: 'prod', force: false, dryRun: false, env, say: l => console.log(l) };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i] ?? usage();
    if (a === '--from') o.from = resolve(next());
    else if (a === '--to') { const t = next(); o.to = t === 'r2' ? 'r2' : resolve(t); }
    else if (a === '--channel') { const c = next(); if (c !== 'prod' && c !== 'debug') usage(); o.channel = c; }
    else if (a === '--min-launcher') { const n = Number(next()); if (!Number.isInteger(n) || n < 1) usage(); o.minLauncher = n; }
    else if (a === '--page') o.page = next();
    else if (a === '--force') o.force = true;
    else if (a === '--dry-run') o.dryRun = true;
    else usage();
  }
  return o;
}

async function sha256(file: string): Promise<string> {
  const h = new Bun.CryptoHasher('sha256');
  for await (const chunk of Bun.file(file).stream()) h.update(chunk);
  return h.digest('hex');
}

const mb = (n: number) => `${(n / 1048576).toFixed(1)} MB`;

function dirTarget(dir: string): Target {
  return {
    name: dir,
    async readFeed() { const f = Bun.file(join(dir, 'feed.json')); return (await f.exists()) ? await f.json() : null; },
    async putZip(file, name) { mkdirSync(dir, { recursive: true }); copyFileSync(file, join(dir, `${name}.part`)); renameSync(join(dir, `${name}.part`), join(dir, name)); },
    async putFeed(body) { mkdirSync(dir, { recursive: true }); writeFileSync(join(dir, 'feed.json.part'), body); renameSync(join(dir, 'feed.json.part'), join(dir, 'feed.json')); },
    async list() { return existsSync(dir) ? readdirSync(dir) : []; },
    async remove(name) { rmSync(join(dir, name), { force: true }); },
    async readManifest() { const f = Bun.file(join(dir, 'latest.json')); return (await f.exists()) ? await f.json() : null; },
    async putBuild(file, key) { const dst = join(dir, key); mkdirSync(join(dst, '..'), { recursive: true }); copyFileSync(file, `${dst}.part`); renameSync(`${dst}.part`, dst); },
    async putManifest(body) { mkdirSync(dir, { recursive: true }); writeFileSync(join(dir, 'latest.json.part'), body); renameSync(join(dir, 'latest.json.part'), join(dir, 'latest.json')); },
    async listBuilds() {
      const b = join(dir, 'builds');
      if (!existsSync(b)) return [];
      return readdirSync(b).flatMap(v => readdirSync(join(b, v)).map(f => `builds/${v}/${f}`));
    },
    async removeBuild(key) { rmSync(join(dir, key), { force: true }); },
  };
}

function r2Target(env: Record<string, string | undefined>, prefix: string): Target {
  const accountId = env.R2_ACCOUNT_ID, bucket = env.R2_BUCKET;
  if (!accountId || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY || !bucket) throw new Error('R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET must be set (the same ones release.sh uses)');
  const client = new S3Client({ accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY, bucket, endpoint: `https://${accountId}.r2.cloudflarestorage.com` });
  const dir = `${prefix}release/`;
  return {
    name: `r2:${bucket}/${dir}`,
    async readFeed() { const f = client.file(`${dir}feed.json`); return (await f.exists()) ? await f.json() : null; },
    async putZip(file, name) {
      const writer = client.file(`${dir}${name}`).writer({ type: 'application/zip', contentDisposition: `attachment; filename="${name}"`, partSize: 16 * 1048576, queueSize: 4, retry: 3 });
      for await (const chunk of Bun.file(file).stream()) { writer.write(chunk); await writer.flush(); }
      await writer.end();
    },
    async putFeed(body) { await client.file(`${dir}feed.json`).write(body, { type: 'application/json' }); },
    async list() {
      const keys: string[] = [];
      let token: string | undefined;
      do {
        const page = await client.list({ prefix: dir, maxKeys: 1000, continuationToken: token });
        for (const c of page.contents ?? []) keys.push(c.key.slice(dir.length));
        token = page.isTruncated ? page.nextContinuationToken : undefined;
      } while (token);
      return keys;
    },
    async remove(name) { await client.delete(`${dir}${name}`); },
    async readManifest() { const f = client.file(`${prefix}latest.json`); return (await f.exists()) ? await f.json() : null; },
    async putBuild(file, key, name) {
      const writer = client.file(`${prefix}${key}`).writer({ type: 'application/zip', contentDisposition: `attachment; filename="${name}"`, partSize: 16 * 1048576, queueSize: 4, retry: 3 });
      for await (const chunk of Bun.file(file).stream()) { writer.write(chunk); await writer.flush(); }
      await writer.end();
    },
    async putManifest(body) { await client.file(`${prefix}latest.json`).write(body, { type: 'application/json' }); },
    async listBuilds() {
      const keys: string[] = [];
      let token: string | undefined;
      do {
        const page = await client.list({ prefix: `${prefix}builds/`, maxKeys: 1000, continuationToken: token });
        for (const c of page.contents ?? []) keys.push(c.key.slice(prefix.length));
        token = page.isTruncated ? page.nextContinuationToken : undefined;
      } while (token);
      return keys;
    },
    async removeBuild(key) { await client.delete(`${prefix}${key}`); },
  };
}

export async function zipVersion(file: string): Promise<string | undefined> {
  const src = await $`unzip -p ${file} manifest.lua`.quiet().nothrow().text();
  return /^ {2}overhaul_version = "([^"]+)",$/m.exec(src)?.[1];
}

export function globalsInfo(src: string): { version?: string; protocol: number; name?: string } {
  return {
    version: /^OVERHAUL_VERSION\s*=\s*'([^']+)'/m.exec(src)?.[1],
    protocol: Number(/^MP_PROTOCOL_VERSION\s*=\s*(\d+)/m.exec(src)?.[1]) || 0,
    name: /^OVERHAUL_NAME\s*=\s*'([^']+)'/m.exec(src)?.[1],
  };
}

export interface ReleaseFile { name: string; file: string; size: number; sha256: string; }

export async function launcherFiles(from: string, feed: ReleaseFeed): Promise<ReleaseFile[]> {
  const out: ReleaseFile[] = [];
  const l = feed.latest;
  const want = [l.launcher, l.launcher?.phone, l.android_apk].filter((e): e is NonNullable<typeof e> => !!e);
  const apks = existsSync(join(from, 'android')) ? readdirSync(join(from, 'android')).filter(n => n.endsWith('.apk')).map(n => join(from, 'android', n)) : [];
  for (const e of want) {
    const candidates = e.url.endsWith('.apk') ? apks : [join(from, e.url)];
    let found: ReleaseFile | undefined;
    for (const file of candidates) {
      if (!existsSync(file) || Bun.file(file).size !== e.size) continue;
      const hash = await sha256(file);
      if (hash === e.sha256) { found = { name: e.url, file, size: e.size, sha256: hash }; break; }
    }
    if (!found) throw new Error(`feed.json offers ${e.url} (${e.size} bytes, sha256 ${e.sha256}) but no matching file is in ${from}. Run pack_overhaul.sh again.`);
    out.push(found);
  }
  return out;
}

export interface PhonePatch { platform: 'android_patch' | 'android_patch_pc'; file: string; name: string; }

export function phonePatches(from: string, v: string, patchset: string): PhonePatch[] {
  const out: PhonePatch[] = [];
  const mobile = join(from, 'android', `android-patch-${v}.zip`);
  if (existsSync(mobile)) out.push({ platform: 'android_patch', file: mobile, name: `android-patch-${v}.zip` });
  out.push({ platform: 'android_patch_pc', file: patchset, name: `android-patch-pc-${v}.zip` });
  return out;
}

async function publishPhone(o: PublishOpts, t: Target, v: string, patchset: string, globals: string): Promise<Manifest | null> {
  const info = globalsInfo(globals);
  if (info.version !== v) { o.say(`phone patches skipped: assets/globals.lua says ${info.version ?? 'nothing'}, the feed ${v}`); return null; }
  const current = parseManifest(await t.readManifest());
  const builds: Record<string, BuildEntry> = { ...(current?.builds ?? {}) };
  for (const p of phonePatches(o.from, v, patchset)) {
    const inner = await zipVersion(p.file);
    if (inner !== v) throw new Error(`${basename(p.file)} holds Overhaul ${inner ?? 'nothing'}, the feed says ${v}`);
    const key = `builds/${v}/${p.name}`;
    const size = Bun.file(p.file).size;
    const hash = await sha256(p.file);
    if (!o.dryRun) await t.putBuild(p.file, key, p.name);
    builds[p.platform] = { key: o.channel === 'debug' ? `debug/${key}` : key, file: p.name, version: v, protocol: info.protocol, size, sha256: hash, ...(info.name ? { name: info.name } : {}) };
    o.say(`${p.platform}: Overhaul ${v}, ${mb(size)}, sha256 ${hash}`);
  }
  const version = Object.values(builds).map(b => b.version).sort(compareVersions).pop()!;
  const manifest: Manifest = { version, released: Date.now(), builds };
  if (o.dryRun) { o.say(`dry run, would write latest.json:\n${JSON.stringify(manifest, null, 2)}`); return manifest; }
  await t.putManifest(JSON.stringify(manifest, null, 2));
  const live = new Set(Object.values(builds).map(b => b.key.replace(/^debug\//, '')));
  const keys = await t.listBuilds();
  const versionOf = (k: string) => k.split('/')[1];
  const keepV = new Set([...new Set(keys.map(versionOf))].sort(compareVersions).slice(-KEEP));
  for (const k of keys) {
    if (live.has(k) || keepV.has(versionOf(k))) continue;
    await t.removeBuild(k);
    o.say(`  removed old ${k}`);
  }
  o.say(`latest.json offers Overhaul ${v} to phone installs`);
  return manifest;
}

export async function publish(o: PublishOpts, target?: Target): Promise<ReleaseFeed> {
  const feedFile = join(o.from, 'feed.json');
  if (!existsSync(feedFile)) throw new Error(`${feedFile} is missing, run tools/release/pack_overhaul.sh first`);
  const raw = await Bun.file(feedFile).json() as Record<string, any>;
  if (raw && typeof raw === 'object' && raw.latest && typeof raw.latest === 'object') {
    if (o.minLauncher !== undefined) raw.latest.min_launcher = o.minLauncher;
    if (o.page !== undefined) raw.page = o.page;
  }
  const feed = parseFeed(raw);
  if (!feed) throw new Error(`${feedFile} is not a valid update feed`);
  if (o.page !== undefined && feed.page !== o.page) throw new Error(`--page must be an http(s) URL`);
  const v = feed.latest.version;
  const zip = join(o.from, typeof raw.latest.url === 'string' && !raw.latest.url.includes('/') ? raw.latest.url : patchsetName(v));
  if (!existsSync(zip)) throw new Error(`${zip} is missing (feed.json points at it)`);
  const size = Bun.file(zip).size;
  if (size !== feed.latest.size) throw new Error(`${basename(zip)} is ${size} bytes but feed.json says ${feed.latest.size}. Run pack_overhaul.sh again.`);
  const hash = await sha256(zip);
  if (hash !== feed.latest.sha256) throw new Error(`${basename(zip)} sha256 is ${hash} but feed.json says ${feed.latest.sha256}. Run pack_overhaul.sh again.`);
  const inner = await zipVersion(zip);
  if (inner !== v) throw new Error(`${basename(zip)} holds Overhaul ${inner ?? 'nothing'}, feed.json says ${v}`);
  o.say(`patch set: Overhaul ${v} for Balatro ${feed.latest.game_version ?? '?'}, ${mb(size)}, sha256 ${hash}`);
  const extra = await launcherFiles(o.from, feed);
  for (const x of extra) o.say(`${x.name}: ${mb(x.size)}, sha256 ${x.sha256}`);

  let t: Target;
  try {
    t = target ?? (o.to === 'r2' ? r2Target(o.env, o.channel === 'debug' ? 'debug/' : '') : dirTarget(o.channel === 'debug' ? join(o.to, 'debug') : o.to));
  } catch (e) {
    if (!o.dryRun) throw e;
    o.say('dry run without R2 credentials: the published version is not checked');
    t = { name: 'r2', readFeed: async () => null, putZip: async () => undefined, putFeed: async () => undefined, list: async () => [], remove: async () => undefined,
      readManifest: async () => null, putBuild: async () => undefined, putManifest: async () => undefined, listBuilds: async () => [], removeBuild: async () => undefined };
  }
  const current = parseFeed(await t.readFeed());
  if (current) o.say(`published now: Overhaul ${current.latest.version}`);
  if (current && compareVersions(v, current.latest.version) <= 0 && !o.force) {
    throw new Error(`Overhaul ${v} is not newer than the published ${current.latest.version}. Bump OVERHAUL_VERSION in assets/globals.lua and pack again (or pass --force).`);
  }
  const body = JSON.stringify(feed, null, 2) + '\n';
  const globals = o.globals ?? await Bun.file(join(root, 'assets/globals.lua')).text();
  if (o.dryRun) { o.say(`dry run, would upload ${patchsetName(v)} and feed.json to ${t.name}:\n${body}`); await publishPhone(o, t, v, zip, globals); return feed; }
  await publishPhone(o, t, v, zip, globals);
  o.say(`uploading ${patchsetName(v)} to ${t.name}`);
  await t.putZip(zip, patchsetName(v));
  for (const x of extra) {
    o.say(`uploading ${x.name} to ${t.name}`);
    await t.putZip(x.file, x.name);
  }
  await t.putFeed(body);
  o.say(`feed.json now offers Overhaul ${v}`);

  const sets = (await t.list()).map(n => /^patchset-(\d+(?:\.\d+){0,3})\.zip$/.exec(n)?.[1]).filter((x): x is string => !!x);
  const keep = new Set([...sets].sort(compareVersions).slice(-KEEP));
  keep.add(v);
  for (const s of sets) {
    if (keep.has(s)) continue;
    await t.remove(patchsetName(s));
    o.say(`  removed old ${patchsetName(s)}`);
  }
  o.say(`Kept patch sets: ${[...keep].sort(compareVersions).join(', ')}`);
  const live = new Set([...extra.map(x => x.name), ...[current?.latest.launcher?.url, current?.latest.launcher?.phone?.url, current?.latest.android_apk?.url].filter((n): n is string => !!n)]);
  for (const n of await t.list()) {
    if (!/^launcher-(code-|android-)/.test(n) || live.has(n)) continue;
    await t.remove(n);
    o.say(`  removed old ${n}`);
  }
  return feed;
}

if (import.meta.main) {
  publish(parseArgs(process.argv.slice(2))).catch(err => { console.error(`publish failed: ${err instanceof Error ? err.message : String(err)}`); process.exit(1); });
}

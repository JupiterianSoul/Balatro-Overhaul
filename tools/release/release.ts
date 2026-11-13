import { S3Client, $ } from 'bun';
import { existsSync, readdirSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { compareVersions, parseManifest, type BuildEntry, type Manifest } from '../../server/src/updates';

const root = resolve(import.meta.dir, '../..');
const KEEP = 2;

interface Opts { channel: 'prod' | 'debug'; linux?: string; android?: string; only: Set<string>; force: boolean; dryRun: boolean; }

function usage(): never {
  console.log(`Usage: ./release.sh [--channel prod|debug] [--only linux,android] [--linux FILE] [--android FILE] [--force] [--dry-run]
  Uploads the built game to R2 and points latest.json at it, then keeps only the last ${KEEP} releases.
  prod (default): dist/linux/Overhaul.love and the newest dist/Balatro_V2.N.apk
  debug: dist/linux-debug/OverhaulDebug.love only, under debug/ (read by the Balatro Debug local server)
  Credentials: ~/.config/balatro-overhaul/release.env`);
  process.exit(1);
}

function parseArgs(argv: string[]): Opts {
  const o: Opts = { channel: 'prod', only: new Set(), force: false, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i] ?? usage();
    if (a === '--channel') { const c = next(); if (c !== 'prod' && c !== 'debug') usage(); o.channel = c; }
    else if (a === '--only') next().split(',').forEach(p => o.only.add(p.trim()));
    else if (a === '--linux') o.linux = next();
    else if (a === '--android') o.android = next();
    else if (a === '--force') o.force = true;
    else if (a === '--dry-run') o.dryRun = true;
    else usage();
  }
  return o;
}

function newestApk(): string | undefined {
  const dist = join(root, 'dist');
  if (!existsSync(dist)) return undefined;
  const apks = readdirSync(dist).map(f => /^Balatro_V2\.(\d+)\.apk$/.exec(f)).filter(Boolean) as RegExpExecArray[];
  apks.sort((a, b) => Number(b[1]) - Number(a[1]));
  return apks[0] ? join(dist, apks[0][0]) : undefined;
}

async function gameVersion(file: string, inner: string): Promise<{ version: string; protocol: number; name?: string }> {
  const src = await $`unzip -p ${file} ${inner}`.quiet().text();
  const version = /^OVERHAUL_VERSION\s*=\s*'([^']+)'/m.exec(src)?.[1];
  const protocol = Number(/^MP_PROTOCOL_VERSION\s*=\s*(\d+)/m.exec(src)?.[1]);
  if (!version || !protocol) throw new Error(`${basename(file)}: no OVERHAUL_VERSION / MP_PROTOCOL_VERSION in ${inner}`);
  const name = /^OVERHAUL_NAME\s*=\s*'([^']+)'/m.exec(src)?.[1];
  return { version, protocol, name };
}

async function sha256(file: string): Promise<string> {
  const h = new Bun.CryptoHasher('sha256');
  for await (const chunk of Bun.file(file).stream()) h.update(chunk);
  return h.digest('hex');
}

const mb = (n: number) => `${(n / 1048576).toFixed(1)} MB`;

async function upload(client: S3Client, key: string, file: string, type: string, name: string): Promise<void> {
  const size = Bun.file(file).size;
  const writer = client.file(key).writer({ type, contentDisposition: `attachment; filename="${name}"`, partSize: 16 * 1048576, queueSize: 4, retry: 3 });
  let sent = 0, shown = -1;
  for await (const chunk of Bun.file(file).stream()) {
    writer.write(chunk);
    await writer.flush();
    sent += chunk.byteLength;
    const pct = Math.floor(sent * 100 / size);
    if (pct >= shown + 10 || sent === size) { shown = pct; process.stdout.write(`  ${key}: ${pct}% of ${mb(size)}\n`); }
  }
  await writer.end();
}

async function listKeys(client: S3Client, prefix: string): Promise<string[]> {
  const keys: string[] = [];
  let token: string | undefined;
  do {
    const page = await client.list({ prefix, maxKeys: 1000, continuationToken: token });
    for (const c of page.contents ?? []) keys.push(c.key);
    token = page.isTruncated ? page.nextContinuationToken : undefined;
  } while (token);
  return keys;
}

async function main(): Promise<void> {
  const o = parseArgs(process.argv.slice(2));
  const e = process.env;
  const accountId = e.R2_ACCOUNT_ID, bucket = e.R2_BUCKET;
  if (!accountId || !e.R2_ACCESS_KEY_ID || !e.R2_SECRET_ACCESS_KEY || !bucket) throw new Error('R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET must be set (~/.config/balatro-overhaul/release.env)');
  const client = new S3Client({ accessKeyId: e.R2_ACCESS_KEY_ID, secretAccessKey: e.R2_SECRET_ACCESS_KEY, bucket, endpoint: `https://${accountId}.r2.cloudflarestorage.com` });
  const prefix = o.channel === 'debug' ? 'debug/' : '';

  const wanted = o.only.size > 0 ? o.only : new Set(o.channel === 'debug' ? ['linux'] : ['linux', 'android']);
  for (const p of wanted) if (p !== 'linux' && p !== 'android') throw new Error(`unknown platform ${p}`);
  if (o.channel === 'debug' && wanted.has('android')) throw new Error('the debug channel only carries the Balatro Debug PC build');

  const jobs: { platform: string; file: string; inner: string; name: string; type: string }[] = [];
  if (wanted.has('linux')) {
    const file = resolve(o.linux ?? join(root, o.channel === 'debug' ? 'dist/linux-debug/OverhaulDebug.love' : 'dist/linux/Overhaul.love'));
    jobs.push({ platform: 'linux', file, inner: 'globals.lua', name: basename(file), type: 'application/zip' });
  }
  if (wanted.has('android')) {
    const file = o.android ? resolve(o.android) : newestApk();
    if (!file) throw new Error('no dist/Balatro_V2.N.apk found, run ./build.sh first');
    jobs.push({ platform: 'android', file, inner: 'assets/globals.lua', name: '', type: 'application/vnd.android.package-archive' });
  }
  for (const j of jobs) if (!existsSync(j.file)) throw new Error(`${j.file} is missing, build it first`);

  const current = parseManifest(await client.file(`${prefix}latest.json`).exists() ? await client.file(`${prefix}latest.json`).json() : null);
  const builds: Record<string, BuildEntry> = { ...(current?.builds ?? {}) };
  const found: { platform: string; version: string; protocol: number; name?: string }[] = [];
  for (const j of jobs) {
    const v = await gameVersion(j.file, j.inner);
    found.push({ platform: j.platform, ...v });
    const old = current?.builds[j.platform];
    if (old && compareVersions(v.version, old.version) <= 0 && !o.force) {
      throw new Error(`${j.platform} build is V ${v.version} but V ${old.version} is already released. Bump OVERHAUL_VERSION in assets/globals.lua and rebuild (or pass --force).`);
    }
  }
  if (new Set(found.map(f => `${f.version}/${f.protocol}`)).size > 1) {
    throw new Error(`builds disagree: ${found.map(f => `${f.platform} V ${f.version} protocol ${f.protocol}`).join(', ')}. Rebuild both from the same commit.`);
  }

  for (const j of jobs) {
    const v = found.find(f => f.platform === j.platform)!;
    const name = j.platform === 'android' ? `Balatro_Overhaul_${v.version}.apk` : j.name;
    const key = `${prefix}builds/${v.version}/${name}`;
    const size = Bun.file(j.file).size;
    console.log(`${j.platform}: V ${v.version} (protocol ${v.protocol}), ${mb(size)}, hashing...`);
    const hash = await sha256(j.file);
    console.log(`  sha256 ${hash}`);
    if (!o.dryRun) await upload(client, key, j.file, j.type, name);
    builds[j.platform] = { key, file: name, version: v.version, protocol: v.protocol, size, sha256: hash, ...(v.name ? { name: v.name } : {}) };
  }

  const version = Object.values(builds).map(b => b.version).sort(compareVersions).pop()!;
  const manifest: Manifest = { version, released: Date.now(), builds };
  if (o.dryRun) { console.log('dry run, would write', JSON.stringify(manifest, null, 2)); return; }
  await client.file(`${prefix}latest.json`).write(JSON.stringify(manifest, null, 2), { type: 'application/json' });
  console.log(`${prefix}latest.json now points at V ${version}`);

  const keys = await listKeys(client, `${prefix}builds/`);
  const versionOf = (k: string) => k.slice(`${prefix}builds/`.length).split('/')[0];
  const live = new Set(Object.values(builds).map(b => b.version));
  const keep = new Set([...new Set(keys.map(versionOf))].sort(compareVersions).slice(-KEEP));
  for (const v of live) keep.add(v);
  for (const k of keys) {
    if (keep.has(versionOf(k))) continue;
    await client.delete(k);
    console.log(`  removed old ${k}`);
  }
  console.log(`Kept releases: ${[...keep].sort(compareVersions).map(v => `V ${v}`).join(', ')}`);
}

main().catch(err => { console.error(`release failed: ${err instanceof Error ? err.message : String(err)}`); process.exit(1); });

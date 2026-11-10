import { describe, it, expect, afterAll } from 'bun:test';
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync, existsSync, rmSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { $ } from 'bun';
import { ReleaseService, DirReleaseStore, UpdateService, parseManifest, parseFeed, releaseFromEnv, RELEASE_PER_IP_PER_MIN, MANIFEST_TTL_MS, LINK_SECONDS, type ReleaseStore } from './updates';
import { startServer, setRelease } from './index';
import { publish, parseArgs, type PublishOpts } from '../../tools/release/publish_feed';

const SHA = 'ab'.repeat(32);
const feedRaw = {
  format: 1,
  latest: { version: '2.6', game_version: '1.0.1o-FULL', url: 'patchset-2.6.zip', size: 9478986, sha256: SHA, patch_format: 1, changelog: { en: 'New', fr: 'Nouveau', es: 'Nuevo' } },
  page: 'https://example.com/overhaul',
};

function fakeStore(data: unknown = feedRaw) {
  const s = {
    reads: [] as string[], downloads: [] as string[], data, fail: false,
    async readJson(key: string) { s.reads.push(key); if (s.fail) throw new Error('down'); return key.endsWith('release/feed.json') ? s.data : null; },
    async download(key: string) { s.downloads.push(key); return new Response(null, { status: 302, headers: { Location: `https://r2.example/${key}?X-Amz-Expires=${LINK_SECONDS}` } }); },
  };
  return s satisfies ReleaseStore & Record<string, unknown>;
}

const req = (svc: ReleaseService, path: string, ip = '1.2.3.4', method = 'GET') => svc.handle(new Request(`http://x${path}`, { method }), ip);

describe('parseFeed', () => {
  it('keeps a good feed and points the url at the server route', () => {
    const f = parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, url: 'https://elsewhere.example/x.zip' } })!;
    expect(f.latest.url).toBe('patchset-2.6.zip');
    expect(f.latest.version).toBe('2.6');
    expect(f.latest.min_launcher).toBe(1);
    expect(f.latest.changelog).toEqual({ en: 'New', fr: 'Nouveau', es: 'Nuevo' });
    expect(f.page).toBe('https://example.com/overhaul');
  });

  it('refuses a bad version, hash, size or format', () => {
    expect(parseFeed(null)).toBeNull();
    expect(parseFeed({ ...feedRaw, format: 2 })).toBeNull();
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, version: '../2.6' } })).toBeNull();
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, sha256: 'nothex' } })).toBeNull();
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, size: 0 } })).toBeNull();
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, patch_format: 'x' } })).toBeNull();
  });

  it('turns min_launcher into the patch_format old launchers read', () => {
    const f = parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, min_launcher: 2 } })!;
    expect(f.latest.patch_format).toBe(2);
    expect(f.latest.min_launcher).toBe(2);
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, sha256: SHA.toUpperCase() } })!.latest.sha256).toBe(SHA);
  });

  it('drops a page that is not a web link', () => {
    expect(parseFeed({ ...feedRaw, page: 'javascript:alert(1)' })!.page).toBeUndefined();
  });

  it('keeps the display name next to the build number', () => {
    const f = parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, version: '30', url: 'patchset-30.zip', name: '2.0 (pre-release)' } })!;
    expect(f.latest.version).toBe('30');
    expect(f.latest.url).toBe('patchset-30.zip');
    expect(f.latest.name).toBe('2.0 (pre-release)');
    expect(parseFeed(feedRaw)!.latest.name).toBeUndefined();
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, name: 'x'.repeat(41) } })!.latest.name).toBeUndefined();
    expect(parseFeed({ ...feedRaw, latest: { ...feedRaw.latest, name: 'a\nb' } })!.latest.name).toBeUndefined();
  });
});

describe('ReleaseService', () => {
  it('answers 404 without a store or a feed', async () => {
    expect((await req(new ReleaseService(null), '/release/feed.json')).status).toBe(404);
    expect((await req(new ReleaseService(fakeStore(null)), '/release/feed.json')).status).toBe(404);
    expect((await req(new ReleaseService(fakeStore({ format: 1 })), '/release/feed.json')).status).toBe(404);
  });

  it('serves the feed under the channel prefix and caches it', async () => {
    let now = 1_000_000;
    const s = fakeStore();
    const svc = new ReleaseService(s, 'debug/', () => now);
    const r = await req(svc, '/release/feed.json');
    expect(r.status).toBe(200);
    expect(r.headers.get('cache-control')).toBe('no-store');
    const body = await r.json() as Record<string, any>;
    expect(body.format).toBe(1);
    expect(body.latest.url).toBe('patchset-2.6.zip');
    await req(svc, '/release/feed.json');
    expect(s.reads).toEqual(['debug/release/feed.json']);
    now += MANIFEST_TTL_MS + 1;
    await req(svc, '/release/feed.json');
    expect(s.reads.length).toBe(2);
  });

  it('keeps the last good feed when the store fails', async () => {
    let now = 1_000_000;
    const s = fakeStore();
    const svc = new ReleaseService(s, '', () => now);
    expect((await req(svc, '/release/feed.json')).status).toBe(200);
    s.fail = true;
    now += MANIFEST_TTL_MS + 1;
    expect((await req(svc, '/release/feed.json')).status).toBe(200);
  });

  it('redirects a patch set download and refuses other paths', async () => {
    const s = fakeStore();
    const svc = new ReleaseService(s);
    const r = await req(svc, '/release/patchset-2.6.zip');
    expect(r.status).toBe(302);
    expect(r.headers.get('location')).toContain('release/patchset-2.6.zip');
    expect(s.downloads).toEqual(['release/patchset-2.6.zip']);
    expect((await req(svc, '/release/patchset-../../latest.json.zip')).status).toBe(404);
    expect((await req(svc, '/release/latest.json')).status).toBe(404);
    expect((await req(svc, '/release/feed.json', '1.2.3.4', 'POST')).status).toBe(405);
    expect((await req(svc, '/release/feed.json', '1.2.3.4', 'HEAD')).status).toBe(200);
  });

  it('rate limits per ip', async () => {
    const svc = new ReleaseService(fakeStore());
    for (let i = 0; i < RELEASE_PER_IP_PER_MIN; i++) expect((await req(svc, '/release/feed.json', '9.9.9.9')).status).toBe(200);
    expect((await req(svc, '/release/feed.json', '9.9.9.9')).status).toBe(429);
    expect((await req(svc, '/release/feed.json', '8.8.8.8')).status).toBe(200);
  });

  it('picks the store from the environment', () => {
    expect(releaseFromEnv({}).configured).toBe(false);
    expect(releaseFromEnv({ RELEASE_DIR: '/tmp/x' }).configured).toBe(true);
    expect(releaseFromEnv({ CF_ACCOUNT_ID: 'a', R2_ACCESS_KEY_ID: 'b', R2_SECRET_ACCESS_KEY: 'c', R2_BUCKET: 'd' }).configured).toBe(true);
  });
});

const work = mkdtempSync(join(tmpdir(), 'release-feed-'));
afterAll(() => rmSync(work, { recursive: true, force: true }));

async function pack(dir: string, version: string, extra: Record<string, unknown> = {}): Promise<string> {
  mkdirSync(join(dir, 'set'), { recursive: true });
  writeFileSync(join(dir, 'set', 'manifest.lua'), `return {\n  format = 1,\n  overhaul_version = "${version}",\n  game_version = "1.0.1o-FULL",\n}\n`);
  writeFileSync(join(dir, 'set', 'globals.lua'), `OVERHAUL_VERSION = '${version}'\n`);
  const zip = join(dir, `patchset-${version}.zip`);
  rmSync(zip, { force: true });
  await $`cd ${join(dir, 'set')} && zip -q -X ${zip} manifest.lua globals.lua`.quiet();
  const data = await Bun.file(zip).arrayBuffer();
  const sha = new Bun.CryptoHasher('sha256').update(data).digest('hex');
  writeFileSync(join(dir, 'feed.json'), JSON.stringify({ format: 1, latest: { version, game_version: '1.0.1o-FULL', url: `patchset-${version}.zip`, size: data.byteLength, sha256: sha, patch_format: 1, ...extra } }));
  return zip;
}

function opts(from: string, to: string, more: Partial<PublishOpts> = {}): PublishOpts {
  return { ...parseArgs(['--from', from, '--to', to], {}), say: () => undefined, ...more };
}

describe('publishing a release (tools/release/publish_feed.ts)', () => {
  const pub = join(work, 'pub');

  it('publishes a packed patch set to a folder', async () => {
    await pack(join(work, 'a'), '2.6');
    const f = await publish(opts(join(work, 'a'), pub));
    expect(f.latest.version).toBe('2.6');
    expect(readdirSync(pub).sort()).toEqual(['feed.json', 'patchset-2.6.zip']);
  });

  it('refuses the same or an older version unless forced', async () => {
    await expect(publish(opts(join(work, 'a'), pub))).rejects.toThrow(/not newer than the published 2.6/);
    await pack(join(work, 'old'), '2.5');
    await expect(publish(opts(join(work, 'old'), pub))).rejects.toThrow(/not newer/);
    await publish(opts(join(work, 'a'), pub, { force: true }));
  });

  it('refuses a zip that does not match feed.json', async () => {
    const dir = join(work, 'bad');
    const zip = await pack(dir, '2.7');
    const d = new Uint8Array(await Bun.file(zip).arrayBuffer());
    d[10] ^= 0xff;
    writeFileSync(zip, d);
    await expect(publish(opts(dir, pub))).rejects.toThrow(/sha256/);
    await pack(dir, '2.7');
    const raw = await Bun.file(join(dir, 'feed.json')).json() as Record<string, any>;
    raw.latest.size += 1;
    writeFileSync(join(dir, 'feed.json'), JSON.stringify(raw));
    await expect(publish(opts(dir, pub))).rejects.toThrow(/bytes but feed.json says/);
    await pack(dir, '2.7');
    raw.latest = { ...(await Bun.file(join(dir, 'feed.json')).json() as Record<string, any>).latest, version: '2.8', url: 'patchset-2.7.zip' };
    writeFileSync(join(dir, 'feed.json'), JSON.stringify(raw));
    await expect(publish(opts(dir, pub))).rejects.toThrow(/holds Overhaul 2.7, feed.json says 2.8/);
    expect(readdirSync(pub).sort()).toEqual(['feed.json', 'patchset-2.6.zip']);
  });

  it('keeps the last two patch sets and sets the minimum launcher', async () => {
    await pack(join(work, 'b'), '2.7');
    await publish(opts(join(work, 'b'), pub));
    await pack(join(work, 'c'), '2.8');
    const f = await publish(opts(join(work, 'c'), pub, { minLauncher: 2 }));
    expect(f.latest.patch_format).toBe(2);
    expect(readdirSync(pub).sort()).toEqual(['feed.json', 'patchset-2.7.zip', 'patchset-2.8.zip']);
  });

  it('dry run writes nothing', async () => {
    await pack(join(work, 'd'), '2.9');
    await publish(opts(join(work, 'd'), pub, { dryRun: true }));
    expect(existsSync(join(pub, 'patchset-2.9.zip'))).toBe(false);
    await publish({ ...opts(join(work, 'd'), 'r2'), to: 'r2', dryRun: true });
    await expect(publish({ ...opts(join(work, 'd'), 'r2'), to: 'r2' })).rejects.toThrow(/R2_ACCOUNT_ID/);
  });

  it('publishes the phone patches into latest.json for in-game updates', async () => {
    const dir = join(work, 'phone');
    const pc = await pack(dir, '3.1');
    mkdirSync(join(dir, 'android'), { recursive: true });
    copyFileSync(pc, join(dir, 'android', 'android-patch-3.1.zip'));
    const to = join(work, 'pub_phone');
    await publish(opts(dir, to, { globals: "OVERHAUL_VERSION = '3.1'\nOVERHAUL_NAME = '3 test'\nMP_PROTOCOL_VERSION = 7\n" }));
    const m = parseManifest(await Bun.file(join(to, 'latest.json')).json())!;
    expect(m.version).toBe('3.1');
    expect(Object.keys(m.builds).sort()).toEqual(['android_patch', 'android_patch_pc']);
    expect(m.builds.android_patch.key).toBe('builds/3.1/android-patch-3.1.zip');
    expect(m.builds.android_patch_pc.protocol).toBe(7);
    expect(m.builds.android_patch_pc.name).toBe('3 test');
    expect(existsSync(join(to, m.builds.android_patch.key))).toBe(true);
    const svc = new UpdateService({ readJson: async () => Bun.file(join(to, 'latest.json')).json(), presign: k => `https://r2.example/${k}` });
    const r = await svc.handle(new Request('http://x/version?platform=android_patch&link=1'), '1.1.1.1');
    const body = await r.json() as Record<string, any>;
    expect(body.build.version).toBe('3.1');
    expect(body.build.url).toBe('https://r2.example/builds/3.1/android-patch-3.1.zip');
    await pack(dir, '3.2');
    rmSync(join(dir, 'android'), { recursive: true });
    await publish(opts(dir, to, { globals: "OVERHAUL_VERSION = '3.2'\nMP_PROTOCOL_VERSION = 7\n" }));
    const m2 = parseManifest(await Bun.file(join(to, 'latest.json')).json())!;
    expect(m2.builds.android_patch_pc.version).toBe('3.2');
    expect(m2.builds.android_patch.version).toBe('3.1');
  });

  it('skips the phone patches when globals.lua is another build', async () => {
    const dir = join(work, 'phone_skip');
    await pack(dir, '4.0');
    const to = join(work, 'pub_skip');
    await publish(opts(dir, to, { globals: "OVERHAUL_VERSION = '3.9'\n" }));
    expect(existsSync(join(to, 'latest.json'))).toBe(false);
  });

  it('the server serves what was published', async () => {
    const server = startServer(0);
    try {
      setRelease(new ReleaseService(new DirReleaseStore(pub)));
      const base = `http://127.0.0.1:${server.port}`;
      const r = await fetch(`${base}/release/feed.json`);
      expect(r.status).toBe(200);
      const feed = await r.json() as Record<string, any>;
      expect(feed.latest.version).toBe('2.8');
      const z = await fetch(new URL(feed.latest.url, `${base}/release/feed.json`));
      expect(z.status).toBe(200);
      const body = await z.arrayBuffer();
      expect(body.byteLength).toBe(feed.latest.size);
      expect(new Bun.CryptoHasher('sha256').update(body).digest('hex')).toBe(feed.latest.sha256);
      expect((await fetch(`${base}/release/patchset-2.6.zip`)).status).toBe(404);
      expect((await fetch(`${base}/release/patchset-2.7.zip`)).status).toBe(200);
      expect((await fetch(`${base}/ping`)).status).toBe(200);
    } finally {
      setRelease(new ReleaseService(null));
      server.stop(true);
    }
  });
});

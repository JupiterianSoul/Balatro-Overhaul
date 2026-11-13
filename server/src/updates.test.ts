import { describe, it, expect, afterAll } from 'bun:test';
import { UpdateService, compareVersions, parseManifest, versionNameOf, VERSION_PER_IP_PER_MIN, MANIFEST_TTL_MS, LINK_SECONDS, type UpdateBucket } from './updates';
import { startServer, setUpdates } from './index';

const SHA = 'a'.repeat(64);
const manifest = {
  version: '2.5', released: 1761800000000,
  builds: {
    android: { key: 'builds/2.5/Balatro_Overhaul_2.5.apk', file: 'Balatro_Overhaul_2.5.apk', version: '2.5', protocol: 10, size: 320000000, sha256: SHA },
    linux: { key: 'builds/2.5/Overhaul.love', file: 'Overhaul.love', version: '2.5', protocol: 10, size: 307000000, sha256: 'b'.repeat(64) },
  },
};

function fakeBucket(data: unknown = manifest) {
  const b = {
    reads: 0, links: [] as string[], data, fail: false,
    async readJson(key: string) { b.reads++; if (b.fail) throw new Error('down'); return key.endsWith('latest.json') ? b.data : null; },
    presign(key: string, seconds: number) { b.links.push(key); return `https://r2.example/${key}?X-Amz-Expires=${seconds}`; },
  };
  return b satisfies UpdateBucket & Record<string, unknown>;
}

const get = (svc: UpdateService, q = '', ip = '1.2.3.4') => svc.handle(new Request(`http://x/version${q}`), ip).then(async r => ({ status: r.status, body: await r.json() as Record<string, any> }));

describe('compareVersions', () => {
  it('compares numerically per part', () => {
    expect(compareVersions('2.10', '2.9')).toBe(1);
    expect(compareVersions('2.4', '2.4.0')).toBe(0);
    expect(compareVersions('2.4', '2.5')).toBe(-1);
    expect(compareVersions('3', '2.99')).toBe(1);
  });

  it('puts the 2.0 build number above every 2.x install', () => {
    for (const old of ['2.5', '2.6', '2.7', '2.99']) expect(compareVersions('30', old)).toBe(1);
    expect(compareVersions('31', '30')).toBe(1);
    expect(compareVersions('30', '30')).toBe(0);
  });
});

describe('versionNameOf', () => {
  it('names a build from the release manifest and nothing else', async () => {
    const named = { ...manifest, version: '40', builds: { android_patch: { key: 'builds/40/p.zip', file: 'p.zip', version: '40', protocol: 10, size: 5, sha256: SHA, name: '2.0 (pre-release)' } } };
    const svc = new UpdateService(fakeBucket(named));
    expect(versionNameOf('40')).toBeUndefined();
    await svc.manifest();
    expect(versionNameOf('40')).toBe('2.0 (pre-release)');
    expect(versionNameOf('39')).toBeUndefined();
    expect(versionNameOf('')).toBeUndefined();
  });
});

describe('parseManifest', () => {
  it('drops builds with a bad hash, key or version', () => {
    const m = parseManifest({ ...manifest, builds: { ...manifest.builds, windows: { key: 'x', version: '2.5', size: 1, sha256: 'nothex' } } });
    expect(Object.keys(m!.builds).sort()).toEqual(['android', 'linux']);
    expect(parseManifest({ version: 'abc' })).toBeNull();
    expect(parseManifest(null)).toBeNull();
  });

  it('keeps the Android patch set feeds next to the APK', () => {
    const patch = { key: 'builds/2.6/patch-mobile.zip', version: '2.6', size: 21000000, sha256: 'c'.repeat(64) };
    const m = parseManifest({ ...manifest, builds: { ...manifest.builds, android_patch: patch, android_patch_pc: { ...patch, key: 'builds/2.6/patch-pc.zip' } } });
    expect(Object.keys(m!.builds).sort()).toEqual(['android', 'android_patch', 'android_patch_pc', 'linux']);
    expect(m!.builds.android_patch.file).toBe('patch-mobile.zip');
  });
});

describe('UpdateService', () => {
  it('passes the display name of a build through', async () => {
    const named = { version: '30', released: 1, builds: { linux: { key: 'builds/30/Overhaul.love', file: 'Overhaul.love', version: '30', name: '2.0 (pre-release)', protocol: 10, size: 5, sha256: SHA } } };
    const svc = new UpdateService(fakeBucket(named));
    expect((await get(svc, '?platform=linux')).body.build.name).toBe('2.0 (pre-release)');
    expect((await get(svc)).body.builds.linux.name).toBe('2.0 (pre-release)');
    expect((await get(new UpdateService(fakeBucket()), '?platform=linux')).body.build.name).toBeUndefined();
  });

  it('answers version null without a bucket or a manifest', async () => {
    expect((await get(new UpdateService(null))).body).toEqual({ version: null });
    expect((await get(new UpdateService(fakeBucket(null)), '?platform=linux')).body).toEqual({ version: null });
  });

  it('lists builds without links', async () => {
    const r = await get(new UpdateService(fakeBucket()));
    expect(r.body.version).toBe('2.5');
    expect(r.body.builds.android).toEqual({ version: '2.5', protocol: 10, size: 320000000, sha256: SHA });
    expect(JSON.stringify(r.body)).not.toContain('https://');
  });

  it('gives a presigned link only when asked for one platform', async () => {
    const b = fakeBucket();
    const svc = new UpdateService(b, 'debug/');
    const plain = await get(svc, '?platform=android');
    expect(plain.body.build.url).toBeUndefined();
    const linked = await get(svc, '?platform=android&link=1');
    expect(linked.body.build.url).toBe(`https://r2.example/builds/2.5/Balatro_Overhaul_2.5.apk?X-Amz-Expires=${LINK_SECONDS}`);
    expect(linked.body.build.sha256).toBe(SHA);
    expect(b.links).toEqual(['builds/2.5/Balatro_Overhaul_2.5.apk']);
    expect((await get(svc, '?platform=windows&link=1')).body).toEqual({ version: '2.5', platform: 'windows', build: null });
  });

  it('reads the manifest under the channel prefix and caches it', async () => {
    let t = 1000;
    const keys: string[] = [];
    const b = { readJson: async (k: string) => { keys.push(k); return manifest; }, presign: () => '' };
    const svc = new UpdateService(b, 'debug/', () => t);
    await Promise.all([svc.manifest(), svc.manifest()]);
    await svc.manifest();
    expect(keys).toEqual(['debug/latest.json']);
    t += MANIFEST_TTL_MS + 1;
    await svc.manifest();
    expect(keys.length).toBe(2);
  });

  it('keeps the last good manifest when R2 fails', async () => {
    let t = 0;
    const b = fakeBucket();
    const svc = new UpdateService(b, '', () => t);
    expect((await svc.manifest())?.version).toBe('2.5');
    b.fail = true;
    t += MANIFEST_TTL_MS + 1;
    expect((await svc.manifest())?.version).toBe('2.5');
  });

  it('rate limits per ip', async () => {
    const svc = new UpdateService(fakeBucket(), '', () => 5000);
    for (let i = 0; i < VERSION_PER_IP_PER_MIN; i++) expect((await get(svc, '', '9.9.9.9')).status).toBe(200);
    expect((await get(svc, '', '9.9.9.9')).status).toBe(429);
    expect((await get(svc, '', '8.8.8.8')).status).toBe(200);
  });
});

describe('GET /version on the server', () => {
  const server = startServer(0);
  afterAll(() => server.stop(true));

  it('serves the update service', async () => {
    setUpdates(new UpdateService(fakeBucket()));
    const r = await fetch(`http://127.0.0.1:${server.port}/version?platform=linux`);
    expect(r.status).toBe(200);
    expect(r.headers.get('cache-control')).toBe('no-store');
    const body = await r.json() as Record<string, any>;
    expect(body.build.version).toBe('2.5');
    expect(body.build.file).toBe('Overhaul.love');
  });
});

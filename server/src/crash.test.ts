import { describe, it, expect, beforeEach, afterAll } from 'bun:test';
import {
  crashSignature,
  scrubReport,
  recordCrash,
  resetCrashState,
  setCrashStorePath,
  setCrashFetcher,
  syncIssue,
  handleCrashRequest,
  crashGroups,
  crashFields,
  issueBody,
  parseIssueCounts,
  CRASH_MAX_BYTES,
  CRASH_PER_IP_PER_HOUR,
} from './crash';
import { startServer } from './index';

const report = (msg: string, line = 147, user = 'gabriel') => [
  'Balatro Overhaul crash report',
  'Date: 2026-10-26 01:41:02',
  'Overhaul version: 2.1',
  'Platform: Linux',
  'Session: modded',
  'Enabled mods:',
  '  Cryptid 0.5.5',
  '  Amulet 1.0',
  '',
  'Error:',
  msg,
  '',
  'Stack Traceback',
  '===============',
  `(3) Lua method 'calculate_xywh' at file 'engine/ui.lua:${line}'`,
  `(4) Lua method 'init' at file 'engine/ui.lua:60'`,
  `(5) Lua field 'func' at file '/home/${user}/.local/share/love/game/mods/Cryptid/items/deck.lua:12'`,
].join('\n');

setCrashStorePath(null);
const post = (body: unknown, ip = '1.2.3.4') =>
  handleCrashRequest(new Request('http://x/crash', { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body) }), ip);

const ctx = (id: string) => [
  '',
  `Report id: ${id}`,
  'Build: 31 (version 2.7)',
  'OS: Linux (Arch Linux), 8 cores, llvmpipe 4.6',
  'Mode: RUN, SELECTING_HAND, deck Red Deck, stake 1, ante 2, normal',
  'Screen: 1280x720 desktop, UI size 100%, picture 1',
  '',
  'Last actions:',
  '     12.0 button play_cards_from_highlighted',
  '     12.4 state RUN HAND_PLAYED',
  '',
  'Log tail:',
  '  [MP] connected',
  '  scoring hand',
].join('\n');

beforeEach(() => {
  resetCrashState();
  delete process.env.GITHUB_TOKEN;
  delete process.env.CRASH_GITHUB_TOKEN;
  delete process.env.CRASH_GITHUB_API;
});

describe('crash signature', () => {
  it('groups the same error with different numbers and users', () => {
    const a = crashSignature(scrubReport(report("engine/ui.lua:147: bad argument #1 to 'getWidth' (table: 0x7f81a)")));
    const b = crashSignature(scrubReport(report("engine/ui.lua:147: bad argument #1 to 'getWidth' (table: 0x99)", 147, 'someone')));
    expect(a.signature).toBe(b.signature);
    expect(a.frames[0]).toBe('engine/ui.lua:147');
  });
  it('splits different errors', () => {
    const a = crashSignature(report('attempt to index a nil value'));
    const b = crashSignature(report('attempt to call a nil value'));
    expect(a.signature).not.toBe(b.signature);
  });
});

describe('scrubbing', () => {
  it('removes user names, emails, ips and tokens', () => {
    const s = scrubReport('C:\\Users\\Gabriel\\AppData /home/gabriel/x me@mail.com 192.168.1.4 ghp_abcdefghijklmnop1234');
    expect(s).not.toContain('Gabriel');
    expect(s).not.toContain('gabriel');
    expect(s).not.toContain('me@mail.com');
    expect(s).not.toContain('192.168.1.4');
    expect(s).not.toContain('ghp_abcdefghijklmnop1234');
  });
});

describe('POST /crash', () => {
  it('stores and counts a group', async () => {
    const r1 = await post({ v: 1, version: '2.1', platform: 'Linux', modded: true, report: report('boom 1') });
    expect(r1.status).toBe(200);
    const r2 = await post({ v: 1, version: '2.1', platform: 'Windows', modded: true, report: report('boom 2') }, '5.6.7.8');
    const j2 = (await r2.json()) as { count: number };
    expect(j2.count).toBe(2);
    const g = crashGroups()[0]!;
    expect(g.platforms).toEqual({ Linux: 1, Windows: 1 });
    expect(Object.keys(g.modSets)[0]).toBe('Cryptid 0.5.5, Amulet 1.0');
    expect(g.sample).not.toContain('gabriel');
  });
  it('rejects bad bodies and big bodies', async () => {
    expect((await post('not json')).status).toBe(400);
    expect((await post({ report: 'x' })).status).toBe(400);
    expect((await post({ report: 'y'.repeat(CRASH_MAX_BYTES + 10) })).status).toBe(413);
  });
  it('rate limits one address', async () => {
    for (let i = 0; i < CRASH_PER_IP_PER_HOUR; i++) expect((await post({ report: report('rl ' + i) }, '9.9.9.9')).status).toBe(200);
    expect((await post({ report: report('rl x') }, '9.9.9.9')).status).toBe(429);
    expect((await post({ report: report('rl y') }, '9.9.9.10')).status).toBe(200);
  });
});

describe('GitHub issues', () => {
  it('does nothing without GITHUB_TOKEN', async () => {
    let calls = 0;
    setCrashFetcher(async () => { calls++; return new Response('{}'); });
    const g = recordCrash({ report: report('no token') });
    expect(await syncIssue(g)).toBe('skipped');
    expect(calls).toBe(0);
  });
  it('creates then updates one issue per group', async () => {
    process.env.GITHUB_TOKEN = 'test-token';
    const seen: { url: string; method: string; body: string }[] = [];
    setCrashFetcher(async (url, init) => {
      seen.push({ url, method: String(init?.method), body: String(init?.body) });
      return new Response(JSON.stringify({ number: 42 }), { status: 201 });
    });
    const g = recordCrash({ report: report('issue test') });
    expect(await syncIssue(g, 1000)).toBe('created');
    expect(seen[0]!.method).toBe('GET');
    expect(seen[0]!.url).toContain('/search/issues?q=');
    expect(seen[1]!.method).toBe('POST');
    expect(JSON.parse(seen[1]!.body).labels).toEqual(['crash']);
    recordCrash({ report: report('issue test') });
    expect(await syncIssue(g, 2000)).toBe('skipped');
    expect(await syncIssue(g, 2000 + 11 * 60 * 1000)).toBe('updated');
    expect(seen[2]!.url).toEndWith('/issues/42');
    expect(JSON.parse(seen[2]!.body).body).toContain('| Seen | **2** times by **0** players |');
  });
  it('adopts an issue that already exists for the signature and keeps its counts', async () => {
    process.env.CRASH_GITHUB_TOKEN = 'test-token';
    process.env.CRASH_GITHUB_API = 'http://fake-github.local/';
    const seen: { url: string; method: string; body: string }[] = [];
    const g = recordCrash({ report: report('adopt test'), player: 'aaaa1111bbbb2222' });
    setCrashFetcher(async (url, init) => {
      seen.push({ url, method: String(init?.method), body: String(init?.body) });
      if (url.includes('/search/issues')) {
        return new Response(JSON.stringify({ items: [{ number: 7, title: `Crash: x [${g.signature}]`, body: '| Seen | **5** times by **3** players |' }] }));
      }
      return new Response('{}', { status: 200 });
    });
    expect(await syncIssue(g, 1000)).toBe('updated');
    expect(seen[0]!.url).toStartWith('http://fake-github.local/search/issues');
    expect(seen[1]!.url).toBe('http://fake-github.local/repos/JupiterianSoul/Balatro-Overhaul-Source/issues/7');
    expect(seen[1]!.method).toBe('PATCH');
    expect(JSON.parse(seen[1]!.body).body).toContain('| Seen | **6** times by **4** players |');
  });
});

describe('issue template', () => {
  it('reads every field of a report', () => {
    const f = crashFields(report('template test') + ctx('abc123'), { version: '2.7', platform: 'Linux' });
    expect(f.build).toBe('31 (version 2.7)');
    expect(f.os).toContain('Arch Linux');
    expect(f.mode).toContain('SELECTING_HAND');
    expect(f.screen).toContain('1280x720');
    expect(f.error).toBe('template test');
    expect(f.stack).toContain("engine/ui.lua:147");
    expect(f.stack).not.toContain('Last actions');
    expect(f.actions).toContain('play_cards_from_highlighted');
    expect(f.log).toBe('[MP] connected\nscoring hand');
  });
  it('writes the fixed sections in order', () => {
    const g = recordCrash({ version: '2.7', platform: 'Linux', report: report('order test') + ctx('ord1'), player: 'aaaa1111bbbb2222' });
    const body = issueBody(g);
    const heads = ['| Seen |', '| Version |', '| Build |', '| Platform |', '| OS |', '| Mode |', '| Screen |', '### Error', '### Stack', '### Last actions', '### Log tail'];
    let at = -1;
    for (const h of heads) {
      const i = body.indexOf(h);
      expect(i).toBeGreaterThan(at);
      at = i;
    }
    expect(parseIssueCounts(body)).toEqual({ count: 1, players: 1 });
  });
  it('counts players once and drops a report sent twice', async () => {
    const one = await post({ report: report('dup test') + ctx('r1'), player: 'aaaa1111bbbb2222' });
    expect(((await one.json()) as { players: number }).players).toBe(1);
    const again = await post({ report: report('dup test') + ctx('r1'), player: 'aaaa1111bbbb2222' });
    expect(((await again.json()) as { duplicate: boolean }).duplicate).toBe(true);
    const two = await post({ report: report('dup test') + ctx('r2'), player: 'cccc3333dddd4444' }, '5.5.5.5');
    const j = (await two.json()) as { count: number; players: number };
    expect(j.count).toBe(2);
    expect(j.players).toBe(2);
    const three = await post({ report: report('dup test') + ctx('r3'), player: 'aaaa1111bbbb2222' }, '6.6.6.6');
    expect(((await three.json()) as { players: number }).players).toBe(2);
  });
});

describe('server route', () => {
  const srv = startServer(0);
  afterAll(() => srv.stop(true));
  it('answers POST /crash over HTTP', async () => {
    const res = await fetch(`http://127.0.0.1:${srv.port}/crash`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ report: report('route test') }),
    });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { ok: boolean }).ok).toBe(true);
  });
});

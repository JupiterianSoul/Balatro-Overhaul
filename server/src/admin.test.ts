import { describe, expect, test } from 'bun:test';
import { Database } from 'bun:sqlite';
import { AdminService, uaFamily, type AdminQuery, type LiveState } from './admin';

const TABLES = `
CREATE TABLE players (pkey TEXT PRIMARY KEY, name TEXT, rp INTEGER, rank INTEGER, peak_rp INTEGER, best_rank INTEGER, season TEXT, xp INTEGER, level INTEGER, packs INTEGER, streak INTEGER, recovery TEXT, created INTEGER, last_seen INTEGER, matches INTEGER, wins INTEGER);
CREATE TABLE social_players (pkey TEXT PRIMARY KEY, code TEXT, name TEXT, last_seen INTEGER);
CREATE TABLE social_links (pkey TEXT, other TEXT, status TEXT, at INTEGER, PRIMARY KEY (pkey, other));
CREATE TABLE matches (id TEXT PRIMARY KEY, mode TEXT, at INTEGER, season TEXT);
CREATE TABLE match_players (match_id TEXT, pkey TEXT, placement INTEGER, players INTEGER, result TEXT, ante INTEGER, score INTEGER, rp_delta INTEGER, xp INTEGER, bot_factor REAL, PRIMARY KEY (match_id, pkey));
CREATE TABLE match_logs (id TEXT PRIMARY KEY, at INTEGER, ended INTEGER, mode TEXT, kind TEXT, ranked INTEGER, status TEXT, keep_until INTEGER, has_replay INTEGER, bytes INTEGER, data TEXT);
CREATE TABLE match_log_players (id TEXT, pkey TEXT, pid INTEGER, at INTEGER, keep_until INTEGER, item TEXT, PRIMARY KEY (id, pkey));
CREATE TABLE chat_reports (id TEXT PRIMARY KEY, reporter TEXT, reported TEXT, kind TEXT, msg_id TEXT, text TEXT, context TEXT, reason TEXT, match_id TEXT, at INTEGER, status TEXT);
CREATE TABLE daily_board (day TEXT, pkey TEXT, sig TEXT, name TEXT, won INTEGER, ante INTEGER, round INTEGER, best REAL, at INTEGER, PRIMARY KEY (day, pkey));
CREATE TABLE minigame_best (pkey TEXT, game TEXT, score INTEGER, low INTEGER, at INTEGER, PRIMARY KEY (pkey, game));
CREATE TABLE forge_mods (id TEXT PRIMARY KEY, owner TEXT, name TEXT, author TEXT, about TEXT, version INTEGER, summary TEXT, size INTEGER, raw TEXT, at INTEGER, updated INTEGER, downloads INTEGER, reports TEXT, hidden INTEGER);
CREATE TABLE recent_players (pkey TEXT, other TEXT, name TEXT, mode TEXT, ranked INTEGER, at INTEGER, PRIMARY KEY (pkey, other));
CREATE TABLE head_to_head (pkey TEXT, other TEXT, wins INTEGER, losses INTEGER, draws INTEGER, at INTEGER, PRIMARY KEY (pkey, other));
CREATE TABLE speedruns (id TEXT, pkey TEXT, name TEXT, cat TEXT, deck TEXT, stake INTEGER, seed_type TEXT, seed TEXT, time REAL, splits TEXT, at INTEGER, v INTEGER, PRIMARY KEY (pkey, id));
CREATE TABLE unlocks (pkey TEXT, item TEXT, source TEXT, at INTEGER, PRIMARY KEY (pkey, item));
CREATE TABLE equipped (pkey TEXT, slot TEXT, item TEXT, PRIMARY KEY (pkey, slot));
CREATE TABLE data_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
`;

const T0 = Date.UTC(2026, 10, 13, 10, 30);
const SECRET_KEYS = ['pkey-alpha-secret', 'pkey-beta-secret', 'pkey-gamma-secret'];

function world(opts: { env?: string | null } = {}) {
  const db = new Database(':memory:');
  db.exec(TABLES);
  const ins = db.prepare('INSERT INTO players VALUES (?, ?, ?, 0, ?, 0, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)');
  ins.run(SECRET_KEYS[0], 'Alpha', 250, 300, '2026-Q4', 900, 5, 2, 'RECOVERY-ALPHA', T0 - 5 * 86_400_000, T0 - 60_000, 12, 8);
  ins.run(SECRET_KEYS[1], 'Beta', 40, 40, '2026-Q4', 100, 2, 0, 'RECOVERY-BETA', T0 - 3_600_000, T0 - 3 * 86_400_000, 1, 0);
  db.prepare('INSERT INTO social_players VALUES (?, ?, ?, ?)').run(SECRET_KEYS[0], 'AAAA-1111', 'Alpha', T0 - 30_000);
  db.prepare('INSERT INTO social_players VALUES (?, ?, ?, ?)').run(SECRET_KEYS[2], 'CCCC-3333', 'Gamma_100%', T0 - 9 * 86_400_000);
  db.prepare('INSERT INTO social_links VALUES (?, ?, ?, ?)').run(SECRET_KEYS[0], SECRET_KEYS[2], 'accepted', T0);
  db.prepare('INSERT INTO social_links VALUES (?, ?, ?, ?)').run(SECRET_KEYS[2], SECRET_KEYS[0], 'accepted', T0);
  db.prepare('INSERT INTO match_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').run('m1', T0 - 7_200_000, T0 - 7_000_000, 'nemesis', '1v1', 0, '', T0 + 1, 1, 100, '{}');
  db.prepare('INSERT INTO match_log_players VALUES (?, ?, ?, ?, ?, ?)').run('m1', SECRET_KEYS[0], 0, T0, T0, '{"won":true}');
  db.prepare('INSERT INTO match_log_players VALUES (?, ?, ?, ?, ?, ?)').run('m1', SECRET_KEYS[1], 1, T0, T0, '');
  db.prepare('INSERT INTO forge_mods VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').run('f1', SECRET_KEYS[0], 'Mod', 'Alpha', '[]', 1, '{"joker":2}', 2048, 'RAWDATA', T0, T0, 3, '', 0);
  const query: AdminQuery = async (sql, params = []) => {
    const st = db.prepare(sql);
    if (st.columnNames.length > 0) return st.all(...(params as never[])) as Record<string, unknown>[];
    st.run(...(params as never[]));
    return [];
  };
  const clock = { t: T0 };
  const live: LiveState = {
    sockets: [{ name: 'Alpha', pkey: SECRET_KEYS[0], version: 'V 2.0.5 b62', mods: [], room: 'ABCD', party: null, where: '', queue: false, rtt: 40, since: T0 - 120_000 },
      { name: '', pkey: '', version: '', mods: [], room: null, party: null, where: '', queue: false, rtt: null, since: T0 - 5000 }],
    rooms: [{ code: 'ABCD', visibility: 'public', ranked: false, quick: false, mode: 'nemesis', phase: 'playing', ante: 3, blind: 'Big', mods: 0, version: 'V 2.0.5 b62', created: T0 - 100_000, activity: T0,
      players: [{ name: 'Alpha', lives: 3, score: 100, status: 'active', here: true }, { name: 'Bot (bot)', lives: 2, score: 50, status: 'active', here: true }] }],
    bots: 1, conns: 2, peakConns: 4, totalConns: 9, matchesStarted: 3, roomsMade: 4,
  };
  const make = () => new AdminService({
    query: () => query, live: () => live, build: 'test', started: T0 - 3_600_000, memory: () => ({ totalMB: 120 }), d1: () => ({ rowsRead: 1 }),
    env: () => (opts.env === undefined ? 'open-sesame' : opts.env ?? undefined), now: () => clock.t,
  });
  return { db, query, clock, live, make, admin: make() };
}

async function get(admin: AdminService, path: string, token: string | null = 'open-sesame', ip = '203.0.113.7') {
  const url = new URL(`http://x${path}`);
  const headers: Record<string, string> = token === null ? {} : { Authorization: `Bearer ${token}` };
  const res = await admin.handle(new Request(url, { headers }), url, ip);
  const text = await res.text();
  let body: unknown = null;
  try {
    body = JSON.parse(text);
  } catch {
    body = null;
  }
  return { status: res.status, text, body: body as Record<string, any> };
}

describe('admin access', () => {
  test('everything is a 404 while no password exists', async () => {
    const w = world({ env: null });
    expect((await get(w.admin, '/admin')).status).toBe(404);
    expect((await get(w.admin, '/admin/api/overview')).status).toBe(404);
  });

  test('a password hash kept in the database opens it', async () => {
    const w = world({ env: null });
    const hash = new Bun.CryptoHasher('sha256').update('from-db').digest('hex');
    w.db.prepare('INSERT INTO data_meta VALUES (?, ?)').run('admin_token_sha256', hash);
    expect((await get(w.admin, '/admin/api/overview', 'from-db')).status).toBe(200);
    expect((await get(w.admin, '/admin/api/overview', 'other')).status).toBe(401);
  });

  test('missing and wrong passwords are refused, then slowed down', async () => {
    const w = world();
    expect((await get(w.admin, '/admin/api/overview', null)).status).toBe(401);
    for (let i = 0; i < 9; i++) expect((await get(w.admin, '/admin/api/overview', 'nope')).status).toBe(401);
    expect((await get(w.admin, '/admin/api/overview')).status).toBe(429);
    expect((await get(w.admin, '/admin/api/overview', 'open-sesame', '203.0.113.8')).status).toBe(200);
    w.clock.t += 11 * 60_000;
    expect((await get(w.admin, '/admin/api/overview')).status).toBe(200);
  });

  test('only GET is answered and the page is served', async () => {
    const w = world();
    const url = new URL('http://x/admin/api/overview');
    const res = await w.admin.handle(new Request(url, { method: 'POST', headers: { Authorization: 'Bearer open-sesame' } }), url, 'ip');
    expect(res.status).toBe(404);
    const page = await get(w.admin, '/admin', null);
    expect(page.status).toBe(200);
    expect(page.text).toContain('Overhaul Admin');
    expect((await get(w.admin, '/admin/manifest.webmanifest', null)).status).toBe(200);
    expect((await get(w.admin, '/admin/icon-192.png', null)).status).toBe(200);
    expect((await get(w.admin, '/admin/../secret', null)).status).toBe(404);
  });
});

describe('admin data', () => {
  test('no secret key, recovery code, address or raw mod data leaves the server', async () => {
    const w = world();
    w.admin.seen('198.51.100.23', 'check', 'android', 'BalatroOverhaul/62');
    await w.admin.sample();
    const paths = ['overview', 'online', 'players', 'stats', 'installs', 'matches', 'boards', 'forge', 'reports'];
    let all = '';
    for (const p of paths) {
      const r = await get(w.admin, `/admin/api/${p}`);
      expect(r.status).toBe(200);
      all += r.text;
    }
    const list = await get(w.admin, '/admin/api/players');
    for (const row of list.body.rows) all += (await get(w.admin, `/admin/api/player?id=${row.id}`)).text;
    for (const k of SECRET_KEYS) expect(all).not.toContain(k);
    expect(all).not.toContain('RECOVERY');
    expect(all).not.toContain('RAWDATA');
    expect(all).not.toContain('198.51.100.23');
    expect(all).not.toContain('203.0.113.7');
  });

  test('overview counts come from the tables and the live server', async () => {
    const w = world();
    const o = (await get(w.admin, '/admin/api/overview')).body;
    expect(o.live.connections).toBe(2);
    expect(o.live.named).toBe(1);
    expect(o.live.in_match).toBe(2);
    expect(o.db.total).toBe(3);
    expect(o.db.active_24h).toBe(1);
    expect(o.db.new_24h).toBe(1);
    expect(o.db.friend_links).toBe(1);
    expect(o.db.logged_24h).toBe(1);
  });

  test('players can be searched, filtered, sorted and paged', async () => {
    const w = world();
    const all = (await get(w.admin, '/admin/api/players?sort=rp')).body;
    expect(all.total).toBe(3);
    expect(all.rows[0].name).toBe('Alpha');
    expect(all.rows[0].online).toBe(true);
    expect(all.rows[0].rank_name).toBeString();
    expect((await get(w.admin, '/admin/api/players?q=bet')).body.rows.map((r: any) => r.name)).toEqual(['Beta']);
    expect((await get(w.admin, '/admin/api/players?q=CCCC')).body.rows.map((r: any) => r.name)).toEqual(['Gamma_100%']);
    expect((await get(w.admin, '/admin/api/players?q=100%25')).body.total).toBe(1);
    expect((await get(w.admin, '/admin/api/players?q=%25')).body.total).toBe(1);
    expect((await get(w.admin, '/admin/api/players?filter=gone')).body.rows.map((r: any) => r.name)).toEqual(['Gamma_100%']);
    expect((await get(w.admin, '/admin/api/players?filter=ranked')).body.total).toBe(2);
    expect((await get(w.admin, "/admin/api/players?sort=name;DROP TABLE players")).body.total).toBe(3);
    const asc = (await get(w.admin, '/admin/api/players?sort=name&dir=asc&size=10&page=0')).body;
    expect(asc.rows.map((r: any) => r.name)).toEqual(['Alpha', 'Beta', 'Gamma_100%']);
  });

  test('a player page shows the profile, matches and friends', async () => {
    const w = world();
    const id = (await get(w.admin, '/admin/api/players?q=Alpha')).body.rows[0].id;
    const p = (await get(w.admin, `/admin/api/player?id=${id}`)).body;
    expect(p.profile.name).toBe('Alpha');
    expect(p.online.room).toBe('ABCD');
    expect(p.logs[0].versus).toBe('Beta');
    expect(p.links[0].name).toBe('Gamma_100%');
    expect(p.forge_mods[0].name).toBe('Mod');
    expect((await get(w.admin, '/admin/api/player?id=unknown')).body.error).toBe('expired');
  });
});

describe('admin history', () => {
  test('hourly samples and daily counts are stored and survive a restart', async () => {
    const w = world();
    await w.admin.ensure();
    w.admin.seen('198.51.100.1', 'check', 'android', 'x');
    w.admin.seen('198.51.100.1', 'check', 'android', 'x');
    w.admin.seen('198.51.100.2', 'check', 'windows', 'x');
    w.admin.seen('198.51.100.2', 'patch', 'patchset-62.zip', 'x');
    await w.admin.sample();
    await w.admin.flush();
    const day = (await w.query('SELECT * FROM admin_days'))[0];
    expect(day.devices).toBe(2);
    expect(day.checks).toBe(3);
    expect(day.patch_dl).toBe(1);
    expect(day.players).toBe(1);
    expect(String(day.seen)).not.toContain('198.51');
    const hour = (await w.query('SELECT * FROM admin_hours'))[0];
    expect(hour.online_peak).toBe(2);
    expect(hour.playing_peak).toBe(2);

    const again = w.make();
    await again.ensure();
    again.seen('198.51.100.1', 'check', 'android', 'x');
    again.seen('198.51.100.3', 'check', 'android', 'x');
    const inst = (await get(again, '/admin/api/installs')).body;
    expect(inst.today.devices).toBe(3);
    expect(inst.today.checks).toBe(5);
    expect(inst.today.rows['check:android'].devices).toBe(2);
    expect(inst.today.rows['check:android'].requests).toBe(4);
    expect(inst.today.rows['patch:patchset-62.zip'].requests).toBe(1);
  });

  test('a new day starts a new count and forgets yesterday\'s devices', async () => {
    const w = world();
    await w.admin.ensure();
    w.admin.seen('198.51.100.1', 'check', 'android', 'x');
    await w.admin.sample();
    await w.admin.flush();
    w.clock.t += 86_400_000;
    w.admin.seen('198.51.100.1', 'check', 'android', 'x');
    await w.admin.sample();
    await w.admin.flush();
    const days = await w.query('SELECT day, devices, seen FROM admin_days ORDER BY day');
    expect(days.length).toBe(2);
    expect(days[0].devices).toBe(1);
    expect(days[1].devices).toBe(1);
    const fresh = w.make();
    await fresh.ensure();
    expect((await w.query('SELECT seen FROM admin_days ORDER BY day'))[0].seen).toBe('');
  });

  test('old samples are pruned', async () => {
    const w = world();
    await w.admin.ensure();
    await w.query('INSERT INTO admin_hours (h) VALUES (?)', [Math.floor((T0 - 100 * 86_400_000) / 3_600_000)]);
    await w.query('INSERT INTO admin_hours (h) VALUES (?)', [Math.floor((T0 - 10 * 86_400_000) / 3_600_000)]);
    await w.make().ensure();
    expect((await w.query('SELECT COUNT(*) n FROM admin_hours'))[0].n).toBe(1);
  });

  test('client families', () => {
    expect(uaFamily('')).toBe('none');
    expect(uaFamily('BalatroOverhaulLauncher/2.0.5')).toBe('launcher');
    expect(uaFamily('Mozilla/5.0 (Linux; Android 15)')).toBe('android');
    expect(uaFamily('curl/8.1')).toBe('curl');
  });
});
